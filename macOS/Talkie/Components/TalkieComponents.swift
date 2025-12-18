//
//  TalkieComponents.swift
//  Talkie
//
//  UI components with built-in performance instrumentation
//  Uses os_signpost for zero-overhead native instrumentation
//  Convention-based automatic naming via environment propagation
//

import SwiftUI
import OSLog

// MARK: - Instrumentation Environment

/// Environment key for current instrumentation section context
private struct InstrumentationSectionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Current instrumentation section (e.g., "AllMemos")
    /// Automatically propagated down the view hierarchy
    var instrumentationSection: String? {
        get { self[InstrumentationSectionKey.self] }
        set { self[InstrumentationSectionKey.self] = newValue }
    }
}

// MARK: - Naming Conventions

/// Automatic naming helper
private func instrumentationName(section: String?, component: String?) -> String {
    switch (section, component) {
    case (let s?, let c?):
        return "\(s).\(c)"
    case (let s?, nil):
        return s
    case (nil, let c?):
        return c
    default:
        return "Unknown"
    }
}

// MARK: - Talkie Section

/// A section of UI that automatically tracks performance via os_signpost
///
/// Automatically sets instrumentation section in environment for child components.
/// Child TalkieButtons, TalkieLists, etc. inherit this section name.
///
/// Convention-based naming:
/// ```
/// TalkieSection("AllMemos") {
///     TalkieButton("Load") { ... }       // Auto-named: AllMemos.Load
///     TalkieList("Memos", items: ...) {} // Auto-named: AllMemos.Memos
/// }
/// ```
///
/// Events emitted to os_signpost:
/// - Section appeared
/// - Data loaded (if onLoad provided)
/// - Section lifecycle interval
struct TalkieSection<Content: View>: View {
    let name: String
    let content: Content
    let onLoad: (() async -> Void)?

    @State private var hasAppeared = false
    @State private var isLoading = false
    @State private var signpostState: OSSignpostIntervalState?

    init(
        _ name: String,
        @ViewBuilder content: () -> Content,
        onLoad: (() async -> Void)? = nil
    ) {
        self.name = name
        self.content = content()
        self.onLoad = onLoad
    }

    var body: some View {
        content
            .environment(\.instrumentationSection, name)  // Propagate to children
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true

                    // Do ALL instrumentation work asynchronously to keep UI snappy
                    Task { @MainActor in
                        let id = talkieSignposter.makeSignpostID()

                        // Begin section lifecycle interval (for Instruments)
                        let state = talkieSignposter.beginInterval("SectionLifecycle", id: id)
                        signpostState = state

                        // Log to os_log
                        talkieEventLogger.info("Section appeared: \(name, privacy: .public)")

                        // If there's an onLoad closure, execute it (DB operations will be tracked
                        // and added to the active Navigate action from the sidebar click)
                        if let onLoad = onLoad {
                            isLoading = true
                            await onLoad()
                            isLoading = false
                        }

                        // Complete the Navigate action (captures view creation + DB operations)
                        PerformanceMonitor.shared.completeAction()

                        // Mark as rendered on next runloop (after SwiftUI layout/paint)
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1))
                            PerformanceMonitor.shared.markActionAsRendered(actionName: name)
                        }
                    }
                }
            }
            .onDisappear {
                // End signpost interval for Instruments
                if let state = signpostState {
                    talkieSignposter.endInterval("SectionLifecycle", state, "\(name)")
                    talkieEventLogger.info("Section disappeared: \(name, privacy: .public)")
                    signpostState = nil
                }
            }
    }
}

// MARK: - Talkie Button

