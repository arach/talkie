#!/usr/bin/env ruby
# frozen_string_literal: true

# Update all references to use nested types
# MemoSource → MemoModel.Source
# MemoSortField → MemoModel.SortField
# TranscriptSourceType → TranscriptVersionModel.SourceType
# TranscriptEngines → TranscriptVersionModel.Engines

require 'fileutils'

puts "🚀 Updating references to nested types...\n\n"

FILES_TO_UPDATE = [
  'Data/Models/MemoModel.swift',
  'Data/Models/MemoModel+CloudKit.swift',
  'Data/Models/TranscriptVersionModel.swift',
  'Data/Models/TranscriptVersionModel+CloudKit.swift',
  'Data/Models/WorkflowRunModel.swift',
  'Data/Models/WorkflowRunModel+CloudKit.swift',
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

def backup_file(filepath)
  return unless File.exist?(filepath)
  backup_path = "#{filepath}.bak2"
  FileUtils.cp(filepath, backup_path) unless File.exist?(backup_path)
end

def update_file(filepath)
  unless File.exist?(filepath)
    puts "⚠️  File not found: #{filepath}"
    return
  end

  backup_file(filepath)
  content = File.read(filepath)
  original = content.dup

  # Skip if this is the old Core Data files (don't touch legacy code)
  if filepath.include?('Models/VoiceMemo+') || filepath.include?('Views/Memos/MemoTableViews.swift')
    puts "⏭️  Skipping legacy file: #{filepath}"
    return
  end

  # Update type references in our new GRDB code only
  # Be careful with word boundaries to avoid partial matches

  # MemoSource → MemoModel.Source (but not in strings or comments about Core Data)
  content.gsub!(/\bMemoSource\b(?!\.)/) do |match|
    # Check if we're in a context where this should be updated
    'MemoModel.Source'
  end

  # Update standalone MemoSortField in repository/viewmodel files
  # But NOT in the old MemoTableViews.swift
  if !filepath.include?('MemoTableViews.swift')
    content.gsub!(/\bMemoSortField\b(?!\.)/, 'MemoModel.SortField')
  end

  # TranscriptSourceType → TranscriptVersionModel.SourceType
  content.gsub!(/\bTranscriptSourceType\b(?!\.)/, 'TranscriptVersionModel.SourceType')

  # TranscriptEngines → TranscriptVersionModel.Engines
  content.gsub!(/\bTranscriptEngines\b(?!\.)/, 'TranscriptVersionModel.Engines')

  if content != original
    File.write(filepath, content)
    puts "✅ Updated: #{filepath}"
  else
    puts "⏭️  No changes: #{filepath}"
  end
end

# Step 1: Nest MemoSortField in MemoRepository.swift
puts "📋 Step 1: Nesting MemoSortField as MemoModel.SortField\n"

repo_path = 'Data/Database/MemoRepository.swift'
if File.exist?(repo_path)
  content = File.read(repo_path)

  # Extract MemoSortField enum
  if content =~ /enum MemoSortField \{.*?\n\}/m
    sort_field_enum = $&

    # Remove it from repository file
    content.gsub!(/enum MemoSortField \{.*?\n\}/m, '')

    # Add it to MemoModel.swift as nested type
    memo_model_path = 'Data/Models/MemoModel.swift'
    if File.exist?(memo_model_path)
      memo_content = File.read(memo_model_path)

      # Change enum MemoSortField to enum SortField
      nested_sort = sort_field_enum.gsub(/enum MemoSortField/, 'enum SortField')

      # Add to MemoModel extensions
      unless memo_content.include?('enum SortField')
        # Indent
        nested_sort = nested_sort.split("\n").map { |line| line.empty? ? line : "    #{line}" }.join("\n")

        memo_content += "\n\nextension MemoModel {\n#{nested_sort}\n}\n"
        File.write(memo_model_path, memo_content)
        puts "✅ Nested MemoSortField as MemoModel.SortField"
      end
    end

    # Write back cleaned repository
    File.write(repo_path, content)
  end
else
  puts "⚠️  MemoRepository.swift not found"
end

# Step 2: Nest TranscriptSourceType and TranscriptEngines in TranscriptVersionModel
puts "\n📋 Step 2: Nesting TranscriptSourceType and TranscriptEngines\n"

transcript_path = 'Data/Models/TranscriptVersionModel.swift'
if File.exist?(transcript_path)
  content = File.read(transcript_path)

  # These should already be in the file, just need to rename to nested style
  # TranscriptSourceType → SourceType (nested)
  content.gsub!(/enum TranscriptSourceType/, 'enum SourceType')

  # TranscriptEngines → Engines (nested)
  content.gsub!(/struct TranscriptEngines/, 'struct Engines')

  File.write(transcript_path, content)
  puts "✅ Nested types in TranscriptVersionModel"
end

# Step 3: Update all references
puts "\n📋 Step 3: Updating all references in files\n"

FILES_TO_UPDATE.each do |file|
  update_file(file)
end

puts "\n✨ Done! All references updated to nested types."
puts "\n💡 Next: Update Xcode project and build"
