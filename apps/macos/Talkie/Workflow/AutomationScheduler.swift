//
//  AutomationScheduler.swift
//  Talkie macOS
//
//  Manages timers for schedule-based automations.
//  Handles hourly, daily, and weekly scheduled automation triggers.
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.workflow)

// MARK: - Automation Scheduler

@MainActor
@Observable
final class AutomationScheduler {
    static let shared = AutomationScheduler()

    // MARK: - State

    /// Whether the scheduler is running
    private(set) var isRunning = false

    /// Next scheduled run times for each automation
    private(set) var nextRunTimes: [UUID: Date] = [:]

    // MARK: - Timers

    /// Main check timer - fires every minute to check for due automations
    @ObservationIgnored private var checkTimer: Timer?

    /// Individual timers for precise scheduling (hourly = check timer, daily/weekly = precise timers)
    @ObservationIgnored private var preciseTimers: [UUID: Timer] = [:]

    /// App Nap prevention - keeps scheduler running when app loses focus
    @ObservationIgnored private var appNapActivity: NSObjectProtocol?

    // MARK: - Configuration

    /// Check interval for hourly automations (every minute)
    private let checkInterval: TimeInterval = 60

    /// Last run timestamps (persisted)
    @ObservationIgnored private var lastRunTimes: [UUID: Date] = [:] {
        didSet {
            persistLastRunTimes()
        }
    }

    // MARK: - Initialization

    private init() {
        loadLastRunTimes()
    }

    // MARK: - Lifecycle

    /// Start the scheduler (call on app launch)
    func start() {
        guard !isRunning else {
            log.debug("AutomationScheduler already running")
            return
        }

        log.info("Starting AutomationScheduler")
        isRunning = true

        // Prevent App Nap
        startAppNapPrevention()

        // Set up timers for scheduled automations
        setupTimers()

        log.info("AutomationScheduler started with \(preciseTimers.count) scheduled automation(s)")
    }

    /// Stop the scheduler (call on app terminate)
    func stop() {
        guard isRunning else { return }

        log.info("Stopping AutomationScheduler")
        isRunning = false

        // Invalidate all timers
        checkTimer?.invalidate()
        checkTimer = nil

        for (_, timer) in preciseTimers {
            timer.invalidate()
        }
        preciseTimers.removeAll()

        // Stop App Nap prevention
        stopAppNapPrevention()
    }

    /// Refresh schedules (call when automations change)
    func refreshSchedules() async {
        guard isRunning else { return }

        log.debug("Refreshing automation schedules")

        // Cancel existing timers
        checkTimer?.invalidate()
        checkTimer = nil
        for (_, timer) in preciseTimers {
            timer.invalidate()
        }
        preciseTimers.removeAll()
        nextRunTimes.removeAll()

        // Set up new timers
        setupTimers()
    }

    // MARK: - Timer Setup

