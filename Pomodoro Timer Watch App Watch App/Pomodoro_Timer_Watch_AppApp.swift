//
//  Pomodoro_Timer_Watch_AppApp.swift
//  Pomodoro Timer Watch App Watch App
//
//  Created by Phil McKenzie on 13/2/2026.
//

import SwiftUI

@main
struct Pomodoro_Timer_Watch_App_Watch_AppApp: App {
    @StateObject private var durationSyncManager = WatchDurationSyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView(durationSyncManager: durationSyncManager)
        }
    }
}
