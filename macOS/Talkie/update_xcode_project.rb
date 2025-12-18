#!/usr/bin/env ruby
# frozen_string_literal: true

# Update Xcode project:
# - Add: MemoModel+CloudKit.swift, TranscriptVersionModel+CloudKit.swift, WorkflowRunModel+CloudKit.swift
# - Remove: MemoSource.swift

require 'fileutils'
require 'securerandom'

PROJECT_FILE = 'Talkie.xcodeproj/project.pbxproj'

def generate_uuid
  SecureRandom.hex(12).upcase
end

puts "🚀 Updating Xcode project...\n\n"

# Backup
FileUtils.cp(PROJECT_FILE, "#{PROJECT_FILE}.bak3")
puts "📦 Backed up project file"

content = File.read(PROJECT_FILE)

# Remove MemoSource.swift references
puts "\n🗑️  Removing MemoSource.swift references"
content.gsub!(/.*MemoSource\.swift.*\n/, '')
puts "✅ Removed MemoSource.swift"

# Add new +CloudKit files
new_files = [
  'Data/Models/MemoModel+CloudKit.swift',
  'Data/Models/TranscriptVersionModel+CloudKit.swift',
  'Data/Models/WorkflowRunModel+CloudKit.swift'
]

puts "\n📝 Adding new +CloudKit files"

# Generate UUIDs
file_refs = {}
build_files = {}

new_files.each do |file_path|
  file_name = File.basename(file_path)
  file_refs[file_path] = generate_uuid
  build_files[file_path] = generate_uuid
  puts "   Generated UUIDs for #{file_name}"
end

# Add PBXFileReference entries
file_ref_section = "/* Begin PBXFileReference section */"
file_ref_index = content.index(file_ref_section)

if file_ref_index
  insert_pos = file_ref_index + file_ref_section.length

  new_entries = new_files.map do |file_path|
    file_name = File.basename(file_path)
    ref_uuid = file_refs[file_path]
    "\n\t\t#{ref_uuid} /* #{file_name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"#{file_name}\"; sourceTree = \"<group>\"; };"
  end.join

  content.insert(insert_pos, new_entries)
  puts "✅ Added PBXFileReference entries"
end

# Add PBXBuildFile entries
build_file_section = "/* Begin PBXBuildFile section */"
build_file_index = content.index(build_file_section)

if build_file_index
  insert_pos = build_file_index + build_file_section.length

  new_entries = new_files.map do |file_path|
    file_name = File.basename(file_path)
    build_uuid = build_files[file_path]
    ref_uuid = file_refs[file_path]
    "\n\t\t#{build_uuid} /* #{file_name} in Sources */ = {isa = PBXBuildFile; fileRef = #{ref_uuid} /* #{file_name} */; };"
  end.join

  content.insert(insert_pos, new_entries)
  puts "✅ Added PBXBuildFile entries"
end

# Add to PBXSourcesBuildPhase
if content =~ /(\/\* Begin PBXSourcesBuildPhase section \*\/.*?files = \()(.*?)(\);)/m
  prefix = $1
  existing = $2
  suffix = $3

  new_entries = new_files.map do |file_path|
    file_name = File.basename(file_path)
    build_uuid = build_files[file_path]
    "\n\t\t\t\t#{build_uuid} /* #{file_name} in Sources */,"
  end.join

  replacement = prefix + existing + new_entries + suffix
  content.sub!(/(\/\* Begin PBXSourcesBuildPhase section \*\/.*?files = \()(.*?)(\);)/m, replacement)
  puts "✅ Added to build phase"
end

File.write(PROJECT_FILE, content)

puts "\n✨ Done! Xcode project updated"
puts "\n📦 New files added:"
new_files.each { |f| puts "   ✓ #{File.basename(f)}" }
