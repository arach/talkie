# Workflow → Skill rename inventory (Subtask A)

**Status:** inventory only · 2026-05-20  
**Scope:** Swift files under `apps/macos/Talkie` and `apps/macos/TalkieAgent`  
**Spec read first:** `docs/planning/2026-05-20-skill-presentation-spec.md`

## Scope and method

- Searched `apps/macos/Talkie` and `apps/macos/TalkieAgent` Swift sources for case-insensitive `workflow` string literals and reviewed the surrounding code.
- This is an inventory only. No source files were edited.
- Proposed replacements follow the pinned spec: user-facing top-level concept becomes **Skill(s)**; **Workflow** stays only as an advanced mode/editor concept and in internal data/model/API names.
- Confidence means "safe for the rename pass" rather than product recommendation:
  - **high**: clearly user-facing copy that refers to the top-level automation concept.
  - **medium**: likely user-facing, but debug/log/legacy/editor/import context may deserve a human skim before editing.

## 1. Rename candidates

### Primary navigation, routing, and companion shortcuts

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Components/TalkieChromeBar.swift:53` | `Workflows` | `Skills` | high | Primary chrome nav slot; keep `.workflows` section enum. |
| `apps/macos/Talkie/Views/AppNavigation.swift:550` | `Workflows` | `Skills` | high | Narrow-layout content sheet title. |
| `apps/macos/Talkie/Views/AppNavigation.swift:880` | `Workflows` | `Skills` | high | Sidebar item title. |
| `apps/macos/Talkie/Views/AppNavigation.swift:1125` | `Workflows` | `Skills` | high | Section wrapper title for `.workflows`. |
| `apps/macos/Talkie/Views/AppNavigation.swift:1989` | `Workflows` | `Skills` | high | Menu/button label navigating to `.workflows`. |
| `apps/macos/Talkie/Views/CommandPalette/PaletteCommand.swift:112` | `Go to Workflows` | `Go to Skills` | high | Command palette title. |
| `apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift:1114` | `Workflow` | `Skill` | high | Paired-device shortcut title. |
| `apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift:1115` | `Open your workflow picker on the Mac.` | `Open your skill picker on the Mac.` | high | Paired-device shortcut subtitle. |
| `apps/macos/Talkie/Services/SystemRoutes.swift:195` | `Navigate to workflows view` | `Navigate to skills view` | medium | Route metadata; keep route path `workflows` unless separately changing URLs. |
| `apps/macos/Talkie/Services/TalkieServer.swift:1648` | `Workflows opened` | `Skills opened` | medium | Companion shortcut response. |
| `apps/macos/TalkieAgent/TalkieAgent/Views/Settings/ConnectionsSettingsSection.swift:213` | `Memos, Workflows & Dictations` | `Memos, Skills & Dictations` | high | TalkieAgent settings card. |
| `apps/macos/TalkieAgent/TalkieAgent/Services/VoiceNavigationHandler.swift:68` | `workflows` | `skills` | medium | Voice-navigation keyword; consider accepting both `workflows` and `skills` during transition. |

### Home, Learn, onboarding, migration, and global surfaces

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Debug/DesignAuditor.swift:94` | `Workflows` | `Skills` | medium | Debug/design-audit screen title. |
| `apps/macos/Talkie/Debug/DesignAuditor.swift:197` | `Workflows` | `Skills` | medium | Debug/design-audit section label. |
| `apps/macos/Talkie/Services/OnboardingProgressManager.swift:51` | `Workflow wizard!` | `Skill wizard!` | medium | Deprecated/legacy onboarding manager, but user copy if surfaced. |
| `apps/macos/Talkie/Services/OnboardingProgressManager.swift:121` | `Discover Workflows` | `Discover Skills` | medium | Deprecated/legacy onboarding tip. |
| `apps/macos/Talkie/Services/OnboardingProgressManager.swift:130` | `Create custom workflows to automate your voice-to-text pipeline` | `Create custom skills to automate your voice-to-text pipeline` | medium | Deprecated/legacy onboarding tip body. |
| `apps/macos/Talkie/Services/Notch/NotchCommunicationView.swift:110` | `Workflow` | `Skill` | medium | Notch/demo module source label. |
| `apps/macos/Talkie/Services/Notch/NotchCommunicationView.swift:113` | `Workflow Queue` | `Skill Queue` | medium | Notch/demo module title. |
| `apps/macos/Talkie/Services/ScreenshotCaptureService.swift:31` | `Smallest files. Downscales aggressively for AI workflows.` | `Smallest files. Downscales aggressively for AI skills.` | high | Screenshot preset detail shown in settings. |
| `apps/macos/Talkie/Views/Home/HomeGrid.swift:500` | `Workflows` | `Skills` | high | Home action card. |
| `apps/macos/Talkie/Views/Home/HomeGrid.swift:797` | `Workflows` | `Skills` | high | Home card metadata title. |
| `apps/macos/Talkie/Views/Home/HomeGrid.swift:797` | `Open workflow automation.` | `Open skill automation.` | high | Home card metadata detail. |
| `apps/macos/Talkie/Views/Home/HomeGrid.swift:805` | `Open workflow and insight activity.` | `Open skill and insight activity.` | medium | Trending widget detail. |
| `apps/macos/Talkie/Views/Home/HomeGrid.swift:819` | `Workflow Runs` | `Skill Runs` | high | Home feature-card title. |
| `apps/macos/Talkie/Views/Home/HomeGrid.swift:819` | `Open workflow runs.` | `Open skill runs.` | high | Home feature-card detail. |
| `apps/macos/Talkie/Views/Home/HomeGridCards.swift:2379` | `WORKFLOW RUNS` / `Workflow Runs` | `SKILL RUNS` / `Skill Runs` | high | All-caps toggle card title. |
| `apps/macos/Talkie/Views/Home/HomeGridCards.swift:2392` | `Run a workflow to see results here` | `Run a skill to see results here` | high | Empty state. |
| `apps/macos/Talkie/Views/Home/HomeGridCards.swift:2574` | `Workflows` | `Skills` | high | Preview/demo home card. |
| `apps/macos/Talkie/Views/Home/HomeLayoutConfig.swift:57` | `Record, workflows, settings` | `Record, skills, settings` | high | Home layout customization description. |
| `apps/macos/Talkie/Views/Home/HomeLayoutConfig.swift:60` | `Captures, workflows, agent` | `Captures, skills, agent` | high | Home layout customization description. |
| `apps/macos/Talkie/Views/Home/HomeLayoutConfig.swift:208` | `Workflows` | `Skills` | high | Home card label. |
| `apps/macos/Talkie/Views/Home/HomeLayoutConfig.swift:219` | `Workflow Runs` | `Skill Runs` | high | Home card label. |
| `apps/macos/Talkie/Views/Home/HomeWidgets.swift:263` | `Workflows` | `Skills` | high | Quick Actions widget demo. |
| `apps/macos/Talkie/Views/Home/ScopeHomeView.swift:241` | `Workflows` | `Skills` | high | Scope home routines panel title. |
| `apps/macos/Talkie/Views/Home/ScopeHomeView.swift:244` | `MANAGE WORKFLOWS` | `MANAGE SKILLS` | high | Scope home panel footer CTA. |
| `apps/macos/Talkie/Views/Learn/ScopeLearnScreen.swift:156` | `Workflows` | `Skills` | high | Learn feature card name; keep glyph case `.workflows`. |
| `apps/macos/Talkie/Views/Learn/ScopeLearnScreen.swift:278` | `How do workflows trigger?` | `How do skills trigger?` | high | Suggested prompt. |
| `apps/macos/Talkie/Views/Learn/ScopeLearnScreen.swift:334` | `How do workflows trigger?` | `How do skills trigger?` | high | Stub-answer match string must change with suggestion. |
| `apps/macos/Talkie/Views/Learn/ScopeLearnScreen.swift:335` | `Open Workflows` | `Open Skills` | high | Stub-answer quick link. |
| `apps/macos/Talkie/Views/Live/History/HistoryView.swift:2927` | `Run a workflow` | `Run a skill` | high | Live history action description. |
| `apps/macos/Talkie/Views/Migration/MigrationView.swift:78` | `Memos, transcripts, workflows, and audio files` | `Memos, transcripts, skills, and audio files` | medium | Migration copy; data still includes workflow tables/files. |
| `apps/macos/Talkie/Views/Onboarding/PermissionsSetupView.swift:80` | `Read app context for workflows` | `Read app context for skills` | high | Onboarding permission copy. |
| `apps/macos/Talkie/Views/Onboarding/PermissionsSetupView.swift:145` | `Read app context for workflows` | `Read app context for skills` | high | Onboarding permission copy in second layout. |
| `apps/macos/Talkie/Views/PendingActionsScreen.swift:100` | `Workflows will appear here while running` | `Skills will appear here while running` | high | Pending Actions empty state; keep `Actions` naming. |
| `apps/macos/Talkie/Views/RecordingPowerInspector.swift:234` | `SYNC & WORKFLOWS` | `SYNC & SKILLS` | medium | Debug/power inspector section. |
| `apps/macos/Talkie/Views/LogsScreen.swift:77` | `WORKFLOW` | `SKILL` | medium | System-event enum raw value; check persistence/back-compat before editing. |
| `apps/macos/Talkie/Views/LogsScreen.swift:86` | `WORKFLOW` | `SKILL` | medium | Visible log chip label. |

