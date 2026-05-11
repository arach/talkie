//
//  Automation.swift
//  Talkie macOS
//
//  Data model for automations - event-triggered or scheduled workflow execution.
//  Extends the existing auto-run infrastructure beyond "on memo sync" to
//  "on any event" + "on schedule".
//

import Foundation
import GRDB

// MARK: - Automation Model

/// An automation that triggers a workflow based on events or schedules
struct Automation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var trigger: AutomationTrigger
    var workflowId: UUID
    var conditions: [AutomationCondition]?  // Future: filter by keyword, length, etc.
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: AutomationTrigger,
        workflowId: UUID,
        conditions: [AutomationCondition]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.workflowId = workflowId
        self.conditions = conditions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Automation Trigger

/// The trigger type for an automation
enum AutomationTrigger: Codable, Equatable {
    case event(EventTrigger)
    case schedule(ScheduleTrigger)

    /// Human-readable description of the trigger
    var displayDescription: String {
        switch self {
        case .event(let event):
            return event.displayDescription
        case .schedule(let schedule):
            return schedule.displayDescription
        }
    }

    /// Icon for the trigger type
    var icon: String {
        switch self {
        case .event:
            return "bolt.fill"
        case .schedule:
            return "calendar.badge.clock"
        }
    }
}

// MARK: - Event Trigger

/// Events that can trigger an automation
enum EventTrigger: String, Codable, CaseIterable, Equatable {
    case memoSynced      // Existing: memo arrives via CloudKit
    case memoCreated     // Local recording completed on Mac
    case dictationEnded  // TalkieAgent session ends

    var displayName: String {
        switch self {
        case .memoSynced:
            return "When memo syncs"
        case .memoCreated:
            return "When memo created locally"
        case .dictationEnded:
            return "When dictation ends"
        }
    }

    var displayDescription: String {
        displayName
    }

    var icon: String {
        switch self {
        case .memoSynced:
            return "icloud.and.arrow.down"
        case .memoCreated:
            return "mic.badge.plus"
        case .dictationEnded:
            return "text.badge.checkmark"
        }
    }
}

// MARK: - Schedule Trigger

/// Schedule-based trigger for automations
struct ScheduleTrigger: Codable, Equatable {
    var interval: ScheduleInterval
    var time: TimeOfDay?       // Hour/minute for daily/weekly
    var weekday: Int?          // 1-7 for weekly (Sunday=1)

    init(interval: ScheduleInterval, time: TimeOfDay? = nil, weekday: Int? = nil) {
        self.interval = interval
        self.time = time
        self.weekday = weekday
    }

    var displayDescription: String {
        switch interval {
        case .hourly:
            return "Every hour"
        case .daily:
            if let time = time {
                return "Daily at \(time.formatted)"
            }
            return "Daily"
        case .weekly:
            let dayName = weekday.flatMap { weekdayName($0) } ?? "week"
            if let time = time {
                return "Every \(dayName) at \(time.formatted)"
            }
            return "Every \(dayName)"
        }
    }

    private func weekdayName(_ day: Int) -> String? {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard day >= 1 && day <= 7 else { return nil }
        return names[day - 1]
    }
}

// MARK: - Schedule Interval

/// Interval for schedule-based automations
enum ScheduleInterval: String, Codable, CaseIterable, Equatable {
    case hourly
    case daily
    case weekly

    var displayName: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

// MARK: - Time of Day

/// Simple hour/minute time representation
struct TimeOfDay: Codable, Equatable {
    var hour: Int      // 0-23
    var minute: Int    // 0-59

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    /// Create from Date (extracts hour and minute)
    init(from date: Date) {
        let calendar = Calendar.current
        self.hour = calendar.component(.hour, from: date)
        self.minute = calendar.component(.minute, from: date)
    }

    /// Format as "9:00 AM"
    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        guard let date = Calendar.current.date(from: components) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }
        return formatter.string(from: date)
    }

    /// Convert to DateComponents for scheduling
    var dateComponents: DateComponents {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return components
    }
}

// MARK: - Automation Condition (Future)

/// Conditions that can filter when an automation runs
/// Future: filter by keyword, memo length, source device, etc.
struct AutomationCondition: Codable, Equatable {
    var field: String          // e.g., "transcript", "title", "duration"
    var op: ConditionOperator  // e.g., "contains", "greaterThan"
    var value: String          // The value to compare against
}

enum ConditionOperator: String, Codable, CaseIterable, Equatable {
    case contains
    case notContains
    case equals
    case notEquals
    case greaterThan
    case lessThan
}

// MARK: - GRDB Support

/// GRDB model for storing automations in the database
struct AutomationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "automations"

    var id: String              // UUID as string
    var name: String
    var isEnabled: Bool
    var triggerJSON: String     // Serialized AutomationTrigger
    var workflowId: String      // UUID as string
    var conditionsJSON: String? // Serialized [AutomationCondition]
    var createdAt: Date
    var updatedAt: Date

    /// Create from domain model
    init(from automation: Automation) throws {
        self.id = automation.id.uuidString
        self.name = automation.name
        self.isEnabled = automation.isEnabled
        self.triggerJSON = try String(data: JSONEncoder().encode(automation.trigger), encoding: .utf8) ?? "{}"
        self.workflowId = automation.workflowId.uuidString
        if let conditions = automation.conditions {
            self.conditionsJSON = try String(data: JSONEncoder().encode(conditions), encoding: .utf8)
        } else {
            self.conditionsJSON = nil
        }
        self.createdAt = automation.createdAt
        self.updatedAt = automation.updatedAt
    }

    /// Convert to domain model
    func toAutomation() throws -> Automation {
        guard let id = UUID(uuidString: self.id),
              let workflowId = UUID(uuidString: self.workflowId) else {
            throw AutomationError.invalidUUID
        }

        let trigger = try JSONDecoder().decode(AutomationTrigger.self, from: Data(triggerJSON.utf8))
        let conditions: [AutomationCondition]?
        if let conditionsJSON = conditionsJSON {
            conditions = try JSONDecoder().decode([AutomationCondition].self, from: Data(conditionsJSON.utf8))
        } else {
            conditions = nil
        }

        return Automation(
            id: id,
            name: name,
            isEnabled: isEnabled,
            trigger: trigger,
            workflowId: workflowId,
            conditions: conditions,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Errors

enum AutomationError: LocalizedError {
    case invalidUUID
    case workflowNotFound(UUID)
    case automationNotFound(UUID)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidUUID:
            return "Invalid automation ID"
        case .workflowNotFound(let id):
            return "Workflow not found: \(id)"
        case .automationNotFound(let id):
            return "Automation not found: \(id)"
        case .encodingFailed:
            return "Failed to encode automation data"
        }
    }
}
