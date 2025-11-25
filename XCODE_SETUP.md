# Xcode Setup Instructions - Updated

## ✅ Architecture Change: macOS-Only LLM/AI

All LLM/AI functionality is now **macOS-only**:
- iOS: Recording + basic transcription + viewing
- macOS: All LLM providers, workflows, model management

## File Structure (Correct)

```
macOS/Talkie/
├── LLMProvider.swift          ✓ macOS only
├── MLXProvider.swift           ✓ macOS only
├── ModelsContentView.swift     ✓ macOS only
├── GeminiService.swift         ✓ macOS only
├── WorkflowExecutor.swift      ✓ macOS only
└── WorkflowAction.swift        ✓ macOS only

iOS/talkie/
├── (No LLM/Services files)    ✓ Recording & viewing only
└── Models/                     ✓ Core Data models
```

## Setup in Xcode

Since all files are now in `macOS/Talkie/`, they should be **automatically included** via file system synchronization.

### Step 1: Refresh Xcode

If you see "Cannot find type 'LLMProvider'" errors in Xcode:

1. **Close Xcode completely**
2. **Delete derived data**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/talkie-*
   ```
3. **Reopen Xcode**
4. **Product → Clean Build Folder** (Cmd+Shift+K)
5. **Product → Build** (Cmd+B)

### Step 2: Verify File Discovery

In Xcode Project Navigator, you should see all these files under `macOS/Talkie/`:
- ✓ LLMProvider.swift
- ✓ MLXProvider.swift
- ✓ ModelsContentView.swift
- ✓ GeminiService.swift
- ✓ WorkflowExecutor.swift

If any are missing, right-click `macOS/Talkie` folder → **Add Files to "talkie"...** → select the missing file.

### Step 3: (Optional) Add MLX Swift Package

To enable actual local model inference:

1. **File → Add Package Dependencies**
2. Enter URL: `https://github.com/ml-explore/mlx-swift`
3. Select version: `0.29.0` or later
4. Click "Add Package"
5. Select target: **Talkie** (macOS only!)
6. Click "Add Package"

Once added:
- Open `macOS/Talkie/MLXProvider.swift`
- Uncomment lines 12-15 (the MLX imports):
  ```swift
  import MLX
  import MLXRandom
  import MLXNN
  import MLXOptimizers
  ```

### Expected Result

After building, navigate to **Models** section in the macOS app:

✅ **Cloud Providers** section
- Gemini with API key configuration
- Shows configured/not configured status

✅ **Local Providers** section (Apple Silicon only)
- MLX model library
- 4 models available: Qwen 2.5 3B, Llama 3.2 3B, Mistral 7B, Phi 3.5 Mini
- Download buttons with progress tracking
- Install/Delete management

✅ **iOS app**
- Simple recording interface
- Basic transcription (native iOS)
- Viewing synced memos
- NO workflow/LLM functionality

## Troubleshooting

**"Cannot find type 'LLMProvider'" in Xcode:**
- Xcode hasn't refreshed file system sync
- Solution: Close Xcode, delete derived data, reopen

**Duplicate symbol errors:**
- Old files in iOS/talkie/Services/ still present
- Solution: Verify `iOS/talkie/Services/` directory doesn't exist

**Models section shows placeholder:**
- ModelsContentView.swift not in build
- Solution: Verify file is in `macOS/Talkie/` and Xcode sees it

**Command line builds work, Xcode doesn't:**
- Xcode cache issue
- Solution: Delete `~/Library/Developer/Xcode/DerivedData/talkie-*`

## Clean Architecture

**macOS (Talkie target):**
- Full LLM provider system
- MLX local inference
- Gemini cloud provider
- Workflow execution
- Model management UI

**iOS (talkie target):**
- Recording with AVFoundation
- Native iOS transcription (Speech framework)
- CloudKit sync for memos
- Display memos from macOS workflows
- NO LLM dependencies

This keeps iOS lightweight and puts all AI processing on macOS! 🎯
