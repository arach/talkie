//
//  ConsoleTabEditor.swift
//  Talkie
//
//  Sheet for creating and editing console tab definitions.
//

import SwiftUI
import AppKit

struct ConsoleTabEditor: View {
    enum Mode {
        case create
        case edit(TabDefinition)
    }

    let mode: Mode
    let onSave: (TabDefinition) -> Void
    let onCancel: () -> Void

    @State private var id: String = ""
    @State private var label: String = ""
    @State private var icon: String = "sparkles"
    @State private var order: Int = 50
    @State private var harness: TabHarness = .claudeCode
    @State private var model: String = ""
    @State private var provider: String = ""
    @State private var systemPrompt: String = ""
    @State private var cwd: String = "~/dev/talkie"
    @State private var launchArgs: String = ""
    @State private var envEntries: [EnvEntry] = []
    @State private var useTmux: Bool = false
    @State private var tmuxSessionName: String = ""
    @State private var shellProgram: String = "/bin/zsh"
    @State private var shellInitScript: String = ""

    struct EnvEntry: Identifiable {
        let id = UUID()
        var key: String
        var value: String
        var type: EnvType

        enum EnvType: String, CaseIterable {
            case literal = "Literal"
            case envRef = "env:"
            case fileRef = "file:"
            case keychainRef = "keychain:"
        }
    }

    init(mode: Mode, onSave: @escaping (TabDefinition) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identitySection
                    harnessSection
                    promptSection
                    environmentSection
                    if harness == .shell {
                        shellSection
                    }
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .frame(minWidth: 560, minHeight: 600)
        .background(Theme.current.surfaceBase)
        .onAppear { loadFromMode() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isCreating ? "NEW TAB" : "EDIT TAB")
                    .font(.techLabelSmall)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                Text(isCreating ? "Create a new console tab" : "Edit \(label)")
                    .font(Theme.current.fontTitleMedium)
                    .foregroundStyle(Theme.current.foreground)
            }

            Spacer()

