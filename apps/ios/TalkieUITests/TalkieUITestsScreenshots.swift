import XCTest

// MARK: - Screenshot Spec

/// Declarative description of one screenshot.
/// Define what state the app should be in — the runner handles launch, wait, and capture.
struct ScreenshotSpec {
    let name: String
    let skipSplash: Bool
    let launchArguments: [String]
    let readyCondition: @MainActor (XCUIApplication) -> XCUIElement
    let navigate: (@MainActor (XCUIApplication) -> Void)?

    init(
        _ name: String,
        skipSplash: Bool = true,
        launchArguments: [String] = [],
        readyWhen readyCondition: @MainActor @escaping (XCUIApplication) -> XCUIElement,
        navigate: (@MainActor (XCUIApplication) -> Void)? = nil
    ) {
        self.name = name
        self.skipSplash = skipSplash
        self.launchArguments = launchArguments
        self.readyCondition = readyCondition
        self.navigate = navigate
    }
}

// MARK: - Screen Catalog

/// All screenshot specs in one place.
/// Adding a new screenshot = adding one entry here + one `func testNN_Name` one-liner.
extension ScreenshotSpec {
    static let splash = ScreenshotSpec(
        "00_Splash",
        skipSplash: false,
        readyWhen: { $0.otherElements["splash.screen"].firstMatch }
    )

    static let home = ScreenshotSpec(
        "01_Home",
        readyWhen: { $0.buttons["memo.row"].firstMatch }
    )

    static let recording = ScreenshotSpec(
        "02_Recording",
        readyWhen: { $0.buttons["recording.stop"].firstMatch },
        navigate: { app in
            // Try as accessibility element first, fall back to button
            let record = app.otherElements["dock.record"].firstMatch
            if record.waitForExistence(timeout: 5) {
                record.tap()
            } else {
                app.buttons["dock.record"].firstMatch.tap()
            }
        }
    )

    static let memoDetail = ScreenshotSpec(
        "03_MemoDetail",
        launchArguments: ["--memo"],
        readyWhen: {
            $0.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "TRANSCRIPT")).firstMatch
        }
    )

    static let settings = ScreenshotSpec(
        "04_Settings",
        launchArguments: ["--settings"],
        readyWhen: {
            $0.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "SETTINGS")).firstMatch
        }
    )

    static let keyboard = ScreenshotSpec(
        "05_Keyboard",
        launchArguments: ["--composeKeyboard"],
        readyWhen: { $0.buttons["compose.keyboard.toggle"].firstMatch }
    )
}

// MARK: - Test Runner

@MainActor
final class TalkieUITestsScreenshots: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        setupSnapshot(app, waitForAnimations: false)
        app.launchArguments += ["-FASTLANE_SNAPSHOT"]
    }

    /// Launch app per spec, navigate if needed, wait for ready element, capture.
    private func capture(_ spec: ScreenshotSpec) {
        if spec.skipSplash {
            app.launchArguments += ["--screenshotSkipSplash"]
        }
        app.launchArguments += spec.launchArguments
        app.launch()

        // Navigate to the target screen (if the spec requires taps)
        spec.navigate?(app)

        // Wait for the screen to be ready
        let readyElement = spec.readyCondition(app)
        XCTAssertTrue(
            readyElement.waitForExistence(timeout: 10),
            "\(spec.name): ready element should exist"
        )

        snapshot(spec.name, timeWaitingForIdle: 0)
    }

    // MARK: - Tests

    func test00_Splash()     { capture(.splash) }
    func test01_Home()       { capture(.home) }
    func test02_Recording()  { capture(.recording) }
    func test03_MemoDetail() { capture(.memoDetail) }
    func test04_Settings()   { capture(.settings) }
    func test05_Keyboard()   { capture(.keyboard) }
}

// MARK: - Screenshot Harness Helpers

private extension TalkieUITestsScreenshots {
    func dismissSystemAlertsIfNeeded() {
        let alerts = [
            app.alerts.firstMatch,
            XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch,
        ]

        for alert in alerts where alert.waitForExistence(timeout: 1) {
            for title in ["Don’t Allow", "Don't Allow", "Allow", "OK"] {
                let button = alert.buttons[title].firstMatch
                if button.exists {
                    button.tap()
                    return
                }
            }
            alert.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.82)).tap()
            return
        }
    }
}

