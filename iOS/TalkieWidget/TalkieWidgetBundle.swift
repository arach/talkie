//
//  TalkieWidgetBundle.swift
//  TalkieWidget
//
//  Created by Arach Tchoupani on 2025-11-29.
//

import WidgetKit
import SwiftUI

@main
struct TalkieWidgetBundle: WidgetBundle {
    var body: some Widget {
        TalkieWidget()
        TalkieWidgetControl()
        TalkieWidgetLiveActivity()
    }
}