    private func setupTimers() {
        let scheduledAutomations = AutomationService.shared.scheduledAutomations

        guard !scheduledAutomations.isEmpty else {
            log.debug("No scheduled automations to set up")
            return
        }

        // Set up check timer for hourly automations
        let hasHourly = scheduledAutomations.contains { automation in
            if case .schedule(let schedule) = automation.trigger {
                return schedule.interval == .hourly
            }
            return false
        }

        if hasHourly {
            checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkHourlyAutomations()
                }
            }
        }

        // Set up precise timers for daily/weekly automations
        for automation in scheduledAutomations {
            if case .schedule(let schedule) = automation.trigger {
                switch schedule.interval {
                case .hourly:
                    // Handled by check timer
                    if let nextRun = calculateNextHourlyRun(automation: automation) {
                        nextRunTimes[automation.id] = nextRun
                    }
                case .daily, .weekly:
                    setupPreciseTimer(for: automation, schedule: schedule)
                }
            }
        }

        log.info("Set up \(preciseTimers.count) precise timer(s), hourly check: \(hasHourly)")
    }

    private func setupPreciseTimer(for automation: Automation, schedule: ScheduleTrigger) {
        guard let nextRun = calculateNextRun(for: schedule) else {
            log.warning("Could not calculate next run time for automation: \(automation.name)")
            return
        }

        nextRunTimes[automation.id] = nextRun

        let interval = nextRun.timeIntervalSinceNow
        guard interval > 0 else {
            // Due now or in the past - run immediately then reschedule
            Task { @MainActor in
                await runScheduledAutomation(automation)
                setupPreciseTimer(for: automation, schedule: schedule)
            }
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.runScheduledAutomation(automation)
                // Reschedule for next run
                self?.setupPreciseTimer(for: automation, schedule: schedule)
            }
        }

        preciseTimers[automation.id] = timer

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, h:mm a"
        log.debug("Scheduled '\(automation.name)' for \(formatter.string(from: nextRun))")
    }

    // MARK: - Run Automations

    private func checkHourlyAutomations() async {
        let hourlyAutomations = AutomationService.shared.scheduledAutomations.filter { automation in
            if case .schedule(let schedule) = automation.trigger {
                return schedule.interval == .hourly
            }
            return false
        }

        for automation in hourlyAutomations {
            // Check if we should run (hasn't run in the last hour)
            let lastRun = lastRunTimes[automation.id]
            let oneHourAgo = Date().addingTimeInterval(-3600)

            if lastRun == nil || lastRun! < oneHourAgo {
                await runScheduledAutomation(automation)
            }
        }
    }

    private func runScheduledAutomation(_ automation: Automation) async {
        log.info("[SCHEDULER] Running scheduled automation: \(automation.name)")

        // Record run time
        lastRunTimes[automation.id] = Date()

        // Run the automation
        await AutomationService.shared.runAutomation(automation, memo: nil)

        // Update next run time
        if case .schedule(let schedule) = automation.trigger {
            if let nextRun = calculateNextRun(for: schedule) {
                nextRunTimes[automation.id] = nextRun
            }
        }
    }

    // MARK: - Time Calculations

    private func calculateNextRun(for schedule: ScheduleTrigger) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        switch schedule.interval {
        case .hourly:
            // Next hour
            return calendar.date(byAdding: .hour, value: 1, to: now)

        case .daily:
            guard let time = schedule.time else {
                // Default to next day at current time
                return calendar.date(byAdding: .day, value: 1, to: now)
            }

            // Find next occurrence of this time
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = time.hour
            components.minute = time.minute

            guard let candidateDate = calendar.date(from: components) else {
                return nil
            }

            // If the time has passed today, schedule for tomorrow
            if candidateDate <= now {
                return calendar.date(byAdding: .day, value: 1, to: candidateDate)
            }
            return candidateDate

        case .weekly:
            guard let time = schedule.time, let targetWeekday = schedule.weekday else {
                // Default to next week at current time
                return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
            }

            let currentWeekday = calendar.component(.weekday, from: now)
            var daysToAdd = targetWeekday - currentWeekday

            // If target day has passed this week, go to next week
            if daysToAdd < 0 {
                daysToAdd += 7
            } else if daysToAdd == 0 {
                // Same day - check if time has passed
                var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
                todayComponents.hour = time.hour
                todayComponents.minute = time.minute

                if let todayTarget = calendar.date(from: todayComponents), todayTarget <= now {
                    daysToAdd = 7 // Next week
                }
            }

            guard let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: now) else {
                return nil
            }

            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = time.hour
            components.minute = time.minute

            return calendar.date(from: components)
        }
    }

    private func calculateNextHourlyRun(automation: Automation) -> Date? {
        let lastRun = lastRunTimes[automation.id]
        let oneHour: TimeInterval = 3600

        if let lastRun = lastRun {
            return lastRun.addingTimeInterval(oneHour)
        }

        // First run - next hour boundary
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.minute = 0
        components.second = 0

        guard let hourStart = calendar.date(from: components) else {
            return nil
        }

        return calendar.date(byAdding: .hour, value: 1, to: hourStart)
    }

    // MARK: - App Nap Prevention

    private func startAppNapPrevention() {
        if let existingActivity = appNapActivity {
            ProcessInfo.processInfo.endActivity(existingActivity)
        }

        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.latencyCritical, .automaticTerminationDisabled],
            reason: "Talkie automation scheduler needs to run scheduled workflows"
        )

        log.debug("App Nap prevention enabled for automation scheduler")
    }

    private func stopAppNapPrevention() {
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
            log.debug("App Nap prevention disabled for automation scheduler")
        }
    }

    // MARK: - Persistence

    private func loadLastRunTimes() {
        let decoded = WorkflowConfigurationStore.shared.configuration.runtime.automationLastRunTimes
        lastRunTimes = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, Date(timeIntervalSince1970: value))
        })
    }

    private func persistLastRunTimes() {
        let encoded = Dictionary(uniqueKeysWithValues: lastRunTimes.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) })
        WorkflowConfigurationStore.shared.updateRuntime { runtime in
            runtime.automationLastRunTimes = encoded
        }
    }
}