### Activity log / AI results / run history

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:60` | `All workflow runs across your memos` | `All skill runs across your memos` | high | Activity log subtitle. |
| `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:91` | `Run workflows on your memos` | `Run skills on your memos` | high | Empty state. |
| `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:141` | `Choose a workflow run to view details` | `Choose a skill run to view details` | high | Empty detail state. |
| `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:655` | `View workflow execution history and results.` | `View skill execution history and results.` | high | Activity log landing copy. |
| `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:662` | `Coming soon: Activity log with workflow execution history` | `Coming soon: Activity log with skill execution history` | high | Placeholder copy. |
| `apps/macos/Talkie/Views/Activity/ActivityLogViews.swift:112` | `Run workflows on your memos` | `Run skills on your memos` | high | Empty state. |
| `apps/macos/Talkie/Views/Activity/ActivityLogViews.swift:128` | `Workflow` | `Skill` | high | Table column header; keep `workflowName` data property. |
| `apps/macos/Talkie/Views/Activity/ActivityLogViews.swift:511` | `Retry this workflow run` | `Retry this skill run` | high | Button help text. |

### Settings: Automations, Quick Actions, Context Actions, model/output/permissions

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:39` | `Configure event-triggered and scheduled workflow automation.` | `Configure event-triggered and scheduled skill automation.` | high | Settings page header. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:74` | `Run workflows automatically based on events or schedules.` | `Run skills automatically based on events or schedules.` | high | Master toggle detail. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:130` | `Create automations to run workflows when events occur or on a schedule.` | `Create automations to run skills when events occur or on a schedule.` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:173` | `Workflows that run on every synced memo. Use Automations above for more control.` | `Skills that run on every synced memo. Use Automations above for more control.` | high | Legacy quick auto-run disclosure copy. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:190` | `Detects "Hey Talkie" voice commands and routes to workflows` | `Detects "Hey Talkie" voice commands and routes to skills` | high | Hey Talkie auto-run explanation. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:232` | `Add Workflow` | `Add Skill` | high | Auto-run menu button. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:329` | `Unknown Workflow` | `Unknown Skill` | high | Fallback name in automation row. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:569` | `Workflow` | `Skill` | high | Add automation sheet section title. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:570` | `Run Workflow` | `Run Skill` | high | Add automation picker label. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:571` | `Select a workflow...` | `Select a skill...` | high | Add automation picker placeholder. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:741` | `Workflow` | `Skill` | high | Edit automation sheet section title. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:742` | `Run Workflow` | `Run Skill` | high | Edit automation picker label. |
| `apps/macos/Talkie/Views/Settings/AutomationsSettings.swift:743` | `Select a workflow...` | `Select a skill...` | high | Edit automation picker placeholder. |
| `apps/macos/Talkie/Views/Settings/BridgeSettingsView.swift:180` | `LIVE WORKFLOWS` | `LIVE SKILLS` | high | Bridge settings section title. |
| `apps/macos/Talkie/Views/Settings/BridgeSettingsView.swift:195` | `Let this Mac register with your Talkie account and claim queued live workflows. When it is idle, it only checks in every \(idlePollIntervalLabel).` | `Let this Mac register with your Talkie account and claim queued live skills. When it is idle, it only checks in every \(idlePollIntervalLabel).` | high | Bridge settings explanatory copy. |
| `apps/macos/Talkie/Views/Settings/BridgeSettingsView.swift:202` | `Enable Workflow Executor` | `Enable Skill Executor` | high | Toggle title. |
| `apps/macos/Talkie/Views/Settings/BridgeSettingsView.swift:206` | `This Mac can register itself as an executor and claim eligible workflow runs for your account.` | `This Mac can register itself as an executor and claim eligible skill runs for your account.` | high | Toggle detail. |
| `apps/macos/Talkie/Views/Settings/BridgeSettingsView.swift:253` | `Workflow` | `Skill` | high | Active status row label. |
| `apps/macos/Talkie/Views/Settings/CameraSettingsView.swift:715` | `Defaults start small for AI workflows. Raise this only when you need sharper saved captures.` | `Defaults start small for AI skills. Raise this only when you need sharper saved captures.` | high | Screenshot storage copy. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:441` | `One-tap workflow buttons after recording or in drafts.` | `One-tap skill buttons after recording or in drafts.` | high | Consumer summary card. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:442` | `Workflow buttons available from context-aware surfaces.` | `Skill buttons available from context-aware surfaces.` | high | Pro summary card. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:446` | `No workflow buttons are configured yet.` | `No skill buttons are configured yet.` | high | Empty preview. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:447` | `No workflow actions are configured for these contexts.` | `No skill actions are configured for these contexts.` | medium | Keeps `actions` tier; only changes `workflow`. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3776` | `Buttons are one-tap workflows` | `Buttons are one-tap skills` | high | Context Actions explainer. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3780` | `Choose which workflows should appear right after recording or while editing in drafts.` | `Choose which skills should appear right after recording or while editing in drafts.` | high | Context Actions explainer. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3781` | `Actions are workflows packaged as buttons. When you enable a workflow for a specific context (interstitial or drafts), it becomes an action—a one-tap transformation for your text.` | `Actions are skills packaged as buttons. When you enable a skill for a specific context (interstitial or drafts), it becomes an action—a one-tap transformation for your text.` | high | Explicitly preserves `Actions`. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3852` | `AVAILABLE WORKFLOWS` / `WORKFLOWS` | `AVAILABLE SKILLS` / `SKILLS` | high | Conditional section title. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3864` | `Choose where each workflow should show up as a button.` | `Choose where each skill should show up as a button.` | high | Context Actions copy. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3865` | `Toggle where each workflow appears as an action button.` | `Toggle where each skill appears as an action button.` | high | Context Actions copy. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3872` | `No workflows yet` | `No skills yet` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3874` | `Create a workflow to turn it into a button` | `Create a skill to turn it into a button` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3875` | `Create a workflow to use it as an action` | `Create a skill to use it as an action` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3895` | `New Workflow` | `New Skill` | high | New action/skill button. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3898` | `Create a custom LLM prompt workflow` | `Create a custom LLM prompt skill` | high | New action/skill button subtitle. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3948` | `Turn on "After Recording" for a workflow above to see it here` | `Turn on "After Recording" for a skill above to see it here` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3949` | `Enable "Interstitial" on a workflow above to see it here` | `Enable "Interstitial" on a skill above to see it here` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3999` | `Turn on "Drafts" for a workflow above to see it here` | `Turn on "Drafts" for a skill above to see it here` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:4000` | `Enable "Drafts" on a workflow above to see it here` | `Enable "Drafts" on a skill above to see it here` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/ScopeContextView.swift:345` | `One-tap workflow buttons after recording or in drafts.` | `One-tap skill buttons after recording or in drafts.` | high | Scope Context overview. |
| `apps/macos/Talkie/Views/Settings/DictationSettings.swift:551` | `Workflow Picker` | `Skill Picker` | high | Mac shortcut title. |
| `apps/macos/Talkie/Views/Settings/DictationSettings.swift:573` | `Jump into workflows on your Mac.` | `Jump into skills on your Mac.` | high | Mac shortcut subtitle. |
| `apps/macos/Talkie/Views/Settings/ModelLibrarySettings.swift:35` | `Configure cloud AI providers and speech models for workflows and smart features.` | `Configure cloud AI providers and speech models for skills and smart features.` | high | Model settings header copy. |
| `apps/macos/Talkie/Views/Settings/OutputSettings.swift:32` | `Configure default output location and path aliases for workflows.` | `Configure default output location and path aliases for skills.` | high | Output settings header copy. |
| `apps/macos/Talkie/Views/Settings/PermissionsSettings.swift:104` | `Needed when a workflow creates Apple Reminders` | `Needed when a skill creates Apple Reminders` | high | Permission description. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:22` | `Pin workflows to show them as quick actions when viewing a memo. Pinned workflows sync to iOS via iCloud and are backed by workflows/config.json.` | `Pin skills to show them as quick actions when viewing a memo. Pinned skills sync to iOS via iCloud and are backed by workflows/config.json.` | high | Preserve `Quick Actions`; config filename can stay literal. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:32` | `PINNED WORKFLOWS` | `PINNED SKILLS` | high | Section title. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:52` | `No workflows pinned` | `No skills pinned` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:55` | `Pin workflows from the list below to show them as quick actions.` | `Pin skills from the list below to show them as quick actions.` | high | Empty state. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:81` | `AVAILABLE WORKFLOWS` | `AVAILABLE SKILLS` | high | Section title. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:101` | `All workflows are pinned` | `All skills are pinned` | high | Empty/complete state. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:104` | `All your workflows are showing as quick actions.` | `All your skills are showing as quick actions.` | high | Empty/complete state. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:129` | `Pinned workflows sync to your iPhone via iCloud for quick access in the iOS app.` | `Pinned skills sync to your iPhone via iCloud for quick access in the iOS app.` | high | Sync note. |
| `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:210` | `Edit workflow` | `Edit skill` | high | Help text. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:21` | `WORKFLOWS` | `SKILLS` | high | Settings page title if this page survives as user-facing Skills settings. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:22` | `Manage and customize your workflow actions.` | `Manage and customize your skill actions.` | high | Settings page subtitle; keep `actions` tier. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:32` | `WORKFLOW LIBRARY` | `SKILL LIBRARY` | high | Section title. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:38` | `\(workflowService.workflows.count) WORKFLOWS` | `\(workflowService.workflows.count) SKILLS` | high | Counter label. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:50` | `+ \(workflowService.workflows.count - 5) more workflows` | `+ \(workflowService.workflows.count - 5) more skills` | high | Overflow count. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:122` | `Workflows currently run automatically or from Quick Actions. See Auto-Run and Quick Actions settings to configure.` | `Skills currently run automatically or from Quick Actions. See Auto-Run and Quick Actions settings to configure.` | high | Learn-more copy. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:210` | `View workflow execution history.` | `View skill execution history.` | high | Activity log settings subtitle. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:245` | `Track when workflows run, view results, and debug any issues. See which memos triggered which workflows.` | `Track when skills run, view results, and debug any issues. See which memos triggered which skills.` | high | Activity log settings body. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:260` | `Re-run failed workflows` | `Re-run failed skills` | high | Planned feature row. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:302` | `Manage which CLI tools can be executed by workflow shell steps.` | `Manage which CLI tools can be executed by skill shell steps.` | medium | Shell step is engine/advanced-editor terminology. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:394` | `Add executable paths above to allow them in Shell workflow steps.` | `Add executable paths above to allow them in Shell skill steps.` | medium | Shell step is engine/advanced-editor terminology. |

