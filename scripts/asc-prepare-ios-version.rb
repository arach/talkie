#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
EDITABLE_VERSION_STATES = %w[
  PREPARE_FOR_SUBMISSION
  READY_FOR_REVIEW
  DEVELOPER_REJECTED
  REJECTED
  METADATA_REJECTED
  INVALID_BINARY
].freeze

def base64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def fixed_width_integer(integer, bytes)
  hex = integer.to_i.to_s(16)
  hex = "0#{hex}" if hex.length.odd?
  [hex].pack("H*").rjust(bytes, "\0")
end

def der_to_raw_ecdsa_signature(der)
  sequence = OpenSSL::ASN1.decode(der)
  unless sequence.is_a?(OpenSSL::ASN1::Sequence) && sequence.value.length == 2
    raise "Unexpected ECDSA signature format"
  end

  fixed_width_integer(sequence.value[0].value, 32) +
    fixed_width_integer(sequence.value[1].value, 32)
end

def build_jwt(key_id:, issuer_id:, private_key_path:)
  header = {
    alg: "ES256",
    kid: key_id,
    typ: "JWT"
  }
  issued_at = Time.now.to_i
  payload = {
    iss: issuer_id,
    iat: issued_at,
    exp: issued_at + (20 * 60),
    aud: "appstoreconnect-v1"
  }

  signing_input = [
    base64url(JSON.generate(header)),
    base64url(JSON.generate(payload))
  ].join(".")

  key = OpenSSL::PKey.read(File.read(private_key_path))
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  signature = der_to_raw_ecdsa_signature(key.dsa_sign_asn1(digest))

  "#{signing_input}.#{base64url(signature)}"
end

class AppStoreConnectClient
  def initialize(token)
    @token = token
  end

  def get(path, query = {})
    request(Net::HTTP::Get, path, query: query)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body: body)
  end

  def patch(path, body)
    request(Net::HTTP::Patch, path, body: body)
  end

  private

  def request(request_class, path, query: {}, body: nil)
    uri = URI("#{API_BASE}#{path}")
    uri.query = URI.encode_www_form(query) unless query.empty?

    request = request_class.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body) unless body.nil?

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    return {} if response.body.nil? || response.body.empty?
    parsed = JSON.parse(response.body)
    return parsed if response.is_a?(Net::HTTPSuccess)

    errors = parsed.fetch("errors", []).map do |error|
      detail = error["detail"] || error["title"]
      code = error["code"] || error["status"]
      [code, detail].compact.join(": ")
    end
    message = errors.empty? ? response.body : errors.join("; ")
    raise "ASC #{request_class::METHOD} #{uri} failed with #{response.code}: #{message}"
  end
end

def resource_attributes(resource)
  resource.fetch("attributes", {})
end

def find_app(client, bundle_id)
  response = client.get("/v1/apps", {
    "filter[bundleId]" => bundle_id,
    "limit" => "1"
  })
  app = response.fetch("data", []).first
  raise "No App Store Connect app found for bundle id #{bundle_id}" if app.nil?

  app
end

def app_store_versions(client, app_id, version: nil)
  query = {
    "filter[platform]" => "IOS",
    "limit" => "200"
  }
  query["filter[versionString]"] = version unless version.nil?

  client.get("/v1/apps/#{app_id}/appStoreVersions", query).fetch("data", [])
end

def create_app_store_version(client, app_id, version)
  body = {
    data: {
      type: "appStoreVersions",
      attributes: {
        platform: "IOS",
        versionString: version
      },
      relationships: {
        app: {
          data: {
            type: "apps",
            id: app_id
          }
        }
      }
    }
  }

  client.post("/v1/appStoreVersions", body).fetch("data")
end

def update_app_store_version_string(client, version_id, version)
  body = {
    data: {
      type: "appStoreVersions",
      id: version_id,
      attributes: {
        versionString: version
      }
    }
  }

  client.patch("/v1/appStoreVersions/#{version_id}", body).fetch("data")
end

def ensure_app_store_version(client, app_id, version)
  matching = app_store_versions(client, app_id, version: version).first
  unless matching.nil?
    attributes = resource_attributes(matching)
    puts "App Store version #{version} already exists (state: #{attributes["appVersionState"] || attributes["appStoreState"]})."
    return matching
  end

  begin
    created = create_app_store_version(client, app_id, version)
    puts "Created App Store version #{version}."
    return created
  rescue StandardError => error
    puts "Could not create App Store version #{version}: #{error.message}"
  end

  editable = app_store_versions(client, app_id).select do |candidate|
    state = resource_attributes(candidate)["appVersionState"] || resource_attributes(candidate)["appStoreState"]
    EDITABLE_VERSION_STATES.include?(state)
  end

  if editable.length != 1
    states = editable.map do |candidate|
      attributes = resource_attributes(candidate)
      "#{attributes["versionString"] || candidate["id"]}:#{attributes["appVersionState"] || attributes["appStoreState"]}"
    end
    raise "Expected one editable iOS App Store version to rename, found #{editable.length} (#{states.join(", ")})."
  end

  candidate = editable.first
  attributes = resource_attributes(candidate)
  old_version = attributes["versionString"]
  state = attributes["appVersionState"] || attributes["appStoreState"]
  updated = update_app_store_version_string(client, candidate.fetch("id"), version)
  puts "Renamed editable App Store version #{old_version} (#{state}) to #{version}."
  updated
