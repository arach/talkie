#!/usr/bin/env ruby
# frozen_string_literal: true

# Restructure to Model+CloudKit pattern with nested domain types
# - MemoModel.swift (canonical)
# - MemoModel+CloudKit.swift (sync adapter)
# - Nested types: MemoModel.Source, MemoModel.SortField, etc.

require 'fileutils'

puts "🚀 Restructuring to clean Model+CloudKit architecture...\n\n"

# Step 1: Read MemoSource.swift and nest it as MemoModel.Source
puts "📋 Step 1: Nesting MemoSource as MemoModel.Source"

memo_source_path = 'Data/Models/MemoSource.swift'
memo_model_path = 'Data/Models/MemoModel.swift'

if File.exist?(memo_source_path) && File.exist?(memo_model_path)
  memo_source = File.read(memo_source_path)
  memo_model = File.read(memo_model_path)

  # Extract the MemoSource enum (remove file header, keep enum and extension)
  source_content = memo_source
    .gsub(/^\/\/.*\n/, '')  # Remove comment lines
    .gsub(/^import .*\n/, '')  # Remove imports
    .strip

  # Nest it in MemoModel file as an extension
  nested_source = "\n\n// MARK: - Nested Types\n\nextension MemoModel {\n"

  # Change enum MemoSource to enum Source
  source_content = source_content.gsub(/enum MemoSource/, 'enum Source')

  # Indent the content
  source_lines = source_content.split("\n")
  indented = source_lines.map { |line| line.empty? ? line : "    #{line}" }.join("\n")

  nested_source += indented
  nested_source += "\n}\n"

  # Append to MemoModel.swift (before final closing brace if exists)
  memo_model += nested_source

  File.write(memo_model_path, memo_model)
  puts "✅ Nested MemoSource as MemoModel.Source"

  # Delete old file
  FileUtils.rm(memo_source_path)
  puts "🗑️  Deleted Data/Models/MemoSource.swift"
else
  puts "⚠️  Files not found for MemoSource nesting"
end

# Step 2: Create MemoModel+CloudKit.swift extension
puts "\n📋 Step 2: Creating MemoModel+CloudKit.swift"

cloudkit_sync_path = 'Data/Sync/CloudKitSyncEngine.swift'
memo_cloudkit_path = 'Data/Models/MemoModel+CloudKit.swift'

