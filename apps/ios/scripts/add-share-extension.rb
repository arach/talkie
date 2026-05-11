#!/usr/bin/env ruby
#
# Adds the TalkieShare extension target to the iOS Xcode project.
# Uses the xcodeproj gem for safe, structured manipulation.
#

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Talkie-iOS.xcodeproj', __dir__)
project = Xcodeproj::Project.open(PROJECT_PATH)

# Check if target already exists
if project.targets.any? { |t| t.name == 'TalkieShare' }
  puts "TalkieShare target already exists — skipping"
  exit 0
end

# Find the main app target
main_target = project.targets.find { |t| t.name == 'Talkie' }
abort("Could not find main Talkie target") unless main_target

# --- 1. Create the new native target ---
share_target = project.new_target(
  :app_extension,
  'TalkieShare',
  :ios,
  '17.0'  # Share extensions work on iOS 17+
)
share_target.product_name = 'TalkieShare'

# --- 2. Add source files ---
share_group = project.main_group.new_group('TalkieShare', 'TalkieShare')

# Add Swift files
swift_files = Dir.glob(File.join(File.dirname(PROJECT_PATH), 'TalkieShare', '*.swift'))
swift_files.each do |file_path|
  file_ref = share_group.new_file(file_path)
  share_target.source_build_phase.add_file_reference(file_ref)
end

# Add Info.plist as file reference (not compiled)
info_plist_path = File.join(File.dirname(PROJECT_PATH), 'TalkieShare', 'Info.plist')
share_group.new_file(info_plist_path)

# Add entitlements as file reference (not compiled)
entitlements_path = File.join(File.dirname(PROJECT_PATH), 'TalkieShare', 'TalkieShare.entitlements')
entitlements_ref = share_group.new_file(entitlements_path)

# --- 3. Configure build settings ---
share_target.build_configurations.each do |config|
  settings = config.build_settings

  settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(TALKIE_IOS_SHARE_BUNDLE_ID)'
  settings['INFOPLIST_FILE'] = 'TalkieShare/Info.plist'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'TalkieShare/TalkieShare.entitlements'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['CODE_SIGN_IDENTITY'] = 'Apple Development'
  settings['DEVELOPMENT_TEAM'] = '$(TALKIE_DEVELOPMENT_TEAM)'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Talkie'
  settings['INFOPLIST_KEY_NSHumanReadableCopyright'] = ''
  settings['CURRENT_PROJECT_VERSION'] = '2'
  settings['MARKETING_VERSION'] = '2.5.2'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
end

# --- 4. Add as dependency of main target ---
main_target.add_dependency(share_target)

# --- 5. Embed the extension in the main app ---
# Find or create the "Embed Foundation Extensions" copy files phase
embed_phase = main_target.build_phases.find { |p|
  p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
  p.name == 'Embed Foundation Extensions'
}

unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed Foundation Extensions'
  embed_phase.dst_subfolder_spec = '13' # PlugIns & Foundation Extensions
  main_target.build_phases << embed_phase
end

# Add the .appex product to the embed phase
build_file = embed_phase.add_file_reference(share_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# --- 6. Save ---
project.save

puts "TalkieShare extension target added successfully!"
puts "  Bundle ID: $(TALKIE_IOS_SHARE_BUNDLE_ID)"
puts "  Files: #{swift_files.map { |f| File.basename(f) }.join(', ')}"
puts "  Embedded in: #{main_target.name}"
