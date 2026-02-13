//
//  WatchDurationSyncManager.swift
//  Pomodoro Timer Watch App Watch App
//
//  Created by Codex on 13/2/2026.
//

import Foundation
import Combine
import WatchConnectivity

struct WatchSyncedTimerState: Equatable {
    let session: WatchPomodoroSession
    let remainingSeconds: Int
    let isRunning: Bool
    let completedFocusSessions: Int
    let didCompleteCycle: Bool
    let sentAt: Date
}

@MainActor
final class WatchDurationSyncManager: NSObject, ObservableObject {
    private enum PayloadKey {
        static let focusMinutes = "focus_minutes"
        static let shortBreakMinutes = "short_break_minutes"
        static let longBreakMinutes = "long_break_minutes"
        static let currentSession = "current_session"
        static let remainingSeconds = "remaining_seconds"
        static let isRunning = "is_running"
        static let completedFocusSessions = "completed_focus_sessions"
        static let didCompleteCycle = "did_complete_cycle"
        static let updatedAt = "updated_at"
    }

    @Published private(set) var durations: WatchPomodoroDurations = .default
    @Published private(set) var timerState: WatchSyncedTimerState?
    @Published private(set) var settingsSyncEventID = 0
    @Published private(set) var lastSyncDate: Date?
    private var hasActivatedSession = false

    func activateIfNeeded() {
        guard WCSession.isSupported(), !hasActivatedSession else { return }
        hasActivatedSession = true

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func apply(context: [String: Any]) {
        let previousDurations = durations

        guard
            let focusMinutes = intValue(for: PayloadKey.focusMinutes, in: context),
            let shortBreakMinutes = intValue(for: PayloadKey.shortBreakMinutes, in: context),
            let longBreakMinutes = intValue(for: PayloadKey.longBreakMinutes, in: context)
        else {
            return
        }

        durations = WatchPomodoroDurations(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes
        ).sanitized()

        if durations != previousDurations {
            settingsSyncEventID += 1
        }

        if
            let currentSessionRawValue = context[PayloadKey.currentSession] as? String,
            let session = WatchPomodoroSession(rawValue: currentSessionRawValue),
            let remainingSeconds = intValue(for: PayloadKey.remainingSeconds, in: context),
            let isRunning = boolValue(for: PayloadKey.isRunning, in: context),
            let completedFocusSessions = intValue(for: PayloadKey.completedFocusSessions, in: context),
            let didCompleteCycle = boolValue(for: PayloadKey.didCompleteCycle, in: context)
        {
            let sentAt: Date
            if let updatedAtSeconds = doubleValue(for: PayloadKey.updatedAt, in: context) {
                sentAt = Date(timeIntervalSince1970: updatedAtSeconds)
            } else {
                sentAt = Date()
            }

            timerState = WatchSyncedTimerState(
                session: session,
                remainingSeconds: max(0, remainingSeconds),
                isRunning: isRunning,
                completedFocusSessions: max(0, completedFocusSessions),
                didCompleteCycle: didCompleteCycle,
                sentAt: sentAt
            )
        }

        lastSyncDate = Date()
    }

    private func intValue(for key: String, in context: [String: Any]) -> Int? {
        if let value = context[key] as? Int {
            return value
        }
        if let value = context[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private func boolValue(for key: String, in context: [String: Any]) -> Bool? {
        if let value = context[key] as? Bool {
            return value
        }
        if let value = context[key] as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private func doubleValue(for key: String, in context: [String: Any]) -> Double? {
        if let value = context[key] as? Double {
            return value
        }
        if let value = context[key] as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}

extension WatchDurationSyncManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.apply(context: context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.apply(context: applicationContext)
        }
    }
}
