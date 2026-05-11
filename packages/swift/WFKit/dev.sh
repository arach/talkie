#!/bin/bash

# Kill any existing Workflow instances
pkill -f "Workflow" 2>/dev/null
sleep 0.5

# Build and run
swift build && swift run Workflow
