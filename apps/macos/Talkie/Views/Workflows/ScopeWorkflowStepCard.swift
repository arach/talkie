//
//  ScopeWorkflowStepCard.swift
//  Talkie macOS
//
//  Cream-phosphor "instrument bay" rendering of a workflow step. Each
//  step type gets its own per-type body. LLM is the hero — rendered as
//  a dark bichromatic panel embedded in the cream desk, mirroring the
//  homepage's Agent Handoff panel. The other types stay on cream with
//  channel-tag chrome and graticule backing.
//
//  Mounted in place of WorkflowStepCard / WorkflowStepEditor's read
//  view when SettingsManager.shared.isScopeTheme is true.
//

import SwiftUI
import TalkieKit
import WFKit

// MARK: - Scope display font helper

/// Cormorant Garamond display font, with serif fallback. Sparse use
/// inside step cards — only the LLM hero's amber phosphor stat readout
/// reaches for it. Editor cards stay primarily monospaced chrome.
private enum ScopeStepFont {
    private static let regularCandidates = [
        "CormorantGaramond-Regular",
        "Cormorant Garamond",
        "CormorantGaramond",
    ]
    private static let mediumCandidates = [
        "CormorantGaramond-Medium",
        "Cormorant Garamond Medium",
    ]

    static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium ? mediumCandidates : regularCandidates) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }
}

// MARK: - Public card

struct ScopeWorkflowStepCard: View {
    let step: WorkflowStep
    let stepNumber: Int
    /// Total steps in the workflow. Used to render the per-step
    /// pipeline strip (S1 → S2 → S3). Defaults to 0, in which case the
    /// strip is hidden.
    let totalSteps: Int

    init(step: WorkflowStep, stepNumber: Int, totalSteps: Int = 0) {
        self.step = step
        self.stepNumber = stepNumber
        self.totalSteps = totalSteps
    }

