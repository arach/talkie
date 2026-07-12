#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "spaceship"

options = {
  locales: %w[en-US en-CA],
  preview_type: Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_67,
  wait_for_processing: false,
  processing_timeout: 1800,
  frame_time_code: "00:00:05:06"
}

OptionParser.new do |parser|
  parser.banner = "Usage: asc-upload-app-preview.rb [options]"
  parser.on("--bundle-id ID", "App bundle identifier") { |value| options[:bundle_id] = value }
  parser.on("--version VERSION", "Editable App Store version") { |value| options[:version] = value }
  parser.on("--path PATH", "App Preview MP4 or MOV") { |value| options[:path] = value }
  parser.on("--locale LOCALE", "Locale to update; may be repeated") do |value|
    options[:locales] = [] unless options[:locales_explicit]
    options[:locales_explicit] = true
    options[:locales] << value
  end
  parser.on("--preview-type TYPE", "App Preview set type (default: IPHONE_67)") do |value|
    options[:preview_type] = value
  end
  parser.on("--wait-for-processing", "Verify processing and set the poster frame") do
    options[:wait_for_processing] = true
  end
  parser.on("--processing-timeout SECONDS", Integer, "Processing timeout (default: 1800)") do |value|
    options[:processing_timeout] = value
  end
  parser.on("--key-id ID", "App Store Connect API key ID") { |value| options[:key_id] = value }
  parser.on("--issuer-id ID", "App Store Connect issuer ID") { |value| options[:issuer_id] = value }
  parser.on("--private-key-path PATH", "App Store Connect .p8 path") do |value|
    options[:private_key_path] = value
  end
end.parse!

required = %i[bundle_id version path key_id issuer_id private_key_path]
missing = required.select { |key| options[key].to_s.empty? }
abort("Missing options: #{missing.join(', ')}") unless missing.empty?
abort("App Preview does not exist: #{options[:path]}") unless File.file?(options[:path])

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: options[:key_id],
  issuer_id: options[:issuer_id],
  filepath: options[:private_key_path],
  in_house: false
)

app = Spaceship::ConnectAPI::App.find(options[:bundle_id])
abort("App not found: #{options[:bundle_id]}") unless app

versions = app.get_app_store_versions(
  filter: { versionString: options[:version], platform: "IOS" },
  includes: nil
)
version = versions.find { |candidate| candidate.version_string == options[:version] }
abort("App Store version not found: #{options[:version]}") unless version

localizations = version.get_app_store_version_localizations

options[:locales].each do |locale|
  localization = localizations.find { |candidate| candidate.locale == locale }
  abort("Localization not found for #{locale}") unless localization

  preview_sets = localization.get_app_preview_sets
  preview_set = preview_sets.find { |candidate| candidate.preview_type == options[:preview_type] }
  preview_set ||= localization.create_app_preview_set(
    attributes: { previewType: options[:preview_type] }
  )

  existing = preview_set.app_previews || []
  # Preserve a working preview until the replacement has uploaded. App Store
  # Connect allows three previews, so only make space first in the unlikely
  # case that a full set already exists.
  while existing.length >= 3
    existing.shift.delete!
  end

  uploaded = preview_set.upload_preview(
    path: File.expand_path(options[:path]),
    wait_for_processing: false
  )

  if options[:wait_for_processing]
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + options[:processing_timeout]
    loop do
      uploaded = Spaceship::ConnectAPI::AppPreview.get(app_preview_id: uploaded.id)
      delivery_state = (uploaded.asset_delivery_state || {})["state"]
      break if uploaded.complete? || uploaded.video_url

      if %w[FAILED REJECTED INVALID].include?(delivery_state)
        abort("#{locale} App Preview processing failed: #{uploaded.asset_delivery_state}")
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        abort("#{locale} App Preview processing timed out after #{options[:processing_timeout]} seconds")
      end

      puts "Waiting for #{locale} App Preview processing (#{delivery_state || 'pending'})..."
      sleep 15
    end

    uploaded = uploaded.update(
      attributes: { previewFrameTimeCode: options[:frame_time_code] }
    )
    puts "Processed #{locale} App Preview and set poster frame to #{options[:frame_time_code]}"
  end

  existing.each(&:delete!)
  puts "Uploaded #{locale} #{options[:preview_type]} App Preview #{uploaded.id}"
end