// MARK: - Phase 0 Chrome Theme Matrix

extension TalkieUITestsScreenshots {
    func testPhase0ThemeChromeScreenshots() {
        let themes = ["scope", "midnight", "tactical", "ghost", "lift"]
        let states = ["resting", "expanded", "listening"]

        for theme in themes {
            for state in states {
                app.terminate()
                app.launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
                app.launchArguments = [
                    "-FASTLANE_SNAPSHOT",
                    "--screenshotSkipSplash",
                    "--screenshotTheme", theme,
                    "--screenshotChromeState", state,
                ]
                app.launch()
                dismissSystemAlertsIfNeeded()

                let label: String
                switch state {
                case "expanded": label = "Hold to talk"
                case "listening": label = "Listening — release to send"
                default: label = "Summon Talkie controls"
                }

                XCTAssertTrue(
                    app.buttons[label].firstMatch.waitForExistence(timeout: 10),
                    "theme-\(theme)-\(state): voice chrome should be ready"
                )
                dismissSystemAlertsIfNeeded()
                snapshot("theme-\(theme)-\(state)", timeWaitingForIdle: 0)
            }
        }
    }
}

// MARK: - M2 Compose Wiring Screenshots

extension TalkieUITestsScreenshots {
    func testM2ComposeStateScreenshots() {
        let states = ["idle", "dictating", "listening", "generating", "diff"]

        for state in states {
            app.terminate()
            app.launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
            app.launchArguments = [
                "-FASTLANE_SNAPSHOT",
                "--screenshotSkipSplash",
                "--screenshotTheme", "scope",
                "--composeState", state,
            ]
            app.launch()
            dismissSystemAlertsIfNeeded()

            let composeHeader = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "COMPOSE WITH")).firstMatch
            XCTAssertTrue(
                composeHeader.waitForExistence(timeout: 10),
                "state-\(state): compose screen should be ready"
            )
            snapshot("state-\(state)", timeWaitingForIdle: 0)
        }
    }

    func testM2HomeToComposeScreenshot() {
        app.terminate()
        app.launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
        app.launchArguments = [
            "-FASTLANE_SNAPSHOT",
            "--screenshotSkipSplash",
            "--screenshotTheme", "scope",
        ]
        app.launch()
        dismissSystemAlertsIfNeeded()

        let continueButton = app.buttons["Continue ›"].firstMatch
        XCTAssertTrue(
            continueButton.waitForExistence(timeout: 10),
            "Home pick-up continue button should exist"
        )
        continueButton.tap()

        let composeHeader = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "COMPOSE WITH")).firstMatch
        XCTAssertTrue(
            composeHeader.waitForExistence(timeout: 10),
            "Home should navigate to Compose"
        )
        snapshot("home-to-compose", timeWaitingForIdle: 0)
    }
}

// MARK: - Compose Action Tray Wiring

extension TalkieUITestsScreenshots {
    func testM2ComposeActionTrayButtons() {
        app.terminate()
        app.launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
        app.launchArguments = [
            "-FASTLANE_SNAPSHOT",
            "--screenshotSkipSplash",
            "--screenshotTheme", "scope",
            "--composeState", "idle",
        ]
        app.launch()
        dismissSystemAlertsIfNeeded()

        let keyboardButton = app.buttons["Keyboard"].firstMatch
        XCTAssertTrue(keyboardButton.waitForExistence(timeout: 10), "Keyboard tray button should exist")
        keyboardButton.tap()
        XCTAssertTrue(keyboardButton.exists, "Keyboard tray button should remain available after requesting focus")

        let voiceButton = app.buttons["Voice command"].firstMatch
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 10), "Voice command tray button should exist")
        voiceButton.tap()
        XCTAssertTrue(app.buttons["Accept"].firstMatch.waitForExistence(timeout: 10), "Voice command button should produce a mock diff")
    }
}
