#!/bin/bash
# Quick launcher for TalkieRunner
cd "$(dirname "$0")"
swift build -c release 2>/dev/null && .build/release/TalkieRunner