### TalkieObject / memo-detail action surfaces

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Database/LiveDictation.swift:106` | `Run Workflow` | `Run Skill` | high | Live dictation quick action display name. |
| `apps/macos/TalkieAgent/TalkieAgent/Database/LiveDictation.swift:106` | `Run Workflow` | `Run Skill` | high | TalkieAgent copy of the same quick action display name. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOActionBarSection.swift:100` | `Workflows` | `Skills` | high | Workflow picker action pill. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOActionBarSection.swift:132` | `Workflows` | `Skills` | high | Workflow picker action pill in standard actions. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:195` | `Run Workflow` | `Run Skill` | high | Picker sheet title. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:219` | `Search workflows...` | `Search skills...` | high | Picker search placeholder. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:246` | `No Workflows` | `No Skills` | high | Picker empty state. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:250` | `Create a workflow in Settings -> Workflows` | `Create a skill in Settings -> Skills` | high | Picker empty state. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:260` | `No matching workflows` | `No matching skills` | high | Picker search empty state. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:285` | `\(filteredWorkflows.count) workflow...` | `\(filteredWorkflows.count) skill...` | high | Picker count label; preserve pluralization logic. |
| `apps/macos/Talkie/Views/TalkieObject/Sections/TOTextProvenanceSection.swift:149` | `WORKFLOW` | `SKILL` | medium | Provenance badge for text generated by workflow/skill runtime. |

### Existing workflow-list/editor entry points outside the new Skills landing page

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Views/Workflows/ScopeWorkflowListColumn.swift:77` | `Workflows` | `Skills` | high | List column header; not the legacy editor title. |
| `apps/macos/Talkie/Views/Workflows/ScopeWorkflowListColumn.swift:96` | `New workflow` | `New skill` | high | Button help text. |
| `apps/macos/Talkie/Views/Workflows/ScopeWorkflowListColumn.swift:135` | `Untitled Workflow` | `Untitled Skill` | medium | Default name for newly created underlying `WorkflowDefinition`. |
| `apps/macos/Talkie/Views/Workflows/WorkflowColumnViews.swift:28` | `Workflows` | `Skills` | high | Column title. |
| `apps/macos/Talkie/Views/Workflows/WorkflowColumnViews.swift:119` | `Untitled Workflow` | `Untitled Skill` | medium | Default name. |
| `apps/macos/Talkie/Views/Workflows/WorkflowColumnViews.swift:181` | `NEW WORKFLOW` | `NEW SKILL` | high | Button label. |
| `apps/macos/Talkie/Views/Workflows/WorkflowColumnViews.swift:264` | `Untitled Workflow` | `Untitled Skill` | medium | Default name. |
| `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift:39` | `WORKFLOWS` | `SKILLS` | high | Content/list header. |
| `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift:108` | `NEW WORKFLOW` | `NEW SKILL` | high | Button label. |
| `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift:193` | `Untitled Workflow` | `Untitled Skill` | medium | Default name. |
| `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift:297` | `Run Workflow` | `Run Skill` | high | Run sheet title. |
| `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift:673` | `New Workflow` | `New Skill` | high | Template picker title. |
| `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift:707` | `Blank Workflow` | `Blank Skill` | high | Template picker blank option. |
| `apps/macos/Talkie/Workflow/WorkflowEditorViewModel.swift:203` | `Untitled Workflow` | `Untitled Skill` | medium | View-model default; verify legacy editor expectations before changing. |