    /// LLM is the hero — the only step rendered as a dark bichromatic
    /// instrument bay. Everything else stays on cream with subtler
    /// instrument chrome.
    private var isHero: Bool {
        if case .llm = step.config { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if totalSteps > 1 {
                pipelineStrip
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            headerStrip
                .padding(.horizontal, 14)
                .padding(.top, totalSteps > 1 ? 8 : 12)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ScopeEdge.faint).frame(height: 1)
                }

            // Body
            Group {
                if isHero, case .llm(let cfg) = step.config {
                    LLMHeroBody(config: cfg, stepNumber: stepNumber)
                } else {
                    creamBody
                        .padding(14)
                }
            }

            footerStrip
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(ScopeEdge.faint).frame(height: 1)
                }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ScopeCanvas.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ScopeEdge.normal, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if !step.isEnabled {
                Rectangle()
                    .fill(ScopeInk.subtle.opacity(0.5))
                    .frame(width: 2)
            } else if isHero {
                Rectangle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 2)
            }
        }
        .opacity(step.isEnabled ? 1.0 : 0.7)
    }

    // MARK: - Pipeline strip

    private var pipelineStrip: some View {
        HStack(spacing: 6) {
            ForEach(1...max(totalSteps, 1), id: \.self) { idx in
                pipelineToken(for: idx)
                if idx < totalSteps {
                    Rectangle()
                        .fill(idx < stepNumber ? ScopeAmber.solid.opacity(0.55) : ScopeEdge.faint)
                        .frame(width: 10, height: 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func pipelineToken(for idx: Int) -> some View {
        let active = idx == stepNumber
        return Text(String(format: "S%d", idx))
            .font(ScopeType.chrome)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(active ? ScopeAmber.solid : ScopeInk.subtle)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? ScopeAmber.tint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(active ? ScopeAmber.solid.opacity(0.45) : ScopeEdge.subtle, lineWidth: 0.5)
            )
    }

    // MARK: - Header

    private var headerStrip: some View {
        HStack(spacing: 10) {
            ChannelLabel(String(format: "S%02d", stepNumber),
                         color: isHero ? ScopeAmber.solid : ScopeInk.faint,
                         strokeColor: isHero ? ScopeAmber.solid.opacity(0.4) : ScopeEdge.normal)

            Image(systemName: step.type.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHero ? ScopeAmber.solid : ScopeInk.muted)
                .phosphorGlow(color: ScopeAmber.solid, radius: isHero ? 3 : 0, opacity: isHero ? 0.32 : 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.type.displayName.uppercased())
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.primary)
                Text(step.type.description)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopeInk.faint)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if !step.isEnabled {
                    statusPin("DISABLED", color: ScopeInk.subtle)
                } else if isHero {
                    statusPin("LIVE", color: ScopeAmber.solid, dot: true)
                }
                statusPin(step.type.category.rawValue.uppercased(), color: ScopeInk.subtle)
            }
        }
    }

    private func statusPin(_ text: String, color: Color, dot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dot {
                PhosphorDot(color: color, size: 5)
            }
            Text(text)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(color.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Cream body (everything except LLM)

    @ViewBuilder
    private var creamBody: some View {
        ZStack(alignment: .topLeading) {
            GraticuleBackground(pitch: 22, color: ScopeTrace.faint, opacity: 0.35)
                .allowsHitTesting(false)

            switch step.config {
            case .shell(let cfg):
                ShellScopeBody(config: cfg)
            case .webhook(let cfg):
                WebhookScopeBody(config: cfg)
            case .email(let cfg):
                EmailScopeBody(config: cfg)
            case .notification(let cfg):
                NotificationScopeBody(config: cfg)
            case .iOSPush(let cfg):
                iOSPushScopeBody(config: cfg)
            case .clipboard(let cfg):
                ClipboardScopeBody(config: cfg)
            case .saveFile(let cfg):
                SaveFileScopeBody(config: cfg)
            case .conditional(let cfg):
                ConditionalScopeBody(config: cfg)
            case .transform(let cfg):
                TransformScopeBody(config: cfg)
            case .transcribe(let cfg):
                TranscribeScopeBody(config: cfg)
            case .speak(let cfg):
                SpeakScopeBody(config: cfg)
            case .cloudUpload(let cfg):
                CloudUploadScopeBody(config: cfg)
            case .trigger(let cfg):
                TriggerScopeBody(config: cfg)
            case .intentExtract(let cfg):
                IntentExtractScopeBody(config: cfg)
            case .executeWorkflows(let cfg):
                ExecuteWorkflowsScopeBody(config: cfg)
            case .appleReminders(let cfg):
                AppleRemindersScopeBody(config: cfg)
            case .appleNotes:
                UnavailableScopeBody(message: "Apple Notes removed — replace this step.")
            case .appleCalendar:
                UnavailableScopeBody(message: "Calendar removed — replace this step.")
            case .llm:
                // Should not occur — hero path handles LLM.
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
    }

    // MARK: - Footer

    private var footerStrip: some View {
        HStack(spacing: 12) {
            footerKV("OUT", step.outputKey.isEmpty ? "—" : "{{\(step.outputKey)}}")
            if let condition = step.condition, !condition.expression.isEmpty {
                Rectangle().fill(ScopeEdge.faint).frame(width: 1, height: 10)
                footerKV("IF", condition.expression)
            }
            Spacer(minLength: 0)
            Text(String(format: "TRIG · S%02d / %@", stepNumber, step.type.rawValue.uppercased()))
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
        }
    }

    private func footerKV(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
            Text(value)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.normal)
                .foregroundStyle(ScopeInk.faint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - LLM Hero (dark instrument bay)

private struct LLMHeroBody: View {
    let config: LLMStepConfig
    let stepNumber: Int

    private var providerName: String {
        config.provider?.displayName.uppercased() ?? "AUTO ROUTE"
    }

    private var modelName: String {
        config.selectedModel?.name ?? config.modelId ?? "auto"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ScopePanel.bg)
            GraticuleBackground(pitch: 22, color: ScopePanel.traceFaint, opacity: 0.55)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                bayHeader

                HStack(alignment: .top, spacing: 0) {
                    statTile(value: providerName, label: "PROVIDER", isText: true)
                    tileDivider
                    statTile(value: modelName, label: "MODEL", isText: true)
                    tileDivider
                    statTile(value: String(format: "%.1f", config.temperature), label: "TEMP", isText: false)
                    tileDivider
                    statTile(value: "\(config.maxTokens)", label: "MAX TOK", isText: false)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)

                promptBlock
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                if let sys = config.systemPrompt, !sys.isEmpty {
                    Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
                    systemBlock(sys)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var bayHeader: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopePanel.trace, size: 5)
            Text(String(format: "RUNNING · S%02d / TALKIE.LLM", stepNumber))
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text(config.isAutoRouted ? "AUTO ROUTE · CHEAPEST AVAILABLE" : "LOCKED PROVIDER · DIRECT PATH")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
        }
    }

    private var tileDivider: some View {
        Rectangle()
            .fill(ScopePanel.Edge.faint)
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func statTile(value: String, label: String, isText: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isText {
                    Text(value.isEmpty ? "—" : value)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ScopePanel.trace)
                        .shadow(color: ScopePanel.traceGlow, radius: 3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(value)
                        .font(ScopeStepFont.display(size: 24, medium: true))
                        .foregroundStyle(ScopePanel.trace)
                        .shadow(color: ScopePanel.traceGlow, radius: 4)
                        .tracking(-0.4)
                }
            }
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("· PROMPT")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopePanel.trace)
                    .shadow(color: ScopePanel.traceGlow, radius: 3)
                Spacer()
                Text("CH-01 INPUT")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopePanel.inkSubtle)
            }
            Text(config.prompt.isEmpty ? "(no prompt set)" : config.prompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(config.prompt.isEmpty ? ScopePanel.inkSubtle : ScopePanel.inkDim)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func systemBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("· SYSTEM")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.traceDim)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ScopePanel.inkMuted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared cream-body primitives

/// Two-column key/value row, monospaced. The workhorse layout for
/// most step bodies.
private struct ScopeRow: View {
    let label: String
    let value: String
    var mono: Bool = true
    var emphasis: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .foregroundStyle(emphasis ? ScopeInk.primary : ScopeInk.dim)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline pill — like DetailBadge but on the Scope vocabulary.
private struct ScopePill: View {
    let text: String
    var amber: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(ScopeType.channel)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(amber ? ScopeAmber.solid : ScopeInk.faint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(amber ? ScopeAmber.tintSubtle : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(amber ? ScopeAmber.solid.opacity(0.4) : ScopeEdge.faint, lineWidth: 0.5)
            )
    }
}

/// Lined "instrument readout" surrounding a primary chunk of text
/// (a command, URL, content template, etc.).
private struct ScopeReadout: View {
    let text: String
    var placeholder: String = "(empty)"

    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(text.isEmpty ? ScopeInk.subtle : ScopeInk.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(ScopeCanvas.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(ScopeEdge.faint, lineWidth: 0.5)
            )
            .lineLimit(3)
    }
}

// MARK: - Per-type cream bodies

private struct ShellScopeBody: View {
    let config: ShellStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: "CLI", amber: true)
                ScopePill(text: "\(config.timeout)s")
                if config.stdin != nil {
                    ScopePill(text: "STDIN")
                }
                if !config.environment.isEmpty {
                    ScopePill(text: "ENV · \(config.environment.count)")
                }
                Spacer(minLength: 0)
            }

            ScopeReadout(text: "$ \(config.executable) \(config.arguments.joined(separator: " "))")

            if let cwd = config.workingDirectory, !cwd.isEmpty {
                ScopeRow(label: "CWD", value: cwd)
            }

            let validation = config.validate()
            if !validation.valid {
                HStack(spacing: 6) {
                    PhosphorDot(color: ScopeAmber.solid, size: 5)
                    Text(validation.errors.first ?? "VALIDATION FAILED")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                }
            }
        }
    }
}

