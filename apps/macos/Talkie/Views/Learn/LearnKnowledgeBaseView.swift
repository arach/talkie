//
//  LearnKnowledgeBaseView.swift
//  Talkie macOS
//
//  Native shell for the Learn KB: search, article index, and app
//  actions stay in SwiftUI while each article renders in WKWebView.
//

import SwiftUI
import TalkieKit

struct LearnKnowledgeBaseView: View {
    let onBridgeAction: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var articles = LearnArticleStore.load()
    @State private var query = ""
    @State private var selectedArticleID: String?

    private var selectedArticle: LearnArticle {
        if let selectedArticleID,
           let article = articles.first(where: { $0.id == selectedArticleID }) {
            return article
        }
        return filteredArticles.first ?? articles.first!
    }

    private var filteredArticles: [LearnArticle] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return articles }

        let terms = trimmed.localizedLowercase
            .split(separator: " ")
            .map(String.init)

        return articles.filter { article in
            terms.allSatisfy { article.searchableText.localizedStandardContains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ScopeEdge.subtle)
            HStack(spacing: 0) {
                articleList
                    .frame(width: 286)
                Divider().overlay(ScopeEdge.subtle)
                LearnKnowledgeWebView(
                    article: selectedArticle,
                    colorScheme: colorScheme,
                    onBridgeAction: onBridgeAction
                )
                .id(selectedArticle.id)
                .frame(maxWidth: .infinity, minHeight: 540)
                .background(webBackground)
            }
            .frame(minHeight: 540)
        }
        .background(ScopeCanvas.surface.opacity(0.46))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if selectedArticleID == nil {
                selectedArticleID = articles.first?.id
            }
        }
        .onChange(of: query) {
            keepSelectionVisible()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    PhosphorDot(color: ScopeAmber.solid, size: 5)
                    Text("Knowledge base")
                        .font(ScopeType.eyebrow)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                }
                Text("Local web articles · native Talkie bridge")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            Spacer(minLength: 12)

            searchField
                .frame(width: 320)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ScopeInk.faint)
            TextField("Search Learn", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.primary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ScopeInk.subtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.54))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var articleList: some View {
        VStack(spacing: 0) {
            if filteredArticles.isEmpty {
                emptySearch
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredArticles) { article in
                            ArticleIndexRow(
                                article: article,
                                isSelected: article.id == selectedArticle.id,
                                onSelect: { selectedArticleID = article.id }
                            )
                        }
                    }
                }
            }
        }
        .background(ScopeCanvas.canvas.opacity(0.48))
    }

    private var emptySearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO MATCH")
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
            Text("Try a surface, shortcut, or provider name.")
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.faint)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }

    private var webBackground: Color {
        colorScheme == .dark ? Color.hex("0A0A0A").opacity(0.96) : ScopeCanvas.canvas
    }

    private func keepSelectionVisible() {
        let visibleIDs = Set(filteredArticles.map(\.id))
        if let selectedArticleID, visibleIDs.contains(selectedArticleID) {
            return
        }
        selectedArticleID = filteredArticles.first?.id
    }
}

private struct ArticleIndexRow: View {
    let article: LearnArticle
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isSelected ? ScopeAmber.solid : ScopeInk.faint.opacity(0.42))
                        .frame(width: 5, height: 5)
                    Text(article.eyebrow.uppercased())
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(isSelected ? ScopeAmber.solid : ScopeInk.subtle)
                    Spacer(minLength: 0)
                    if article.fileURL != nil {
                        Text("HTML")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.normal)
                            .foregroundStyle(ScopeInk.subtle)
                    }
                }

                Text(article.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.dim)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(article.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(3)
                    .lineSpacing(2)

                if !article.shortcuts.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(article.shortcuts.prefix(2), id: \.keys) { shortcut in
                            Text(shortcut.keys)
                                .font(ScopeType.chrome)
                                .tracking(ScopeType.Tracking.normal)
                                .foregroundStyle(ScopeInk.faint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.42))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(rowBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScopeEdge.subtle)
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return ScopeAmber.tint
        }
        if isHovered {
            return Color.white.opacity(0.34)
        }
        return Color.clear
    }
}
