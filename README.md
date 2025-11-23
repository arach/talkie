# Talkie

A multi-platform communication application with iOS, macOS, and backend components.

## Project Structure

```
talkie/
├── iOS/              # iOS application (SwiftUI)
├── macOS/            # macOS companion app (future)
├── Backend/          # Backend API services (future)
└── Shared/           # Shared code and protocols
```

## Getting Started

### iOS Development

Requirements:
- macOS 13.0+
- Xcode 14.0+
- Swift 5.9+

```bash
cd iOS
open talkie.xcodeproj
```

Run the app using Xcode's play button or:
```bash
cd iOS
xcodebuild -scheme talkie -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Project Architecture

**iOS App (`iOS/talkie/`)**:
- `App/` - Application entry point and configuration
- `Views/` - SwiftUI view components
- `Models/` - Data models and Core Data entities
- `Resources/` - Assets, Info.plist, and data models

**Testing**:
- `talkieTests/` - Unit tests
- `talkieUITests/` - UI/E2E tests

## Development

### iOS App Structure
- Built with SwiftUI
- Core Data for local persistence
- Follows MVC/MVVM architecture

### Future Components
- **macOS**: Native companion app for desktop
- **Backend**: API services for cross-platform sync
- **Shared**: Common protocols and data structures

## Contributing

When making changes:
1. Create a feature branch
2. Make your changes with tests
3. Submit a pull request

## License

[Add your license here]
