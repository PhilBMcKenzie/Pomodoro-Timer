//
//  Pomodoro_TimerApp.swift
//  Pomodoro Timer
//
//  Created by Phil McKenzie on 7/2/2026.
//

import SwiftUI

@main
struct Pomodoro_TimerApp: App {
    @StateObject private var feedbackManager = SessionFeedbackManager()

    var body: some Scene {
        WindowGroup {
            ContentView(feedbackManager: feedbackManager)
        }
    }
}