### Runtime/system-event/error text that may surface to users

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Services/QuickActionRunner.swift:173` | `Workflow started` | `Skill started` | medium | App/system log entry. |
| `apps/macos/TalkieAgent/TalkieAgent/Services/QuickActionRunner.swift:194` | `Workflow started` | `Skill started` | medium | TalkieAgent app/system log entry. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:47` | `Check Settings > Workflows > Auto-run` | `Check Settings > Skills > Automations` | medium | System-event detail; exact settings path may need adjustment. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:72` | `[AUTO-RUN] No workflows configured` | `[AUTO-RUN] No skills configured` | medium | System-event title. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:72` | `Enable auto-run on workflows in Settings` | `Enable auto-run on skills in Settings` | medium | System-event detail. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:79` | `[AUTO-RUN] Found \(autoRunWorkflows.count) workflow(s)` | `[AUTO-RUN] Found \(autoRunWorkflows.count) skill(s)` | medium | System-event title. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:90` | `[AUTO-RUN] Workflow split` | `[AUTO-RUN] Skill split` | medium | System-event title. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:98` | `Running \(transcriptionWorkflows.count) workflow(s)` | `Running \(transcriptionWorkflows.count) skill(s)` | medium | System-event detail. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:103` | `Transcription workflow starting...` | `Transcription skill starting...` | medium | System-event detail. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:124` | `Running \(postTranscriptionWorkflows.count) workflow(s)` | `Running \(postTranscriptionWorkflows.count) skill(s)` | medium | System-event detail. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:129` | `Post-transcription workflow starting...` | `Post-transcription skill starting...` | medium | System-event detail. |
| `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:145` | `No transcript available for \(postTranscriptionWorkflows.count) workflow(s)` | `No transcript available for \(postTranscriptionWorkflows.count) skill(s)` | medium | System-event detail. |
| `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:217` | `Detects voice commands and routes to appropriate workflows` | `Detects voice commands and routes to appropriate skills` | high | Hey Talkie seed description. |
| `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:803` | `Good balance - most workflows` | `Good balance - most skills` | medium | Cost-tier description in editor/config UI. |
| `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:1342` | `Add it in Settings > Workflows > Allowed Commands.` | `Add it in Settings > Skills > Allowed Commands.` | medium | Validation error; exact settings path may change. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:300` | `Workflow '…' is no longer available.` | `Skill '…' is no longer available.` | medium | Retry error. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:305` | `The memo for workflow '…' is no longer available.` | `The memo for skill '…' is no longer available.` | medium | Retry error. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:458` | `TalkieServer workflow runtime is unavailable.` | `TalkieServer skill runtime is unavailable.` | medium | Runtime error; engine still called workflow internally. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:488` | `Workflow runtime returned an invalid response.` | `Skill runtime returned an invalid response.` | medium | Runtime error. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:521` | `Local workflow host failed to start.` | `Local skill host failed to start.` | medium | Runtime error; may actually refer to sidecar workflow host. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:533` | `Local workflow host was unreachable while running … Try rerunning the workflow or restarting Talkie.` | `Local skill host was unreachable while running … Try rerunning the skill or restarting Talkie.` | medium | Runtime error. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:547` | `Workflow runtime request failed …` | `Skill runtime request failed …` | medium | Runtime error. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:554` | `the workflow step` | `the skill step` | medium | Runtime error fallback label. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:1448` | `Apple Notes actions have been removed from Workflow Runner. Remove this step or replace it with another supported action.` | `Apple Notes actions have been removed from Skill Runner. Remove this step or replace it with another supported action.` | medium | Error text; `Workflow Runner` may be an internal engine name. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:1495` | `Calendar actions have been removed from Workflow Runner. Remove this step or replace it with another supported action.` | `Calendar actions have been removed from Skill Runner. Remove this step or replace it with another supported action.` | medium | Error text; `Workflow Runner` may be an internal engine name. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2309` | `…: No workflow mapped` | `…: No skill mapped` | medium | `executeWorkflows` result text. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2316` | `Executed workflow '…' for intent '…'` | `Executed skill '…' for intent '…'` | medium | `executeWorkflows` result text. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2327` | `Executed … workflow(s)` | `Executed … skill(s)` | medium | `executeWorkflows` summary. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2432` | `Voice memo must be transcribed before running workflows.` | `Voice memo must be transcribed before running skills.` | high | Localized error. |
| `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2434` | `Workflow execution failed: …` | `Skill execution failed: …` | high | Localized error. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneClient.swift:157` | `You need to sign into Talkie before this Mac can claim live workflows.` | `You need to sign into Talkie before this Mac can claim live skills.` | high | Localized error. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneClient.swift:361` | `Live workflow request failed …` | `Live skill request failed …` | medium | Localized/API error. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneClient.swift:362` | `Live workflow request failed: …` | `Live skill request failed: …` | medium | Localized/API error. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneService.swift:492` | `Sign into Talkie before this Mac can claim live workflows.` | `Sign into Talkie before this Mac can claim live skills.` | high | Localized error. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneService.swift:494` | `Live workflow run has an invalid workflow ID: …` | `Live skill run has an invalid skill ID: …` | medium | Error text; underlying API still uses workflow IDs. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneService.swift:496` | `Workflow … is not available on this Mac.` | `Skill … is not available on this Mac.` | high | Localized error. |
| `apps/macos/Talkie/Services/WorkflowControlPlaneService.swift:498` | `Live workflow run has an invalid memo ID: …` | `Live skill run has an invalid memo ID: …` | medium | Error text; underlying API still uses workflow IDs. |

