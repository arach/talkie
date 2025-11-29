//
//  TalkieWidgetBundle.swift
//  TalkieWidget
//
//  Widget bundle for Talkie
//

import WidgetKit
import SwiftUI

@main
struct TalkieWidgetBundle: WidgetBundle {
    var body: some Widget {
        TalkieWidget()
        TalkieWidgetControl()
    }
}