            if case .edit(let tab) = mode, let url = tab.sourceURL {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.plain)
                .font(.geist(size: 12, weight: .medium))
                .foregroundStyle(Theme.current.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IDENTITY")
                .font(.techLabelSmall)
                .foregroundStyle(Theme.current.foregroundSecondary)

            if isCreating {
                editorField("ID", text: $id, placeholder: "my-tab")
            }

            editorField("Label", text: $label, placeholder: "My Tab")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon")
                        .font(.geist(size: 11, weight: .medium))
                        .foregroundStyle(Theme.current.foregroundSecondary)

                    Picker("", selection: $icon) {
                        Label("Sparkles", systemImage: "sparkles").tag("sparkles")
                        Label("Terminal", systemImage: "apple.terminal").tag("apple.terminal")
                        Label("Circle Grid", systemImage: "circle.grid.cross").tag("circle.grid.cross")
                        Label("Bolt", systemImage: "bolt").tag("bolt")
                        Label("Gear", systemImage: "gear").tag("gear")
                        Label("Wand", systemImage: "wand.and.stars").tag("wand.and.stars")
                        Label("Code", systemImage: "chevron.left.forwardslash.chevron.right").tag("chevron.left.forwardslash.chevron.right")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Order")
                        .font(.geist(size: 11, weight: .medium))
                        .foregroundStyle(Theme.current.foregroundSecondary)

                    TextField("", value: $order, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Harness

    private var harnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HARNESS")
                .font(.techLabelSmall)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Picker("Harness", selection: $harness) {
                ForEach(TabHarness.allCases, id: \.self) { h in
                    HStack {
                        Text(h.displayName)
                        if h.comingSoon {
                            Text("(coming soon)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            if harness != .shell {
                modelProviderSection
            }

            editorField("Working Directory", text: $cwd, placeholder: "~/dev/talkie")

            editorField("Launch Args", text: $launchArgs, placeholder: "space-separated args")

            Toggle(isOn: $useTmux) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wrap in tmux")
                        .font(.geist(size: 12, weight: .medium))
                    Text("Keeps the session alive when you switch tabs.")
                        .font(.geist(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundMuted)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!AgentHarnessProfile.consoleTmuxAvailable)

            if useTmux {
                editorField("Session Name", text: $tmuxSessionName, placeholder: "talkie-\(id)")
            }
        }
    }

    // MARK: - Model & Provider

    private var modelProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if harness == .pi {
                // Pi supports --provider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider")
                        .font(.geist(size: 11, weight: .medium))
                        .foregroundStyle(Theme.current.foregroundSecondary)

                    Picker("", selection: $provider) {
                        Text("Default").tag("")
                        ForEach(Self.piProviders, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.geist(size: 11, weight: .medium))
                    .foregroundStyle(Theme.current.foregroundSecondary)

                HStack(spacing: 8) {
                    TextField(modelPlaceholder, text: $model)
                        .textFieldStyle(.roundedBorder)
                        .font(.geistMono(size: 12))

                    Menu {
                        ForEach(modelPresets, id: \.value) { preset in
                            Button(preset.label) {
                                model = preset.value
                                if !preset.provider.isEmpty {
                                    provider = preset.provider
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.current.foregroundSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }

                if !model.isEmpty {
                    Text("Passed as --model \(model)\(harness == .pi && !provider.isEmpty ? " --provider \(provider)" : "")")
                        .font(.geist(size: 10, weight: .regular))
                        .foregroundStyle(Theme.current.foregroundMuted)
                }
            }
        }
    }

    private var modelPlaceholder: String {
        switch harness {
        case .claudeCode: "claude-sonnet-4-6"
        case .pi: "gemini-2.5-pro"
        case .opencode: "claude-sonnet-4-6"
        case .shell: ""
        }
    }

    private struct ModelPreset {
        let label: String
        let value: String
        let provider: String
    }

    private var modelPresets: [ModelPreset] {
        switch harness {
        case .claudeCode:
            return [
                ModelPreset(label: "Opus 4.6", value: "claude-opus-4-6", provider: ""),
                ModelPreset(label: "Sonnet 4.6", value: "claude-sonnet-4-6", provider: ""),
                ModelPreset(label: "Haiku 4.5", value: "claude-haiku-4-5-20251001", provider: ""),
                ModelPreset(label: "Sonnet (alias)", value: "sonnet", provider: ""),
                ModelPreset(label: "Opus (alias)", value: "opus", provider: ""),
            ]
        case .pi:
            return [
                ModelPreset(label: "Gemini 2.5 Pro", value: "gemini-2.5-pro", provider: "google"),
                ModelPreset(label: "Gemini 2.5 Flash", value: "gemini-2.5-flash", provider: "google"),
                ModelPreset(label: "Claude Sonnet 4.6", value: "claude-sonnet-4-6", provider: "anthropic"),
                ModelPreset(label: "Claude Opus 4.6", value: "claude-opus-4-6", provider: "anthropic"),
                ModelPreset(label: "GPT-4.1", value: "gpt-4.1", provider: "openai"),
                ModelPreset(label: "o3", value: "o3", provider: "openai"),
                ModelPreset(label: "Copilot (GPT-4.1)", value: "gpt-4.1", provider: "copilot"),
            ]
        case .opencode:
            return [
                ModelPreset(label: "Claude Sonnet 4.6", value: "claude-sonnet-4-6", provider: ""),
                ModelPreset(label: "Claude Opus 4.6", value: "claude-opus-4-6", provider: ""),
                ModelPreset(label: "GPT-4.1", value: "gpt-4.1", provider: ""),
            ]
        case .shell:
            return []
        }
    }

    private static let piProviders = [
        "google", "anthropic", "openai", "copilot", "groq", "openrouter",
    ]

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SYSTEM PROMPT")
                .font(.techLabelSmall)
                .foregroundStyle(Theme.current.foregroundSecondary)

            TextEditor(text: $systemPrompt)
                .font(.geistMono(size: 12, weight: .regular))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.current.surface1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.current.border, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ENVIRONMENT")
                    .font(.techLabelSmall)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                Spacer()

                Button {
                    envEntries.append(EnvEntry(key: "", value: "", type: .literal))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.geist(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.current.accent)
            }

            ForEach($envEntries) { $entry in
                HStack(spacing: 8) {
                    TextField("KEY", text: $entry.key)
                        .textFieldStyle(.roundedBorder)
                        .font(.geistMono(size: 11))
                        .frame(width: 140)

                    Picker("", selection: $entry.type) {
                        ForEach(EnvEntry.EnvType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)

                    TextField("value", text: $entry.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.geistMono(size: 11))

                    Button {
                        envEntries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Shell

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHELL")
                .font(.techLabelSmall)
                .foregroundStyle(Theme.current.foregroundSecondary)

            editorField("Program", text: $shellProgram, placeholder: "/bin/zsh")
            editorField("Init Script", text: $shellInitScript, placeholder: "~/.talkie/tabs/talkie-shell.init.zsh")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Spacer()

            Button(isCreating ? "Create" : "Save") {
                let tab = buildDefinition()
                onSave(tab)
            }
            .buttonStyle(.borderedProminent)
            .disabled(id.isEmpty || label.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private func loadFromMode() {
        switch mode {
        case .create:
            id = "new-\(Int(Date().timeIntervalSince1970))"
        case .edit(let tab):
            id = tab.id
            label = tab.label
            icon = tab.icon
            order = tab.order
            harness = tab.harness
            model = tab.model ?? ""
            provider = tab.provider ?? ""
            systemPrompt = tab.systemPrompt
            cwd = tab.cwd
            launchArgs = tab.launchArgs.joined(separator: " ")
            useTmux = tab.useTmux
            tmuxSessionName = tab.tmuxSessionName ?? ""
            envEntries = tab.env.map { key, value in
                let (type, cleanValue) = parseEnvValue(value)
                return EnvEntry(key: key, value: cleanValue, type: type)
            }.sorted { $0.key < $1.key }
            shellProgram = tab.shell?.program ?? "/bin/zsh"
            shellInitScript = tab.shell?.initScript ?? ""
        }
    }

    private func buildDefinition() -> TabDefinition {
        var env: [String: String] = [:]
        for entry in envEntries where !entry.key.isEmpty {
            let value: String
            switch entry.type {
            case .literal: value = entry.value
            case .envRef: value = "${env:\(entry.value)}"
            case .fileRef: value = "${file:\(entry.value)}"
            case .keychainRef: value = "${keychain:\(entry.value)}"
            }
            env[entry.key] = value
        }

        var shell: TabDefinition.ShellConfig?
        if harness == .shell {
            shell = TabDefinition.ShellConfig(
                program: shellProgram.isEmpty ? "/bin/zsh" : shellProgram,
                initScript: shellInitScript.isEmpty ? nil : shellInitScript
            )
        }

        let args = launchArgs
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        return TabDefinition(
            id: id,
            label: label,
            icon: icon,
            order: order,
            harness: harness,
            model: model.isEmpty ? nil : model,
            provider: provider.isEmpty ? nil : provider,
            systemPrompt: systemPrompt,
            cwd: cwd,
            launchArgs: args,
            readOnly: false,
            useTmux: useTmux,
            tmuxSessionName: tmuxSessionName.isEmpty ? nil : tmuxSessionName,
            env: env,
            shell: shell,
            sourceURL: nil
        )
    }

    private func parseEnvValue(_ value: String) -> (EnvEntry.EnvType, String) {
        if value.hasPrefix("${env:") && value.hasSuffix("}") {
            return (.envRef, String(value.dropFirst(6).dropLast(1)))
        }
        if value.hasPrefix("${file:") && value.hasSuffix("}") {
            return (.fileRef, String(value.dropFirst(7).dropLast(1)))
        }
        if value.hasPrefix("${keychain:") && value.hasSuffix("}") {
            return (.keychainRef, String(value.dropFirst(11).dropLast(1)))
        }
        return (.literal, value)
    }

    private func editorField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.geist(size: 11, weight: .medium))
                .foregroundStyle(Theme.current.foregroundSecondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.geistMono(size: 12))
        }
    }
}
