//
//  WatchPomodoroViewModel.swift
//  Pomodoro Timer Watch App Watch App
//
//  Created by Codex on 13/2/2026.
//

import Combine
import Foundation
import WatchKit

enum WatchPomodoroSession: String, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .focus:
            return "Focus"
        case .shortBreak:
            return "Short Break"
        case .longBreak:
            return "Long Break"
        }
    }

    var compactTitle: String {
        switch self {
        case .focus:
            return "Focus"
        case .shortBreak:
            return "Short"
        case .longBreak:
            return "Long"
        }
    }
}

struct WatchPomodoroDurations: Equatable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int

    static let `default` = WatchPomodoroDurations(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 20
    )

    func sanitized() -> WatchPomodoroDurations {
        WatchPomodoroDurations(
            focusMinutes: min(max(1, focusMinutes), 120),
            shortBreakMinutes: min(max(1, shortBreakMinutes), 60),
            longBreakMinutes: min(max(1, longBreakMinutes), 90)
        )
    }

    func durationSeconds(for session: WatchPomodoroSession) -> Int {
        let safe = sanitized()
        switch session {
        case .focus:
            return safe.focusMinutes * 60
        case .shortBreak:
            return safe.shortBreakMinutes * 60
        case .longBreak:
            return safe.longBreakMinutes * 60
        }
    }
}

@MainActor
final class WatchPomodoroViewModel: ObservableObject {
    @Published private(set) var currentSession: WatchPomodoroSession = .focus
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var completedFocusSessions = 0
    @Published private(set) var isRunning = false
    @Published private(set) var didCompleteCycle = false

    private var durations: WatchPomodoroDurations
    private var timerCancellable: AnyCancellable?
    private var sessionEndDate: Date?

    init(
        durations: WatchPomodoroDurations = WatchPomodoroDurations(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 20
        )
    ) {
        let safeDurations = durations.sanitized()
        self.durations = safeDurations
        self.remainingSeconds = safeDurations.durationSeconds(for: .focus)
    }

    var sessionDurationSeconds: Int {
        durations.durationSeconds(for: currentSession)
    }

    var remainingProgress: Double {
        guard sessionDurationSeconds > 0 else { return 0 }
        return max(0, min(1, Double(remainingSeconds) / Double(sessionDurationSeconds)))
    }

    var timeLabel: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var cycleLabel: String {
        if didCompleteCycle {
            return "Cycle complete"
        }

        if currentSession == .longBreak,
           completedFocusSessions > 0,
           completedFocusSessions.isMultiple(of: 4) {
            return "Pomodoro 4/4"
        }

        let cyclePosition = (completedFocusSessions % 4) + 1
        return "Pomodoro \(cyclePosition)/4"
    }

    var statusLabel: String {
        if didCompleteCycle {
            return "Ready to restart"
        }
        return isRunning ? "Running" : "Paused"
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func updateDurations(_ newDurations: WatchPomodoroDurations) {
        let safeDurations = newDurations.sanitized()
        guard safeDurations != durations else { return }

        let oldDuration = sessionDurationSeconds
        let elapsed = max(0, oldDuration - remainingSeconds)
        durations = safeDurations
        let updatedDuration = sessionDurationSeconds
        remainingSeconds = max(0, updatedDuration - elapsed)

        if isRunning {
            sessionEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            if remainingSeconds == 0 {
                tick()
            }
        }
    }

    func applySyncedState(_ syncedState: WatchSyncedTimerState, durations newDurations: WatchPomodoroDurations) {
        stopTimer()
        durations = newDurations.sanitized()
        currentSession = syncedState.session
        completedFocusSessions = max(0, syncedState.completedFocusSessions)
        didCompleteCycle = syncedState.didCompleteCycle

        let transferDelay = max(0, Int(Date().timeIntervalSince(syncedState.sentAt)))
        remainingSeconds = max(0, syncedState.remainingSeconds - transferDelay)

        guard syncedState.isRunning, !didCompleteCycle, remainingSeconds > 0 else { return }
        beginRunningTimer()
    }

    func start() {
        if didCompleteCycle {
            resetCycleState()
        }

        guard !isRunning else { return }

        beginRunningTimer()
    }

    func pause() {
        guard isRunning else { return }
        syncRemainingTime()
        stopTimer()
    }

    func resetCurrentSession() {
        stopTimer()
        didCompleteCycle = false
        remainingSeconds = sessionDurationSeconds
    }

    func skipSession() {
        stopTimer()
        didCompleteCycle = false
        _ = advanceToNextSession(creditFocusSession: false)
    }

    func selectSession(_ session: WatchPomodoroSession) {
        stopTimer()
        didCompleteCycle = false
        currentSession = session
        remainingSeconds = sessionDurationSeconds
    }

    func syncAfterForeground() {
        guard isRunning else { return }
        tick()
    }

    private func tick() {
        guard isRunning else { return }

        syncRemainingTime()
        guard remainingSeconds == 0 else { return }

        let completedSession = currentSession
        stopTimer()

        let completedFullCycle = advanceToNextSession(creditFocusSession: true)
        didCompleteCycle = completedFullCycle
        playCompletionHaptic(for: completedSession, cycleComplete: completedFullCycle)
    }

    private func syncRemainingTime() {
        guard let sessionEndDate else { return }
        let secondsLeft = Int(ceil(sessionEndDate.timeIntervalSinceNow))
        remainingSeconds = max(0, secondsLeft)
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
        sessionEndDate = nil
    }

    private func beginRunningTimer() {
        isRunning = true
        sessionEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))

        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func advanceToNextSession(creditFocusSession: Bool) -> Bool {
        if currentSession == .focus {
            if creditFocusSession {
                completedFocusSessions += 1
            }

            if completedFocusSessions > 0 && completedFocusSessions.isMultiple(of: 4) {
                currentSession = .longBreak
            } else {
                currentSession = .shortBreak
            }

            remainingSeconds = sessionDurationSeconds
            return false
        }

        if currentSession == .longBreak,
           creditFocusSession,
           completedFocusSessions > 0,
           completedFocusSessions.isMultiple(of: 4) {
            remainingSeconds = 0
            return true
        } else {
            currentSession = .focus
            remainingSeconds = sessionDurationSeconds
            return false
        }
    }

    private func resetCycleState() {
        completedFocusSessions = 0
        currentSession = .focus
        remainingSeconds = durations.durationSeconds(for: .focus)
        didCompleteCycle = false
    }

    private func playCompletionHaptic(for session: WatchPomodoroSession, cycleComplete: Bool) {
        if cycleComplete {
            WKInterfaceDevice.current().play(.success)
        } else if session == .focus {
            WKInterfaceDevice.current().play(.notification)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
    }
}
