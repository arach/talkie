//
//  WorkflowStore.swift
//  Talkie
//
//  Securely stores imported workflows in Keychain.
//
//  DEPRECATED: This is the legacy storage system. New imports use:
//  - WorkflowFileRepository for workflow definitions (JSON files)
//  - CredentialStore for secure credentials (Keychain by UUID)
//
//  This class is kept for migration purposes only. See WorkflowMigrationService.
//

import Foundation
import Security
import TalkieKit

private let log = Log(.workflow)

// MARK: - Workflow Store (Legacy)

@available(*, deprecated, message: "Use WorkflowFileRepository + CredentialStore instead")
actor WorkflowStore {

    static let shared = WorkflowStore()

    private let service = "com.jdi.talkie.workflows"

    private init() {}

    // MARK: - CRUD Operations

    /// Get all stored workflows
    func listWorkflows() -> [StoredWorkflow] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> StoredWorkflow? in
            guard let data = item[kSecValueData as String] as? Data else {
                return nil
            }
            return try? JSONDecoder().decode(StoredWorkflow.self, from: data)
        }
    }

    /// Get a specific workflow by ID
    func getWorkflow(id: UUID) -> StoredWorkflow? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(StoredWorkflow.self, from: data)
    }

    /// Get the default workflow (for quick action)
    func getDefaultWorkflow() -> StoredWorkflow? {
        listWorkflows().first { $0.isDefault } ?? listWorkflows().first
    }

    /// Store a workflow
    func storeWorkflow(_ workflow: StoredWorkflow) throws {
        let data = try JSONEncoder().encode(workflow)

        // Check if exists
        let existingQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: workflow.id.uuidString
        ]

        let status = SecItemCopyMatching(existingQuery as CFDictionary, nil)

        if status == errSecSuccess {
            // Update existing
            let updateQuery: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(existingQuery as CFDictionary, updateQuery as CFDictionary)
            if updateStatus != errSecSuccess {
                throw WorkflowStoreError.saveFailed(updateStatus)
            }
        } else {
            // Add new
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: workflow.id.uuidString,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw WorkflowStoreError.saveFailed(addStatus)
            }
        }

        log.info("Stored workflow: \(workflow.name)")
    }

    /// Delete a workflow
    func deleteWorkflow(id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw WorkflowStoreError.deleteFailed(status)
        }

        log.info("Deleted workflow: \(id)")
    }

    /// Set a workflow as default
    func setDefaultWorkflow(id: UUID) throws {
        var workflows = listWorkflows()

        for i in workflows.indices {
            var workflow = workflows[i]
            workflow.isDefault = (workflow.id == id)
            try storeWorkflow(workflow)
        }

        log.info("Set default workflow: \(id)")
    }

    /// Check if any workflows are configured
    var hasWorkflows: Bool {
        !listWorkflows().isEmpty
    }
}

// MARK: - Errors

enum WorkflowStoreError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save workflow (error \(status))"
        case .deleteFailed(let status):
            return "Failed to delete workflow (error \(status))"
        }
    }
}
