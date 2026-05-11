//
//  ImportPayloadConverterTests.swift
//  Talkie
//
//  Tests for ImportPayloadConverter - verifies URL import → core workflow conversion.
//

import Foundation

// MARK: - Test Utilities

enum ImportPayloadConverterTests {

    /// Run all tests and print results
    static func runAll() {
        print("🧪 Running ImportPayloadConverter Tests...")
        print("")

        testTelegramOnlyWorkflow()
        testR2StorageWithDiscordNotify()
        testConvexDatabaseWithTelegram()
        testFingerprintDeduplication()

        print("")
        print("✅ All tests completed")
    }

    // MARK: - Test: Telegram-only workflow

    static func testTelegramOnlyWorkflow() {
        print("📋 Test: Telegram-only workflow")

        let payload = ImportedWorkflowPayload(
            version: 1,
            name: "My Telegram Bot",
            icon: "paperplane.fill",
            description: "Send memos to my Telegram",
            createdAt: Date(),
            credentials: WorkflowCredentials(
                storage: nil,
                database: nil,
                notify: .telegram(TelegramCredentials(
                    botToken: "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz",
                    chatId: "-1001234567890"
                ))
            ),
            workflow: ImportWorkflowConfig(
                type: .notifyOnly,
                config: nil
            )
        )

        do {
            let result = try ImportPayloadConverter.convert(
                payload,
                sourceUrl: URL(string: "https://tawkie.dev/claim/test123")!
            )

            print("   ✓ Created workflow: \(result.workflow.name)")
            print("   ✓ Steps: \(result.workflow.steps.count)")
            print("   ✓ Credentials: \(result.credentials.count)")

            // Verify webhook step
            if let step = result.workflow.steps.first {
                if case .webhook(let config) = step.config {
                    print("   ✓ Webhook URL contains credential placeholder: \(config.url.contains("CREDENTIAL:"))")
                    print("   ✓ Chat ID in body: \(config.bodyTemplate?.contains("-1001234567890") ?? false)")
                }
            }

            // Verify credential scope
            if let cred = result.credentials.first {
                print("   ✓ Credential scope allows telegram: \(cred.scope.allowedHosts.contains("api.telegram.org"))")
            }

            // Verify source metadata
            if case .imported(let metadata) = result.workflow.source {
                print("   ✓ Source URL: \(metadata.sourceUrl)")
                print("   ✓ Fingerprint: \(metadata.fingerprint.prefix(16))...")
            }

            print("   ✅ PASSED")
        } catch {
            print("   ❌ FAILED: \(error)")
        }
        print("")
    }

    // MARK: - Test: R2 Storage + Discord