private struct WebhookScopeBody: View {
    let config: WebhookStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: config.method.rawValue, amber: true)
                if config.includeTranscript { ScopePill(text: "TRANSCRIPT") }
                if config.includeMetadata { ScopePill(text: "META") }
                if config.auth != nil { ScopePill(text: "AUTH") }
                Spacer(minLength: 0)
            }
            ScopeReadout(text: config.url, placeholder: "(no endpoint)")
            if !config.headers.isEmpty {
                ScopeRow(label: "HEADERS", value: config.headers.keys.sorted().joined(separator: ", "))
            }
        }
    }
}

private struct EmailScopeBody: View {
    let config: EmailStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if config.isHTML { ScopePill(text: "HTML", amber: true) } else { ScopePill(text: "PLAIN") }
                Spacer(minLength: 0)
            }
            ScopeRow(label: "TO", value: config.to.isEmpty ? "—" : config.to, emphasis: true)
            if let cc = config.cc, !cc.isEmpty { ScopeRow(label: "CC", value: cc) }
            if let bcc = config.bcc, !bcc.isEmpty { ScopeRow(label: "BCC", value: bcc) }
            ScopeRow(label: "SUBJECT", value: config.subject.isEmpty ? "—" : config.subject)
            if !config.body.isEmpty {
                Text(config.body)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.muted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }
}

