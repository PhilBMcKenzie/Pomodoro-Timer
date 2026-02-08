//
//  ContentView.swift
//  Pomodoro Timer
//
//  Created by Phil McKenzie on 7/2/2026.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("focus_minutes") private var focusMinutes = 25
    @AppStorage("short_break_minutes") private var shortBreakMinutes = 5
    @AppStorage("long_break_minutes") private var longBreakMinutes = 20
    @AppStorage("auto_advance_enabled") private var autoAdvanceEnabled = false
    @AppStorage("coaching_statements_enabled") private var coachingStatementsEnabled = true
    @AppStorage("focus_sound_id") private var focusSoundID = TimerSoundOption.defaultFocus.rawValue
    @AppStorage("short_break_sound_id") private var shortBreakSoundID = TimerSoundOption.defaultShortBreak.rawValue
    @AppStorage("long_break_sound_id") private var longBreakSoundID = TimerSoundOption.defaultLongBreak.rawValue

    @StateObject private var viewModel = PomodoroViewModel()
    @ObservedObject private var feedbackManager: SessionFeedbackManager
    @State private var showingPreferences = false
    @State private var sessionChangeCueActive = false
    @State private var sessionCueResetTask: Task<Void, Never>?
    @State private var activeCoachingMessage = ""
    @State private var cycleCompletionCelebrationVisible = false
    @State private var cycleCompletionCelebrationBurst = false
    @State private var cycleCompletionCelebrationTask: Task<Void, Never>?
    @State private var animateRing = true
    @State private var lastMessageRefreshBucket = 0
    @Environment(\.scenePhase) private var scenePhase
    private let secondaryButtonWidth: CGFloat = 150

    init(feedbackManager: SessionFeedbackManager = SessionFeedbackManager()) {
        _feedbackManager = ObservedObject(wrappedValue: feedbackManager)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                let contentPadding: CGFloat = 20
                let landscapeRingDiameter = max(
                    220,
                    min(
                        geometry.size.height - (contentPadding * 2),
                        geometry.size.width * 0.55
                    )
                )

                Group {
                    if isLandscape {
                        HStack(alignment: .center, spacing: 28) {
                            timerRingView(diameter: landscapeRingDiameter)

                            VStack(spacing: 20) {
                                sessionHeaderView
                                controlsAndInfoView
                            }
                            .frame(maxWidth: min(360, geometry.size.width * 0.42))
                        }
                    } else {
                        VStack(spacing: 28) {
                            sessionHeaderView
                            timerRingView(diameter: 280)
                            controlsAndInfoView
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(contentPadding)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingPreferences) {
            TimerPreferencesView(
                focusMinutes: $focusMinutes,
                shortBreakMinutes: $shortBreakMinutes,
                longBreakMinutes: $longBreakMinutes,
                autoAdvanceEnabled: $autoAdvanceEnabled,
                coachingStatementsEnabled: $coachingStatementsEnabled,
                focusSoundID: $focusSoundID,
                shortBreakSoundID: $shortBreakSoundID,
                longBreakSoundID: $longBreakSoundID,
                previewSound: { soundID in
                    feedbackManager.previewSound(option: soundOption(from: soundID))
                }
            )
        }
        .onAppear {
            sanitizeSoundPreferences()
            feedbackManager.requestAuthorizationIfNeeded()
            applyDurationPreferences()
            viewModel.setAutoAdvanceEnabled(autoAdvanceEnabled)
            handleCoachingStatementsPreferenceChange(isEnabled: coachingStatementsEnabled)
            handlePendingNotificationActionIfNeeded()
        }
        .onChange(of: viewModel.sessionCompletionCount) { _, _ in
            guard let completedSession = viewModel.lastCompletedSession else { return }
            if viewModel.didCompleteCycle {
                feedbackManager.handleCycleCompleted()
                triggerCycleCompletionCelebration()
            } else {
                feedbackManager.handleSessionCompleted(
                    soundOption: completionSoundOption(for: completedSession)
                )
            }
            if shouldScheduleSessionEndNotification && !viewModel.didCompleteCycle {
                feedbackManager.scheduleSessionEndNotification(
                    for: viewModel.currentSession,
                    secondsRemaining: viewModel.remainingSeconds
                )
            } else if viewModel.didCompleteCycle {
                feedbackManager.cancelScheduledSessionEndNotification()
            }
        }
        .onChange(of: focusMinutes) { _, _ in
            applyDurationPreferences()
        }
        .onChange(of: shortBreakMinutes) { _, _ in
            applyDurationPreferences()
        }
        .onChange(of: longBreakMinutes) { _, _ in
            applyDurationPreferences()
        }
        .onChange(of: autoAdvanceEnabled) { _, isEnabled in
            viewModel.setAutoAdvanceEnabled(isEnabled)
        }
        .onChange(of: coachingStatementsEnabled) { _, isEnabled in
            handleCoachingStatementsPreferenceChange(isEnabled: isEnabled)
        }
        .onChange(of: viewModel.currentSession) { _, _ in
            handleSessionTransition()
        }
        .onChange(of: viewModel.remainingSeconds) { _, _ in
            updateCoachingMessageIfNeeded()
        }
        .onChange(of: viewModel.isRunning) { _, isRunning in
            if isRunning {
                if shouldScheduleSessionEndNotification && !viewModel.didCompleteCycle {
                    feedbackManager.scheduleSessionEndNotification(
                        for: viewModel.currentSession,
                        secondsRemaining: viewModel.remainingSeconds
                    )
                } else {
                    feedbackManager.cancelScheduledSessionEndNotification()
                }
                lastMessageRefreshBucket = messageRefreshBucket(for: viewModel.currentSession)
            } else {
                feedbackManager.cancelScheduledSessionEndNotification()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                animateRing = false
                feedbackManager.cancelScheduledSessionEndNotification()
                viewModel.syncAfterForeground()
                handlePendingNotificationActionIfNeeded()
                DispatchQueue.main.async {
                    animateRing = true
                }
            } else if shouldScheduleSessionEndNotification {
                feedbackManager.scheduleSessionEndNotification(
                    for: viewModel.currentSession,
                    secondsRemaining: viewModel.remainingSeconds
                )
            }
        }
        .onChange(of: feedbackManager.pendingNotificationAction) { _, _ in
            handlePendingNotificationActionIfNeeded()
        }
        .onDisappear {
            sessionCueResetTask?.cancel()
            sessionCueResetTask = nil
            cycleCompletionCelebrationTask?.cancel()
            cycleCompletionCelebrationTask = nil
        }
    }

    private var sessionHeaderView: some View {
        VStack(spacing: 8) {
            Text(sessionTitle)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(sessionChangeCueActive ? sessionAccentColor : Color.primary)
            Text(sessionSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .scaleEffect(sessionChangeCueActive ? 1.03 : 1)
    }

    private func timerRingView(diameter: CGFloat) -> some View {
        ZStack {
            CircularCountdownRing(
                progress: viewModel.remainingProgress,
                session: viewModel.currentSession
            )
            .animation(animateRing ? .linear(duration: 0.95) : nil, value: viewModel.remainingProgress)

            Group {
                if shouldPulseCountdownText {
                    TimelineView(.animation) { context in
                        timerTextContent(diameter: diameter, opacity: countdownTextOpacity(at: context.date))
                    }
                } else {
                    timerTextContent(diameter: diameter, opacity: 1)
                }
            }
        }
        .overlay {
            Circle()
                .stroke(sessionAccentColor.opacity(sessionChangeCueActive ? 0.32 : 0), lineWidth: 4)
                .padding(8)
        }
        .overlay {
            if cycleCompletionCelebrationVisible {
                CycleCompletionCelebrationOverlay(isBursting: cycleCompletionCelebrationBurst)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .scaleEffect(sessionChangeCueActive ? 1.02 : 1)
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private func timerTextContent(diameter: CGFloat, opacity: Double) -> some View {
        VStack(spacing: 10) {
            Text(viewModel.timeLabel)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Time remaining")
                .opacity(opacity)

            if coachingStatementsEnabled {
                Text(activeCoachingMessage)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: diameter * 0.58)
                    .accessibilityLabel("Coaching message")
            }
        }
    }

    private var shouldPulseCountdownText: Bool {
        viewModel.isRunning && viewModel.remainingSeconds > 0 && viewModel.remainingSeconds <= 10
    }

    private func countdownTextOpacity(at date: Date) -> Double {
        guard shouldPulseCountdownText else { return 1 }

        let cycleDuration = 1.15
        let phase = (date.timeIntervalSinceReferenceDate / cycleDuration) * (2 * Double.pi)
        let normalizedSine = (sin(phase) + 1) / 2
        return 0.55 + (0.45 * normalizedSine)
    }

    private var controlsAndInfoView: some View {
        VStack(spacing: 20) {
            Button(viewModel.isRunning ? "Pause Session" : "Start Session") {
                if viewModel.isRunning {
                    viewModel.pause()
                } else {
                    viewModel.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.vertical, 12)

            HStack(spacing: 10) {
                Button {
                    viewModel.resetCurrentSession()
                } label: {
                    Text("Reset Session")
                        .frame(width: secondaryButtonWidth)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.secondary)

                Button {
                    viewModel.skipSession()
                } label: {
                    Text("Skip Session")
                        .frame(width: secondaryButtonWidth)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.resetCycle()
                } label: {
                    Text("Reset Cycle")
                        .frame(width: secondaryButtonWidth)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.secondary)

                Button {
                    showingPreferences = true
                } label: {
                    Text("Preferences")
                        .frame(width: secondaryButtonWidth)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.secondary)
                .accessibilityLabel("Open timer preferences")
            }

            VStack(spacing: 6) {
                Text("Pattern: \(focusMinutes) min focus, \(shortBreakMinutes) min short break, \(longBreakMinutes) min long break after 4 focus sessions")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionAccentColor: Color {
        viewModel.currentSession.ringColors.first ?? .accentColor
    }

    private var sessionTitle: String {
        if viewModel.didCompleteCycle {
            return "Cycle Complete"
        }
        return viewModel.currentSession.title
    }

    private var sessionSubtitle: String {
        if viewModel.didCompleteCycle {
            return "All 4 Pomodoros finished"
        }
        return viewModel.cyclePositionLabel
    }

    private func triggerSessionTransitionCue() {
        sessionCueResetTask?.cancel()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
            sessionChangeCueActive = true
        }

        sessionCueResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                sessionChangeCueActive = false
            }
        }
    }

    private func triggerCycleCompletionCelebration() {
        cycleCompletionCelebrationTask?.cancel()
        cycleCompletionCelebrationBurst = false

        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
            cycleCompletionCelebrationVisible = true
        }

        cycleCompletionCelebrationTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 1.1)) {
                cycleCompletionCelebrationBurst = true
            }

            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.25)) {
                cycleCompletionCelebrationVisible = false
                cycleCompletionCelebrationBurst = false
            }
        }
    }

    private func initializeCoachingMessage() {
        guard coachingStatementsEnabled else {
            activeCoachingMessage = ""
            return
        }
        activeCoachingMessage = randomMessage(
            for: viewModel.currentSession,
            excluding: nil
        )
        lastMessageRefreshBucket = messageRefreshBucket(for: viewModel.currentSession)
    }

    private func handleSessionTransition() {
        triggerSessionTransitionCue()
        guard coachingStatementsEnabled else { return }
        let refreshedMessage = randomMessage(
            for: viewModel.currentSession,
            excluding: activeCoachingMessage
        )
        activeCoachingMessage = refreshedMessage
        lastMessageRefreshBucket = messageRefreshBucket(for: viewModel.currentSession)
    }

    private func updateCoachingMessageIfNeeded() {
        guard coachingStatementsEnabled, viewModel.isRunning else { return }
        let bucket = messageRefreshBucket(for: viewModel.currentSession)
        guard bucket != lastMessageRefreshBucket else { return }
        lastMessageRefreshBucket = bucket
        activeCoachingMessage = randomMessage(
            for: viewModel.currentSession,
            excluding: activeCoachingMessage
        )
    }

    private func messageRefreshBucket(for session: PomodoroSession) -> Int {
        let elapsedSeconds = max(0, viewModel.sessionDurationSeconds - viewModel.remainingSeconds)
        let intervalSeconds = messageRefreshIntervalSeconds(for: session)
        return elapsedSeconds / intervalSeconds
    }

    private func messageRefreshIntervalSeconds(for session: PomodoroSession) -> Int {
        let totalSessionSeconds = max(1, viewModel.sessionDurationSeconds)
        let fraction: Double

        switch session {
        case .focus:
            fraction = 0.10
        case .shortBreak, .longBreak:
            fraction = 0.10
        }

        return max(1, Int((Double(totalSessionSeconds) * fraction).rounded(.up)))
    }

    private func randomMessage(for session: PomodoroSession, excluding excluded: String?) -> String {
        let messages = coachingMessages(for: session)
        guard !messages.isEmpty else { return "" }
        guard
            let excluded,
            messages.count > 1,
            messages.contains(excluded)
        else {
            return messages.randomElement() ?? ""
        }

        let candidates = messages.filter { $0 != excluded }
        return candidates.randomElement() ?? excluded
    }

    private func coachingMessages(for session: PomodoroSession) -> [String] {
        switch session {
        case .focus:
            return SessionCoachingMessages.focus
        case .shortBreak, .longBreak:
            return SessionCoachingMessages.breaks
        }
    }

    private func handleCoachingStatementsPreferenceChange(isEnabled: Bool) {
        if isEnabled {
            initializeCoachingMessage()
        } else {
            activeCoachingMessage = ""
        }
    }

    private var durationPreferences: PomodoroDurations {
        PomodoroDurations(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes
        )
    }

    private func applyDurationPreferences() {
        viewModel.updateDurations(durationPreferences)
        if shouldScheduleSessionEndNotification {
            feedbackManager.scheduleSessionEndNotification(
                for: viewModel.currentSession,
                secondsRemaining: viewModel.remainingSeconds
            )
        } else {
            feedbackManager.cancelScheduledSessionEndNotification()
        }
    }

    private var shouldScheduleSessionEndNotification: Bool {
        viewModel.isRunning && scenePhase != .active
    }

    private func completionSoundOption(for session: PomodoroSession) -> TimerSoundOption {
        switch session {
        case .focus:
            return soundOption(from: focusSoundID, fallback: .defaultFocus)
        case .shortBreak:
            return soundOption(from: shortBreakSoundID, fallback: .defaultShortBreak)
        case .longBreak:
            return soundOption(from: longBreakSoundID, fallback: .defaultLongBreak)
        }
    }

    private func sanitizeSoundPreferences() {
        if TimerSoundOption(rawValue: focusSoundID) == nil {
            focusSoundID = TimerSoundOption.defaultFocus.rawValue
        }
        if TimerSoundOption(rawValue: shortBreakSoundID) == nil {
            shortBreakSoundID = TimerSoundOption.defaultShortBreak.rawValue
        }
        if TimerSoundOption(rawValue: longBreakSoundID) == nil {
            longBreakSoundID = TimerSoundOption.defaultLongBreak.rawValue
        }
    }

    private func soundOption(from rawValue: Int, fallback: TimerSoundOption = .none) -> TimerSoundOption {
        TimerSoundOption(rawValue: rawValue) ?? fallback
    }

    private func handlePendingNotificationActionIfNeeded() {
        guard let action = feedbackManager.consumePendingNotificationAction() else { return }

        viewModel.syncAfterForeground()

        switch action {
        case .startFocus:
            viewModel.startFocusSession()
        case .startBreak:
            viewModel.startBreakSession()
        case .skip:
            viewModel.skipAndStartNextSession()
        }
    }
}

