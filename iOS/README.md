# Talkie iOS

Native iOS application built with SwiftUI.

## Requirements

- macOS 13.0+
- Xcode 14.0+
- iOS 16.0+ (deployment target)
- Swift 5.9+

## Getting Started

1. **Open the project**:
   ```bash
   open talkie.xcodeproj
   ```

2. **Select a simulator** or connect a device in Xcode

3. **Run the app** using `Cmd+R` or the play button

## Project Structure

```
talkie/
├── App/                 # Application entry point
│   └── talkieApp.swift  # Main app struct
├── Views/               # SwiftUI views
│   └── ContentView.swift
├── Models/              # Data models
│   └── Persistence.swift
└── Resources/           # Assets and configuration
    ├── Assets.xcassets/
    ├── Info.plist
    └── talkie.xcdatamodeld/
```

## Architecture

- **UI**: SwiftUI for declarative UI
- **Data**: Core Data for local persistence
- **Pattern**: MVVM architecture

## Testing

### Run All Tests
```bash
xcodebuild -scheme talkie -destination 'platform=iOS Simulator,name=iPhone 15' test
```

### Test Targets
- `talkieTests/` - Unit tests
- `talkieUITests/` - UI/Integration tests

## Building

### Debug Build
```bash
xcodebuild -scheme talkie -configuration Debug build
```

### Release Build
```bash
xcodebuild -scheme talkie -configuration Release archive
```

## Common Tasks

### Adding a New View
1. Right-click `Views/` folder in Xcode
2. New File > SwiftUI View
3. Name your view (e.g., `SettingsView.swift`)

### Modifying Data Model
1. Open `Resources/talkie.xcdatamodeld`
2. Add/modify entities and attributes
3. Update model version if needed for migration

## Troubleshooting

**Build Errors After Restructuring**:
- Clean build folder: `Cmd+Shift+K`
- If files are red in Xcode, re-add them from Finder

**Core Data Issues**:
- Delete app from simulator
- Clean build folder
- Rebuild and run

## Next Steps

- [ ] Implement core features
- [ ] Add unit test coverage
- [ ] Set up CI/CD
- [ ] Add app icon and launch screen
