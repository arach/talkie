//
//  SmartAction.swift
//  Talkie
//
//  Smart action definitions with detailed prompt templates for text transformation
//

import Foundation

/// A smart action with an icon, name, and detailed prompt template
struct SmartAction: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let defaultPrompt: String

    static func == (lhs: SmartAction, rhs: SmartAction) -> Bool {
        lhs.id == rhs.id
    }

    /// Built-in smart actions with curated prompt templates
    static let builtIn: [SmartAction] = [
        SmartAction(
            id: "fix_grammar",
            name: "Fix Grammar",
            icon: "textformat.abc",
            defaultPrompt: """
            Fix grammar, spelling, and punctuation errors in this text.

            Guidelines:
            - Preserve the original voice, tone, and style
            - Keep casual language if the text is informal
            - Don't change the meaning or add new content
            - Fix run-on sentences and fragments
            - Correct subject-verb agreement

            Return only the corrected text, nothing else.
            """
        ),
        SmartAction(
            id: "concise",
            name: "Concise",
            icon: "arrow.down.right.and.arrow.up.left",
            defaultPrompt: """
            Make this text more concise and direct.

            Guidelines:
            - Remove redundant words and phrases
            - Eliminate filler words (um, uh, like, basically, actually)
            - Combine sentences where appropriate
            - Keep the core message and all important details
            - Aim for 30-50% reduction in length
            - Maintain the original tone

            Return only the shortened text, nothing else.
            """
        ),
        SmartAction(
            id: "professional",
            name: "Professional",
            icon: "briefcase",
            defaultPrompt: """
            Rewrite this text in a professional tone suitable for business communication.

            Guidelines:
            - Use formal but not stiff language
            - Remove slang, casual expressions, and filler words
            - Structure sentences clearly
            - Be direct and confident
            - Maintain politeness without being overly formal
            - Keep the original meaning intact

            Return only the rewritten text, nothing else.
            """
        ),
        SmartAction(
            id: "bullet_points",
            name: "Bullet Points",
            icon: "list.bullet",
            defaultPrompt: """
            Convert this text into clear, organized bullet points.

            Guidelines:
            - Extract the key points and organize them logically
            - Use parallel structure for bullets
            - Keep each bullet concise (1-2 sentences max)
            - Group related points together with headers if needed
            - Don't add information that wasn't in the original
            - Preserve important details and nuances

            Return only the bulleted list, nothing else.
            """
        )
    ]

    /// Get a smart action by ID
    static func action(id: String) -> SmartAction? {
        builtIn.first { $0.id == id }
    }

    /// Convert a Workflow to a SmartAction (extracts prompt from first LLM step)
    static func from(workflow: Workflow) -> SmartAction? {
        // Find the first LLM step to extract the prompt
        guard let firstStep = workflow.steps.first(where: { $0.type == .llm }),
              case .llm(let config) = firstStep.config else {
            return nil
        }

        return SmartAction(
            id: workflow.id.uuidString,
            name: workflow.name,
            icon: workflow.icon,
            defaultPrompt: config.prompt
        )
    }

    /// Get combined actions for interstitial: custom actions from WorkflowService + built-in actions
    @MainActor
    static func combinedActions(sourceAppBundleID: String? = nil) -> [SmartAction] {
        let workflowService = WorkflowService.shared
        let customActions = workflowService.actionsForInterstitial(sourceAppBundleID: sourceAppBundleID)
            .compactMap { SmartAction.from(workflow: $0) }

        // Custom actions first, then built-in
        return customActions + builtIn
    }

    /// Get combined actions for drafts: custom actions from WorkflowService + built-in actions
    /// - Parameter appPreset: Optional app preset to filter by (e.g., "Email", "Code")
    @MainActor
    static func combinedActionsForDrafts(appPreset: String? = nil) -> [SmartAction] {
        let workflowService = WorkflowService.shared
        let customActions = workflowService.actionsForDrafts(appPreset: appPreset)
            .compactMap { SmartAction.from(workflow: $0) }

        // Custom actions first, then built-in
        return customActions + builtIn
    }

    /// Get available app presets for the drafts picker
    @MainActor
    static var availableAppPresets: [String] {
        WorkflowService.shared.availableAppPresets()
    }
}
