//
//  ImportPayloadConverter.swift
//  Talkie
//
//  Converts ImportedWorkflowPayload to core WorkflowDefinition + credentials.
//  Presets (Telegram, Discord, etc.) are compiled to explicit webhook configs at import time.
//

import Foundation
import CryptoKit
import TalkieKit

private let log = Log(.workflow)

// MARK: - Converter Result

struct ImportConversionResult {
    let workflow: WorkflowDefinition
    let credentials: [SecureCredential]
    let secrets: [UUID: String]  // Maps credential ID to its secret value
}

// MARK: - Import Payload Converter

enum ImportPayloadConverter {

    // MARK: - Convert

    /// Convert an imported workflow payload to a core WorkflowDefinition with credentials
    static func convert(_ payload: ImportedWorkflowPayload, sourceUrl: URL) throws -> ImportConversionResult {
        // Generate fingerprint for deduplication
        let fingerprint = computeFingerprint(payload)

        var steps: [WorkflowStep] = []
        var credentials: [SecureCredential] = []
        var secrets: [UUID: String] = [:]

        // 1. Cloud upload step (if storage configured)
        if let storage = payload.credentials.storage {
            let (step, credential, secret) = try makeCloudUploadStep(storage)
            steps.append(step)
            credentials.append(credential)
            secrets[credential.id] = secret
        }

        // 2. Database step (if configured) - uses webhook
        if let database = payload.credentials.database {
            let (step, credential, secret) = try makeDatabaseWebhookStep(database)
            steps.append(step)
            credentials.append(credential)
            secrets[credential.id] = secret
        }

        // 3. Notify step (if configured) - compiles preset to explicit webhook
        if let notify = payload.credentials.notify {
            let (step, credential, secret) = try makeNotifyWebhookStep(notify)
            steps.append(step)
            credentials.append(credential)
            secrets[credential.id] = secret
        }

        // Create the workflow definition
        let workflow = WorkflowDefinition(
            id: UUID(),
            name: payload.name,
            description: payload.description ?? "Imported workflow",
            icon: payload.icon ?? "paperplane.fill",
            color: .cyan,
            steps: steps,
            isEnabled: true,
            isPinned: false,
            autoRun: false,
            source: .imported(ImportMetadata(
                sourceUrl: sourceUrl,
                importedAt: Date(),
                fingerprint: fingerprint
            ))
        )

        log.info("Converted import payload to workflow: \(workflow.name) with \(steps.count) steps and \(credentials.count) credentials")

        return ImportConversionResult(
            workflow: workflow,
            credentials: credentials,
            secrets: secrets
        )
    }

    // MARK: - Cloud Upload Step

    private static func makeCloudUploadStep(_ storage: StorageCredentials) throws -> (WorkflowStep, SecureCredential, String) {
        let credentialId = UUID()

        let (provider, bucket, region, endpoint, accessKeyId, secretKey) = extractStorageDetails(storage)

        let step = WorkflowStep(
            type: .cloudUpload,
            config: .cloudUpload(CloudUploadStepConfig(
                provider: provider,
                bucket: bucket,
                region: region,
                endpoint: endpoint,
                pathTemplate: "audio/{{MEMO_ID}}.m4a",
                credentialId: credentialId,
                contentType: "audio/mp4"
            )),
            outputKey: "audioUrl"
        )

        let scope = CredentialScope.s3(endpoint: endpoint, region: region)
        let credential = SecureCredential(
            id: credentialId,
            name: "\(provider.displayName) Storage",
            type: .awsSigningKey(accessKeyId: accessKeyId),
            scope: scope
        )

        return (step, credential, secretKey)
    }

    private static func extractStorageDetails(_ storage: StorageCredentials) -> (CloudStorageProvider, String, String?, String?, String, String) {
        switch storage {
        case .r2(let creds):
            return (.r2, creds.bucket, creds.region, creds.endpoint, creds.accessKeyId, creds.secretAccessKey)
        case .s3(let creds):
            return (.s3, creds.bucket, creds.region, creds.endpoint, creds.accessKeyId, creds.secretAccessKey)
        case .convex(let creds):
            // Convex storage uses a different upload mechanism
            return (.s3, "convex", nil, creds.url, "convex", creds.deployKey)
        }
    }

    // MARK: - Database Webhook Step

    private static func makeDatabaseWebhookStep(_ database: DatabaseCredentials) throws -> (WorkflowStep, SecureCredential, String) {
        let credentialId = UUID()

        let (url, deployKey, scope) = extractDatabaseDetails(database)

        let step = WorkflowStep(
            type: .webhook,
            config: .webhook(WebhookStepConfig(
                url: "\(url)/api/mutation",
                method: .post,
                headers: ["Content-Type": "application/json"],
                bodyTemplate: """
                {
                    "path": "memos:create",
                    "args": {
                        "id": "{{MEMO_ID}}",
                        "title": "{{TITLE}}",
                        "transcript": "{{TRANSCRIPT}}",
                        "audioUrl": "{{audioUrl}}",
                        "duration": {{DURATION}},
                        "createdAt": "{{DATE_ISO}}"
                    }
                }
                """,
                includeTranscript: false,
                includeMetadata: false,
                auth: .bearer(credentialId: credentialId)
            )),
            outputKey: "databaseResult"
        )

        let credential = SecureCredential(
            id: credentialId,
            name: "Database Deploy Key",
            type: .convexDeployKey(url: url),
            scope: scope
        )

        return (step, credential, deployKey)
    }