/// A button that automatically tracks clicks and action duration via os_signpost
///
/// Automatically inherits section name from parent TalkieSection.
///
/// Convention-based naming:
/// ```
/// TalkieSection("AllMemos") {
///     TalkieButton("Load") { ... }  // Auto-named: AllMemos.Load
/// }
/// ```
///
/// Or explicit section override:
/// ```
/// TalkieButton("Load", section: "Settings") { ... }  // Named: Settings.Load
/// ```
///
/// Events emitted:
/// - Click event
/// - Action interval (begin/end)
struct TalkieButton<Label: View>: View {
    let name: String
    let explicitSection: String?
    let action: () async -> Void
    let label: Label

    @Environment(\.instrumentationSection) private var environmentSection
    @State private var isExecuting = false

    /// Create button with automatic section inheritance
    init(
        _ name: String,
        action: @escaping () async -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = nil
        self.action = action
        self.label = label()
    }

    /// Create button with explicit section override
    init(
        _ name: String,
        section: String,
        action: @escaping () async -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = section
        self.action = action
        self.label = label()
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        Button {
            Task {
                isExecuting = true

                // Start a new performance action for this button click
                await MainActor.run {
                    PerformanceMonitor.shared.startAction(
                        type: "Click",
                        name: fullName,
                        context: explicitSection ?? environmentSection
                    )
                }

                // Begin signpost interval for Instruments
                let id = talkieSignposter.makeSignpostID()
                let state = talkieSignposter.beginInterval("ButtonAction", id: id)

                // Execute the action (operations will be tracked automatically)
                await action()

                // End signpost interval
                talkieSignposter.endInterval("ButtonAction", state, "\(fullName)")

                // Complete the performance action
                await MainActor.run {
                    PerformanceMonitor.shared.completeAction()
                    isExecuting = false
                }
            }
        } label: {
            label
        }
        .disabled(isExecuting)
    }
}

// MARK: - Talkie Button Sync

/// Synchronous version of TalkieButton for non-async actions
///
/// Same convention-based naming as TalkieButton.
struct TalkieButtonSync<Label: View>: View {
    let name: String
    let explicitSection: String?
    let action: () -> Void
    let label: Label

    @Environment(\.instrumentationSection) private var environmentSection

    /// Create button with automatic section inheritance
    init(
        _ name: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = nil
        self.action = action
        self.label = label()
    }

    /// Create button with explicit section override
    init(
        _ name: String,
        section: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = section
        self.action = action
        self.label = label()
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        Button {
            let id = talkieSignposter.makeSignpostID()
            talkieSignposter.emitEvent("Click", id: id, "\(fullName)")
            action()
        } label: {
            label
        }
    }
}

// MARK: - Talkie Row

/// A row component that tracks clicks via os_signpost
///
/// Automatically inherits section name from parent TalkieSection.
///
/// Convention-based naming:
/// ```
/// TalkieSection("AllMemos") {
///     TalkieList("Memos", items: memos) { memo in
///         TalkieRow("MemoRow", id: memo.id) { ... }  // Auto-named: AllMemos.MemoRow
///     }
/// }
/// ```
struct TalkieRow<Content: View>: View {
    let name: String
    let explicitSection: String?
    let id: String
    let onTap: () -> Void
    let content: Content

    @Environment(\.instrumentationSection) private var environmentSection

    /// Create row with automatic section inheritance
    init(
        _ name: String,
        id: String,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.explicitSection = nil
        self.id = id
        self.onTap = onTap
        self.content = content()
    }

    /// Create row with explicit section override
    init(
        _ name: String,
        section: String,
        id: String,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.explicitSection = section
        self.id = id
        self.onTap = onTap
        self.content = content()
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                let id = talkieSignposter.makeSignpostID()
                talkieSignposter.emitEvent("RowClick", id: id, "\(fullName)")
                onTap()
            }
    }
}

// MARK: - Talkie List

/// A list that tracks loading and scrolling performance via os_signpost
///
/// Automatically inherits section name from parent TalkieSection.
///
/// Convention-based naming:
/// ```
/// TalkieSection("AllMemos") {
///     TalkieList("Memos", items: memos) { ... }  // Auto-named: AllMemos.Memos
/// }
/// ```
struct TalkieList<Item: Identifiable, RowContent: View>: View {
    let name: String
    let explicitSection: String?
    let items: [Item]
    let rowContent: (Item) -> RowContent
    let onLoadMore: (() async -> Void)?

