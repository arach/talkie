//
//  ImportedWorkflow.swift
//  Talkie
//
//  A workflow + credentials imported via URL.
//  Generic pattern - tawkie.dev is one use case.
//

import Foundation

// MARK: - Imported Workflow Payload

/// Payload received from an import URL (e.g., tawkie.dev/claim/xxx)
struct ImportedWorkflowPayload: Codable, Sendable {
    let version: Int
    let name: String
    let icon: String?              // SF Symbol name or emoji
    let description: String?
    let createdAt: Date?

    let credentials: WorkflowCredentials
    let workflow: ImportWorkflowConfig
}

// MARK: - Credentials

/// Credentials for external services
struct WorkflowCredentials: Codable, Sendable {
    let storage: StorageCredentials?
    let database: DatabaseCredentials?
    let notify: NotifyCredentials?
}

// MARK: - Storage Credentials

enum StorageCredentials: Codable, Sendable {
    case r2(R2Credentials)
    case s3(S3Credentials)
    case convex(ConvexCredentials)

    var provider: String {
        switch self {
        case .r2: return "r2"
        case .s3: return "s3"
        case .convex: return "convex"
        }
    }
}

struct R2Credentials: Codable, Sendable {
    let endpoint: String
    let bucket: String
    let region: String?
    let accessKeyId: String
    let secretAccessKey: String
}

struct S3Credentials: Codable, Sendable {
    let endpoint: String?
    let bucket: String
    let region: String
    let accessKeyId: String
    let secretAccessKey: String
}

// MARK: - Database Credentials

enum DatabaseCredentials: Codable, Sendable {
    case convex(ConvexCredentials)
    case turso(TursoCredentials)

    var provider: String {
        switch self {
        case .convex: return "convex"
        case .turso: return "turso"
        }
    }
}

struct ConvexCredentials: Codable, Sendable {
    let url: String
    let deployKey: String
}

struct TursoCredentials: Codable, Sendable {
    let url: String
    let authToken: String
}

// MARK: - Notify Credentials

enum NotifyCredentials: Codable, Sendable {
    case telegram(TelegramCredentials)
    case discord(DiscordCredentials)
    case webhook(WebhookCredentials)

    var provider: String {
        switch self {
        case .telegram: return "telegram"
        case .discord: return "discord"
        case .webhook: return "webhook"
        }
    }
}

struct TelegramCredentials: Codable, Sendable {
    let botToken: String
    let chatId: String
}

struct DiscordCredentials: Codable, Sendable {
    let webhookUrl: String
}

struct WebhookCredentials: Codable, Sendable {
    let url: String
    let headers: [String: String]?
}

// MARK: - Import Workflow Config (renamed to avoid collision with core WorkflowDefinition)

/// Defines what the imported workflow does
struct ImportWorkflowConfig: Codable, Sendable {
    let type: ImportWorkflowType
    let config: ImportWorkflowOptions?
}

enum ImportWorkflowType: String, Codable, Sendable {
    case sendToAgent = "send_to_agent"  // Upload audio + send notification
    case uploadOnly = "upload_only"      // Just upload, no notification
    case notifyOnly = "notify_only"      // Just send notification
}

struct ImportWorkflowOptions: Codable, Sendable {
    /// Path template for audio upload (e.g., "audio/{memo.id}.m4a")
    let audioPathTemplate: String?

    /// Message template for notification
    let messageTemplate: String?

    /// Whether to include transcript in notification
    let includeTranscript: Bool?

    /// Whether to include audio URL in notification
    let includeAudioUrl: Bool?
}

// MARK: - Stored Workflow

/// What gets stored in Keychain after import (legacy - being migrated to core WorkflowDefinition)
struct StoredWorkflow: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let description: String?
    let importedAt: Date
    let sourceUrl: String?  // Where it came from (for reference)

    let credentials: WorkflowCredentials
    let workflow: ImportWorkflowConfig

    var isDefault: Bool = false
}

// MARK: - Codable Helpers

extension StorageCredentials {
    enum CodingKeys: String, CodingKey {
        case provider
        case endpoint, bucket, region, accessKeyId, secretAccessKey
        case url, deployKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(String.self, forKey: .provider)