private struct TimerPreferencesView: View {
    @Binding var focusMinutes: Int
    @Binding var shortBreakMinutes: Int
    @Binding var longBreakMinutes: Int
    @Binding var autoAdvanceEnabled: Bool
    @Binding var coachingStatementsEnabled: Bool
    @Binding var focusSoundID: Int
    @Binding var shortBreakSoundID: Int
    @Binding var longBreakSoundID: Int
    let previewSound: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var soundPreviewEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Session Durations") {
                    durationSliderRow(
                        title: "Focus",
                        minutes: $focusMinutes,
                        range: 1...120
                    )

                    durationSliderRow(
                        title: "Short Break",
                        minutes: $shortBreakMinutes,
                        range: 1...60
                    )

                    durationSliderRow(
                        title: "Long Break",
                        minutes: $longBreakMinutes,
                        range: 1...90
                    )
                }

                Section {
                    Button("Reset Session Durations to Defaults") {
                        resetDurationsToDefaults()
                    }
                }

                Section("Behavior") {
                    Toggle("Auto-start next session", isOn: $autoAdvanceEnabled)
                    Toggle("Show coaching statements", isOn: $coachingStatementsEnabled)
                }

                Section("Sounds") {
                    Picker("Focus Complete", selection: $focusSoundID) {
                        ForEach(TimerSoundOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .onChange(of: focusSoundID) { _, newValue in
                        previewIfEnabled(soundID: newValue)
                    }

                    Picker("Short Break Complete", selection: $shortBreakSoundID) {
                        ForEach(TimerSoundOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .onChange(of: shortBreakSoundID) { _, newValue in
                        previewIfEnabled(soundID: newValue)
                    }

                    Picker("Long Break Complete", selection: $longBreakSoundID) {
                        ForEach(TimerSoundOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .onChange(of: longBreakSoundID) { _, newValue in
                        previewIfEnabled(soundID: newValue)
                    }

                    Button(soundPreviewEnabled ? "Sound Preview: On" : "Sound Preview: Off") {
                        soundPreviewEnabled.toggle()
                    }
                }
            }
            .navigationTitle("Preferences")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func preferenceRow(title: String, minutes: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(minutes) min")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func durationSliderRow(title: String, minutes: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            preferenceRow(title: title, minutes: minutes.wrappedValue)

            Slider(
                value: Binding(
                    get: { Double(minutes.wrappedValue) },
                    set: { minutes.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )

            HStack {
                Text("\(range.lowerBound) min")
                Spacer()
                Text("\(range.upperBound) min")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func resetDurationsToDefaults() {
        focusMinutes = PomodoroDurations.default.focusMinutes
        shortBreakMinutes = PomodoroDurations.default.shortBreakMinutes
        longBreakMinutes = PomodoroDurations.default.longBreakMinutes
    }

    private func previewIfEnabled(soundID: Int) {
        guard soundPreviewEnabled else { return }
        previewSound(soundID)
    }
}

private struct CircularCountdownRing: View {
    let progress: Double
    let session: PomodoroSession

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 20)
                .foregroundStyle(.secondary.opacity(0.15))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: session.ringColors,
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: session.ringColors[0].opacity(0.25), radius: 8)
        }
    }
}

private struct CycleCompletionCelebrationOverlay: View {
    let isBursting: Bool

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let angle = (Double(index) / 16.0) * 2 * Double.pi
                let radius: CGFloat = isBursting ? 150 : 16
                let size: CGFloat = index.isMultiple(of: 2) ? 14 : 10

                Circle()
                    .fill(celebrationColors[index % celebrationColors.count])
                    .frame(width: size, height: size)
                    .offset(
                        x: CGFloat(cos(angle)) * radius,
                        y: CGFloat(sin(angle)) * radius
                    )
                    .scaleEffect(isBursting ? 0.15 : 1)
                    .opacity(isBursting ? 0 : 0.95)
                    .animation(.easeOut(duration: 1.0).delay(Double(index) * 0.02), value: isBursting)
            }

            Image(systemName: "party.popper.fill")
                .font(.system(size: isBursting ? 54 : 40, weight: .bold))
                .foregroundStyle(.yellow, .orange)
                .shadow(color: Color.orange.opacity(0.35), radius: 10)
                .scaleEffect(isBursting ? 1.22 : 1)
                .opacity(isBursting ? 0.1 : 1)
                .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isBursting)
        }
        .allowsHitTesting(false)
    }

    private var celebrationColors: [Color] {
        [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.cyan, Color.mint]
    }
}