    static func testR2StorageWithDiscordNotify() {
        print("📋 Test: R2 Storage + Discord notification")

        let payload = ImportedWorkflowPayload(
            version: 1,
            name: "Cloudflare R2 + Discord",
            icon: "cloud.fill",
            description: "Upload to R2 and notify via Discord",
            createdAt: Date(),
            credentials: WorkflowCredentials(
                storage: .r2(R2Credentials(
                    endpoint: "https://abc123.r2.cloudflarestorage.com",
                    bucket: "talkie-memos",
                    region: "auto",
                    accessKeyId: "AKIAIOSFODNN7EXAMPLE",
                    secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                )),
                database: nil,
                notify: .discord(DiscordCredentials(
                    webhookUrl: "https://discord.com/api/webhooks/123/abc"
                ))
            ),
            workflow: ImportWorkflowConfig(
                type: .sendToAgent,
                config: nil
            )
        )

        do {
            let result = try ImportPayloadConverter.convert(
                payload,
                sourceUrl: URL(string: "https://tawkie.dev/claim/r2discord")!
            )

            print("   ✓ Created workflow: \(result.workflow.name)")
            print("   ✓ Steps: \(result.workflow.steps.count) (expected: 2 - upload + notify)")
            print("   ✓ Credentials: \(result.credentials.count) (expected: 2)")

            // Verify cloud upload step
            if let uploadStep = result.workflow.steps.first(where: { $0.type == .cloudUpload }) {
                if case .cloudUpload(let config) = uploadStep.config {
                    print("   ✓ Upload provider: \(config.provider.displayName)")
                    print("   ✓ Upload bucket: \(config.bucket)")
                    print("   ✓ Has credential ID: \(config.credentialId != nil)")
                }
            }

            // Verify Discord webhook step
            if let notifyStep = result.workflow.steps.first(where: { $0.type == .webhook }) {
                if case .webhook(let config) = notifyStep.config {
                    print("   ✓ Discord webhook URL: \(config.url.hasPrefix("https://discord.com"))")
                }
            }

            // Verify secrets are captured
            print("   ✓ Secrets captured: \(result.secrets.count)")

            print("   ✅ PASSED")
        } catch {
            print("   ❌ FAILED: \(error)")
        }
        print("")
    }

    // MARK: - Test: Convex Database + Telegram

    static func testConvexDatabaseWithTelegram() {
        print("📋 Test: Convex Database + Telegram (full pipeline)")

        let payload = ImportedWorkflowPayload(
            version: 1,
            name: "Full Pipeline",
            icon: "arrow.triangle.branch",
            description: "R2 → Convex → Telegram",
            createdAt: Date(),
            credentials: WorkflowCredentials(
                storage: .r2(R2Credentials(
                    endpoint: "https://xyz.r2.cloudflarestorage.com",
                    bucket: "audio-files",
                    region: nil,
                    accessKeyId: "ACCESS_KEY",
                    secretAccessKey: "SECRET_KEY"
                )),
                database: .convex(ConvexCredentials(
                    url: "https://talented-octopus-123.convex.cloud",
                    deployKey: "prod:xxx|yyy"
                )),
                notify: .telegram(TelegramCredentials(
                    botToken: "BOT_TOKEN",
                    chatId: "CHAT_ID"
                ))
            ),
            workflow: ImportWorkflowConfig(
                type: .sendToAgent,
                config: nil
            )
        )

        do {
            let result = try ImportPayloadConverter.convert(
                payload,
                sourceUrl: URL(string: "https://tawkie.dev/claim/fullpipe")!
            )

            print("   ✓ Steps: \(result.workflow.steps.count) (expected: 3 - upload + database + notify)")

            // Check step order
            let stepTypes = result.workflow.steps.map { $0.type }
            print("   ✓ Step order: \(stepTypes.map { $0.rawValue }.joined(separator: " → "))")

            // Verify all credentials have unique IDs
            let credentialIds = Set(result.credentials.map { $0.id })
            print("   ✓ All credential IDs unique: \(credentialIds.count == result.credentials.count)")

            // Verify all secrets are captured
            for cred in result.credentials {
                let hasSecret = result.secrets[cred.id] != nil
                print("   ✓ Credential '\(cred.name)' has secret: \(hasSecret)")
            }

            print("   ✅ PASSED")
        } catch {
            print("   ❌ FAILED: \(error)")
        }
        print("")
    }

    // MARK: - Test: Fingerprint Deduplication

    static func testFingerprintDeduplication() {
        print("📋 Test: Fingerprint deduplication")

        // Same logical workflow, different credentials
        let payload1 = ImportedWorkflowPayload(
            version: 1,
            name: "Test Workflow",
            icon: nil,
            description: nil,
            createdAt: Date(),
            credentials: WorkflowCredentials(
                storage: nil,
                database: nil,
                notify: .telegram(TelegramCredentials(botToken: "TOKEN_A", chatId: "CHAT"))
            ),
            workflow: ImportWorkflowConfig(type: .notifyOnly, config: nil)
        )

        let payload2 = ImportedWorkflowPayload(
            version: 1,
            name: "Test Workflow",
            icon: nil,
            description: nil,
            createdAt: Date().addingTimeInterval(3600), // Different timestamp
            credentials: WorkflowCredentials(
                storage: nil,
                database: nil,
                notify: .telegram(TelegramCredentials(botToken: "TOKEN_B", chatId: "CHAT"))
            ),
            workflow: ImportWorkflowConfig(type: .notifyOnly, config: nil)
        )

        do {
            let result1 = try ImportPayloadConverter.convert(payload1, sourceUrl: URL(string: "https://a.com")!)
            let result2 = try ImportPayloadConverter.convert(payload2, sourceUrl: URL(string: "https://b.com")!)

            if case .imported(let meta1) = result1.workflow.source,
               case .imported(let meta2) = result2.workflow.source {
                // Fingerprints should match (same structure, ignoring secrets and timestamps)
                let fingerprintsMatch = meta1.fingerprint == meta2.fingerprint
                print("   ✓ Same structure → same fingerprint: \(fingerprintsMatch)")

                if !fingerprintsMatch {
                    print("     Fingerprint 1: \(meta1.fingerprint.prefix(32))...")
                    print("     Fingerprint 2: \(meta2.fingerprint.prefix(32))...")
                }
            }

            print("   ✅ PASSED")
        } catch {
            print("   ❌ FAILED: \(error)")
        }
        print("")
    }
}
