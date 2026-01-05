#!/bin/bash
# Bump version across all projects
# Usage: ./scripts/bump-version.sh [major|minor|patch] or ./scripts/bump-version.sh 1.7.15

VERSION_FILE="$(dirname "$0")/../VERSION"
CURRENT=$(cat "$VERSION_FILE" | tr -d '\n')

if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    NEW_VERSION="$1"
elif [[ "$1" == "patch" ]]; then
    NEW_VERSION=$(echo "$CURRENT" | awk -F. '{print $1"."$2"."$3+1}')
elif [[ "$1" == "minor" ]]; then
    NEW_VERSION=$(echo "$CURRENT" | awk -F. '{print $1"."$2+1".0"}')
elif [[ "$1" == "major" ]]; then
    NEW_VERSION=$(echo "$CURRENT" | awk -F. '{print $1+1".0.0"}')
else
    echo "Current version: $CURRENT"
    echo "Usage: $0 [major|minor|patch|X.Y.Z]"
    exit 0
fi

echo "Bumping version: $CURRENT -> $NEW_VERSION"

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Update Talkie project.yml
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" "$(dirname "$0")/../macOS/Talkie/project.yml"

# Update Talkie pbxproj
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" "$(dirname "$0")/../macOS/Talkie/Talkie.xcodeproj/project.pbxproj"

# Update TalkieLive project.yml if exists
if [ -f "$(dirname "$0")/../macOS/TalkieLive/project.yml" ]; then
    sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" "$(dirname "$0")/../macOS/TalkieLive/project.yml"
fi

# Update TalkieEngine project.yml if exists
if [ -f "$(dirname "$0")/../macOS/TalkieEngine/project.yml" ]; then
    sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" "$(dirname "$0")/../macOS/TalkieEngine/project.yml"
fi

echo "Updated to $NEW_VERSION"
