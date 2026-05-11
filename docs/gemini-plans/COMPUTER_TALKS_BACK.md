# Computer Talks Back: Interactive Opportunities

## Overview

Moving beyond "Voice Memos" to "Voice Conversations". Integrating Text-to-Speech (TTS) allows Talkie to close the loop, verifying intent, providing summaries, and proactively notifying the user.

**Technical Foundation**: See `docs/specs/text-to-speech.md` for the implementation spec (TTSManager, Providers).

## Core Interaction Opportunities

### 1. The "Refinement" Loop (Conversational Repair)
Instead of just saving a potentially wrong transcript, Talkie can verify:
- **User**: "Email John about the project."
- **Talkie (TTS)**: "Which John? John Doe or John Smith?"
- **User**: "Smith."
- **Talkie**: "Drafting email to John Smith."

**Workflow Implementation**:
- New Workflow Step: `Ask for Input` (Speech-to-Text-to-Speech loop).
- Pause workflow execution until user responds.
- *Format*: Schema TBD (replacing legacy TWF).

### 2. Workflow Outputs ("Read it back")
For hands-free usage (driving, cooking):
- **User**: "Summarize this article..." (shares URL)
- **Talkie**: (Processes) -> (TTS) "Here's the summary: The article discusses..."
- **Benefit**: Turns Talkie into a personalized podcast/radio station.

### 3. Proactive "Nudges" & Notifications
If Talkie has context (Calendar, Reminders), it can speak without a direct prompt.
- **Scenario**: 5 minutes before a meeting.
- **Talkie**: "Heads up, you have 'Team Sync' in 5 minutes. Do you want to review the last meeting's notes?"
- **Trigger**: System Events / Calendar Observers -> Workflow Trigger -> TTS.

### 4. The "Daily Download"
A scheduled morning briefing workflow.
- **Trigger**: 8:00 AM or "Good Morning" voice command.
- **Content**:
    - Weather (API)
    - Calendar summary
    - Urgent tasks from yesterday
    - Random "Memory" from the Talkie database ("Remember 3 months ago you had an idea for...")
- **Output**: Synthesized audio stream (potentially mixing music/sound effects).

## Integration Points

### Workflow Editor Updates
- **New Step**: `Speak Text`
    - Input: Text (from variable or static).
    - Config: Voice ID, Speed, "Wait for finish" (bool).
- **New Step**: `Prompt User`
    - Input: Question to ask.
    - Output: User's spoken response (text).

*(Implementation pending definition of new Workflow schema)*

### UI/UX Considerations
- **Interruptibility**: User must be able to "barge in" (stop TTS by speaking or tapping).
- **Voice Persona**: Allow user to select a "Talkie Voice" that feels distinct from system Siri.
- **Visuals**: When computer is talking, show a waveform or visualizer so the user knows audio is coming from Talkie.

## "Ambient" Synergy
Combining "Ambient Mode" + "Computer Talks Back" = **Star Trek Computer**.
- "Computer, where is that file?"
- "It is in the Documents folder."

## Research & prototyping
- **Latency**: For conversational repair, latency must be <500ms. Cloud TTS might be too slow.
- **Local TTS**: Prioritize `TalkieEngine` integration of fast, local TTS (e.g., Piper or optimized MLX models) for the interactive loops.