### Agent console surface copy

| Occurrence | Current string | Proposed new string | Confidence | Notes |
|---|---|---|---|---|
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleModel.swift:45` | `…workflow surfaces in this workspace…` | `…skill/workflow surfaces in this workspace…` | medium | Starter prompt visible/editable in console; maybe keep if generated workspace still exposes workflow files. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleProfile.swift:30` | `…create or run workflows from the mounted workspace.` | `…create or run skills from the mounted workspace.` | medium | Console profile summary; generated docs still use workflow JSON. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleProfile.swift:76` | `…creating or running workflows with the mounted workspace loaded.` | `…creating or running skills with the mounted workspace loaded.` | medium | Console profile summary. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2524` | `Loading Talkie settings and workflow guides` | `Loading Talkie settings and skill guides` | medium | Console boot line; check generated guide filenames before editing. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2743` | `Configure Talkie, inspect mounted settings, and create or run workflows from this workspace.` | `Configure Talkie, inspect mounted settings, and create or run skills from this workspace.` | medium | Console guide copy. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2750` | `Run Workflows` | `Run Skills` | high | Console badge title. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2760` | `Loading Talkie config, workflow guides, and the mounted workspace before the terminal attaches.` | `Loading Talkie config, skill guides, and the mounted workspace before the terminal attaches.` | medium | Console loading copy; guide files still workflow-named today. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2771` | `…config and workflow tasks are ready…` | `…config and skill tasks are ready…` | medium | Console boot copy. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2792` | `Configure Talkie or Run Workflows` | `Configure Talkie or Run Skills` | high | Console inactive title. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2797` | `…workflow work from the same workspace.` | `…skill work from the same workspace.` | medium | Console inactive subtitle. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2807` | `Run Workflows` | `Run Skills` | high | Console inactive badge. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2829` | `Run workflows` | `Run skills` | high | Console suggested task heading in multiline text. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2830` | `Create, revise, or troubleshoot workflows in Live Config/workflow-user and explain what changed.` | `Create, revise, or troubleshoot skills in Live Config/workflow-user and explain what changed.` | medium | Keep path literal `workflow-user` unless storage is changed. |
| `apps/macos/Talkie/Views/Console/ConsoleScreen.swift:2842` | `Open config and workflow context` | `Open config and skill context` | medium | Console action subtitle. |

## 2. Keep as-is / out of scope for this rename pass

These occurrences should not be renamed mechanically in Subtask A/B because they are internal API, data model, storage, route, or explicit advanced-editor/WFKit vocabulary.

| Category | Examples / occurrences | Rationale |
|---|---|---|
| Internal types and model names | `WorkflowDefinition`, `WorkflowStep`, `WorkflowService`, `WorkflowFileRepository`, `WorkflowExecutor`, `WorkflowRunModel`, `WorkflowEventModel`, `WorkflowPreferences`, `WorkflowControlPlane*` across `apps/macos/Talkie/Workflow/**`, `apps/macos/Talkie/Data/**`, and views | Spec says Skills are a view over `WorkflowDefinition`; no data-model rename in this pass. |
| Internal enum/case/identifier names | `NavigationSection.workflows`, `.workflows`, `HomeCardType.actionWorkflows`, `featureWorkflowRuns`, `SystemEventType.workflow`, `QuickAction.runWorkflow`, `VoiceNavigationHandler` routing internals | Keep wire names unless a later API/storage migration is scoped. For visible labels tied to these identifiers, see candidates above. |
| Routes, URL paths, API paths, database/table names, storage keys | `workflows`, `/workflows/run`, `/workflows/host/execute-step`, `api/workflow-runs/...`, `workflow_runs`, `workflow_steps`, `workflow_events`, `workflow_preferences`, `pinnedWorkflows`, `workflows_v2`, `pendingWorkflowIds`, `workflow-picker`, `navigateWorkflows`, `browseWorkflows` | Data/API compatibility. Several user-facing labels can change while these remain stable. |
| File and directory names / generated workspace paths | `Views/Workflows/...`, `WorkflowTemplates`, `StarterWorkflows`, `Live Config/workflow-user`, `Live Config/workflow-system`, `WORKFLOW_AUTHORING.md`, `WORKFLOW_CAPABILITIES.md`, `WORKFLOW_GUIDE.md`, `WORKFLOW_STEP_CATALOG.json` | Paths are not user taxonomy unless explicitly shown as prose; preserve literal paths in copy. |
| WFKit / advanced graph schema labels | `apps/macos/Talkie/Workflow/TalkieWorkflowSchema.swift:883` `Target Workflow`, `:910` `Execute Workflows`, field ids such as `targetWorkflowId` | This is schema/advanced-editor vocabulary and may be public to WFKit/visualizer. Spec explicitly leaves WFKit/public API alone. |
| Step type raw/display names and config ids | `WorkflowStep.StepType.executeWorkflows`, `displayName: "Execute Workflows"`, config ids `targetWorkflowId`, `executeWorkflows`, template variables `{{WORKFLOW_NAME}}` | Engine/catalog names should not be renamed as part of copy-only pass. |
| Template variables and notification placeholders | `WorkflowDefinition.swift:753` `{{WORKFLOW_NAME}} Complete`, `:1618` `Workflow Complete`, `:1619` `{{WORKFLOW_NAME}} finished processing`, `WorkflowViews.swift:4061` / `:4072` examples | `WORKFLOW_NAME` is a variable contract. Human-facing defaults may be revisited with a migration/compat story, not a simple label pass. |
| Debug/log implementation text not intended as product copy | Startup signposts (`StartupCoordinator.swift:303` `Workflows`, `:332` `Workflow Control Plane`), repository/database migration logs, `WorkflowMigrationService` logs, `WorkflowStore` logs, `WorkflowService` logs, `WorkflowFileRepository` logs | Internal diagnostics. User-visible log chips/details are separately listed as medium-confidence candidates. |
| Import/store/service errors that quote data model | `WorkflowImportService`/`WorkflowStore` internals, `SimpleWorkflowLoader.swift:134` `Workflow file not found`, `WorkflowFileRepository.swift:493` `Workflow not found`, `WorkflowService.swift` migration strings | Mostly internal/developer-facing and tied to `.workflow.json` storage. |
| Existing `Action` terminology | `SmartAction`, `PendingActions`, `Quick Actions`, `ActionEditorSheet`, `Mac Actions`, `ComposeWorkflowAction`, `NodeType.action` | Spec says do **not** rename existing `Action` senses. Candidate rows only change `workflow` → `skill`, never `Action`. |
| Skills landing mode badge/copy | `apps/macos/Talkie/Views/Skills/ScopeSkillsLandingView.swift:1084` `WORKFLOW`, `:1124` `Yours · workflow`, `:1367` text describing `workflow (graduated into the legacy editor)` | Spec says `WORKFLOW` is a mode badge and can appear where advanced/legacy editor mode is relevant. |
| CoreData/debug record type labels | `apps/macos/Talkie/Views/Settings/iOSSettingsView.swift:2271` `Workflow`, `:2272` `WorkflowStep` | Debug/schema record type display, not product taxonomy. |
| Legacy/import comments | Comments such as `// Workflows`, file headers mentioning workflow, TODOs, and type/member names | Not user-visible copy. |

## 3. Ambiguous / needs human call

These are user-visible or semi-user-visible, but the right rename depends on whether that surface should speak product vocabulary (**Skill**) or engine/legacy vocabulary (**Workflow**).

| Occurrence | Current string | Possible new string | Why ambiguous |
|---|---|---|---|
| `apps/macos/Talkie/Views/Settings/AboutSettingsView.swift:130` | `Workflow Config` | `Skill Config` or keep | The value is `workflowControlPlaneConfigPath`; label may intentionally describe the legacy config file. |
| `apps/macos/Talkie/Views/Settings/AboutSettingsView.swift:517` | `Workflow Config: …` | `Skill Config: …` or keep | Debug-info export; same concern as row above. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:68` | `WORKFLOW BUILDER` | `SKILL BUILDER` or keep | If this card opens the legacy/advanced editor, Workflow may be intentional. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:89` | `Visual Workflow Editor` | keep, or `Visual Skill Editor` | Spec preserves the legacy `Workflow Editor` title; this is an entry-card title, not the editor title itself. |
| `apps/macos/Talkie/Views/Settings/WorkflowSettings.swift:93` | `Create custom workflows with a drag-and-drop interface…` | `Create custom skills…` or keep | Drag/drop graph editor may be the advanced Workflow escape hatch. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowImportView.swift:54` | `Import Workflow` | `Import Skill` | Import feature is URL/credential/Claw-oriented and may refer to an external legacy workflow format. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowImportView.swift:57` | `Paste a URL to import a workflow with credentials` | `Paste a URL to import a skill with credentials` | Same import-format ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowImportView.swift:195` | `Successfully imported workflow: …` | `Successfully imported skill: …` | Same import-format ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowImportView.swift:201` | `Failed to import workflow: …` | `Failed to import skill: …` | Same import-format ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowListView.swift:32` | `Workflows imported from external URLs. Used for 'Send to Claw' actions.` | `Skills imported from external URLs…` | External Claw terminology may still be Workflow. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowListView.swift:37` | `Import Workflow` | `Import Skill` | External import ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowListView.swift:55` | `No workflows connected` | `No skills connected` | External import ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowListView.swift:57` | `Import a workflow from tawkie.dev or another source` | `Import a skill from tawkie.dev or another source` | External import ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/WorkflowListView.swift:144` | `Delete Workflow?` | `Delete Skill?` | External import ambiguity. |
| `apps/macos/Talkie/Features/WorkflowImport/Views/SendToClawButton.swift:78` | `No Claw connected. Import a workflow first.` | `No Claw connected. Import a skill first.` | External Claw workflow terminology may be intentional. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:551` | `Workflow Visualization` | keep or `Skill Visualization` | Visualizer is tied to WFKit/advanced graph editor. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1131` | `Stops workflow if no match` | `Stops skill if no match` | Trigger-step detail inside the editor; may be advanced-engine vocabulary. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1236` | `Workflow name` | `Skill name` | In editor surface; decide whether this editor is legacy Workflow-only or a Skills view over `WorkflowDefinition`. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1290` | `What does this workflow do?` | `What does this skill do?` | Same editor-surface ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1389` | `Add steps to define workflow actions` | `Add steps to define skill actions` | Same editor-surface ambiguity; also preserves `actions`. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1389` | `This workflow has no steps yet` | `This skill has no steps yet` | Same editor-surface ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1544` | `New Workflow` / `Edit Workflow` | keep or `New Skill` / `Edit Skill` | Legacy sheet marked in code as legacy/kept for reference; spec only explicitly preserves legacy 3-column title. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1572` | `Workflow Name` | `Skill Name` | Same legacy sheet ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1581` | `What does this workflow do?` | `What does this skill do?` | Same legacy sheet ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1605` | `WORKFLOW STEPS` | keep or `SKILL STEPS` | Advanced editor/step-list terminology. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:1708` | `Add steps to define what this workflow does` | `Add steps to define what this skill does` | Legacy sheet/editor ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:2010` | `This saved workflow still contains a legacy Apple Notes step.` | `This saved skill still contains…` | Existing saved `.workflow.json` files may intentionally be called workflows in advanced editor. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:2017` | `This saved workflow still contains a legacy Calendar step.` | `This saved skill still contains…` | Same as above. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5024` | `Gates workflow execution` | `Gates skill execution` | Step config detail in advanced editor. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5257` | `Map intents to workflows. When an intent is detected, its target workflow will execute.` | `Map intents to skills…` | Product spec maps route mode to `intentExtract + executeWorkflows`, but advanced editor may expose engine wording. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5342` | `Will try to find a workflow matching …` | `Will try to find a skill matching …` | Same routing/advanced-editor ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5344` | `Intent will be logged but no workflow will execute` | `…no skill will execute` | Same routing/advanced-editor ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5346` | `…the selected workflow will execute` | `…the selected skill will execute` | Same routing/advanced-editor ambiguity. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5478` | `Target Workflow:` | keep or `Target Skill:` | WFKit/schema uses `Target Workflow`; editor copy may follow schema or product vocabulary. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5617` | `Run workflows concurrently` | `Run skills concurrently` | `executeWorkflows` step config; advanced engine vocabulary. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5635` | `Halt if any workflow fails` | `Halt if any skill fails` | Same step config. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5650` | `Workflow Routing` | `Skill Routing` or keep | Routing config inside `executeWorkflows`. |
| `apps/macos/Talkie/Workflow/WorkflowViews.swift:5652` | `…executes the workflow mapped to each intent's targetWorkflowId.` | `…executes the skill mapped…` or keep field name | Human text plus literal field-name coupling. |
| `apps/macos/Talkie/Services/Agents/TabPresets.swift:97` | `workflow authoring` | `skill authoring` or keep | Agent-console system prompt currently orients agents to `.workflow.json` authoring. |
| `apps/macos/Talkie/Services/Agents/TabPresets.swift:98` | `…before creating a workflow.` | `…before creating a skill.` or keep | Same generated-agent-doc ambiguity. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleProfile.swift:33` | `…before creating a workflow.` | `…before creating a skill.` or keep | Fallback prompt, not ordinary product UI. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleProfile.swift:37` | `Turn workflow requests into real workflow files…` | `Turn skill requests into real workflow files…` | Could bridge product wording to storage wording. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleProfile.swift:41` | `…closest workflow template.` | `…closest skill/workflow template.` | Agent workspace still mounts `Workflow Templates`. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentConsoleProfile.swift:45` | `…creating a workflow…Live Config/workflow-user…` | `…creating a skill…Live Config/workflow-user…` | Keep literal path. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentWorkspaceStore.swift:539-586` | Generated `# Workflow Guide` markdown | Keep, or add Skill-facing wrapper | This is documentation for file-backed `.workflow.json` internals. |
| `apps/macos/Talkie/Services/Agents/ManagedAgentWorkspaceStore.swift:597-620` | Generated `# Workflow Authoring` markdown | Keep, or change to `Skill Authoring` with storage caveats | Same generated-agent-doc ambiguity. |

## Quick implementation notes for the rename pass

- The safe first edit set is the **high-confidence candidates outside `Workflow/WorkflowViews.swift` and `Features/WorkflowImport`**.
- Keep `Action` labels as-is while changing phrases like `workflow actions` → `skill actions` where the noun is the top-level container.
- Keep internal symbols, route paths, database/storage keys, generated path names, and `{{WORKFLOW_NAME}}` template variables untouched unless a separate migration task is opened.
- Where a line contains both all-caps and title-case alternatives (for example `uiAllCaps ? "WORKFLOW RUNS" : "Workflow Runs"`), update both literals together.
