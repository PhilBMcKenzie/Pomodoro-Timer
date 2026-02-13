//
//  PhoneWatchSyncManager.swift
//  Pomodoro Timer
//
//  Created by Codex on 13/2/2026.
//

import Foundation
import Combine
import WatchConnectivity

@MainActor
final class PhoneWatchSyncManager: NSObject, ObservableObject {
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

    private struct SyncSignature: Equatable {
        let durations: PomodoroDurations
        let currentSession: PomodoroSession
        let remainingSeconds: Int
        let isRunning: Bool
        let completedFocusSessions: Int
        let didCompleteCycle: Bool
    }

    private var hasActivatedSession = false
    private var pendingContext: [String: Any]?
    private var pendingSignature: SyncSignature?
    private var lastSentSignature: SyncSignature?
    private var lastSentDate: Date?
    private let runningUpdateThrottleInterval: TimeInterval = 5

    func activateIfNeeded() {
        guard WCSession.isSupported(), !hasActivatedSession else { return }
        hasActivatedSession = true

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func syncState(
        durations: PomodoroDurations,
        currentSession: PomodoroSession,
        remainingSeconds: Int,
        isRunning: Bool,
        completedFocusSessions: Int,
        didCompleteCycle: Bool,
        force: Bool = false
    ) {
        activateIfNeeded()

        let safe = durations.sanitized()
        let now = Date()
        let signature = SyncSignature(
            durations: safe,
            currentSession: currentSession,
            remainingSeconds: max(0, remainingSeconds),
            isRunning: isRunning,
            completedFocusSessions: max(0, completedFocusSessions),
            didCompleteCycle: didCompleteCycle
        )

        if !force && shouldThrottle(signature: signature, now: now) {
            return
        }

        let context: [String: Any] = [
            PayloadKey.focusMinutes: safe.focusMinutes,
            PayloadKey.shortBreakMinutes: safe.shortBreakMinutes,
            PayloadKey.longBreakMinutes: safe.longBreakMinutes,
            PayloadKey.currentSession: currentSession.rawValue,
            PayloadKey.remainingSeconds: max(0, remainingSeconds),
            PayloadKey.isRunning: isRunning,
            PayloadKey.completedFocusSessions: max(0, completedFocusSessions),
            PayloadKey.didCompleteCycle: didCompleteCycle,
            PayloadKey.updatedAt: now.timeIntervalSince1970
        ]

        pendingContext = context
        pendingSignature = signature
        pushPendingContextIfPossible()
    }

    private func shouldThrottle(signature: SyncSignature, now: Date) -> Bool {
        guard let lastSentSignature else { return false }

        let durationAndSessionStateUnchanged =
            lastSentSignature.durations == signature.durations &&
            lastSentSignature.currentSession == signature.currentSession &&
            lastSentSignature.isRunning == signature.isRunning &&
            lastSentSignature.completedFocusSessions == signature.completedFocusSessions &&
            lastSentSignature.didCompleteCycle == signature.didCompleteCycle

        if signature == lastSentSignature {
            return true
        }

        guard signature.isRunning, durationAndSessionStateUnchanged else {
            return false
        }

        guard let lastSentDate else { return false }
        return now.timeIntervalSince(lastSentDate) < runningUpdateThrottleInterval
    }

    private func pushPendingContextIfPossible() {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else { return }
        guard let context = pendingContext else { return }
        guard let signature = pendingSignature else { return }

        do {
            try WCSession.default.updateApplicationContext(context)
            pendingContext = nil
            pendingSignature = nil
            lastSentSignature = signature
            lastSentDate = Date()
        } catch {
            // Keep pending payload and retry on the next activation or update call.
        }
    }
}

extension PhoneWatchSyncManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        Task { @MainActor [weak self] in
            self?.pushPendingContextIfPossible()
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
