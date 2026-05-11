import SwiftUI

// MARK: - Inspector View

public struct InspectorView: View {
    @Bindable var state: CanvasState
    @Binding var isVisible: Bool
    @State private var expandedSections: Set<String> = ["node", "config", "details", "connection"]
    @Environment(\.wfTheme) private var theme
    @Environment(\.wfReadOnly) private var isReadOnly
    @Environment(\.wfSchema) private var schema

    public init(state: CanvasState, isVisible: Binding<Bool>) {
        self.state = state
        self._isVisible = isVisible
    }

    public var body: some View {
        VStack(spacing: 0) {
            inspectorHeader

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            if let connectionId = state.selectedConnectionId,
               let connection = state.connections.first(where: { $0.id == connectionId }) {
                // Connection selected - show connection inspector
                ScrollView {
                    VStack(spacing: 0) {
                        InspectorSection(
                            title: "CONNECTION",
                            icon: "arrow.right",
                            id: "connection",
                            expandedSections: $expandedSections
                        ) {
                            connectionSection(connection)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.visible)
            } else if let node = state.singleSelectedNode {
                ScrollView {
                    VStack(spacing: 0) {
                        // NODE: Identity, style, position
                        InspectorSection(
                            title: "NODE",
                            icon: "square.on.square",
                            id: "node",
                            expandedSections: $expandedSections
                        ) {
                            consolidatedNodeSection(node)
                        }

                        // CONFIG: Settings + Ports (hidden in read-only mode)
                        if !isReadOnly {
                            InspectorSection(
                                title: "CONFIG",
                                icon: "gearshape.fill",
                                id: "config",
                                expandedSections: $expandedSections
                            ) {
                                consolidatedConfigSection(node)
                            }
                        }

                        // DETAILS: Show customFields in read-only mode
                        if let customFields = node.configuration.customFields, !customFields.isEmpty {
                            InspectorSection(
                                title: "DETAILS",
                                icon: "doc.text.fill",
                                id: "details",
                                expandedSections: $expandedSections
                            ) {
                                customFieldsSection(customFields)
                            }
                        }

                        // RELATED: Show connected nodes
                        let connected = state.connectedNodes(for: node.id)
                        if !connected.upstream.isEmpty || !connected.downstream.isEmpty {
                            InspectorSection(
                                title: "RELATED",
                                icon: "point.3.connected.trianglepath.dotted",
                                id: "related",
                                expandedSections: $expandedSections
                            ) {
                                relatedNodesSection(upstream: connected.upstream, downstream: connected.downstream)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.visible)
            } else if state.selectedNodeIds.count > 1 {
                multiSelectionView
            } else {
                emptySelectionView
            }
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: .infinity)
        .background(theme.panelBackground)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    // MARK: - Header

    @ViewBuilder
    private var inspectorHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("INSPECTOR")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .tracking(1.2)
                    .foregroundColor(theme.textSecondary)

                Spacer()

                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(theme.sectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            // Back button when there's history
            if let previousInfo = state.previousItemInfo() {
                Button(action: { state.navigateBack() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))

                        Image(systemName: previousInfo.icon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(previousInfo.color)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(previousInfo.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)

                        Spacer()
                    }
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.accent.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.sectionBackground)
    }

    // MARK: - Consolidated Node Section (Identity + Style + Position)

    @ViewBuilder
    private func consolidatedNodeSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Type badge + Color picker
            HStack(spacing: 10) {
                // Type badge
                HStack(spacing: 6) {
                    Image(systemName: node.type.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(node.effectiveColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(node.type.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }

                Spacer()

                // Color picker (hidden in read-only mode)
                if !isReadOnly {
                    ColorPickerButton(
                        selectedColor: node.effectiveColor,
                        defaultColor: node.type.color,
                        customColor: node.customColor,
                        onColorChange: { newColor in
                            var updated = node
                            updated.customColor = newColor
                            state.updateNode(updated)
                        }
                    )
                }
            }

            // Row 2: Title (read-only or editable)
            if isReadOnly {
                Text(node.title)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
            } else {
                TextField("Node name", text: Binding(
                    get: { node.title },
                    set: { newValue in
                        var updated = node
                        updated.title = newValue
                        state.updateNode(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            }

            // Row 3: Position (read-only display in read-only mode)
            if isReadOnly {
                HStack(spacing: 12) {
                    InspectorInlineField(label: "X", labelWidth: 14) {
                        Text(String(format: "%.0f", node.position.x))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(theme.border, lineWidth: 1)
                            )
                    }

                    InspectorInlineField(label: "Y", labelWidth: 14) {
                        Text(String(format: "%.0f", node.position.y))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(theme.border, lineWidth: 1)
                            )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    InspectorInlineField(label: "X", labelWidth: 14) {
                        TextField("X", value: Binding(
                            get: { node.position.x },
                            set: { newValue in
                                guard let newValue = newValue else { return }
                                var updated = node
                                updated.position.x = newValue
                                state.updateNode(updated)
                            }
                        ), format: .number)
                        .textFieldStyle(InspectorCompactTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                    }

                    InspectorInlineField(label: "Y", labelWidth: 14) {
                        TextField("Y", value: Binding(
                            get: { node.position.y },
                            set: { newValue in
                                guard let newValue = newValue else { return }
                                var updated = node
                                updated.position.y = newValue
                                state.updateNode(updated)
                            }
                        ), format: .number)
                        .textFieldStyle(InspectorCompactTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Consolidated Config Section (Settings + Ports)

    @ViewBuilder
    private func consolidatedConfigSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Settings
            nodeConfigurationSection(node)

            // Divider between settings and ports
            if !node.inputs.isEmpty || !node.outputs.isEmpty {
                Rectangle()
                    .fill(theme.border.opacity(0.5))
                    .frame(height: 1)

                // Ports
                portsSection(node)
            }
        }
    }

    // MARK: - Node Configuration Section

    @ViewBuilder
    private func nodeConfigurationSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch node.type {
            case .llm:
                llmConfigSection(node)
            case .condition:
                conditionConfigSection(node)
            case .transform:
                transformConfigSection(node)
            case .action:
                actionConfigSection(node)
            case .notification:
                notificationConfigSection(node)
            case .trigger:
                triggerConfigSection(node)
            case .output:
                outputConfigSection(node)
            }
        }
    }

    // MARK: - LLM Config

    @ViewBuilder
    private func llmConfigSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorField(label: "Model") {
                InspectorPicker(
                    selection: Binding(
                        get: { node.configuration.model ?? "gemini-2.0-flash" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.model = newValue
                            state.updateNode(updated)
                        }
                    ),
                    options: [
                        ("gemini-2.0-flash", "Gemini 2.0 Flash"),
                        ("gemini-1.5-pro", "Gemini 1.5 Pro"),
                        ("gpt-4o", "GPT-4o"),
                        ("claude-sonnet-4", "Claude Sonnet 4")
                    ]
                )
            }

            InspectorField(label: "Temperature") {
                VStack(spacing: 4) {
                    HStack {
                        Slider(value: Binding(
                            get: { node.configuration.temperature ?? 0.7 },
                            set: { newValue in
                                var updated = node
                                updated.configuration.temperature = newValue
                                state.updateNode(updated)
                            }
                        ), in: 0...2, step: 0.1)
                        .accentColor(node.effectiveColor)

                        Text(String(format: "%.1f", node.configuration.temperature ?? 0.7))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.textPrimary)
                            .frame(width: 36)
                            .padding(4)
                            .background(theme.panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                    }

                    HStack {
                        Text("0.0")
                        Spacer()
                        Text("Precise")
                        Spacer()
                        Text("Creative")
                        Spacer()
                        Text("2.0")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                }
            }

            InspectorField(label: "Max Tokens") {
                TextField("Max tokens (optional)", value: Binding(
                    get: { node.configuration.maxTokens },
                    set: { newValue in
                        var updated = node
                        updated.configuration.maxTokens = newValue
                        state.updateNode(updated)
                    }
                ), format: .number)
                .textFieldStyle(InspectorTextFieldStyle())
                .font(.system(size: 11, design: .monospaced))
            }

            InspectorField(label: "System Prompt") {
                InspectorTextEditor(
                    text: Binding(
                        get: { node.configuration.systemPrompt ?? "" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.systemPrompt = newValue.isEmpty ? nil : newValue
                            state.updateNode(updated)
                        }
                    ),
                    placeholder: "Optional system instructions...",
                    height: 80
                )
            }

            InspectorField(label: "Prompt") {
                InspectorTextEditor(
                    text: Binding(
                        get: { node.configuration.prompt ?? "" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.prompt = newValue
                            state.updateNode(updated)
                        }
                    ),
                    placeholder: "Enter your prompt...",
                    height: 120
                )
            }
        }
    }

    // MARK: - Condition Config

    @ViewBuilder
    private func conditionConfigSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorField(label: "Condition") {
                InspectorTextEditor(
                    text: Binding(
                        get: { node.configuration.condition ?? "" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.condition = newValue
                            state.updateNode(updated)
                        }
                    ),
                    placeholder: "e.g., output.contains('urgent')",
                    height: 80
                )
            }

            Text("Use variables: {{input}}, {{output}}")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textTertiary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
        }
    }

    // MARK: - Transform Config

    @ViewBuilder
    private func transformConfigSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorField(label: "Transform Type") {
                InspectorPicker(
                    selection: Binding(
                        get: { node.configuration.transformType ?? "extractJSON" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.transformType = newValue
                            state.updateNode(updated)
                        }
                    ),
                    options: [
                        ("extractJSON", "Extract JSON"),
                        ("extractList", "Extract List"),
                        ("formatMarkdown", "Format Markdown"),
                        ("regex", "Regex"),
                        ("template", "Template")
                    ]
                )
            }

            InspectorField(label: "Expression") {
                InspectorTextEditor(
                    text: Binding(
                        get: { node.configuration.expression ?? "" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.expression = newValue
                            state.updateNode(updated)
                        }
                    ),
                    placeholder: "Enter transform expression...",
                    height: 100
                )
            }
        }
    }

    // MARK: - Action Config

    @ViewBuilder
    private func actionConfigSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorField(label: "Action Type") {
                InspectorPicker(
                    selection: Binding(
                        get: { node.configuration.actionType ?? "notification" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.actionType = newValue
                            state.updateNode(updated)
                        }
                    ),
                    options: [
                        ("notification", "Notification"),
                        ("reminder", "Reminder"),
                        ("appleNotes", "Apple Notes"),
                        ("clipboard", "Clipboard"),
                        ("saveFile", "Save File"),
                        ("webhook", "Webhook"),
                        ("shell", "Shell Command")
                    ]
                )
            }

            if let actionType = node.configuration.actionType {
                switch actionType {
                case "webhook":
                    InspectorField(label: "Webhook URL") {
                        TextField("https://...", text: Binding(
                            get: { node.configuration.actionConfig?["url"] ?? "" },
                            set: { newValue in
                                var updated = node
                                var config = updated.configuration.actionConfig ?? [:]
                                config["url"] = newValue
                                updated.configuration.actionConfig = config
                                state.updateNode(updated)
                            }
                        ))
                        .textFieldStyle(InspectorTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                    }
                case "shell":
                    InspectorField(label: "Command") {
                        InspectorTextEditor(
                            text: Binding(
                                get: { node.configuration.actionConfig?["command"] ?? "" },
                                set: { newValue in
                                    var updated = node
                                    var config = updated.configuration.actionConfig ?? [:]
                                    config["command"] = newValue
                                    updated.configuration.actionConfig = config
                                    state.updateNode(updated)
                                }
                            ),
                            placeholder: "Enter shell command...",
                            height: 80
                        )
                    }
                case "saveFile":
                    InspectorField(label: "File Path") {
                        TextField("~/Documents/output.txt", text: Binding(
                            get: { node.configuration.actionConfig?["path"] ?? "" },
                            set: { newValue in
                                var updated = node
                                var config = updated.configuration.actionConfig ?? [:]
                                config["path"] = newValue
                                updated.configuration.actionConfig = config
                                state.updateNode(updated)
                            }
                        ))
                        .textFieldStyle(InspectorTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                    }
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Notification Config

    @ViewBuilder
    private func notificationConfigSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorField(label: "Channel") {
                HStack(spacing: 8) {
                    ForEach(NotificationChannel.allCases) { channel in
                        Button(action: {
                            var updated = node
                            updated.configuration.notificationChannel = channel
                            state.updateNode(updated)
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: channel.icon)
                                    .font(.system(size: 14))
                                Text(channel.rawValue)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(node.configuration.notificationChannel == channel ? .white : theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(node.configuration.notificationChannel == channel ? node.effectiveColor : theme.inputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(node.configuration.notificationChannel == channel ? node.effectiveColor : theme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            InspectorField(label: "Title") {
                TextField("Notification title", text: Binding(
                    get: { node.configuration.notificationTitle ?? "" },
                    set: { newValue in
                        var updated = node
                        updated.configuration.notificationTitle = newValue.isEmpty ? nil : newValue
                        state.updateNode(updated)
                    }
                ))
                .textFieldStyle(InspectorTextFieldStyle())
            }

            InspectorField(label: "Body") {
                InspectorTextEditor(
                    text: Binding(
                        get: { node.configuration.notificationBody ?? "" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.notificationBody = newValue.isEmpty ? nil : newValue
                            state.updateNode(updated)
                        }
                    ),
                    placeholder: "Notification message...",
                    height: 80
                )
            }

            // Show recipient field for email/sms
            if let channel = node.configuration.notificationChannel, channel != .push {
                InspectorField(label: channel == .email ? "Email" : "Phone") {
                    TextField(channel == .email ? "email@example.com" : "+1234567890", text: Binding(
                        get: { node.configuration.notificationRecipient ?? "" },
                        set: { newValue in
                            var updated = node
                            updated.configuration.notificationRecipient = newValue.isEmpty ? nil : newValue
                            state.updateNode(updated)
                        }
                    ))
                    .textFieldStyle(InspectorTextFieldStyle())
                    .font(.system(size: 11, design: .monospaced))
                }
            }

            Text("Variables: {{input}}, {{output}}")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textTertiary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
        }
    }

    // MARK: - Trigger Config

    @ViewBuilder
    private func triggerConfigSection(_ node: WorkflowNode) -> some View {
        Text("Workflow entry point")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.textTertiary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
    }

    // MARK: - Output Config

    @ViewBuilder
    private func outputConfigSection(_ node: WorkflowNode) -> some View {
        Text("Workflow endpoint")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.textTertiary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
    }

    // MARK: - Related Nodes Section

    @ViewBuilder
    private func relatedNodesSection(upstream: [WorkflowNode], downstream: [WorkflowNode]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Upstream nodes (inputs to this node)
            if !upstream.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                        Text("INPUTS FROM")
                            .font(.system(size: 9, weight: .semibold, design: .default))
                            .tracking(0.5)
                            .foregroundColor(theme.textTertiary)
                    }

                    ForEach(upstream) { node in
                        relatedNodeRow(node, direction: .upstream)
                    }
                }
            }

            // Downstream nodes (outputs from this node)
            if !downstream.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                        Text("OUTPUTS TO")
                            .font(.system(size: 9, weight: .semibold, design: .default))
                            .tracking(0.5)
                            .foregroundColor(theme.textTertiary)
                    }

                    ForEach(downstream) { node in
                        relatedNodeRow(node, direction: .downstream)
                    }
                }
            }
        }
    }

    private enum ConnectionDirection {
        case upstream
        case downstream
    }

    @ViewBuilder
    private func relatedNodeRow(_ node: WorkflowNode, direction: ConnectionDirection) -> some View {
        Button(action: {
            state.navigateToNode(node.id)
        }) {
            HStack(spacing: 10) {
                // Direction arrow
                Image(systemName: direction == .upstream ? "arrow.left" : "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(theme.textTertiary)
                    .frame(width: 12)

                // Node icon
                Image(systemName: node.type.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(node.effectiveColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Node title
                Text(node.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Chevron to indicate clickable
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connection Section

    @ViewBuilder
    private func connectionNodeRow(node: WorkflowNode, port: Port?) -> some View {
        Button(action: {
            state.navigateToNode(node.id)
        }) {
            HStack(spacing: 10) {
                Image(systemName: node.type.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(node.effectiveColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    if let port = port {
                        Text("Port: \(port.label)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(10)
            .background(theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func connectionSection(_ connection: WorkflowConnection) -> some View {
        let sourceNode = state.nodes.first { $0.id == connection.sourceNodeId }
        let targetNode = state.nodes.first { $0.id == connection.targetNodeId }
        let sourcePort = sourceNode?.outputs.first { $0.id == connection.sourcePortId }
        let targetPort = targetNode?.inputs.first { $0.id == connection.targetPortId }

        VStack(alignment: .leading, spacing: 16) {
            // Source node info
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM")
                    .font(.system(size: 9, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)

                if let node = sourceNode {
                    connectionNodeRow(node: node, port: sourcePort)
                } else {
                    HStack(spacing: 10) {
                        Text("Unknown node")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                        Spacer()
                    }
                    .padding(10)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                }
            }

            // Break link action (between FROM and TO) - subtle disconnect button
            if !isReadOnly {
                HStack {
                    Spacer()
                    BreakLinkButton {
                        state.removeConnection(connection.id)
                        state.deselectConnection()
                    }
                    Spacer()
                }
            } else {
                // Read-only: just show arrow
                HStack {
                    Spacer()
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                }
            }

            // Target node info
            VStack(alignment: .leading, spacing: 8) {
                Text("TO")
                    .font(.system(size: 9, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)

                if let node = targetNode {
                    connectionNodeRow(node: node, port: targetPort)
                } else {
                    HStack(spacing: 10) {
                        Text("Unknown node")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                        Spacer()
                    }
                    .padding(10)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                }
            }

            // Waypoints info
            if !connection.waypoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WAYPOINTS")
                        .font(.system(size: 9, weight: .semibold, design: .default))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)

                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 12))
                            .foregroundColor(theme.accent)

                        Text("\(connection.waypoints.count) custom point\(connection.waypoints.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textSecondary)

                        Spacer()

                        if !isReadOnly {
                            Button(action: {
                                state.clearSelectedConnectionWaypoints()
                            }) {
                                Text("Reset")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                }
            }
        }
    }

    // MARK: - Custom Fields Section (Schema-Aware Display)

    @ViewBuilder
    private func customFieldsSection(_ customFields: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Try to get schema for the selected node
            if let node = state.singleSelectedNode,
               let nodeTypeSchema = resolveSchema(for: node, customFields: customFields) {
                // Use schema-ordered fields
                schemaOrderedFieldsView(customFields: customFields, nodeTypeSchema: nodeTypeSchema)
            } else {
                // Fallback: show all customFields alphabetically
                ForEach(customFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    customFieldRow(key: key, value: value, fieldSchema: nil)
                }
            }
        }
    }

    /// Resolve schema for a node, trying multiple identifiers
    private func resolveSchema(for node: WorkflowNode, customFields: [String: String]) -> WFNodeTypeSchema? {
        guard let schema = schema else { return nil }

        // Try 1: actionType from configuration (most specific)
        if let actionType = node.configuration.actionType,
           let found = schema.schema(for: actionType) {
            return found
        }

        // Try 2: configType from customFields
        if let configType = customFields["configType"],
           let found = schema.schema(for: configType) {
            return found
        }

        // Try 3: Generic node type
        if let found = schema.schema(for: node.type.rawValue) {
            return found
        }

        return nil
    }

    @ViewBuilder
    private func schemaOrderedFieldsView(customFields: [String: String], nodeTypeSchema: WFNodeTypeSchema) -> some View {
        // Group fields by their group property
        let groupedFields = Dictionary(grouping: nodeTypeSchema.fields) { $0.group ?? "" }
        let sortedGroups = groupedFields.keys.sorted()

        ForEach(sortedGroups, id: \.self) { group in
            if !group.isEmpty {
                // Group header
                Text(group.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
                    .padding(.top, 8)
            }

            // Fields in this group, sorted by order
            let fieldsInGroup = (groupedFields[group] ?? []).sorted { $0.order < $1.order }
            ForEach(fieldsInGroup) { fieldSchema in
                // Skip hidden fields
                if case .hidden = fieldSchema.type {
                    EmptyView()
                } else if let value = customFields[fieldSchema.id] {
                    customFieldRow(key: fieldSchema.id, value: value, fieldSchema: fieldSchema, customFields: customFields)
                } else if case .objectArray = fieldSchema.type {
                    // Object arrays may not have a direct value but have nested keys
                    customFieldRow(key: fieldSchema.id, value: "", fieldSchema: fieldSchema, customFields: customFields)
                }
            }
        }

        // Show any remaining fields not in schema
        let schemaFieldIds = Set(nodeTypeSchema.fields.map { $0.id })
        let unmappedFields = customFields.filter { !schemaFieldIds.contains($0.key) }
        if !unmappedFields.isEmpty {
            Text("OTHER")
                .font(.system(size: 8, weight: .bold, design: .default))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
                .padding(.top, 8)

            ForEach(unmappedFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                customFieldRow(key: key, value: value, fieldSchema: nil)
            }
        }
    }

    @ViewBuilder
    private func customFieldRow(key: String, value: String, fieldSchema: WFFieldSchema?, customFields: [String: String]? = nil) -> some View {
        if let schema = fieldSchema {
            switch schema.type {
            case .objectArray(let objectSchema):
                // Object array with full schema
                let items = ObjectArrayFieldView.parseItems(
                    from: customFields ?? [:],
                    fieldId: key,
                    schema: objectSchema
                )
                ObjectArrayFieldView(
                    fieldSchema: schema,
                    objectSchema: objectSchema,
                    items: items,
                    isReadOnly: true
                )

            case .stringArray(let options):
                // Simple string array
                let items = StringArrayFieldView.parseItems(
                    from: customFields ?? [:],
                    fieldId: key
                )
                StringArrayFieldView(
                    fieldSchema: schema,
                    options: options,
                    items: items,
                    isReadOnly: true
                )

            case .keyValueArray(let options):
                // Key-value pairs
                let items = KeyValueArrayFieldView.parseItems(
                    from: customFields ?? [:],
                    fieldId: key
                )
                KeyValueArrayFieldView(
                    fieldSchema: schema,
                    options: options,
                    items: items,
                    isReadOnly: true
                )

            default:
                // Standard field rendering
                standardFieldRow(key: key, value: value, fieldSchema: fieldSchema)
            }
        } else {
            // No schema, use standard rendering
            standardFieldRow(key: key, value: value, fieldSchema: fieldSchema)
        }
    }

    @ViewBuilder
    private func standardFieldRow(key: String, value: String, fieldSchema: WFFieldSchema?) -> some View {
        let displayKey = fieldSchema?.displayName ?? formatFieldKey(key)
        let isLongValue = value.count > 50 || value.contains("\n") || (fieldSchema.map { isMultilineField($0.type) } ?? false)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(displayKey)
                    .font(.system(size: 9, weight: .medium, design: .default))
                    .tracking(0.3)
                    .foregroundColor(theme.textTertiary)
                    .textCase(.uppercase)

                if let helpText = fieldSchema?.helpText {
                    Button(action: {}) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(helpText)
                }
            }

            // Check for boolean type - render with checkbox style
            if let schema = fieldSchema, case .boolean = schema.type {
                booleanFieldDisplay(value: value)
            } else if isLongValue {
                // Multi-line text area for long values
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                    .overlay(
                        RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                    .textSelection(.enabled)
            } else {
                // Single line display
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                    .overlay(
                        RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func booleanFieldDisplay(value: String) -> some View {
        let isTrue = value == "true" || value == "1" || value.lowercased() == "yes"
        HStack(spacing: 6) {
            Image(systemName: isTrue ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundColor(isTrue ? theme.accent : theme.textTertiary)
            Text(isTrue ? "Yes" : "No")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    /// Check if field type implies multiline display
    private func isMultilineField(_ fieldType: WFFieldType) -> Bool {
        switch fieldType {
        case .text:
            return true
        case .objectArray:
            return true
        default:
            return false
        }
    }

    /// Formats customField keys like "_0.modelId" to "Model ID"
    private func formatFieldKey(_ key: String) -> String {
        var formatted = key
        // Remove leading underscore and number prefix (e.g., "_0.")
        if let range = formatted.range(of: "^_\\d+\\.", options: .regularExpression) {
            formatted.removeSubrange(range)
        }
        // Convert camelCase to Title Case
        formatted = formatted.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        // Capitalize first letter
        return formatted.prefix(1).uppercased() + formatted.dropFirst()
    }

    // MARK: - Ports Section

    @ViewBuilder
    private func portsSection(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !node.inputs.isEmpty {
                Text("INPUTS")
                    .font(.system(size: 9, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(theme.textSecondary)
                    .textCase(.uppercase)

                ForEach(node.inputs) { port in
                    portRow(port, nodeId: node.id, isInput: true, connections: connectionsForPort(nodeId: node.id, portId: port.id))
                }
            }

            if !node.outputs.isEmpty {
                Text("OUTPUTS")
                    .font(.system(size: 9, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(theme.textSecondary)
                    .textCase(.uppercase)
                    .padding(.top, 4)

                ForEach(node.outputs) { port in
                    portRow(port, nodeId: node.id, isInput: false, connections: connectionsForPort(nodeId: node.id, portId: port.id))
                }
            }

            // Connection mode hint
            if state.isConnecting {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text("Click a port on the canvas to connect")
                        .font(.system(size: 9))
                    Spacer()
                    Button(action: { state.cancelPendingConnection() }) {
                        Text("Cancel")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(theme.accent)
                .padding(8)
                .background(theme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func portRow(_ port: Port, nodeId: UUID, isInput: Bool, connections: [WorkflowConnection]) -> some View {
        let isConnecting = state.pendingConnection?.sourceAnchor.portId == port.id
        let isValidTarget = state.validDropPortIds.contains(port.id)

        HStack(spacing: 8) {
            // Port indicator
            Circle()
                .fill(isConnecting ? theme.accent : (connections.isEmpty ? theme.border : Color.blue))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .strokeBorder(isConnecting ? theme.accent : .clear, lineWidth: 2)
                        .scaleEffect(1.5)
                )

            Text(port.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isConnecting ? theme.accent : theme.textSecondary)

            Spacer()

            if !connections.isEmpty {
                // Show connection count badge - clickable to select connection
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(connections.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if isValidTarget {
                // This port is a valid drop target
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.green)
            } else if !state.isConnecting {
                // Show connect button for unconnected ports
                Button(action: {
                    state.startConnectionFromPort(nodeId: nodeId, portId: port.id, isInput: isInput)
                }) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Start connection from this port")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .fill(isConnecting ? theme.accent.opacity(0.1) : (isValidTarget ? Color.green.opacity(0.1) : theme.panelBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .strokeBorder(isConnecting ? theme.accent : (isValidTarget ? Color.green : Color.clear), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isValidTarget {
                // Complete connection to this port
                state.completeConnection(to: nodeId, targetPortId: port.id, isInput: isInput)
            } else if !connections.isEmpty {
                // Select the first connection on this port
                let connection = connections[0]
                state.clearSelection()
                state.selectConnection(connection.id)
            } else if connections.isEmpty && !state.isConnecting {
                // Start connection from this port
                state.startConnectionFromPort(nodeId: nodeId, portId: port.id, isInput: isInput)
            }
        }
    }

    private func connectionsForPort(nodeId: UUID, portId: UUID) -> [WorkflowConnection] {
        state.connections.filter {
            ($0.sourceNodeId == nodeId && $0.sourcePortId == portId) ||
            ($0.targetNodeId == nodeId && $0.targetPortId == portId)
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 32))
                .foregroundColor(theme.textTertiary)

            Text("NO SELECTION")
                .font(.system(size: 11, weight: .bold, design: .default))
                .tracking(1.0)
                .foregroundColor(theme.textSecondary)

            Text("Select a node to inspect\nand edit its properties")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var multiSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32))
                .foregroundColor(theme.textTertiary)

            Text("\(state.selectedNodeIds.count) NODES SELECTED")
                .font(.system(size: 11, weight: .bold, design: .default))
                .tracking(1.0)
                .foregroundColor(theme.textSecondary)

            Button(action: { state.removeSelectedNodes() }) {
                Text("DELETE SELECTED")
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Inspector Section

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    let id: String
    @Binding var expandedSections: Set<String>
    @ViewBuilder let content: () -> Content
    @Environment(\.wfTheme) private var theme

    var isExpanded: Bool {
        expandedSections.contains(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { toggleExpanded() }) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 16, height: 16)

                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .tracking(1.0)
                        .foregroundColor(theme.textSecondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(theme.border.opacity(0.5))
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                content()
                    .padding(12)
            }
        }
        .background(theme.sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .strokeBorder(theme.border.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }
}

// MARK: - Inspector Field (Stacked)

struct InspectorField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    @Environment(\.wfTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .default))
                .tracking(0.3)
                .foregroundColor(theme.textTertiary)

            content()
        }
    }
}

// MARK: - Inspector Inline Field

struct InspectorInlineField<Content: View>: View {
    let label: String
    let labelWidth: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.wfTheme) private var theme

    init(label: String, labelWidth: CGFloat = 50, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundColor(theme.textSecondary)
                .frame(width: labelWidth, alignment: .leading)

            content()
        }
    }
}

// MARK: - Inspector Text Field Style

struct InspectorTextFieldStyle: TextFieldStyle {
    @Environment(\.wfTheme) private var theme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundColor(theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                    .fill(theme.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Inspector Compact Text Field Style

struct InspectorCompactTextFieldStyle: TextFieldStyle {
    @Environment(\.wfTheme) private var theme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundColor(theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Inspector Text Editor

struct InspectorTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let height: CGFloat
    @Environment(\.wfTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textPlaceholder)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .fill(theme.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Inspector Picker (Custom Popover)

struct InspectorPicker: View {
    @Binding var selection: String
    let options: [(value: String, label: String)]
    @State private var isOpen: Bool = false
    @Environment(\.wfTheme) private var theme

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? selection
    }

    var body: some View {
        Button(action: { isOpen.toggle() }) {
            HStack {
                Text(selectedLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                    .fill(theme.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                    .strokeBorder(isOpen ? theme.accent : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.value) { option in
                    Button(action: {
                        selection = option.value
                        isOpen = false
                    }) {
                        HStack {
                            Text(option.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(selection == option.value ? theme.accent : theme.textPrimary)
                            Spacer()
                            if selection == option.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(theme.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: WFDesign.radiusXS)
                                .fill(selection == option.value ? theme.accent.opacity(0.1) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(minWidth: 150)
            .background(theme.panelBackground)
        }
    }
}

// MARK: - Color Picker Button

struct ColorPickerButton: View {
    let selectedColor: Color
    let defaultColor: Color
    let customColor: String?
    let onColorChange: (String?) -> Void
    @State private var isOpen: Bool = false
    @Environment(\.wfTheme) private var theme

    var body: some View {
        Button(action: { isOpen.toggle() }) {
            Circle()
                .fill(selectedColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .strokeBorder(isOpen ? theme.accent : theme.textPrimary.opacity(0.2), lineWidth: isOpen ? 2 : 1)
                )
                .shadow(color: selectedColor.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                // Default color option
                Button(action: {
                    onColorChange(nil)
                    isOpen = false
                }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(defaultColor)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        customColor == nil ? Color.white : theme.border,
                                        lineWidth: customColor == nil ? 2 : 1
                                    )
                            )
                        Text("Default")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(customColor == nil ? theme.accent : theme.textPrimary)
                        Spacer()
                        if customColor == nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(theme.accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(customColor == nil ? theme.accent.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)

                Divider()

                // Color grid
                LazyVGrid(columns: [
                    GridItem(.fixed(24)),
                    GridItem(.fixed(24)),
                    GridItem(.fixed(24)),
                    GridItem(.fixed(24)),
                    GridItem(.fixed(24))
                ], spacing: 6) {
                    ForEach(WFColorPresets.all, id: \.self) { hexColor in
                        Button(action: {
                            onColorChange(hexColor)
                            isOpen = false
                        }) {
                            Circle()
                                .fill(Color(hex: hexColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            customColor == hexColor ? Color.white : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .background(theme.panelBackground)
        }
    }
}

// MARK: - Break Link Button

/// A very subtle button for breaking/disconnecting a connection
private struct BreakLinkButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.wfTheme) private var theme

    var body: some View {
        Button(action: action) {
            // Simple small "x" to indicate disconnect
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(isHovered ? theme.error.opacity(0.8) : theme.textTertiary.opacity(0.4))
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(isHovered ? theme.error.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Disconnect")
    }
}
