//
//  WorkflowMigrationService.swift
//  Talkie
//
//  Migrates imported workflows from old Keychain-based storage (WorkflowStore)
//  to the new unified system (WorkflowFileRepository + CredentialStore).
//

import Foundation
import TalkieKit

private let log = Log(.workflow)

// MARK: - Migration Service

enum WorkflowMigrationService {

    private static let migrationVersionKey = "WorkflowMigration.version"
    private static let currentMigrationVersion = 1

    // MARK: - Run Migration

    /// Run migration if needed (call on app launch)
    static func runMigrationIfNeeded() async {
        let lastMigrationVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)

        guard lastMigrationVersion < currentMigrationVersion else {
            log.debug("Workflow migration already at version \(currentMigrationVersion)")
            return
        }

        log.info("Running workflow migration from version \(lastMigrationVersion) to \(currentMigrationVersion)")

        do {
            // Migration 1: Move from WorkflowStore (Keychain) to WorkflowFileRepository
            if lastMigrationVersion < 1 {
                try await migrateFromKeychainToFileRepository()
            }

            UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
            log.info("Workflow migration completed successfully")
        } catch {
            log.error("Workflow migration failed: \(error)")
        }
    }

    // MARK: - Migration 1: Keychain to FileRepository

    private static func migrateFromKeychainToFileRepository() async throws {
        log.info("Migrating workflows from Keychain to FileRepository...")

        // Get all workflows from old store
        let oldWorkflows = await WorkflowStore.shared.listWorkflows()

        guard !oldWorkflows.isEmpty else {
            log.info("No workflows to migrate from Keychain")
            return
        }

        log.info("Found \(oldWorkflows.count) workflows to migrate")

        var migratedCount = 0
        var failedCount = 0

        for oldWorkflow in oldWorkflows {
            do {
                // Convert to new format
                let (newWorkflow, credentials, secrets) = try convertStoredWorkflow(oldWorkflow)

                // Store credentials
                for credential in credentials {
                    if let secret = secrets[credential.id] {
                        try await CredentialStore.shared.store(credential, secret: secret)
                    }
                }

                // Save workflow to imported/ directory
                try await WorkflowFileRepository.shared.save(newWorkflow, source: .imported)

                // Delete from old store
                try await WorkflowStore.shared.deleteWorkflow(id: oldWorkflow.id)

                migratedCount += 1
                log.info("Migrated workflow: \(oldWorkflow.name)")
            } catch {
                failedCount += 1
                log.error("Failed to migrate workflow '\(oldWorkflow.name)': \(error)")
            }
        }

        log.info("Migration complete: \(migratedCount) migrated, \(failedCount) failed")
    }

    // MARK: - Convert StoredWorkflow

    private static func convertStoredWorkflow(_ stored: StoredWorkflow) throws
        -> (WorkflowDefinition, [SecureCredential], [UUID: String])
    {
        var steps: [WorkflowStep] = []
        var credentials: [SecureCredential] = []
        var secrets: [UUID: String] = [:]

        // Convert storage credentials
        if let storage = stored.credentials.storage {
            let credentialId = UUID()
            let (provider, bucket, region, endpoint, accessKeyId, secretKey) = extractStorageDetails(storage)

            steps.append(WorkflowStep(
                type: .cloudUpload,
                config: .cloudUpload(CloudUploadStepConfig(
                    provider: provider,
                    bucket: bucket,
                    region: region,
                    endpoint: endpoint,
                    pathTemplate: "audio/{{MEMO_ID}}.m4a",
                    credentialId: credentialId
                )),
                outputKey: "audioUrl"
            ))

            let credential = SecureCredential(
                id: credentialId,
                name: "Storage (\(provider.displayName))",
                type: .awsSigningKey(accessKeyId: accessKeyId),
                scope: CredentialScope.s3(endpoint: endpoint, region: region)
            )
            credentials.append(credential)
            secrets[credentialId] = secretKey
        }

        // Convert notify credentials
        if let notify = stored.credentials.notify {
            let credentialId = UUID()
            let (step, credential, secret) = makeNotifyStep(notify, credentialId: credentialId)
            steps.append(step)
            credentials.append(credential)
            secrets[credentialId] = secret
        }

        // Create source metadata
        let sourceUrl = URL(string: stored.sourceUrl ?? "https://unknown.local") ?? URL(string: "https://unknown.local")!

        let workflow = WorkflowDefinition(
            id: stored.id,  // Preserve original ID
            name: stored.name,
            description: stored.description ?? "Migrated workflow",
            icon: stored.icon,
            color: .cyan,
            steps: steps,
            isEnabled: true,
            source: .imported(ImportMetadata(
                sourceUrl: sourceUrl,
                importedAt: stored.importedAt,
                fingerprint: "migrated-\(stored.id.uuidString)"
            ))
        )

        return (workflow, credentials, secrets)
    }

    private static func extractStorageDetails(_ storage: StorageCredentials) -> (CloudStorageProvider, String, String?, String?, String, String) {
        switch storage {
        case .r2(let creds):
            return (.r2, creds.bucket, creds.region, creds.endpoint, creds.accessKeyId, creds.secretAccessKey)
        case .s3(let creds):
            return (.s3, creds.bucket, creds.region, creds.endpoint, creds.accessKeyId, creds.secretAccessKey)
        case .convex(let creds):
            return (.s3, "convex", nil, creds.url, "convex", creds.deployKey)
        }
    }

    private static func makeNotifyStep(_ notify: NotifyCredentials, credentialId: UUID) -> (WorkflowStep, SecureCredential, String) {
        switch notify {
        case .telegram(let creds):
            let step = WorkflowStep(
                type: .webhook,
                config: .webhook(WebhookStepConfig(
                    url: "https://api.telegram.org/bot{{CREDENTIAL:\(credentialId)}}/sendMessage",
                    method: .post,
                    headers: ["Content-Type": "application/json"],
                    bodyTemplate: """
                    {"chat_id":"\(creds.chatId)","text":"**{{TITLE}}**\\n\\n{{TRANSCRIPT}}","parse_mode":"Markdown"}
                    """
                )),
                outputKey: "notifyResult"
            )
            let credential = SecureCredential(
                id: credentialId,
                name: "Telegram Bot",
                type: .telegramBot(chatId: creds.chatId),
                scope: CredentialScope.telegram()
            )
            return (step, credential, creds.botToken)

        case .discord(let creds):
            let step = WorkflowStep(
                type: .webhook,
                config: .webhook(WebhookStepConfig(
                    url: creds.webhookUrl,
                    method: .post,
                    headers: ["Content-Type": "application/json"],
                    bodyTemplate: """
                    {"content":"**{{TITLE}}**\\n\\n{{TRANSCRIPT}}"}
                    """
                )),
                outputKey: "notifyResult"
            )
            let credential = SecureCredential(
                id: credentialId,
                name: "Discord Webhook",
                type: .discordWebhook,
                scope: CredentialScope.discord()
            )
            return (step, credential, creds.webhookUrl)

        case .webhook(let creds):
            let step = WorkflowStep(
                type: .webhook,
                config: .webhook(WebhookStepConfig(
                    url: creds.url,
                    method: .post,
                    headers: creds.headers ?? [:],
                    bodyTemplate: nil,
                    includeTranscript: true,
                    includeMetadata: true
                )),
                outputKey: "notifyResult"
            )
            let host = URL(string: creds.url)?.host ?? "*"
            let credential = SecureCredential(
                id: credentialId,
                name: "Webhook",
                type: .apiKey,
                scope: CredentialScope(allowedHosts: [host])
            )
            return (step, credential, creds.url)
        }
    }
}
