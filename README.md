# Talkie

![macOS](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)
![iOS](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License](https://img.shields.io/badge/License-EULA-lightgrey)

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

## Development

```bash
# iOS
open "iOS/Talkie OS.xcodeproj"

# macOS (Talkie Core)
open macOS/Talkie/Talkie.xcodeproj

# macOS (TalkieLive)
open macOS/TalkieLive/TalkieLive.xcodeproj

# macOS (TalkieEngine - transcription service)
open macOS/TalkieEngine/TalkieEngine.xcodeproj
```

## License

See [LICENSE](LICENSE) for details.
