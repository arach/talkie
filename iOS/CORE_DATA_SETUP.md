# Core Data Model Setup for Voice Memos

## Required Changes

You need to manually update the Core Data model in Xcode to add the `VoiceMemo` entity.

### Steps:

1. **Open the project in Xcode**:
   ```bash
   cd iOS
   open talkie.xcodeproj
   ```

2. **Open the Core Data model**:
   - In Xcode's Project Navigator, navigate to:
     `talkie/Resources/talkie.xcdatamodeld/talkie.xcdatamodel`
   - Click on it to open the Core Data model editor

3. **Add the VoiceMemo entity**:
   - Click the **"Add Entity"** button at the bottom of the editor
   - Name it `VoiceMemo`
   - Set **Codegen** to "Class Definition" in the Data Model Inspector (right panel)

4. **Add the following attributes** to the VoiceMemo entity:

   | Attribute Name | Type | Optional | Default |
   |---------------|------|----------|---------|
   | `id` | UUID | No | - |
   | `title` | String | Yes | - |
   | `createdAt` | Date | Yes | - |
   | `duration` | Double | No | 0 |
   | `fileURL` | String | Yes | - |
   | `transcription` | String | Yes | - |
   | `isTranscribing` | Boolean | No | NO |
   | `waveformData` | Binary Data | Yes | - |

5. **Configure iCloud sync** (optional but recommended):
   - Select the **"talkie"** target in the Project Navigator
   - Go to **"Signing & Capabilities"**
   - Click **"+ Capability"**
   - Add **"iCloud"**
   - Check **"CloudKit"**
   - Under **"Containers"**, add: `iCloud.com.yourcompany.talkie` (replace with your bundle ID)

6. **Update Persistence.swift** (if using CloudKit):
   - The current `Persistence.swift` already supports Core Data
   - To enable iCloud sync, modify the container initialization in `Persistence.swift`:

   ```swift
   init(inMemory: Bool = false) {
       container = NSPersistentCloudKitContainer(name: "talkie") // Changed from NSPersistentContainer

       if inMemory {
           container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
       }

       // Enable CloudKit sync
       if let description = container.persistentStoreDescriptions.first {
           description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
               containerIdentifier: "iCloud.com.yourcompany.talkie"
           )
       }

       container.loadPersistentStores(completionHandler: { (storeDescription, error) in
           if let error = error as NSError? {
               fatalError("Unresolved error \(error), \(error.userInfo)")
           }
       })
       container.viewContext.automaticallyMergesChangesFromParent = true
   }
   ```

7. **Build and run**:
   - Clean build folder: `Cmd + Shift + K`
   - Build and run: `Cmd + R`

## Verification

After making these changes:
- The app should launch with the Voice Memos list view
- You should be able to tap the red mic button to start recording
- Recordings should save with waveform visualization
- Playback should work with play/pause controls
- Transcription should start automatically after recording

## Troubleshooting

**If you see compile errors**:
- Make sure `VoiceMemo+CoreDataProperties.swift` is added to the target
- Clean build folder and rebuild
- Check that the entity name exactly matches "VoiceMemo"

**If recordings don't save**:
- Check that microphone permissions are granted
- Look for errors in the Xcode console

**If transcription doesn't work**:
- Grant speech recognition permission when prompted
- Check that `NSSpeechRecognitionUsageDescription` is in Info.plist

**If iCloud sync doesn't work**:
- Ensure you're signed in to iCloud on the device/simulator
- Check that CloudKit capabilities are properly configured
- Verify the container identifier matches
