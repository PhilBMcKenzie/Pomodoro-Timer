# Repository Guidelines

## Project Structure & Module Organization
- `Pomodoro Timer/` contains the app source.
- `Pomodoro Timer/ContentView.swift` is the main SwiftUI screen and interaction wiring.
- `Pomodoro Timer/PomodoroViewModel.swift` holds timer/session state and progression logic.
- `Pomodoro Timer/SessionFeedbackManager.swift` manages notifications, haptics, and sound playback.
- `Pomodoro Timer/TimerSoundOption.swift` defines selectable completion sounds.
- `Pomodoro Timer/Sounds/` stores `.wav` assets; `Pomodoro Timer/Assets.xcassets/` stores app icons/colors.
- `Pomodoro Timer.xcodeproj/` is the Xcode project (single app target). There is currently no test target checked in.

## Build, Test, and Development Commands
Run these on macOS with Xcode installed:
- `open "Pomodoro Timer.xcodeproj"` opens the project in Xcode for iterative development.
- `xcodebuild -project "Pomodoro Timer.xcodeproj" -scheme "Pomodoro Timer" -configuration Debug build` performs a CLI debug build.
- `xcodebuild -project "Pomodoro Timer.xcodeproj" -scheme "Pomodoro Timer" clean` clears build artifacts.
- `xcodebuild -project "Pomodoro Timer.xcodeproj" -scheme "Pomodoro Timer" test` runs tests after a test target is added.

## Coding Style & Naming Conventions
- Follow standard Swift style: 4-space indentation, no tabs, and clear `private` scoping where possible.
- Use `UpperCamelCase` for types (`PomodoroViewModel`) and `lowerCamelCase` for properties/functions (`remainingSeconds`, `startFocusSession`).
- Keep enum cases lower camel case (`shortBreak`, `longBreak`).
- Organize SwiftUI views into small computed properties/functions when view bodies grow.

## Testing Guidelines
- Preferred framework: XCTest.
- Add tests under a dedicated target (for example, `Pomodoro TimerTests/`).
- Name tests by behavior, e.g., `test_WhenFocusSessionCompletes_AdvancesToBreak()`.
- Prioritize logic coverage for session transitions, duration updates, and notification action handling.

## Commit & Pull Request Guidelines
- Current history is minimal (`Initial Commit`), so keep commit messages short, imperative, and specific.
- Use one clear subject line (ideally <= 72 chars); add a body for rationale when behavior changes.
- PRs should include: change summary, test notes, linked issue (if any), and screenshots/video for UI updates.