private extension PomodoroSession {
    var ringColors: [Color] {
        switch self {
        case .focus:
            return [Color.red, Color.orange]
        case .shortBreak:
            return [Color.green, Color.mint]
        case .longBreak:
            return [Color.blue, Color.cyan]
        }
    }
}

private enum SessionCoachingMessages {
    static let focus: [String] = [
        "One thing. Right now",
        "Action creates momentum",
        "Eat the frog",
        "Just start. Correct later",
        "Five minutes. That's all",
        "Don't think. Do",
        "Be here, not there",
        "Attack the task",
        "Clear the desk. Clear the mind",
        "Today is for doing",
        "Starve the distraction",
        "Feed the focus",
        "Phone down. Eyes up",
        "Close the tabs",
        "Ignore the ping",
        "Not now. Later",
        "Don't drift",
        "Silence the noise",
        "Stop scrolling. Start building",
        "Your attention is currency. Spend it wisely",
        "No excuses",
        "Respect the clock",
        "Discipline over motivation",
        "Do the work",
        "Feelings don't matter. Actions do",
        "Don't cheat yourself",
        "Keep the promise to yourself",
        "Hard work works",
        "You are not a procrastinator. Stop acting like one",
        "Earn your relaxation",
        "Lock it in",
        "Chase the flow",
        "You are a machine",
        "Breathe. Focus. Execute",
        "Find your rhythm",
        "This is where you grow",
        "Deep work wins",
        "Embrace the grind",
        "You are capable of hard things",
        "Stay in the zone",
        "Finish strong",
        "Almost there",
        "Grind now. Shine later",
        "Future You will thank you",
        "Results are waiting",
        "Don't stop halfway",
        "Push through the resistance",
        "Leave nothing on the table",
        "Close the loop",
        "Done is better than perfect"
    ]