if File.exist?(cloudkit_sync_path)
  sync_content = File.read(cloudkit_sync_path)

  # Extract conversion methods (convertMemoToRecord and convertRecordToMemo)
  # This is a simplified extraction - we'll create the structure manually

  cloudkit_extension = <<~SWIFT
    //
    //  MemoModel+CloudKit.swift
    //  Talkie
    //
    //  CloudKit sync adapter for MemoModel
    //  Converts between local MemoModel and CloudKit CKRecord
    //

    import Foundation
    import CloudKit

    extension MemoModel {
        // MARK: - CloudKit Record Type

        static let cloudKitRecordType = "VoiceMemo"
        static let cloudKitZoneID = CKRecordZone.ID(zoneName: "TalkieMemos", ownerName: CKCurrentUserDefaultName)

        // MARK: - To CloudKit Record

        func toCKRecord() -> CKRecord {
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: Self.cloudKitZoneID)
            let record = CKRecord(recordType: Self.cloudKitRecordType, recordID: recordID)

            // Core properties
            record["createdAt"] = createdAt as CKRecordValue
            record["lastModified"] = lastModified as CKRecordValue
            record["title"] = (title ?? "") as CKRecordValue
            record["duration"] = duration as CKRecordValue
            record["sortOrder"] = sortOrder as CKRecordValue

            // Content
            record["transcription"] = (transcription ?? "") as CKRecordValue
            record["notes"] = (notes ?? "") as CKRecordValue
            record["summary"] = (summary ?? "") as CKRecordValue
            record["tasks"] = (tasks ?? "") as CKRecordValue
            record["reminders"] = (reminders ?? "") as CKRecordValue

            // Audio (store as CKAsset)
            if let audioPath = audioFilePath {
                let audioURL = Self.audioStorageURL(for: audioPath)
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    let asset = CKAsset(fileURL: audioURL)
                    record["audioAsset"] = asset
                }
            }

            // Waveform data
            if let waveform = waveformData {
                record["waveformData"] = waveform as CKRecordValue
            }

            // Processing state
            record["isTranscribing"] = isTranscribing as CKRecordValue
            record["isProcessingSummary"] = isProcessingSummary as CKRecordValue
            record["isProcessingTasks"] = isProcessingTasks as CKRecordValue
            record["isProcessingReminders"] = isProcessingReminders as CKRecordValue
            record["autoProcessed"] = autoProcessed as CKRecordValue

            // Provenance
            record["originDeviceId"] = (originDeviceId ?? "") as CKRecordValue
            if let macReceived = macReceivedAt {
                record["macReceivedAt"] = macReceived as CKRecordValue
            }

            record["pendingWorkflowIds"] = (pendingWorkflowIds ?? "") as CKRecordValue

            return record
        }

        // MARK: - From CloudKit Record

        static func fromCKRecord(_ record: CKRecord) -> MemoModel? {
            guard let idString = record.recordID.recordName,
                  let id = UUID(uuidString: idString),
                  let createdAt = record["createdAt"] as? Date,
                  let lastModified = record["lastModified"] as? Date else {
                return nil
            }

            let title = record["title"] as? String
            let duration = record["duration"] as? Double ?? 0
            let sortOrder = record["sortOrder"] as? Int ?? 0

            let transcription = record["transcription"] as? String
            let notes = record["notes"] as? String
            let summary = record["summary"] as? String
            let tasks = record["tasks"] as? String
            let reminders = record["reminders"] as? String

            // Handle audio asset
            var audioFilePath: String?
            if let audioAsset = record["audioAsset"] as? CKAsset,
               let assetURL = audioAsset.fileURL {
                // Download and save audio file
                audioFilePath = saveAudioAsset(assetURL, memoId: id)
            }

            let waveformData = record["waveformData"] as? Data

            let isTranscribing = record["isTranscribing"] as? Bool ?? false
            let isProcessingSummary = record["isProcessingSummary"] as? Bool ?? false
            let isProcessingTasks = record["isProcessingTasks"] as? Bool ?? false
            let isProcessingReminders = record["isProcessingReminders"] as? Bool ?? false
            let autoProcessed = record["autoProcessed"] as? Bool ?? false

            let originDeviceId = record["originDeviceId"] as? String
            let macReceivedAt = record["macReceivedAt"] as? Date
            let pendingWorkflowIds = record["pendingWorkflowIds"] as? String

            return MemoModel(
                id: id,
                createdAt: createdAt,
                lastModified: lastModified,
                title: title,
                duration: duration,
                sortOrder: sortOrder,
                transcription: transcription,
                notes: notes,
                summary: summary,
                tasks: tasks,
                reminders: reminders,
                audioFilePath: audioFilePath,
                waveformData: waveformData,
                isTranscribing: isTranscribing,
                isProcessingSummary: isProcessingSummary,
                isProcessingTasks: isProcessingTasks,
                isProcessingReminders: isProcessingReminders,
                autoProcessed: autoProcessed,
                originDeviceId: originDeviceId,
                macReceivedAt: macReceivedAt,
                cloudSyncedAt: Date(),  // Mark as synced
                pendingWorkflowIds: pendingWorkflowIds
            )
        }

        // MARK: - Audio Helpers

        private static func audioStorageURL(for relativePath: String) -> URL {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            return appSupport
                .appendingPathComponent("Talkie/Audio", isDirectory: true)
                .appendingPathComponent(relativePath)
        }

        private static func saveAudioAsset(_ assetURL: URL, memoId: UUID) -> String {
            let fileName = "\\(memoId.uuidString).m4a"
            let destinationURL = audioStorageURL(for: fileName)

            // Copy file
            try? FileManager.default.copyItem(at: assetURL, to: destinationURL)

            return fileName
        }
    }
  SWIFT

  File.write(memo_cloudkit_path, cloudkit_extension)
  puts "✅ Created MemoModel+CloudKit.swift"
else
  puts "⚠️  CloudKitSyncEngine.swift not found"
end

# Step 3: Create TranscriptVersionModel+CloudKit.swift
puts "\n📋 Step 3: Creating TranscriptVersionModel+CloudKit.swift"

transcript_cloudkit_path = 'Data/Models/TranscriptVersionModel+CloudKit.swift'

transcript_cloudkit = <<~SWIFT
  //
  //  TranscriptVersionModel+CloudKit.swift
  //  Talkie
  //
  //  CloudKit sync adapter for TranscriptVersionModel (if needed)
  //

  import Foundation
  import CloudKit

  extension TranscriptVersionModel {
      // CloudKit sync for transcript versions
      // (Can be added later if needed for full sync)
  }
SWIFT

File.write(transcript_cloudkit_path, transcript_cloudkit)
puts "✅ Created TranscriptVersionModel+CloudKit.swift"

# Step 4: Create WorkflowRunModel+CloudKit.swift
puts "\n📋 Step 4: Creating WorkflowRunModel+CloudKit.swift"

workflow_cloudkit_path = 'Data/Models/WorkflowRunModel+CloudKit.swift'

workflow_cloudkit = <<~SWIFT
  //
  //  WorkflowRunModel+CloudKit.swift
  //  Talkie
  //
  //  CloudKit sync adapter for WorkflowRunModel (if needed)
  //

  import Foundation
  import CloudKit

  extension WorkflowRunModel {
      // CloudKit sync for workflow runs
      // (Can be added later if needed for full sync)
  }
SWIFT

File.write(workflow_cloudkit_path, workflow_cloudkit)
puts "✅ Created WorkflowRunModel+CloudKit.swift"

puts "\n✨ Done! New architecture:"
puts "   Data/Models/MemoModel.swift (canonical + nested Source)"
puts "   Data/Models/MemoModel+CloudKit.swift (sync adapter)"
puts "   Data/Models/TranscriptVersionModel.swift"
puts "   Data/Models/TranscriptVersionModel+CloudKit.swift"
puts "   Data/Models/WorkflowRunModel.swift"
puts "   Data/Models/WorkflowRunModel+CloudKit.swift"

puts "\n💡 Next: Update references from MemoSource to MemoModel.Source"
