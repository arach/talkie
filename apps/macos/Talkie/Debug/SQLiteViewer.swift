//
//  SQLiteViewer.swift
//  Talkie
//
//  Simple SQLite viewer for debugging database issues
//

import SwiftUI
import GRDB
import TalkieKit

#if DEBUG

struct SQLiteViewer: View {
    @State private var tables: [(name: String, count: Int)] = []
    @State private var selectedTable: String? = nil
    @State private var queryResults: [[String: String]] = []
    @State private var columns: [String] = []
    @State private var error: String?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    private var dbPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Talkie/talkie_grdb.sqlite").path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("SQLite Viewer")
                        .font(.headline)

                    Spacer()

                    Button("Refresh") {
                        Task { await loadTables() }
                    }

                    Button("Close") {
                        dismiss()
                    }
                }

                // Show actual database path
                Text(dbPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding()
            .background(Theme.current.surfaceBase)

            Divider()

            HSplitView {
                // Left: Tables list
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tables")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    Divider()

                    List(selection: $selectedTable) {
                        ForEach(tables, id: \.name) { table in
                            HStack {
                                Text(table.name)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Text("\(table.count)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .tag(table.name)
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 180, maxWidth: 220)

                // Right: Results
                VStack(spacing: 0) {
                    if let error = error {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isLoading {
                        BrailleSpinner()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if columns.isEmpty {
                        VStack {
                            Image(systemName: "tablecells")
                                .font(.largeTitle)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Text("Select a table")
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Results table
                        resultsTable
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await loadTables()
        }
        .onChange(of: selectedTable) { _, newTable in
            if let table = newTable {
                Task { await loadTableData(table) }
            }
        }
    }

    private var resultsTable: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // Rows
                    ForEach(Array(queryResults.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.self) { col in
                                let value = row[col] ?? ""
                                Text(value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(value == "NULL" ? .gray : Theme.current.foreground)
                                    .frame(minWidth: 120, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .lineLimit(1)
                            }
                        }
                        .background(index % 2 == 0 ? Theme.current.surface1 : Theme.current.surface2)
                    }
                } header: {
                    // Header
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { col in
                            Text(col)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.current.foreground)
                                .frame(minWidth: 120, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(Theme.current.surfaceBase)
                }
            }
        }
    }

    private func loadTables() async {
        isLoading = true
        error = nil

        do {
            let db = try await DatabaseManager.shared.databaseWhenReady()
            tables = try await db.read { db in
                let tableNames = try String.fetchAll(db, sql: """
                    SELECT name FROM sqlite_master
                    WHERE type='table' AND name NOT LIKE 'sqlite_%'
                    ORDER BY name
                """)

                return try tableNames.map { name in
                    let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(name)\"") ?? 0
                    return (name: name, count: count)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadTableData(_ tableName: String) async {
        isLoading = true
        error = nil
        queryResults = []
        columns = []

        do {
            let db = try await DatabaseManager.shared.databaseWhenReady()
            try await db.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \"\(tableName)\" LIMIT 100")
                if let first = rows.first {
                    columns = Array(first.columnNames)
                }
                queryResults = rows.map { row in
                    var dict: [String: String] = [:]
                    for col in row.columnNames {
                        let value: DatabaseValue = row[col]
                        switch value.storage {
                        case .null:
                            dict[col] = "NULL"
                        case .int64(let i):
                            dict[col] = "\(i)"
                        case .double(let d):
                            dict[col] = String(format: "%.2f", d)
                        case .string(let s):
                            dict[col] = String(s.prefix(50))
                        case .blob(let data):
                            dict[col] = "[\(data.count) bytes]"
                        }
                    }
                    return dict
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#endif