private struct NotificationScopeBody: View {
    let config: NotificationStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if config.sound { ScopePill(text: "SOUND", amber: true) } else { ScopePill(text: "SILENT") }
                if config.actionLabel != nil { ScopePill(text: "ACTION") }
                Spacer(minLength: 0)
            }
            ScopeRow(label: "TITLE", value: config.title.isEmpty ? "—" : config.title, emphasis: true)
            if !config.body.isEmpty {
                ScopeRow(label: "BODY", value: config.body)
            }
        }
    }
}

private struct iOSPushScopeBody: View {
    let config: iOSPushStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScopePill(text: "iOS", amber: true)
                if config.sound { ScopePill(text: "SOUND") }
                if config.includeOutput { ScopePill(text: "PAYLOAD") }
                Spacer(minLength: 0)
            }
            ScopeRow(label: "TITLE", value: config.title.isEmpty ? "—" : config.title, emphasis: true)
            if !config.body.isEmpty {
                ScopeRow(label: "BODY", value: config.body)
            }
        }
    }
}

private struct ClipboardScopeBody: View {
    let config: ClipboardStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScopePill(text: "PASTEBOARD", amber: true)
                Spacer(minLength: 0)
            }
            ScopeReadout(text: config.content)
        }
    }
}

private struct SaveFileScopeBody: View {
    let config: SaveFileStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScopePill(text: "DISK", amber: true)
                if config.appendIfExists { ScopePill(text: "APPEND") } else { ScopePill(text: "OVERWRITE") }
                Spacer(minLength: 0)
            }
            ScopeRow(label: "FILE", value: config.filename, emphasis: true)
            if let dir = config.directory, !dir.isEmpty {
                ScopeRow(label: "DIR", value: dir)
            }
            if !config.content.isEmpty {
                ScopeReadout(text: config.content)
            }
        }
    }
}

private struct ConditionalScopeBody: View {
    let config: ConditionalStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: "BRANCH", amber: true)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("IF")
                        .font(ScopeType.eyebrow)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                    Text(config.condition.isEmpty ? "(no condition)" : config.condition)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(config.condition.isEmpty ? ScopeInk.subtle : ScopeInk.primary)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 14) {
                branchTile(label: "THEN", count: config.thenSteps.count)
                SignalPath(color: ScopeAmber.solid, width: 22)
                branchTile(label: "ELSE", count: config.elseSteps.count)
                Spacer(minLength: 0)
            }
        }
    }

    private func branchTile(label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Text("\(count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(ScopeInk.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(ScopeEdge.normal, lineWidth: 0.5)
        )
    }
}

private struct TransformScopeBody: View {
    let config: TransformStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScopePill(text: config.operation.rawValue, amber: true)
                if !config.parameters.isEmpty {
                    ScopePill(text: "PARAM · \(config.parameters.count)")
                }
                Spacer(minLength: 0)
            }
            Text(config.operation.description)
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.muted)
            if !config.parameters.isEmpty {
                ScopeRow(label: "PARAMS",
                         value: config.parameters.keys.sorted().joined(separator: ", "))
            }
        }
    }
}

private struct TranscribeScopeBody: View {
    let config: TranscribeStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: config.qualityTier.displayName, amber: true)
                ScopePill(text: config.qualityTier == .fast ? "APPLE" : "ENGINE")
                if config.overwriteExisting { ScopePill(text: "OVERWRITE") }
                if config.saveAsVersion { ScopePill(text: "VERSIONED") }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Image(systemName: config.qualityTier.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.qualityTier.description)
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.dim)
                    Text("PRIMARY · \(config.primaryModel.uppercased())")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                }
            }
            if let fallback = config.effectiveFallbackModel {
                ScopeRow(label: "FALLBACK", value: fallback)
            }
        }
    }
}

