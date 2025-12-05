# Talkie

A multi-platform voice memo application with intelligent workflow automation.

**[Security Model](SECURITY.md)** | **[Implementation Notes](IMPLEMENTATION_SUMMARY.md)** | **[Website](https://usetalkie.com)**

<p align="center">
  <img src="Landing/public/screenshots/iphone-16-pro-max-1.png" alt="Talkie - Voice Memos + AI" width="280"/>
</p>

## Overview

Talkie transforms voice memos into actionable outputs through customizable workflows. Record a thought, and let AI-powered workflows summarize it, extract tasks, create calendar events, or pipe it through your favorite CLI tools.

### Key Features

- **Voice Recording**: Quick capture with push-to-talk or tap-to-record
- **Apple Transcription**: On-device speech-to-text via Apple Speech framework
- **Workflow Automation**: Chain together LLM processing, shell commands, and integrations
- **CLI Integration**: Run tools like `claude`, `gh`, `jq` with full access to your configured environment
- **Apple Ecosystem**: Native integration with Notes, Reminders, Calendar

## Project Structure

```
talkie/
├── iOS/              # iOS application (SwiftUI)
├── macOS/            # macOS application (SwiftUI)
├── Backend/          # Backend API services (planned)
├── Landing/          # Marketing website
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

### macOS App

The macOS app includes the full workflow system:

```bash
cd macOS
open Talkie.xcodeproj
```

**Workflow Features**:
- Multi-step workflow builder
- LLM integration (Gemini, OpenAI, Anthropic, Groq)
- Shell command execution with security controls
- Apple integrations (Notes, Reminders, Calendar)
- Webhook support for external services

See [SECURITY.md](SECURITY.md) for details on the shell execution security model.

### Planned Components
- **Backend**: API services for cross-platform sync
- **Shared**: Common protocols and data structures

## Contributing

When making changes:
1. Create a feature branch
2. Make your changes with tests
3. Submit a pull request

## License

[Add your license here]
