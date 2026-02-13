//
//  ContentView.swift
//  Pomodoro Timer Watch App Watch App
//
//  Created by Phil McKenzie on 13/2/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var durationSyncManager: WatchDurationSyncManager
    @StateObject private var viewModel = WatchPomodoroViewModel()
    @State private var syncedFromPhoneVisible = false
    @State private var syncIndicatorResetID = 0
    @Environment(\.scenePhase) private var scenePhase

    init(durationSyncManager: WatchDurationSyncManager) {
        _durationSyncManager = ObservedObject(wrappedValue: durationSyncManager)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = WatchLayoutProfile(size: geometry.size)
            let diameter = layout.ringDiameter(for: geometry.size)
            let lineWidth = max(layout.minimumLineWidth, diameter * layout.ringLineWidthFactor)

            VStack(spacing: layout.verticalSpacing) {
                sessionHeader(layout: layout)
                timerRing(diameter: diameter, lineWidth: lineWidth, layout: layout)
                timerControls(layout: layout)
                sessionButtons(layout: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
        }
        .onAppear {
            durationSyncManager.activateIfNeeded()
            applyIncomingSyncStateIfAvailable()
        }
        .onChange(of: durationSyncManager.durations) { _, newDurations in
            if durationSyncManager.timerState == nil {
                viewModel.updateDurations(newDurations)
            }
        }
        .onChange(of: durationSyncManager.timerState) { _, newTimerState in
            guard let newTimerState else { return }
            viewModel.applySyncedState(newTimerState, durations: durationSyncManager.durations)
        }
        .onChange(of: durationSyncManager.settingsSyncEventID) { _, eventID in
            guard eventID > 0 else { return }
            triggerSyncedIndicator()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                durationSyncManager.activateIfNeeded()
                if durationSyncManager.timerState == nil {
                    viewModel.syncAfterForeground()
                } else {
                    applyIncomingSyncStateIfAvailable()
                }
            }
        }
        .task(id: syncIndicatorResetID) {
            guard syncIndicatorResetID > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                syncedFromPhoneVisible = false
            }
        }
    }

    private func sessionHeader(layout: WatchLayoutProfile) -> some View {
        VStack(spacing: 2) {
            Text(viewModel.currentSession.title)
                .font(
                    .system(
                        size: layout.sessionTitleFontSize,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(viewModel.cycleLabel)
                .font(
                    .system(
                        size: layout.cycleLabelFontSize,
                        weight: .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if syncedFromPhoneVisible {
                Text("Synced from iPhone")
                    .font(
                        .system(
                            size: max(8, layout.cycleLabelFontSize - 0.5),
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    private func timerRing(diameter: CGFloat, lineWidth: CGFloat, layout: WatchLayoutProfile) -> some View {
        ZStack {
            WatchTimerRing(
                progress: viewModel.remainingProgress,
                color: sessionColor(for: viewModel.currentSession),
                lineWidth: lineWidth
            )
            .animation(.linear(duration: 0.95), value: viewModel.remainingProgress)
            .frame(width: diameter, height: diameter)

            VStack(spacing: 2) {
                Text(viewModel.timeLabel)
                    .font(.system(size: layout.timeLabelFontSize(for: diameter), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text(viewModel.statusLabel)
                    .font(
                        .system(
                            size: layout.statusLabelFontSize,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timerControls(layout: WatchLayoutProfile) -> some View {
        HStack(spacing: layout.controlSpacing) {
            Button {
                viewModel.resetCurrentSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: layout.secondaryButtonFontSize, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(layout.controlSize)
            .accessibilityLabel("Reset session")

            Button {
                viewModel.toggleRunning()
            } label: {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: layout.secondaryButtonFontSize, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(layout.controlSize)
            .tint(sessionColor(for: viewModel.currentSession))
            .accessibilityLabel(viewModel.isRunning ? "Pause timer" : "Start timer")

            Button {
                viewModel.skipSession()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: layout.secondaryButtonFontSize, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(layout.controlSize)
            .accessibilityLabel("Skip session")
        }
    }

    private func sessionButtons(layout: WatchLayoutProfile) -> some View {
        HStack(spacing: layout.sessionSwitchSpacing) {
            ForEach(WatchPomodoroSession.allCases) { session in
                Button {
                    viewModel.selectSession(session)
                } label: {
                    Text(sessionButtonTitle(for: session, style: layout.sessionLabelStyle))
                        .font(.system(size: layout.sessionButtonFontSize, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(layout.controlSize)
                .tint(
                    session == viewModel.currentSession
                        ? sessionColor(for: session)
                        : Color.gray.opacity(0.35)
                )
                .accessibilityLabel("Switch to \(session.title)")
            }
        }
    }

    private func sessionButtonTitle(for session: WatchPomodoroSession, style: WatchLayoutProfile.SessionLabelStyle) -> String {
        switch style {
        case .full:
            return session.title
        case .compact:
            return session.compactTitle
        case .initials:
            switch session {
            case .focus:
                return "F"
            case .shortBreak:
                return "SB"
            case .longBreak:
                return "LB"
            }
        }
    }

    private func sessionColor(for session: WatchPomodoroSession) -> Color {
        switch session {
        case .focus:
            return .orange
        case .shortBreak:
            return .mint
        case .longBreak:
            return .blue
        }
    }

    private func applyIncomingSyncStateIfAvailable() {
        if let timerState = durationSyncManager.timerState {
            viewModel.applySyncedState(timerState, durations: durationSyncManager.durations)
        } else {
            viewModel.updateDurations(durationSyncManager.durations)
        }
    }

    private func triggerSyncedIndicator() {
        withAnimation(.easeOut(duration: 0.2)) {
            syncedFromPhoneVisible = true
        }
        syncIndicatorResetID += 1
    }
}

private struct WatchLayoutProfile {
    enum SessionLabelStyle {
        case full
        case compact
        case initials
    }

    private enum CaseSize {
        case mm40
        case mm41
        case mm44
        case mm45
        case mm49

        init(screenHeight: CGFloat) {
            switch screenHeight {
            case ..<205:
                self = .mm40
            case ..<220:
                self = .mm41
            case ..<233:
                self = .mm44
            case ..<248:
                self = .mm45
            default:
                self = .mm49
            }
        }
    }

    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let verticalSpacing: CGFloat
    let ringHeightFraction: CGFloat
    let ringMinimumDiameter: CGFloat
    let ringLineWidthFactor: CGFloat
    let minimumLineWidth: CGFloat
    let sessionTitleFontSize: CGFloat
    let cycleLabelFontSize: CGFloat
    let statusLabelFontSize: CGFloat
    let controlSpacing: CGFloat
    let controlSize: ControlSize
    let primaryButtonMinWidth: CGFloat
    let primaryButtonFontSize: CGFloat
    let secondaryButtonFontSize: CGFloat
    let sessionSwitchSpacing: CGFloat
    let sessionButtonFontSize: CGFloat
    let sessionLabelStyle: SessionLabelStyle
    let timeLabelScale: CGFloat
    let minimumTimeLabelSize: CGFloat

    init(size: CGSize) {
        let caseSize = CaseSize(screenHeight: max(size.width, size.height))

        switch caseSize {
        case .mm40:
            horizontalPadding = 4
            verticalPadding = 2
            verticalSpacing = 4
            ringHeightFraction = 0.5
            ringMinimumDiameter = 84
            ringLineWidthFactor = 0.095
            minimumLineWidth = 7
            sessionTitleFontSize = 13
            cycleLabelFontSize = 9
            statusLabelFontSize = 9
            controlSpacing = 6
            controlSize = .mini
            primaryButtonMinWidth = 40
            primaryButtonFontSize = 15
            secondaryButtonFontSize = 11
            sessionSwitchSpacing = 3
            sessionButtonFontSize = 9
            sessionLabelStyle = .initials
            timeLabelScale = 0.245
            minimumTimeLabelSize = 21
        case .mm41:
            horizontalPadding = 5
            verticalPadding = 3
            verticalSpacing = 5
            ringHeightFraction = 0.52
            ringMinimumDiameter = 90
            ringLineWidthFactor = 0.1
            minimumLineWidth = 8
            sessionTitleFontSize = 14
            cycleLabelFontSize = 9.5
            statusLabelFontSize = 9.5
            controlSpacing = 7
            controlSize = .mini
            primaryButtonMinWidth = 42
            primaryButtonFontSize = 16
            secondaryButtonFontSize = 11
            sessionSwitchSpacing = 4
            sessionButtonFontSize = 9.5
            sessionLabelStyle = .compact
            timeLabelScale = 0.252
            minimumTimeLabelSize = 22
        case .mm44:
            horizontalPadding = 6
            verticalPadding = 4
            verticalSpacing = 6
            ringHeightFraction = 0.54
            ringMinimumDiameter = 98
            ringLineWidthFactor = 0.102
            minimumLineWidth = 8.5
            sessionTitleFontSize = 14.5
            cycleLabelFontSize = 10
            statusLabelFontSize = 10
            controlSpacing = 8
            controlSize = .small
            primaryButtonMinWidth = 44
            primaryButtonFontSize = 16.5
            secondaryButtonFontSize = 11.5
            sessionSwitchSpacing = 4
            sessionButtonFontSize = 10
            sessionLabelStyle = .compact
            timeLabelScale = 0.258
            minimumTimeLabelSize = 23
        case .mm45:
            horizontalPadding = 7
            verticalPadding = 4
            verticalSpacing = 7
            ringHeightFraction = 0.55
            ringMinimumDiameter = 106
            ringLineWidthFactor = 0.104
            minimumLineWidth = 9
            sessionTitleFontSize = 15
            cycleLabelFontSize = 10.5
            statusLabelFontSize = 10.5
            controlSpacing = 8
            controlSize = .small
            primaryButtonMinWidth = 46
            primaryButtonFontSize = 17
            secondaryButtonFontSize = 12
            sessionSwitchSpacing = 5
            sessionButtonFontSize = 10.5
            sessionLabelStyle = .compact
            timeLabelScale = 0.264
            minimumTimeLabelSize = 24
        case .mm49:
            horizontalPadding = 8
            verticalPadding = 5
            verticalSpacing = 8
            ringHeightFraction = 0.56
            ringMinimumDiameter = 114
            ringLineWidthFactor = 0.108
            minimumLineWidth = 9.5
            sessionTitleFontSize = 16
            cycleLabelFontSize = 11
            statusLabelFontSize = 11
            controlSpacing = 9
            controlSize = .small
            primaryButtonMinWidth = 48
            primaryButtonFontSize = 17.5
            secondaryButtonFontSize = 12.5
            sessionSwitchSpacing = 5
            sessionButtonFontSize = 11
            sessionLabelStyle = .compact
            timeLabelScale = 0.272
            minimumTimeLabelSize = 25
        }
    }

    func ringDiameter(for size: CGSize) -> CGFloat {
        let widthLimit = size.width - (horizontalPadding * 2) - 6
        let heightLimit = size.height * ringHeightFraction
        let desired = max(ringMinimumDiameter, min(widthLimit, heightLimit))
        return max(72, min(desired, widthLimit))
    }

    func timeLabelFontSize(for diameter: CGFloat) -> CGFloat {
        max(minimumTimeLabelSize, diameter * timeLabelScale)
    }
}

private struct WatchTimerRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let clampedProgress = max(0, min(1, progress))

        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview {
    ContentView(durationSyncManager: WatchDurationSyncManager())
}
