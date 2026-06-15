//
//  ScopeWorkflowStepList.swift
//  Talkie macOS
//

import SwiftUI
import Foundation
import TalkieKit

struct ScopeWorkflowStepList: View {
    let workflow: WorkflowDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { idx, step in
                ScopeWorkflowStepRow(index: idx, step: step, first: idx == 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
    }
}

private struct ScopeWorkflowStepRow: View {
    let index: Int
    let step: WorkflowStep
    let first: Bool

    private var stepNumber: String {
        let number = index + 1
        return number < 10 ? "0\(number)" : "\(number)"
    }

    private var headline: String {
        step.outputKey.isEmpty ? step.type.displayName : step.outputKey
    }

    private var details: ScopeStepDetails { step.scopeDetails }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { ScopeRule(.row) }

            VStack(alignment: .leading, spacing: 10) {
                // Headline row: N° · name · kind · disabled?
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(stepNumber)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                        .frame(width: 20, alignment: .leading)

                    Text(headline)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ScopeInk.primary)

                    Text("·")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)

                    Text(step.type.displayName.lowercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)

                    if !step.isEnabled {
                        Text("disabled")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                    }

                    Spacer()
                }

                // Config summary (provider · model · params)
                if let summary = details.summaryLine {
                    HStack(alignment: .top, spacing: 8) {
                        Spacer().frame(width: 20)
                        Text(summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }

                // WHEN clause
                if let cond = step.condition {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Spacer().frame(width: 20)
                        Text("when")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                        Text(cond.expression)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                // IN bindings
                ForEach(Array(details.inputs.enumerated()), id: \.offset) { _, token in
                    ScopeWorkflowBindingLine(direction: "in", token: token, type: nil, note: nil)
                }

                // OUT binding
                if !step.outputKey.isEmpty {
                    ScopeWorkflowBindingLine(
                        direction: "out",
                        token: step.outputKey,
                        type: details.outputTypeTag,
                        note: nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

private struct ScopeWorkflowBindingLine: View {
    let direction: String
    let token: String
    let type: String?
    let note: String?

    private var arrow: String { direction == "in" ? "←" : "→" }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Spacer().frame(width: 20)
            Text(direction)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
                .frame(width: 22, alignment: .leading)
            Text(arrow)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
            ScopeWorkflowTokenChip(text: token)
            if let type {
                ScopeWorkflowTypeTag(text: type)
            }
            if let note {
                Text("· \(note)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

private struct ScopeWorkflowTokenChip: View {
    let text: String

    var body: some View {
        Text("{\(text)}")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(ScopeBrass.solid)
    }
}

private struct ScopeWorkflowTypeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(ScopeInk.subtle)
    }
}

// MARK: - Step detail extraction
//
// Pulls a one-line summary, template-input tokens, and an output
// type tag out of a WorkflowStep's config. This is enough for the
// step row to render with the same density as the studio donor
// without modelling per-kind detail panes yet.

private struct ScopeStepDetails {
    let summaryLine: String?
    let inputs: [String]
    let outputTypeTag: String
}

private extension WorkflowStep {
    var scopeDetails: ScopeStepDetails {
        switch config {
        case .llm(let c):
            let provider = c.provider?.displayName ?? (c.autoRoute ? "auto" : "—")
            let model: String = {
                if let id = c.modelId, !id.isEmpty { return id }
                if let tier = c.costTier { return tier.displayName }
                return "auto"
            }()
            let summary = "\(provider) · \(model) · temp \(formatNum(c.temperature)) · max \(c.maxTokens)"
            var sources = [c.prompt]
            if let s = c.systemPrompt { sources.append(s) }
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: sources),
                outputTypeTag: "TXT"
            )

        case .shell(let c):
            let exe = (c.executable as NSString).lastPathComponent
            let summary = "\(exe) · timeout \(c.timeout)s\(c.captureStderr ? " · +stderr" : "")"
            var sources = c.arguments
            if let s = c.stdin { sources.append(s) }
            if let p = c.promptTemplate { sources.append(p) }
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: sources),
                outputTypeTag: "TXT"
            )

        case .transcribe(let c):
            let summary = "\(c.qualityTier.displayName) · \(c.primaryModel)"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: ["AUDIO"],
                outputTypeTag: "TXT"
            )

        case .speak(let c):
            let voice = c.voice ?? "default"
            let summary = "\(c.provider.displayName) · voice \(voice) · rate \(formatNum(Double(c.rate)))"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: [c.text]),
                outputTypeTag: "AUDIO"
            )

        case .trigger(let c):
            let head = c.phrases.first ?? ""
            let summary = "phrases [\(c.phrases.count)] · '\(head)' · \(c.searchLocation.displayName)"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: ["TRANSCRIPT"],
                outputTypeTag: "EVT"
            )

        case .intentExtract(let c):
            let summary = "input '\(c.inputKey)'"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: [c.inputKey],
                outputTypeTag: "JSON"
            )

        case .webhook(let c):
            let summary = "\(c.method.rawValue) \(c.url)"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: [c.url, c.bodyTemplate ?? ""]),
                outputTypeTag: "JSON"
            )

        case .conditional(let c):
            return ScopeStepDetails(
                summaryLine: "if \(c.condition)",
                inputs: scopeTemplateTokens(from: [c.condition]),
                outputTypeTag: "BOOL"
            )

        case .transform(let c):
            return ScopeStepDetails(
                summaryLine: "transform · \(c.operation.rawValue)",
                inputs: scopeTemplateTokens(from: Array(c.parameters.values)),
                outputTypeTag: "TXT"
            )

        default:
            return ScopeStepDetails(
                summaryLine: nil,
                inputs: [],
                outputTypeTag: scopeDefaultOutputTag(for: type)
            )
        }
    }
}

private func formatNum(_ value: Double) -> String {
    let style = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US_POSIX"))
        .grouping(.never)

    if value == value.rounded() {
        return value.formatted(style.precision(.fractionLength(0)))
    }

    return value.formatted(style.precision(.fractionLength(0...2)))
}

private func scopeTemplateTokens(from sources: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    let pattern = try? NSRegularExpression(pattern: "\\{\\{\\s*([A-Za-z0-9_.]+)\\s*\\}\\}")
    for src in sources where !src.isEmpty {
        let range = NSRange(src.startIndex..., in: src)
        pattern?.enumerateMatches(in: src, range: range) { match, _, _ in
            guard let m = match,
                  let r = Range(m.range(at: 1), in: src) else { return }
            let token = String(src[r])
            if !seen.contains(token) {
                seen.insert(token)
                ordered.append(token)
            }
        }
    }
    return ordered
}

private func scopeDefaultOutputTag(for type: WorkflowStep.StepType) -> String {
    switch type {
    case .transcribe, .speak: return "TXT"
    case .clipboard, .saveFile: return "TXT"
    case .webhook, .intentExtract, .conditional: return "JSON"
    case .notification, .iOSPush, .email, .appleNotes, .appleReminders, .appleCalendar: return "EVT"
    case .cloudUpload: return "URL"
    default: return "TXT"
    }
}