    @Environment(\.instrumentationSection) private var environmentSection
    @State private var hasAppeared = false
    @State private var signpostState: OSSignpostIntervalState?

    /// Create list with automatic section inheritance
    init(
        _ name: String,
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.name = name
        self.explicitSection = nil
        self.items = items
        self.rowContent = rowContent
        self.onLoadMore = onLoadMore
    }

    /// Create list with explicit section override
    init(
        _ name: String,
        section: String,
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.name = name
        self.explicitSection = section
        self.items = items
        self.rowContent = rowContent
        self.onLoadMore = onLoadMore
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    rowContent(item)
                        .onAppear {
                            // Trigger load more when approaching end
                            if let lastItem = items.last, item.id == lastItem.id {
                                if let onLoadMore = onLoadMore {
                                    Task {
                                        let id = talkieSignposter.makeSignpostID()
                                        talkieSignposter.emitEvent("LoadMore", id: id, "\(fullName)")
                                        await onLoadMore()
                                    }
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                let id = talkieSignposter.makeSignpostID()

                // Begin list lifecycle
                let state = talkieSignposter.beginInterval("ListLifecycle", id: id)
                signpostState = state
            }
        }
        .onDisappear {
            if let state = signpostState {
                talkieSignposter.endInterval("ListLifecycle", state, "\(fullName)")
                signpostState = nil
            }
        }
    }
}

// MARK: - Preview Examples

#Preview("Convention-Based Naming") {
    TalkieSection("AllMemos") {
        VStack(spacing: 20) {
            // Auto-named: AllMemos.Refresh
            TalkieButton("Refresh") {
                try? await Task.sleep(for: .milliseconds(100))
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            // Auto-named: AllMemos.Delete
            TalkieButtonSync("Delete") {
                print("Delete clicked")
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Text("All buttons above auto-inherit 'AllMemos' section")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    } onLoad: {
        try? await Task.sleep(for: .milliseconds(50))
    }
}

#Preview("Explicit Section Override") {
    VStack(spacing: 20) {
        // Explicit section: Settings.Save
        TalkieButton("Save", section: "Settings") {
            try? await Task.sleep(for: .milliseconds(100))
        } label: {
            Text("Save Settings")
        }

        // Explicit section: Settings.Reset
        TalkieButtonSync("Reset", section: "Settings") {
            print("Reset clicked")
        } label: {
            Text("Reset")
        }
    }
    .padding()
}

#Preview("Nested Sections") {
    TalkieSection("MemoDetail") {
        VStack(spacing: 20) {
            // Auto-named: MemoDetail.Edit
            TalkieButton("Edit") {
                try? await Task.sleep(for: .milliseconds(100))
            } label: {
                Text("Edit")
            }

            // Nested section with override
            TalkieSection("Metadata") {
                VStack {
                    // Auto-named: Metadata.UpdateTags (inherits Metadata, not MemoDetail)
                    TalkieButton("UpdateTags") {
                        try? await Task.sleep(for: .milliseconds(50))
                    } label: {
                        Text("Update Tags")
                    }
                }
            }
        }
        .padding()
    }
}

#Preview("List Example") {
    struct Memo: Identifiable {
        let id = UUID()
        let title: String
    }

    let memos = (1...20).map { Memo(title: "Memo \($0)") }

    return TalkieSection("AllMemos") {
        VStack {
            // Auto-named: AllMemos.MemoList
            TalkieList("MemoList", items: memos) { memo in
                // Auto-named: AllMemos.MemoRow
                TalkieRow("MemoRow", id: memo.id.uuidString) {
                    print("Tapped: \(memo.title)")
                } content: {
                    Text(memo.title)
                        .padding()
                }
            }
        }
    }
}
