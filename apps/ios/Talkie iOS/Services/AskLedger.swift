//
//  AskLedger.swift
//  Talkie iOS
//
//  The durable record of an ask, whatever device it was spoken into.
//
//  Before this existed the phone's only memory of a Watch ask was
//  `AskInFlightRegistry`, which is deliberately ephemeral: an answered ask
//  retires after four seconds and nothing survives a relaunch. Once that pill
//  faded, the ask had no representation on the phone at all — it had become an
//  ordinary `VoiceMemo` whose only tell was an "Ask AI …" title.
//
//  This ledger is that missing representation. It is fed from the same funnel
//  that drives the pill and the Live Activity — `sendMemoUpdate` — so the
//  wrist, the lock screen, the tray pill, and the Ask AI surface cannot
//  disagree about where an ask has got to.
//

import Foundation
import UIKit
import TalkieMobileKit

/// Which device the question was spoken or typed into. Recorded rather than
/// inferred: once an ask is on the phone, nothing about the text says where it
/// came from, and "answer my wrist asked for" is a materially different thing
/// to the wearer than one they typed here.
enum AskOrigin: String, Codable, Equatable {
    case phone
    case watch
}

extension WatchSessionManager.AskPhase: Codable {}
extension WatchSessionManager.AnswerDelivery: Codable {}

/// One ask, from the moment the phone started working on it through to an
/// answer or a failure.
///
/// Question and answer are separate fields rather than the single rolling
/// `text` the in-flight pill carries: the pill only ever shows the latest
/// thing, whereas a settled ask has to be able to show both halves.
struct AskRecord: Codable, Identifiable, Equatable {
    /// The memo id the Watch minted. Deliberately the same key the memo, the
    /// agent session, and the in-flight pill are stored under, so any of them
    /// can reach the others without a lookup table.
    let id: String
    var origin: AskOrigin
    var question: String?
    var answer: String?
    var phase: WatchSessionManager.AskPhase
    /// Who narrated the answer. `phoneAudio` is why the wrist offers "read
    /// answer" instead of "play answer" — the audio never went to the Watch.
    var delivery: WatchSessionManager.AnswerDelivery?
    let createdAt: Date
    var updatedAt: Date

    var isSettled: Bool { phase.isSettled }
    var didFail: Bool { phase == .failed }
}

@MainActor
final class AskLedger: ObservableObject {
    static let shared = AskLedger()

    /// Oldest first, so the Ask AI surface can append it to a conversation
    /// without re-sorting on every render.
    @Published private(set) var records: [AskRecord] = []

    /// Matches `AgentSessionStore.maxSessions`: the two are keyed by the same
    /// memo id, and an ask whose conversation has already been evicted has
    /// nothing left to open.
    private let maxRecords = 100

    private let fileManager = FileManager.default

    private init() {
        // Anything still in flight on disk belongs to a process that is gone,
        // so it is stale no matter how recently it was touched.
        records = Self.settling(load(), staleAfter: 0)
        save()

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleStaleAsks() }
        }
    }

    // MARK: - Abandoned asks

    /// How long an ask may sit without moving before it is presumed dead.
    ///
    /// An ask that completes normally takes a handful of seconds end to end —
    /// transcription, the model, then speech — so a minute of silence is well
    /// past any healthy request while staying clear of a slow one. There is no
    /// truer source for this than the shape of the work itself: nothing in the
    /// pipeline reports a deadline the ledger could adopt instead.
    private static let staleAfter: TimeInterval = 60

    /// The other half of the problem `init` handles.
    ///
    /// An ask can also be abandoned inside a process that goes on living: the
    /// phone is woken by the Watch, starts work in the background, and is
    /// suspended before the answer lands. The task never resumes, but the
    /// process survives, so nothing reloads the ledger and the record sits at
    /// `answering` for as long as the app stays up.
    ///
    /// Foreground is the right moment to check because it is exactly when
    /// suspension ended and when somebody is about to read the thread.
    func settleStaleAsks() {
        let updated = Self.settling(records, staleAfter: Self.staleAfter)
        guard updated != records else { return }
        records = updated
        save()
    }

    /// Settles every unfinished ask that has gone quiet for longer than
    /// `staleAfter`, as the failure it already is.
    ///
    /// Left alone these render as a thread that says "Answering" forever,
    /// which is a promise the app cannot keep and reads as a hang.
    private static func settling(
        _ records: [AskRecord],
        staleAfter: TimeInterval
    ) -> [AskRecord] {
        let now = Date()
        return records.map { record in
            guard !record.isSettled,
                  now.timeIntervalSince(record.updatedAt) >= staleAfter else { return record }
            var settled = record
            settled.phase = .failed
            // `updatedAt` is deliberately left alone: the ask stopped when it
            // stopped, not when this pass noticed.
            if settled.answer == nil {
                settled.answer = abandonedMessage
            }
            return settled
        }
    }

    private static let abandonedMessage = "Interrupted — the answer never arrived."

    // MARK: - Ingest

    /// Files a phase transition against an ask, creating the record on the
    /// first ask-only phase.
    ///
    /// `text` means different things at different phases — it is the question
    /// while the answer is outstanding and the answer once it lands — so it is
    /// routed to the right field here rather than stored raw.
    func record(
        memoId: String,
        origin: AskOrigin,
        phase: WatchSessionManager.AskPhase,
        text: String?,
        delivery: WatchSessionManager.AnswerDelivery?
    ) {
        guard !memoId.isEmpty else { return }

        let index = records.firstIndex { $0.id == memoId }
        // Every ask passes through an ask-only phase before it can settle, so
        // gating creation here is enough to keep plain Watch dictation — which
        // shares this funnel — out of the ledger entirely.
        guard index != nil || phase.impliesAsk else { return }

        let now = Date()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = (trimmed?.isEmpty == false) ? trimmed : nil

        if let index {
            records[index].phase = phase
            records[index].updatedAt = now
            if let delivery {
                records[index].delivery = delivery
            }
            records[index] = records[index].applying(payload, phase: phase)
        } else {
            let fresh = AskRecord(
                id: memoId,
                origin: origin,
                question: nil,
                answer: nil,
                phase: phase,
                delivery: delivery,
                createdAt: now,
                updatedAt: now
            )
            records.append(fresh.applying(payload, phase: phase))
        }

        save()
    }

    func remove(_ memoId: String) {
        records.removeAll { $0.id == memoId }
        save()
    }

    func removeAll() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private var storageURL: URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) else { return nil }
        return container.appendingPathComponent("ask-ledger.json")
    }

    private func load() -> [AskRecord] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([AskRecord].self, from: data) else {
            AppLogger.persistence.warning("Ask ledger decode failed; starting empty")
            return []
        }
        return decoded.sorted { $0.createdAt < $1.createdAt }
    }

    private func save() {
        // Oldest first, so trimming drops the far end of the history.
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }

        guard let url = storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension AskRecord {
    /// Non-mutating so the create and update paths can share one rule about
    /// which half of the ask a phase's text belongs to.
    func applying(_ payload: String?, phase: WatchSessionManager.AskPhase) -> AskRecord {
        guard let payload else { return self }
        var copy = self
        switch phase {
        case .answered, .failed:
            copy.answer = payload
        case .queued, .sending, .received, .transcribing, .answering:
            copy.question = payload
        }
        return copy
    }
}
