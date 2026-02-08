# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Debug build
xcodebuild -project "Pomodoro Timer.xcodeproj" -scheme "Pomodoro Timer" -configuration Debug build

# Clean build artifacts
xcodebuild -project "Pomodoro Timer.xcodeproj" -scheme "Pomodoro Timer" clean

# Run tests (once a test target is added)
xcodebuild -project "Pomodoro Timer.xcodeproj" -scheme "Pomodoro Timer" test
```

Single target, single scheme. No SPM dependencies. No test target exists yet — preferred framework is XCTest.

## Architecture

iOS SwiftUI app implementing a standard Pomodoro timer with a 4-session cycle (focus → short break, repeated 3 times, then focus → long break).

**Key files:**

- `Pomodoro_TimerApp.swift` — App entry point. Creates `SessionFeedbackManager` as a `@StateObject` and injects it into `ContentView`.
- `PomodoroViewModel.swift` — `@MainActor ObservableObject` owning all timer state: session type, countdown, cycle progression, auto-advance. Uses `Date`-based timing (stores `sessionEndDate`, syncs on tick). No external dependencies. Contains `PomodoroSession` enum and `PomodoroDurations` value type.
- `ContentView.swift` — Single-file view layer containing: `ContentView` (main screen with landscape/portrait layout), `TimerPreferencesView` (settings sheet), `CircularCountdownRing`, `CycleCompletionCelebrationOverlay`, and `SessionCoachingMessages`. User preferences stored via `@AppStorage`. Wires `onChange` handlers to sync preferences → ViewModel and trigger feedback.
- `SessionFeedbackManager.swift` — `NSObject` + `ObservableObject` handling notifications (`UNUserNotificationCenter`), haptics (`UINotificationFeedbackGenerator`), and sound playback (`AVAudioPlayer`). Also acts as `UNUserNotificationCenterDelegate` for actionable notification responses (start focus / start break / skip). Publishes `pendingNotificationAction` for the view to consume.
- `TimerSoundOption.swift` — `Int`-backed enum mapping sound IDs to `.wav` filenames in `Sounds/`.

**Data flow:** `@AppStorage` preferences in `ContentView` → pushed to `PomodoroViewModel` via `updateDurations()` / `setAutoAdvanceEnabled()`. Session completion events flow back via `@Published` properties (`sessionCompletionCount`, `lastCompletedSession`, `didCompleteCycle`) observed with `onChange` in `ContentView`, which triggers `SessionFeedbackManager` for sounds/haptics/notifications.

**Notification actions:** When the app is backgrounded during a running timer, a scheduled local notification fires at session end. The notification has actionable buttons (Start Focus / Start Break / Skip) whose responses are queued in `SessionFeedbackManager.pendingNotificationAction` and consumed when the view becomes active.

## Coding Conventions

- Swift style: 4-space indentation, `private` scoping by default
- `UpperCamelCase` types, `lowerCamelCase` properties/functions, `lowerCamelCase` enum cases
- Sound assets are `.wav` files in `Pomodoro Timer/Sounds/`, referenced by filename string in `TimerSoundOption`