    static let breaks: [String] = [
        "Stand up immediately",
        "Shake out the tension",
        "Stretch toward the ceiling",
        "Touch your toes",
        "Walk away from the desk",
        "Shoulders down. Relax",
        "Unclench your jaw",
        "Get the blood flowing",
        "Dance it out",
        "Change your posture",
        "Eyes off the screen",
        "Look out a window",
        "Focus on distance (20 feet away)",
        "Find something green",
        "Close your eyes",
        "Splash water on your face",
        "Breathe in fresh air",
        "Listen to the room tone",
        "Feel your feet on the floor",
        "Rest your vision",
        "Drink a full glass",
        "Hydrate to dominate",
        "Make tea, mindfully",
        "Refill the water bottle",
        "Grab a healthy snack",
        "Fuel the machine",
        "Sip slowly",
        "Water first",
        "Nourish your focus",
        "Brain needs fluid",
        "Don't touch the phone",
        "No social media",
        "Do not check email",
        "Stay offline",
        "Resist the scroll",
        "Keep the dopamine low",
        "Real world only",
        "Notifications can wait",
        "Leave the device behind",
        "Protect your peace",
        "Let the brain idle",
        "Stop thinking",
        "Zone out intentionally",
        "Empty the cache",
        "Be boring for 5 minutes",
        "Silence is golden",
        "Let the subconscious work",
        "You earned this rest",
        "Reset for the next round",
        "Breathe. Reset. Ready"
    ]
}

#Preview {
    ContentView()
}