        switch provider {
        case "r2":
            self = .r2(R2Credentials(
                endpoint: try container.decode(String.self, forKey: .endpoint),
                bucket: try container.decode(String.self, forKey: .bucket),
                region: try container.decodeIfPresent(String.self, forKey: .region),
                accessKeyId: try container.decode(String.self, forKey: .accessKeyId),
                secretAccessKey: try container.decode(String.self, forKey: .secretAccessKey)
            ))
        case "s3":
            self = .s3(S3Credentials(
                endpoint: try container.decodeIfPresent(String.self, forKey: .endpoint),
                bucket: try container.decode(String.self, forKey: .bucket),
                region: try container.decode(String.self, forKey: .region),
                accessKeyId: try container.decode(String.self, forKey: .accessKeyId),
                secretAccessKey: try container.decode(String.self, forKey: .secretAccessKey)
            ))
        case "convex":
            self = .convex(ConvexCredentials(
                url: try container.decode(String.self, forKey: .url),
                deployKey: try container.decode(String.self, forKey: .deployKey)
            ))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .provider,
                in: container,
                debugDescription: "Unknown storage provider: \(provider)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .r2(let creds):
            try container.encode("r2", forKey: .provider)
            try container.encode(creds.endpoint, forKey: .endpoint)
            try container.encode(creds.bucket, forKey: .bucket)
            try container.encodeIfPresent(creds.region, forKey: .region)
            try container.encode(creds.accessKeyId, forKey: .accessKeyId)
            try container.encode(creds.secretAccessKey, forKey: .secretAccessKey)
        case .s3(let creds):
            try container.encode("s3", forKey: .provider)
            try container.encodeIfPresent(creds.endpoint, forKey: .endpoint)
            try container.encode(creds.bucket, forKey: .bucket)
            try container.encode(creds.region, forKey: .region)
            try container.encode(creds.accessKeyId, forKey: .accessKeyId)
            try container.encode(creds.secretAccessKey, forKey: .secretAccessKey)
        case .convex(let creds):
            try container.encode("convex", forKey: .provider)
            try container.encode(creds.url, forKey: .url)
            try container.encode(creds.deployKey, forKey: .deployKey)
        }
    }
}

extension DatabaseCredentials {
    enum CodingKeys: String, CodingKey {
        case provider
        case url, deployKey, authToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(String.self, forKey: .provider)

        switch provider {
        case "convex":
            self = .convex(ConvexCredentials(
                url: try container.decode(String.self, forKey: .url),
                deployKey: try container.decode(String.self, forKey: .deployKey)
            ))
        case "turso":
            self = .turso(TursoCredentials(
                url: try container.decode(String.self, forKey: .url),
                authToken: try container.decode(String.self, forKey: .authToken)
            ))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .provider,
                in: container,
                debugDescription: "Unknown database provider: \(provider)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .convex(let creds):
            try container.encode("convex", forKey: .provider)
            try container.encode(creds.url, forKey: .url)
            try container.encode(creds.deployKey, forKey: .deployKey)
        case .turso(let creds):
            try container.encode("turso", forKey: .provider)
            try container.encode(creds.url, forKey: .url)
            try container.encode(creds.authToken, forKey: .authToken)
        }
    }
}

extension NotifyCredentials {
    enum CodingKeys: String, CodingKey {
        case provider
        case botToken, chatId
        case webhookUrl
        case url, headers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(String.self, forKey: .provider)

        switch provider {
        case "telegram":
            self = .telegram(TelegramCredentials(
                botToken: try container.decode(String.self, forKey: .botToken),
                chatId: try container.decode(String.self, forKey: .chatId)
            ))
        case "discord":
            self = .discord(DiscordCredentials(
                webhookUrl: try container.decode(String.self, forKey: .webhookUrl)
            ))
        case "webhook":
            self = .webhook(WebhookCredentials(
                url: try container.decode(String.self, forKey: .url),
                headers: try container.decodeIfPresent([String: String].self, forKey: .headers)
            ))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .provider,
                in: container,
                debugDescription: "Unknown notify provider: \(provider)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .telegram(let creds):
            try container.encode("telegram", forKey: .provider)
            try container.encode(creds.botToken, forKey: .botToken)
            try container.encode(creds.chatId, forKey: .chatId)
        case .discord(let creds):
            try container.encode("discord", forKey: .provider)
            try container.encode(creds.webhookUrl, forKey: .webhookUrl)
        case .webhook(let creds):
            try container.encode("webhook", forKey: .provider)
            try container.encode(creds.url, forKey: .url)
            try container.encodeIfPresent(creds.headers, forKey: .headers)
        }
    }
}
