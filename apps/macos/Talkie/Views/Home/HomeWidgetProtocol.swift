//
//  HomeWidgetProtocol.swift
//  Talkie
//
//  Protocol and size enum for home page widgets.
//  Widgets are either half-width (2 per row) or full-width.
//

import SwiftUI

// MARK: - Widget Size

enum HomeWidgetSize {
    /// Half-width: two widgets per row
    case half
    /// Full-width: one widget per row
    case full
}

// MARK: - Home Widget Protocol

@MainActor
protocol HomeWidget: View {
    var widgetID: String { get }
    var title: String { get }
    var size: HomeWidgetSize { get }
}
