//
//  SkillFileFormatTests.swift
//  Talkie macOS
//
//  Lightweight debug-command tests for .skill.md parsing.
//

import Foundation

enum SkillFileFormatTests {
    static func runAll() {
        print("🧪 Running SkillFileFormat tests...")
        testAtomicSkillRoundTrip()
        testFrontmatterOnlyParsesWithEmptySteps()
        testBodyOnlyThrows()
        testBundledDailyStandupStarterParses()
        print("✅ SkillFileFormat tests completed")
    }

    private static func testAtomicSkillRoundTrip() {
        let markdown = """
        ---
        id: 00000000-0000-0000-0000-000000000011
        name: Daily Standup
        description: Three bullets, Claude tightens the language, posted to #standup before you stand up.
        icon: person.3.fill
        color: blue
        isEnabled: true
        ---

        WHEN voice "standup"

        WITH dictation
              ↳ three bullets

        DO   slack.post
              ↳ channel: #standup
              ↳ polish: claude.tighten

        THEN voice ack
        """

        do {
            let definition = try parseSkillFile(markdown)
            expect(definition.name == "Daily Standup", "Expected parsed name")
            expect(definition.steps.map(\.type) == [.trigger, .transcribe, .llm, .webhook, .speak], "Expected trigger → transcribe → llm → webhook → speak")

            guard case .webhook(let webhook) = definition.steps[3].config else {
                fail("Expected Slack webhook step")
                return
            }
            expect(webhook.url == SkillFileFormat.slackWebhookURLPlaceholder, "Expected Slack webhook UserDefaults placeholder")
            expect(webhook.bodyTemplate?.contains("{{PREVIOUS_OUTPUT_JSON}}") == true, "Expected JSON-safe previous output placeholder")

            let serialized = serializeSkill(definition)
            let reparsed = try parseSkillFile(serialized)
            let reserialized = serializeSkill(reparsed)
            expect(serialized == reserialized, "Expected canonical serialize(parse(x)) to be stable")
            print("  ✓ atomic skill round-trip")
        } catch {
            fail("Atomic skill round-trip threw: \(error)")
        }
    }

    private static func testFrontmatterOnlyParsesWithEmptySteps() {
        let markdown = """
        ---
        name: Empty Skill
        description: Metadata only.
        icon: wand.and.stars
        color: teal
        isEnabled: true
        ---
        """

        do {
            let definition = try parseSkillFile(markdown)
            expect(definition.name == "Empty Skill", "Expected metadata-only name")
            expect(definition.steps.isEmpty, "Expected no steps")
            print("  ✓ frontmatter-only parses with empty steps")
        } catch {
            fail("Frontmatter-only parse threw: \(error)")
        }
    }

    private static func testBodyOnlyThrows() {
        do {
            _ = try parseSkillFile("WHEN voice \"standup\"\nDO slack.post")
            fail("Expected body-only file to throw")
        } catch SkillFileFormatError.missingFrontmatter {
            print("  ✓ body-only file throws missingFrontmatter")
        } catch {
            fail("Expected missingFrontmatter, got: \(error)")
        }
    }

    private static func testBundledDailyStandupStarterParses() {
        do {
            guard let url = Bundle.main.url(
                forResource: "daily-standup",
                withExtension: "skill.md",
                subdirectory: "Resources/Starters"
            ) else {
                fail("Expected bundled Resources/Starters/daily-standup.skill.md")
                return
            }

            let markdown = try String(contentsOf: url, encoding: .utf8)
            let definition = try parseSkillFile(markdown)
            expect(definition.name == "Daily Standup", "Expected bundled Daily Standup name")
            expect(definition.steps.map(\.type) == [.trigger, .transcribe, .llm, .webhook, .speak], "Expected bundled Daily Standup executable step chain")

            guard case .webhook(let webhook) = definition.steps[3].config else {
                fail("Expected bundled Daily Standup webhook step")
                return
            }

            expect(webhook.url == SkillFileFormat.slackWebhookURLPlaceholder, "Expected bundled Daily Standup to read Slack URL from UserDefaults placeholder")
            print("  ✓ bundled Daily Standup starter parses")
        } catch {
            fail("Bundled Daily Standup parse threw: \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) {
        print("  ❌ \(message)")
        assertionFailure(message)
    }
}
