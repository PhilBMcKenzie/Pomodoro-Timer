import Foundation
import Combine
import UIKit
import UserNotifications
import AVFoundation

@MainActor
final class SessionFeedbackManager: NSObject, ObservableObject {
    enum NotificationAction: String {
        case startFocus = "pomodoro.action.start.focus"
        case startBreak = "pomodoro.action.start.break"
        case skip = "pomodoro.action.skip"
    }

    private let notificationCenter = UNUserNotificationCenter.current()
    private let activeSessionNotificationIdentifier = "pomodoro.active.session.end"
    private let sessionEndCategoryIdentifier = "pomodoro.session.end.category"
    private var didCheckAuthorization = false
    private var audioPlayer: AVAudioPlayer?
    @Published private(set) var pendingNotificationAction: NotificationAction?
    @Published private(set) var notificationsDenied = false
    private let cycleCompletedSoundFileName = "cycle-complete-fanfare"

    override init() {
        super.init()
        notificationCenter.delegate = self
        configureNotificationActions()
    }

    func requestAuthorizationIfNeeded() {
        guard !didCheckAuthorization else { return }
        didCheckAuthorization = true

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in
                        self.notificationsDenied = !granted
                    }
                }
            case .denied:
                Task { @MainActor in
                    self.notificationsDenied = true
                }
            default:
                Task { @MainActor in
                    self.notificationsDenied = false
                }
            }
        }
    }

    func refreshNotificationAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            Task { @MainActor in
                self.notificationsDenied = (settings.authorizationStatus == .denied)
            }
        }
    }

    func scheduleSessionEndNotification(for session: PomodoroSession, secondsRemaining: Int) {
        cancelScheduledSessionEndNotification()
        guard secondsRemaining > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(session.title) session complete"
        content.subtitle = "Continue from your lock screen."
        content.body = "Start your next session or skip ahead."
        content.categoryIdentifier = sessionEndCategoryIdentifier
        content.threadIdentifier = "pomodoro.timer"
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(secondsRemaining),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: activeSessionNotificationIdentifier,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    func cancelScheduledSessionEndNotification() {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [activeSessionNotificationIdentifier]
        )
    }

    func handleSessionCompleted(soundOption: TimerSoundOption) {
        guard UIApplication.shared.applicationState == .active else { return }
        playSound(option: soundOption, playCount: 3)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    func handleCycleCompleted() {
        guard UIApplication.shared.applicationState == .active else { return }

        playSound(fileName: cycleCompletedSoundFileName, playCount: 2)

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            let followUpGenerator = UINotificationFeedbackGenerator()
            followUpGenerator.prepare()
            followUpGenerator.notificationOccurred(.success)
        }
    }

    func previewSound(option: TimerSoundOption) {
        playSound(option: option)
    }

    func consumePendingNotificationAction() -> NotificationAction? {
        let action = pendingNotificationAction
        pendingNotificationAction = nil
        return action
    }

    private func playSound(option: TimerSoundOption, playCount: Int = 1) {
        guard let fileName = option.fileName else { return }
        playSound(fileName: fileName, playCount: playCount)
    }

    private func playSound(fileName: String, playCount: Int = 1) {
        guard let url = soundURL(for: fileName) else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = max(0, playCount - 1)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("[SessionFeedbackManager] Sound playback failed for '\(fileName)': \(error)")
            audioPlayer = nil
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SessionFeedbackManager] Audio session deactivation failed: \(error)")
        }
    }

    private func configureNotificationActions() {
        let startFocusAction = UNNotificationAction(
            identifier: NotificationAction.startFocus.rawValue,
            title: "Start Focus",
            options: [.foreground]
        )

        let startBreakAction = UNNotificationAction(
            identifier: NotificationAction.startBreak.rawValue,
            title: "Start Break",
            options: [.foreground]
        )

        let skipAction = UNNotificationAction(
            identifier: NotificationAction.skip.rawValue,
            title: "Skip",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: sessionEndCategoryIdentifier,
            actions: [startBreakAction, startFocusAction, skipAction],
            intentIdentifiers: []
        )

        notificationCenter.setNotificationCategories([category])
    }

    private func soundURL(for fileName: String) -> URL? {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "wav", subdirectory: "Sounds") {
            return url
        }
        if let url = Bundle.main.url(forResource: fileName, withExtension: "wav") {
            return url
        }
        return nil
    }
}

extension SessionFeedbackManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let action = NotificationAction(rawValue: response.actionIdentifier) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            self.pendingNotificationAction = action
        }

        completionHandler()
    }
}

extension SessionFeedbackManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        deactivateAudioSession()
    }
}
