import XCTest

@MainActor
final class SSHTerminalUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += [
            "-FASTLANE_SNAPSHOT",
            "--screenshotSkipSplash",
            "--enableConnectionCenter",
        ]
    }

    func testConnectToLocalSSHFixture() {
        app.launch()

        let settingsButton = app.buttons["dock.settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        tapElement(identifier: "settings.connectionCenter")
        tapElement(identifier: "connection.macBridge")
        tapElement(identifier: "bridge.sshTerminal")

        replaceText(in: app.textFields["ssh.host"].firstMatch, with: "127.0.0.1")
        replaceText(in: app.textFields["ssh.port"].firstMatch, with: "2222")
        replaceText(in: app.textFields["ssh.username"].firstMatch, with: "talkie")

        let passwordField = app.secureTextFields["ssh.password"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("talkie-demo")

        let connectButton = app.buttons["ssh.connect"].firstMatch
        XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
        connectButton.tap()

        let status = app.staticTexts["ssh.status.title"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))

        let connected = NSPredicate(format: "label == %@", "Connected")
        expectation(for: connected, evaluatedWith: status)
        waitForExpectations(timeout: 20)
    }

    private func tapElement(identifier: String) {
        let element = findElement(identifier: identifier)

        if element.waitForExistence(timeout: 2), element.isHittable {
            element.tap()
            return
        }

        for _ in 0..<5 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable {
                element.tap()
                return
            }
        }

        XCTFail("Failed to find tappable element: \(identifier)")
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()

        let deleteCount = 32
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deleteCount))
        element.typeText(text)
    }

    private func findElement(identifier: String) -> XCUIElement {
        let candidates = [
            app.buttons[identifier].firstMatch,
            app.otherElements[identifier].firstMatch,
            app.staticTexts[identifier].firstMatch,
        ]

        for candidate in candidates where candidate.exists {
            return candidate
        }

        return candidates[0]
    }
}
