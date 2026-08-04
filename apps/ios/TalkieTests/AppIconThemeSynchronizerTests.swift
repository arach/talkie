//
//  AppIconThemeSynchronizerTests.swift
//  TalkieTests
//


import XCTest
@testable import Talkie_iOS

final class AppIconThemeSynchronizerTests: XCTestCase {
    func testPorcelainUsesPrimaryBlueIcon() {
        XCTAssertNil(AppTheme.porcelain.alternateAppIconName)
    }

    func testEveryOtherThemeMapsToItsCompiledAlternateIcon() {
        let expectedNames: [AppTheme: String] = [
            .scope: "AppIconScope",
            .mineral: "AppIconMineral",
            .midnight: "AppIconMidnight",
            .tactical: "AppIconTactical",
            .ghost: "AppIconGhost",
            .lift: "AppIconLift",
            .graphite: "AppIconGraphite",
            .carbon: "AppIconCarbon",
            .ember: "AppIconEmber",
        ]

        for theme in AppTheme.allCases where theme != .porcelain {
            XCTAssertEqual(theme.alternateAppIconName, expectedNames[theme])
        }
    }
}
