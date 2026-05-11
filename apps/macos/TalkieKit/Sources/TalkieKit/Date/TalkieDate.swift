//
//  TalkieDate.swift
//  TalkieKit
//
//  Centralized date handling for Talkie.
//
//  DATE STRATEGY:
//  - Storage: Always UTC (ISO8601 strings in GRDB, or Unix epoch)
//  - Display: Convert to local timezone using these helpers
//  - SQL: Use 'localtime' modifier for date grouping/filtering
//
//  Usage:
//    TalkieDate.iso8601(date)           // For storage/sync
//    TalkieDate.displayTime(date)       // For UI (local timezone)
//    TalkieDate.displayDate(date)       // For UI (local timezone)
//    TalkieDate.logFileName(date)       // For log file names
//

import Foundation

// MARK: - TalkieDate

/// Centralized date formatting and conversion utilities.
/// All formatters are cached and explicitly configured for timezone handling.
public enum TalkieDate {

    // MARK: - Timezone Constants

    /// UTC timezone for storage operations
    public static let utc = TimeZone(identifier: "UTC")!

    /// Current local timezone for display
    public static var local: TimeZone { .current }

    // MARK: - Cached Formatters (Thread-Safe)

    /// ISO8601 with fractional seconds - for storage, sync, and serialization
    /// Output: "2025-02-06T14:30:45.123Z"
    private static let _iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 without fractional seconds - for simpler serialization
    /// Output: "2025-02-06T14:30:45Z"
    private static let _iso8601SimpleFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Time display formatter (local timezone)
    /// Output: "2:30 PM" or "14:30" depending on locale
    private static let _timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    /// Date display formatter (local timezone)
    /// Output: "Feb 6, 2025" or locale-appropriate
    private static let _dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    /// Date and time display formatter (local timezone)
    /// Output: "Feb 6, 2025 at 2:30 PM"
    private static let _dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    /// Short date formatter (local timezone)
    /// Output: "2/6/25" or locale-appropriate
    private static let _shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .short
        formatter.timeZone = .current
        return formatter
    }()

    /// Console/log time formatter (local timezone)
    /// Output: "14:30:45"
    private static let _consoleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    /// Log filename date formatter (local timezone)
    /// Output: "2025-02-06"
    private static let _logFileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    /// Database date key formatter (local timezone for grouping)
    /// Output: "2025-02-06"
    private static let _dbDateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    /// Relative date formatter for "today", "yesterday", etc.
    private static let _relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Compact relative formatter ("2h ago", "3d ago")
    private static let _compactRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Storage & Sync (UTC)

    /// Convert date to ISO8601 string for storage/sync
    /// Always uses UTC timezone with fractional seconds
    public static func iso8601(_ date: Date) -> String {
        _iso8601Formatter.string(from: date)
    }

    /// Convert date to simple ISO8601 string (no fractional seconds)
    public static func iso8601Simple(_ date: Date) -> String {
        _iso8601SimpleFormatter.string(from: date)
    }

    /// Parse ISO8601 string to date
    public static func fromISO8601(_ string: String) -> Date? {
        _iso8601Formatter.date(from: string) ?? _iso8601SimpleFormatter.date(from: string)
    }

    /// Unix epoch timestamp (seconds since 1970)
    public static func epoch(_ date: Date) -> Double {
        date.timeIntervalSince1970
    }

    /// Create date from Unix epoch timestamp
    public static func fromEpoch(_ timestamp: Double) -> Date {
        Date(timeIntervalSince1970: timestamp)
    }

    // MARK: - Display (Local Timezone)

    /// Format time for display (e.g., "2:30 PM")
    public static func displayTime(_ date: Date) -> String {
        _timeFormatter.string(from: date)
    }

    /// Format date for display (e.g., "Feb 6, 2025")
    public static func displayDate(_ date: Date) -> String {
        _dateFormatter.string(from: date)
    }

    /// Format date and time for display (e.g., "Feb 6, 2025 at 2:30 PM")
    public static func displayDateTime(_ date: Date) -> String {
        _dateTimeFormatter.string(from: date)
    }

    /// Format short date for display (e.g., "2/6/25")
    public static func displayShortDate(_ date: Date) -> String {
        _shortDateFormatter.string(from: date)
    }

    /// Relative time string (e.g., "2 hours ago", "yesterday")
    public static func relative(_ date: Date, to reference: Date = Date()) -> String {
        _relativeFormatter.localizedString(for: date, relativeTo: reference)
    }

    /// Compact relative time (e.g., "2h ago", "3d ago")
    public static func relativeCompact(_ date: Date, to reference: Date = Date()) -> String {
        _compactRelativeFormatter.localizedString(for: date, relativeTo: reference)
    }

    // MARK: - Console & Logging

    /// Format for console display (e.g., "14:30:45")
    public static func consoleTime(_ date: Date) -> String {
        _consoleTimeFormatter.string(from: date)
    }

    /// Format for log filenames (e.g., "2025-02-06")
    public static func logFileDate(_ date: Date) -> String {
        _logFileDateFormatter.string(from: date)
    }

    /// Generate log filename (e.g., "talkie-2025-02-06.log")
    public static func logFileName(_ date: Date, prefix: String = "talkie") -> String {
        "\(prefix)-\(logFileDate(date)).log"
    }

    // MARK: - Database Keys (Local Timezone)

    /// Format date as database key for grouping (e.g., "2025-02-06")
    /// Uses local timezone so dates group correctly for the user
    public static func dbDateKey(_ date: Date) -> String {
        _dbDateKeyFormatter.string(from: date)
    }

    /// Parse database date key back to Date (start of day in local timezone)
    public static func fromDBDateKey(_ key: String) -> Date? {
        _dbDateKeyFormatter.date(from: key)
    }

    // MARK: - Calendar Helpers

    /// Start of day in local timezone
    public static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Start of today in local timezone
    public static var startOfToday: Date {
        startOfDay(Date())
    }

    /// Check if date is today in local timezone
    public static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Check if date is yesterday in local timezone
    public static func isYesterday(_ date: Date) -> Bool {
        Calendar.current.isDateInYesterday(date)
    }

    /// Check if date is within the current week in local timezone
    public static func isThisWeek(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }

    /// Check if date is within the current month in local timezone
    public static func isThisMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    /// Days ago from now
    public static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    /// Start of week in local timezone (Sunday or Monday depending on locale)
    public static func startOfWeek(_ date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Start of month in local timezone
    public static func startOfMonth(_ date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

// MARK: - SQL Helpers

extension TalkieDate {

    /// SQL fragment for extracting local date from UTC timestamp
    /// Use this in GROUP BY and WHERE clauses for date-based queries
    ///
    /// Example: `SELECT \(TalkieDate.sqlLocalDate("createdAt")) as day, COUNT(*) ...`
    public static func sqlLocalDate(_ column: String) -> String {
        "date(\(column), 'localtime')"
    }

    /// SQL fragment for extracting local datetime from UTC timestamp
    public static func sqlLocalDateTime(_ column: String) -> String {
        "datetime(\(column), 'localtime')"
    }

    /// SQL predicate for "today" in local timezone
    /// Returns: `date(column, 'localtime') = date('now', 'localtime')`
    public static func sqlIsToday(_ column: String) -> String {
        "date(\(column), 'localtime') = date('now', 'localtime')"
    }

    /// SQL predicate for "this week" in local timezone
    /// Uses start of current week as boundary
    public static func sqlIsThisWeek(_ column: String) -> String {
        "date(\(column), 'localtime') >= date('now', 'localtime', 'weekday 0', '-7 days')"
    }

    /// SQL predicate for "this month" in local timezone
    /// Uses start of current month as boundary
    public static func sqlIsThisMonth(_ column: String) -> String {
        "date(\(column), 'localtime') >= date('now', 'localtime', 'start of month')"
    }

    /// SQL predicate for dates within the last N days (local timezone)
    public static func sqlLastNDays(_ column: String, days: Int) -> String {
        "date(\(column), 'localtime') >= date('now', 'localtime', '-\(days) days')"
    }
}

// MARK: - Date Extension

public extension Date {

    /// Convert to ISO8601 string for storage
    var iso8601: String { TalkieDate.iso8601(self) }

    /// Convert to display time string
    var displayTime: String { TalkieDate.displayTime(self) }

    /// Convert to display date string
    var displayDate: String { TalkieDate.displayDate(self) }

    /// Convert to display date+time string
    var displayDateTime: String { TalkieDate.displayDateTime(self) }

    /// Convert to database date key (for grouping)
    var dbDateKey: String { TalkieDate.dbDateKey(self) }

    /// Check if this date is today
    var isToday: Bool { TalkieDate.isToday(self) }

    /// Check if this date is yesterday
    var isYesterday: Bool { TalkieDate.isYesterday(self) }

    /// Start of this day
    var startOfDay: Date { TalkieDate.startOfDay(self) }

    /// Relative description from now
    var relativeDescription: String { TalkieDate.relative(self) }
}
