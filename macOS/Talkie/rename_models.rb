#!/usr/bin/env ruby
# frozen_string_literal: true

# Rename GRDB models to avoid conflicts with Core Data auto-generated classes
# VoiceMemo → MemoModel
# TranscriptVersion → TranscriptVersionModel
# WorkflowRun → WorkflowRunModel

require 'fileutils'

# Files that need updates (initially)
INITIAL_FILES = [
  'Data/Models/VoiceMemo.swift',
  'Data/Models/TranscriptVersion.swift',
  'Data/Models/WorkflowRun.swift',
  'Data/Models/MemoSource.swift',
  'Data/Database/DatabaseManager.swift',
  'Data/Database/MemoRepository.swift',
  'Data/Database/GRDBRepository.swift',
  'Data/Database/CoreDataMigration.swift',
  'Data/ViewModels/MemosViewModel.swift',
  'Data/Sync/CloudKitSyncEngine.swift',
  'Views/Memos/AllMemosView2.swift',
  'Views/Migration/MigrationView.swift',
  'App/DataLayerIntegration.swift'
].freeze

# Rename mappings
RENAMES = {
  'VoiceMemo' => 'MemoModel',
  'TranscriptVersion' => 'TranscriptVersionModel',
  'WorkflowRun' => 'WorkflowRunModel'
}.freeze

def backup_file(filepath)
  backup_path = "#{filepath}.bak"
  FileUtils.cp(filepath, backup_path)
  puts "📦 Backed up: #{filepath} → #{backup_path}"
end

def update_file(filepath)
  unless File.exist?(filepath)
    puts "⚠️  File not found: #{filepath}"
    return
  end

  backup_file(filepath)

  content = File.read(filepath)
  original_content = content.dup

  # Apply all renames
  RENAMES.each do |old_name, new_name|
    # Struct declarations
    content.gsub!(/struct #{old_name}(\s*[:{\s])/, "struct #{new_name}\\1")

    # Extension declarations
    content.gsub!(/extension #{old_name}(\s*[:{\s])/, "extension #{new_name}\\1")

    # Type references in parameters, returns, properties
    content.gsub!(/:\s*#{old_name}(\s*[,\)\{\s\?!])/, ": #{new_name}\\1")
    content.gsub!(/:\s*\[#{old_name}\](\s*[,\)\{\s\?!=])/, ": [#{new_name}]\\1")

    # Generic type parameters
    content.gsub!(/<#{old_name}>/, "<#{new_name}>")

    # Static references (ClassName.property)
    content.gsub!(/#{old_name}\./, "#{new_name}.")

    # Type annotations and casts
    content.gsub!(/as\s+#{old_name}(\s*[,\)\{\s\?!])/, "as #{new_name}\\1")
    content.gsub!(/as\?\s+#{old_name}(\s*[,\)\{\s\?!])/, "as? #{new_name}\\1")

    # NSFetchRequest and Core Data queries (keep old name for Core Data)
    # Undo the replacement if it's in NSFetchRequest context
    content.gsub!(/NSFetchRequest<#{new_name}>/, "NSFetchRequest<#{old_name}>")

    # Function return types
    content.gsub!(/->\s*#{old_name}(\s*[,\)\{\s\?!])/, "-> #{new_name}\\1")
    content.gsub!(/->\s*\[#{old_name}\](\s*[,\)\{\s\?!=])/, "-> [#{new_name}]\\1")

    # Array/Dictionary types
    content.gsub!(/\[#{old_name}:\s*/, "[#{new_name}: ")

    # Comments (update for clarity, but not critical)
    content.gsub!(/\/\/\s*#{old_name}(\s)/, "// #{new_name}\\1")
  end

  if content != original_content
    File.write(filepath, content)
    puts "✅ Updated: #{filepath}"
  else
    puts "⏭️  No changes: #{filepath}"
  end
end

def rename_files
  file_renames = [
    ['Data/Models/VoiceMemo.swift', 'Data/Models/MemoModel.swift'],
    ['Data/Models/TranscriptVersion.swift', 'Data/Models/TranscriptVersionModel.swift'],
    ['Data/Models/WorkflowRun.swift', 'Data/Models/WorkflowRunModel.swift']
  ]

  updated_files = INITIAL_FILES.dup

  file_renames.each do |old_path, new_path|
    if File.exist?(old_path)
      FileUtils.mv(old_path, new_path)
      puts "📝 Renamed file: #{old_path} → #{new_path}"

      # Update file list
      updated_files.delete(old_path)
      updated_files << new_path
    end
  end

  updated_files
end

def update_xcode_project
  project_file = 'Talkie.xcodeproj/project.pbxproj'

  unless File.exist?(project_file)
    puts "⚠️  Xcode project not found: #{project_file}"
    return
  end

  backup_file(project_file)

  content = File.read(project_file)

  # Update file paths
  content.gsub!('Data/Models/VoiceMemo.swift', 'Data/Models/MemoModel.swift')
  content.gsub!('Data/Models/TranscriptVersion.swift', 'Data/Models/TranscriptVersionModel.swift')
  content.gsub!('Data/Models/WorkflowRun.swift', 'Data/Models/WorkflowRunModel.swift')

  # Update file references (just the filename part)
  content.gsub!('VoiceMemo.swift', 'MemoModel.swift')
  content.gsub!('TranscriptVersion.swift', 'TranscriptVersionModel.swift')
  content.gsub!('WorkflowRun.swift', 'WorkflowRunModel.swift')

  File.write(project_file, content)
  puts "✅ Updated Xcode project: #{project_file}"
end

# Main execution
puts "🚀 Starting model rename to fix naming conflicts...\n\n"

puts "📋 Step 1: Rename model files"
files_to_update = rename_files

puts "\n📋 Step 2: Update content in all files"
files_to_update.each { |file| update_file(file) }

puts "\n📋 Step 3: Update Xcode project references"
update_xcode_project

puts "\n✨ Done! All models renamed:"
RENAMES.each { |old, new| puts "   #{old} → #{new}" }

puts "\n💡 Next steps:"
puts "   1. Build the project: ⌘ + B"
puts "   2. If successful, delete .bak files"
puts "   3. If errors persist, restore from .bak files"