private struct SpeakScopeBody: View {
    let config: SpeakStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: config.provider.displayName, amber: true)
                if config.playImmediately { ScopePill(text: "PLAY NOW") }
                if config.saveToFile { ScopePill(text: "SAVE") }
                if config.useCache { ScopePill(text: "CACHE") }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                statColumn(label: "RATE", value: String(format: "%.2f", config.rate))
                statColumn(label: "PITCH", value: String(format: "%.2f", config.pitch))
                if let voice = config.voice, !voice.isEmpty {
                    statColumn(label: "VOICE", value: voice)
                }
                Spacer(minLength: 0)
            }
            ScopeReadout(text: config.text)
        }
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(ScopeInk.primary)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
        }
    }
}

private struct CloudUploadScopeBody: View {
    let config: CloudUploadStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: config.provider.displayName, amber: true)
                ScopePill(text: config.contentType)
                if config.credentialId != nil { ScopePill(text: "CRED · OK") }
                Spacer(minLength: 0)
            }
            ScopeRow(label: "BUCKET", value: config.bucket.isEmpty ? "—" : config.bucket, emphasis: true)
            if let region = config.region, !region.isEmpty {
                ScopeRow(label: "REGION", value: region)
            }
            if let endpoint = config.endpoint, !endpoint.isEmpty {
                ScopeRow(label: "ENDPOINT", value: endpoint)
            }
            ScopeReadout(text: config.pathTemplate)
        }
    }
}

private struct TriggerScopeBody: View {
    let config: TriggerStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: "TRIGGER", amber: true)
                ScopePill(text: config.searchLocation.rawValue)
                if config.caseSensitive { ScopePill(text: "CASE") }
                if config.stopIfNoMatch { ScopePill(text: "GATE") }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("· PHRASES")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                if config.phrases.isEmpty {
                    Text("(none)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                } else {
                    FlowingPhrases(phrases: config.phrases)
                }
            }
            ScopeRow(label: "WINDOW", value: "\(config.contextWindowSize) WORDS")
        }
    }
}

private struct FlowingPhrases: View {
    let phrases: [String]

    var body: some View {
        // Lightweight wrapping — VStack of HStacks chunked at 3 per row.
        let chunks = phrases.chunked(into: 3)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                HStack(spacing: 6) {
                    ForEach(chunk, id: \.self) { phrase in
                        Text("\u{201C}\(phrase)\u{201D}")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ScopeAmber.tintSubtle)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(ScopeAmber.solid.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }
}

private struct IntentExtractScopeBody: View {
    let config: IntentExtractStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: config.extractionMethod.rawValue, amber: true)
                ScopePill(text: String(format: "CONF ≥ %.0f%%", config.confidenceThreshold * 100))
                Spacer(minLength: 0)
            }
            ScopeRow(label: "INPUT", value: config.inputKey)
            HStack(spacing: 6) {
                Text("\(config.recognizedIntents.filter { $0.isEnabled }.count)")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(ScopeInk.primary)
                Text("ACTIVE INTENT\(config.recognizedIntents.filter { $0.isEnabled }.count == 1 ? "" : "S")")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ExecuteWorkflowsScopeBody: View {
    let config: ExecuteWorkflowsStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ScopePill(text: config.parallel ? "PARALLEL" : "SEQUENTIAL", amber: true)
                if config.stopOnError { ScopePill(text: "STOP ON ERR") }
                Spacer(minLength: 0)
            }
            ScopeRow(label: "INTENTS", value: config.intentsKey)
            HStack(spacing: 8) {
                SignalPath(color: ScopeAmber.solid, width: 32)
                Text("FAN-OUT")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
        }
    }
}

private struct AppleRemindersScopeBody: View {
    let config: AppleRemindersStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScopePill(text: "REMINDERS", amber: true)
                if config.priority != .none { ScopePill(text: "P · \(config.priority.displayName)") }
                if config.dueDate != nil { ScopePill(text: "DUE") }
                Spacer(minLength: 0)
            }
            if let list = config.listName, !list.isEmpty {
                ScopeRow(label: "LIST", value: list)
            }
            ScopeRow(label: "TITLE", value: config.title.isEmpty ? "—" : config.title, emphasis: true)
            if let notes = config.notes, !notes.isEmpty {
                ScopeRow(label: "NOTES", value: notes)
            }
        }
    }
}

private struct UnavailableScopeBody: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopeAmber.solid, size: 5)
            Text(message)
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeAmber.solid)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Array chunk helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