end

def builds_for_version(client, app_id, version, build_number, audience: "APP_STORE_ELIGIBLE", processing_state: "VALID")
  query = {
    "filter[app]" => app_id,
    "filter[preReleaseVersion.version]" => version,
    "filter[version]" => build_number,
    "filter[expired]" => "false",
    "sort" => "-uploadedDate",
    "limit" => "1"
  }
  query["filter[buildAudienceType]"] = audience unless audience.nil?
  query["filter[processingState]"] = processing_state unless processing_state.nil?

  client.get("/v1/builds", query).fetch("data", [])
end

def describe_latest_build(client, app_id, version, build_number)
  builds = builds_for_version(client, app_id, version, build_number, audience: nil, processing_state: nil)
  return "no matching build found yet" if builds.empty?

  attributes = resource_attributes(builds.first)
  state = attributes["processingState"] || "unknown"
  audience = attributes["buildAudienceType"] || "unknown audience"
  uploaded = attributes["uploadedDate"] || "unknown upload time"
  "latest matching build state: #{state}, #{audience}, uploaded #{uploaded}"
end

def find_valid_build(client, app_id, version, build_number)
  builds_for_version(client, app_id, version, build_number).first ||
    builds_for_version(client, app_id, version, build_number, audience: nil).first
end

def wait_for_valid_build(client, app_id, version, build_number, timeout_seconds)
  deadline = Time.now + timeout_seconds

  loop do
    build = find_valid_build(client, app_id, version, build_number)
    return build unless build.nil?

    status = describe_latest_build(client, app_id, version, build_number)
    raise "Timed out waiting for valid build #{version} (#{build_number}); #{status}." if Time.now >= deadline

    puts "Waiting for valid build #{version} (#{build_number}); #{status}."
    sleep 30
  end
end

def attach_build(client, app_store_version_id, build_id)
  body = {
    data: {
      type: "builds",
      id: build_id
    }
  }

  client.patch("/v1/appStoreVersions/#{app_store_version_id}/relationships/build", body)
end

options = {
  attach_build: false,
  build_timeout: 30 * 60
}

OptionParser.new do |parser|
  parser.banner = "Usage: asc-prepare-ios-version.rb --bundle-id ID --version VERSION [options]"

  parser.on("--bundle-id ID", "Bundle identifier, for example to.talkie.app") { |value| options[:bundle_id] = value }
  parser.on("--version VERSION", "App Store version string, for example 2.5.26") { |value| options[:version] = value }
  parser.on("--build NUMBER", "Build number to attach to the App Store version") { |value| options[:build_number] = value }
  parser.on("--key-id ID", "App Store Connect API key id") { |value| options[:key_id] = value }
  parser.on("--issuer-id ID", "App Store Connect API issuer id") { |value| options[:issuer_id] = value }
  parser.on("--private-key-path PATH", "Path to the App Store Connect .p8 private key") { |value| options[:private_key_path] = value }
  parser.on("--attach-build", "Attach the matching valid build to the App Store version") { options[:attach_build] = true }
  parser.on("--build-timeout SECONDS", Integer, "Seconds to wait for a valid build when attaching") { |value| options[:build_timeout] = value }
end.parse!

required = %i[bundle_id version key_id issuer_id private_key_path]
required << :build_number if options[:attach_build]
missing = required.select { |key| options[key].nil? || options[key].empty? }
unless missing.empty?
  raise OptionParser::MissingArgument, missing.map { |key| "--#{key.to_s.tr("_", "-")}" }.join(", ")
end

token = build_jwt(
  key_id: options.fetch(:key_id),
  issuer_id: options.fetch(:issuer_id),
  private_key_path: options.fetch(:private_key_path)
)
client = AppStoreConnectClient.new(token)

app = find_app(client, options.fetch(:bundle_id))
app_id = app.fetch("id")
app_store_version = ensure_app_store_version(client, app_id, options.fetch(:version))

if options[:attach_build]
  build = wait_for_valid_build(
    client,
    app_id,
    options.fetch(:version),
    options.fetch(:build_number),
    options.fetch(:build_timeout)
  )
  attach_build(client, app_store_version.fetch("id"), build.fetch("id"))
  puts "Attached build #{options.fetch(:version)} (#{options.fetch(:build_number)}) to App Store version #{options.fetch(:version)}."
end
