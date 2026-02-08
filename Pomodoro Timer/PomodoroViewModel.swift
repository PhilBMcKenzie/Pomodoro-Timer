import Foundation
import Combine

enum PomodoroSession: String, CaseIterable {
    case focus
    case shortBreak
    case longBreak

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
}

struct PomodoroDurations: Equatable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int

    static let `default` = PomodoroDurations(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 20
    )

    func sanitized() -> PomodoroDurations {
        PomodoroDurations(
            focusMinutes: max(1, focusMinutes),
            shortBreakMinutes: max(1, shortBreakMinutes),
            longBreakMinutes: max(1, longBreakMinutes)
        )
    }

    func durationSeconds(for session: PomodoroSession) -> Int {
        switch session {
        case .focus:
            return max(1, focusMinutes) * 60
        case .shortBreak:
            return max(1, shortBreakMinutes) * 60
        case .longBreak:
            return max(1, longBreakMinutes) * 60
        }
    }
}

@MainActor
final class PomodoroViewModel: ObservableObject {
    @Published private(set) var currentSession: PomodoroSession = .focus
    @Published private(set) var remainingSeconds: Int = PomodoroDurations.default.durationSeconds(for: .focus)
    @Published private(set) var completedFocusSessions = 0
    @Published private(set) var isRunning = false
    @Published private(set) var lastCompletedSession: PomodoroSession?
    @Published private(set) var sessionCompletionCount = 0
    @Published private(set) var didCompleteCycle = false
    @Published private(set) var cycleCompletionCount = 0

    private var durations: PomodoroDurations
    private var autoAdvanceEnabled = false
    var sessionDurationSeconds: Int {
        durations.durationSeconds(for: currentSession)
    }

    var progress: Double {
        guard sessionDurationSeconds > 0 else { return 0 }
        let elapsed = sessionDurationSeconds - remainingSeconds
        return max(0, min(1, Double(elapsed) / Double(sessionDurationSeconds)))
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

    var cyclePositionLabel: String {
        if didCompleteCycle {
            return "All 4 Pomodoros complete"
        }

        if currentSession == .longBreak, completedFocusSessions > 0, completedFocusSessions.isMultiple(of: 4) {
            return "Pomodoro 4 of 4"
        }

        let position = (completedFocusSessions % 4) + 1
        return "Pomodoro \(position) of 4"
    }

    private var timer: Timer?
    private var sessionEndDate: Date?

    init(durations: PomodoroDurations = .default) {
        let safeDurations = durations.sanitized()
        self.durations = safeDurations
        self.remainingSeconds = safeDurations.durationSeconds(for: .focus)
    }

    func updateDurations(_ newDurations: PomodoroDurations) {
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

    func setAutoAdvanceEnabled(_ isEnabled: Bool) {
        autoAdvanceEnabled = isEnabled
    }

    func start() {
        if didCompleteCycle {
            clearCycleCompletionState()
            currentSession = .focus
            remainingSeconds = durations.durationSeconds(for: .focus)
        }

        guard !isRunning else { return }

        isRunning = true
        sessionEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func pause() {
        guard isRunning else { return }

        syncRemainingTime()
        timer?.invalidate()
        timer = nil
        sessionEndDate = nil
        isRunning = false
    }

    func resetCurrentSession() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        sessionEndDate = nil
        clearCycleCompletionState()
        remainingSeconds = sessionDurationSeconds
    }

    func resetCycle() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        sessionEndDate = nil
        currentSession = .focus
        completedFocusSessions = 0
        clearCycleCompletionState()
        remainingSeconds = sessionDurationSeconds
    }

    func skipSession() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        sessionEndDate = nil
        clearCycleCompletionState()
        _ = advanceToNextSession(creditFocusSession: false)
    }

    func startFocusSession() {
        startSession(.focus)
    }

    func startBreakSession() {
        let breakSession: PomodoroSession
        if currentSession == .shortBreak || currentSession == .longBreak {
            breakSession = currentSession
        } else if completedFocusSessions > 0 && completedFocusSessions.isMultiple(of: 4) {
            breakSession = .longBreak
        } else {
            breakSession = .shortBreak
        }

        startSession(breakSession)
    }

    func skipAndStartNextSession() {
        skipSession()
        start()
    }

    func syncAfterForeground() {
        guard isRunning else { return }
        tick()
    }

    private func startSession(_ session: PomodoroSession) {
        timer?.invalidate()
        timer = nil
        isRunning = false
        sessionEndDate = nil
        clearCycleCompletionState()
        currentSession = session
        remainingSeconds = sessionDurationSeconds
        start()
    }

    private func tick() {
        guard isRunning else { return }

        syncRemainingTime()

        if remainingSeconds == 0 {
            let completedSession = currentSession
            timer?.invalidate()
            timer = nil
            isRunning = false
            sessionEndDate = nil
            let didCompleteFullCycle = advanceToNextSession(creditFocusSession: true)
            lastCompletedSession = completedSession
            if didCompleteFullCycle {
                didCompleteCycle = true
                cycleCompletionCount += 1
            }
            sessionCompletionCount += 1
            if autoAdvanceEnabled && !didCompleteFullCycle {
                start()
            }
        }
    }

    private func syncRemainingTime() {
        guard let sessionEndDate else { return }
        let secondsLeft = Int(ceil(sessionEndDate.timeIntervalSinceNow))
        remainingSeconds = max(0, secondsLeft)
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

        if currentSession == .longBreak, creditFocusSession, completedFocusSessions > 0, completedFocusSessions.isMultiple(of: 4) {
            remainingSeconds = 0
            return true
        } else {
            currentSession = .focus
            remainingSeconds = sessionDurationSeconds
            return false
        }
    }

    private func clearCycleCompletionState() {
        didCompleteCycle = false
    }
}