    private static func extractDatabaseDetails(_ database: DatabaseCredentials) -> (String, String, CredentialScope) {
        switch database {
        case .convex(let creds):
            return (creds.url, creds.deployKey, CredentialScope.convex(url: creds.url))
        case .turso(let creds):
            return (creds.url, creds.authToken, CredentialScope(allowedHosts: [URL(string: creds.url)?.host ?? "*.turso.io"]))
        }
    }

    // MARK: - Notify Webhook Step

    private static func makeNotifyWebhookStep(_ notify: NotifyCredentials) throws -> (WorkflowStep, SecureCredential, String) {
        switch notify {
        case .telegram(let creds):
            return makeTelegramStep(creds)
        case .discord(let creds):
            return makeDiscordStep(creds)
        case .webhook(let creds):
            return makeGenericWebhookStep(creds)
        }
    }

    private static func makeTelegramStep(_ creds: TelegramCredentials) -> (WorkflowStep, SecureCredential, String) {
        let credentialId = UUID()

        // Token is embedded in URL for Telegram API
        let step = WorkflowStep(
            type: .webhook,
            config: .webhook(WebhookStepConfig(
                url: "https://api.telegram.org/bot{{CREDENTIAL:\(credentialId)}}/sendMessage",
                method: .post,
                headers: ["Content-Type": "application/json"],
                bodyTemplate: """
                {
                    "chat_id": "\(creds.chatId)",
                    "text": "**{{TITLE}}**\\n\\n{{TRANSCRIPT}}\\n\\n{{audioUrl}}",
                    "parse_mode": "Markdown"
                }
                """,
                includeTranscript: false,
                includeMetadata: false,
                auth: nil  // Token is in URL for Telegram
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
    }

    private static func makeDiscordStep(_ creds: DiscordCredentials) -> (WorkflowStep, SecureCredential, String) {
        let credentialId = UUID()

        let step = WorkflowStep(
            type: .webhook,
            config: .webhook(WebhookStepConfig(
                url: creds.webhookUrl,
                method: .post,
                headers: ["Content-Type": "application/json"],
                bodyTemplate: """
                {
                    "content": "**{{TITLE}}**\\n\\n{{TRANSCRIPT}}\\n\\n{{audioUrl}}"
                }
                """,
                includeTranscript: false,
                includeMetadata: false,
                auth: nil  // Discord webhook URLs include auth
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
    }

    private static func makeGenericWebhookStep(_ creds: WebhookCredentials) -> (WorkflowStep, SecureCredential, String) {
        let credentialId = UUID()

        var headers = creds.headers ?? [:]
        headers["Content-Type"] = headers["Content-Type"] ?? "application/json"

        let step = WorkflowStep(
            type: .webhook,
            config: .webhook(WebhookStepConfig(
                url: creds.url,
                method: .post,
                headers: headers,
                bodyTemplate: """
                {
                    "type": "memo",
                    "memo": {
                        "id": "{{MEMO_ID}}",
                        "title": "{{TITLE}}",
                        "transcript": "{{TRANSCRIPT}}",
                        "audioUrl": "{{audioUrl}}",
                        "duration": {{DURATION}},
                        "createdAt": "{{DATE_ISO}}"
                    }
                }
                """,
                includeTranscript: false,
                includeMetadata: false,
                auth: nil
            )),
            outputKey: "notifyResult"
        )

        // Extract host for scope
        let host = URL(string: creds.url)?.host ?? "*"
        let credential = SecureCredential(
            id: credentialId,
            name: "Webhook",
            type: .apiKey,
            scope: CredentialScope(allowedHosts: [host])
        )

        return (step, credential, creds.url)
    }

    // MARK: - Fingerprint

    /// Compute a fingerprint for duplicate detection
    /// Normalized: sorted keys, no timestamps
    private static func computeFingerprint(_ payload: ImportedWorkflowPayload) -> String {
        // Create a normalized representation
        var normalizedParts: [String] = []

        normalizedParts.append("name:\(payload.name)")
        normalizedParts.append("version:\(payload.version)")

        // Add storage provider (not keys, which would change)
        if let storage = payload.credentials.storage {
            normalizedParts.append("storage:\(storage.provider)")
        }

        // Add database provider
        if let database = payload.credentials.database {
            normalizedParts.append("database:\(database.provider)")
        }

        // Add notify provider
        if let notify = payload.credentials.notify {
            normalizedParts.append("notify:\(notify.provider)")
        }

        normalizedParts.append("workflow:\(payload.workflow.type.rawValue)")

        let normalized = normalizedParts.sorted().joined(separator: "|")
        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)

        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Check for Duplicate

extension ImportPayloadConverter {

    /// Check if a workflow with the same fingerprint already exists
    static func findExistingWorkflow(for payload: ImportedWorkflowPayload, in workflows: [WorkflowDefinition]) -> WorkflowDefinition? {
        let fingerprint = computeFingerprint(payload)

        return workflows.first { workflow in
            guard case .imported(let metadata) = workflow.source else { return false }
            return metadata.fingerprint == fingerprint
        }
    }

    /// Check if a workflow from the same source URL exists
    static func findWorkflowFromSameSource(_ sourceUrl: URL, in workflows: [WorkflowDefinition]) -> WorkflowDefinition? {
        return workflows.first { workflow in
            guard case .imported(let metadata) = workflow.source else { return false }
            return metadata.sourceUrl == sourceUrl
        }
    }
}
