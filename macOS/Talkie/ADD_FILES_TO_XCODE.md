# How to Add New Component Files to Xcode Project

The following files need to be manually added to the Xcode project:

## Files to Add

### Components/
1. `FormControls.swift` - Already exists at `macOS/Talkie/Components/FormControls.swift` ✨ NEW

### Views/Live/Components/
2. `OverlayStylePreviews.swift` - Already exists at `macOS/Talkie/Views/Live/Components/OverlayStylePreviews.swift`
3. `HotkeyRecorder.swift` - Already exists at `macOS/Talkie/Views/Live/Components/HotkeyRecorder.swift`
4. `AudioDeviceSelector.swift` - Already exists at `macOS/Talkie/Views/Live/Components/AudioDeviceSelector.swift`
5. `SoundPicker.swift` - Already exists at `macOS/Talkie/Views/Live/Components/SoundPicker.swift`

### Services/Audio/
6. `AudioDeviceManager.swift` - Already exists at `macOS/Talkie/Services/Audio/AudioDeviceManager.swift`

## Steps to Add Files in Xcode

1. **Open the project**:
   ```bash
   open macOS/Talkie/Talkie.xcodeproj
   ```

2. **Add FormControls** (NEW):
   - In Xcode, in the Project Navigator, find or create the `Components` folder at the root level
   - Right-click on `Components` folder → "Add Files to Talkie..."
   - Navigate to `macOS/Talkie/Components/`
   - Select `FormControls.swift`
   - **Important**: Make sure "Copy items if needed" is **UNCHECKED** (files are already in the right location)
   - **Important**: Make sure "Create groups" is selected (not "Create folder references")
   - **Important**: Make sure "Talkie" target is **CHECKED**
   - Click "Add"

3. **Add Live Component Files**:
   - In Xcode, navigate to `Views` → `Live` in the Project Navigator
   - Right-click on the `Live` folder → "Add Files to Talkie..."
   - Navigate to `macOS/Talkie/Views/Live/Components/`
   - Select all 4 component files (OverlayStylePreviews.swift, HotkeyRecorder.swift, AudioDeviceSelector.swift, SoundPicker.swift)
   - **Important**: Same settings as above (don't copy, create groups, check Talkie target)
   - Click "Add"

4. **Add AudioDeviceManager**:
   - In Xcode, navigate to `Services` in the Project Navigator
   - Right-click on the `Services` folder → "Add Files to Talkie..."
   - Navigate to `macOS/Talkie/Services/Audio/`
   - Select `AudioDeviceManager.swift`
   - **Important**: Same settings as above (don't copy, create groups, check Talkie target)
   - Click "Add"

4. **Build the project**:
   ```bash
   cd macOS/Talkie && xcodebuild -project Talkie.xcodeproj -scheme Talkie -configuration Debug build
   ```

## What These Files Do

- **FormControls.swift**: Reusable styled form components (Toggle, Dropdown, Checkbox, TabSelector) aligned with design system
- **OverlayStylePreviews.swift**: Animated particle and waveform previews for overlay style selection
- **HotkeyRecorder.swift**: Interactive keyboard shortcut recorder with live capture
- **AudioDeviceSelector.swift**: Audio input device picker with real-time level meter
- **SoundPicker.swift**: Sound selection grid with instant preview playback
- **AudioDeviceManager.swift**: CoreAudio wrapper for enumerating and selecting input devices

## Alternative: Run Script to Add Files

If you prefer, you can also add the files programmatically, but this requires careful handling of the Xcode project structure. The manual approach through Xcode's UI is more reliable.
