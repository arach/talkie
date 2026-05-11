//
//  FilterChip.swift
//  Talkie
//
//  Semantic filter chips for RecordingsScreen.
//

import SwiftUI

// MARK: - Single Filter Chip

struct SemanticFilterChip: View {
    let filter: SemanticFilter
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(filter.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var background: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor.opacity(0.2))
        } else {
            return AnyShapeStyle(Color.primary.opacity(0.05))
        }
    }

    private var foregroundColor: Color {
        isActive ? .accentColor : .secondary
    }

    private var borderColor: Color {
        isActive ? .accentColor.opacity(0.3) : .clear
    }
}

// MARK: - Date Filter Chip

struct DateFilterChip: View {
    let date: Date
    let onClear: () -> Void

    private var label: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium))

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.2))
        .foregroundColor(.accentColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Filter Chip Bar

struct FilterChipBar: View {
    @Bindable var viewModel: RecordingsViewModel
    var filters: [SemanticFilter] = SemanticFilter.defaultFilters
    var horizontalInset: CGFloat = RecordingsHeaderLayout.horizontalInset
    @State private var showingDatePicker = false
    @State private var pickerDate = Date()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Date filter chip (shown when active)
                if let date = viewModel.filterState.dateFilter {
                    DateFilterChip(date: date) {
                        Task { await viewModel.clearDateFilter() }
                    }
                }

                // Time filter chips
                ForEach(filters) { filter in
                    SemanticFilterChip(
                        filter: filter,
                        isActive: viewModel.isSemanticFilterActive(filter)
                    ) {
                        Task {
                            await viewModel.toggleSemanticFilter(filter)
                        }
                    }
                }

                // Calendar picker button
                Button {
                    pickerDate = viewModel.filterState.dateFilter ?? Date()
                    showingDatePicker.toggle()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Filter by date")
                .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) {
                    DatePicker(
                        "Pick a date",
                        selection: $pickerDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .onChange(of: pickerDate) { _, newDate in
                        showingDatePicker = false
                        Task { await viewModel.setDateFilter(newDate) }
                    }
                }

                // Divider before additional filter groups if needed
                if !SemanticFilter.statusFilters.isEmpty {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)

                    // Show status filters in a menu to save space
                    FilterMenu(
                        title: "More",
                        icon: "ellipsis.circle",
                        filters: SemanticFilter.statusFilters + SemanticFilter.sourceFilters,
                        viewModel: viewModel
                    )
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 0)
        }
        .frame(height: RecordingsHeaderLayout.secondaryBandHeight)
    }
}

// MARK: - Filter Menu (for overflow filters)

struct FilterMenu: View {
    let title: String
    let icon: String
    let filters: [SemanticFilter]
    @Bindable var viewModel: RecordingsViewModel

    private var activeCount: Int {
        filters.filter { viewModel.isSemanticFilterActive($0) }.count
    }

    var body: some View {
        Menu {
            ForEach(filters) { filter in
                Button {
                    Task {
                        await viewModel.toggleSemanticFilter(filter)
                    }
                } label: {
                    HStack {
                        Label(filter.label, systemImage: filter.icon)
                        if viewModel.isSemanticFilterActive(filter) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if activeCount > 0 {
                Divider()
                Button("Clear Filters") {
                    Task {
                        for filter in filters where viewModel.isSemanticFilterActive(filter) {
                            await viewModel.toggleSemanticFilter(filter)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(activeCount > 0 ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            .foregroundColor(activeCount > 0 ? .accentColor : .secondary)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Inline Search Field

struct InlineSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)?
    @FocusState.Binding var isFocused: Bool

    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            if isExpanded || !text.isEmpty {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit {
                        onSubmit?()
                    }
                    .frame(minWidth: 120, maxWidth: 200)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
                isFocused = true
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && text.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SemanticFilterChip(filter: .all, isActive: true) {}
        SemanticFilterChip(filter: .memos, isActive: false) {}
        SemanticFilterChip(filter: .today, isActive: true) {}

        Divider()

        FilterChipBar(viewModel: RecordingsViewModel.shared)
    }
    .padding()
    .frame(width: 500)
}
