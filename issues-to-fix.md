# Issues To Fix

Fragility and reliability issues identified across device form factors and iOS configurations. Work through these top-down — P0 items first.

---

## P1 — Likely to cause problems on real-world devices

### 1. Timer ring and text look disproportionately small on iPad

**File:** `ContentView.swift:66`

**Problem:** Portrait mode uses a fixed 280pt ring. On an iPad Pro 12.9" (1024pt wide, 1366pt tall), the ring fills ~27% of the width. The 56pt time label is similarly tiny relative to the screen. The app technically works but looks like a scaled-up iPhone app rather than a native iPad experience.

**Recommended fix:** Scale the ring diameter based on available geometry for both portrait and landscape:
```swift
let portraitRingDiameter = min(480, min(geometry.size.width, geometry.size.height) * 0.55)
```
Also scale the font sizes proportionally, or set device-class-appropriate base sizes using `horizontalSizeClass`.

**Verification:** Run on iPad Pro 12.9" and iPad mini simulators in both orientations. The ring should look proportional on both.

- [ ] Fixed

---

### 2. Concurrency safety / Swift 6 readiness

**File:** `SessionFeedbackManager.swift`

**Problem:** `SessionFeedbackManager` is a non-isolated `NSObject` with `@Published` properties. `pendingNotificationAction` is mutated from `DispatchQueue.main.async` (line 199) in the notification delegate callback and read from `@MainActor` context in `ContentView`. This works under Swift 5 concurrency but will produce data race warnings/errors under Swift 6 strict concurrency checking. The `consumePendingNotificationAction()` method is also not protected against concurrent access.

**Recommended fix:** Mark `SessionFeedbackManager` as `@MainActor`. Change the `nonisolated` delegate methods to dispatch via `MainActor.run {}` instead of `DispatchQueue.main.async`:
```swift
nonisolated func userNotificationCenter(...) {
    Task { @MainActor in
        self.pendingNotificationAction = action
    }
    completionHandler()
}
```
Audit for any other non-main-actor access paths.

**Verification:** Enable strict concurrency checking in build settings (`SWIFT_STRICT_CONCURRENCY = complete`) and confirm no warnings.

- [ ] Fixed

---

### 3. Celebration overlay burst radius is not device-relative

**File:** `ContentView.swift:712`

**Problem:** `CycleCompletionCelebrationOverlay` uses a hardcoded burst radius of 150pt. On a 280pt ring, particles fly well outside the ring boundary and may be clipped by the frame. On iPad with a proportionally larger ring (if issue #6 is fixed), 150pt would look undersized.

**Recommended fix:** Pass the ring diameter into the overlay and compute the burst radius as a proportion:
```swift
let radius: CGFloat = isBursting ? diameter * 0.55 : 16
```

**Verification:** Trigger a cycle completion on both iPhone SE and iPad Pro and confirm particles stay within visible bounds.

- [ ] Fixed

---

## P2 — Edge cases that reduce reliability

### 4. Race between foreground sync and notification action handling

**File:** `ContentView.swift:154-169`

**Problem:** When the app returns to foreground, `syncAfterForeground()` calls `tick()` which may detect session completion (remainingSeconds == 0), increment `sessionCompletionCount`, and trigger sound/haptic feedback via the `onChange` handler. Then `handlePendingNotificationActionIfNeeded()` immediately starts a new session from the notification action. The completion feedback (sound, haptic, visual cue) is effectively lost because the new session starts instantly.

**Recommended fix:** Check whether a notification action is pending *before* running `syncAfterForeground()`. If an action is pending, let the action handler drive the state transition instead of the tick:
```swift
if newValue == .active {
    animateRing = false
    feedbackManager.cancelScheduledSessionEndNotification()
    if feedbackManager.pendingNotificationAction != nil {
        handlePendingNotificationActionIfNeeded()
    } else {
        viewModel.syncAfterForeground()
    }
    DispatchQueue.main.async { animateRing = true }
}
```

**Verification:** Background the app during a running session, wait for it to complete, tap a notification action, and confirm the correct session starts without double-feedback.

- [ ] Fixed

---

### 5. Unstructured Tasks may leak if view identity changes

**File:** `ContentView.swift:24, 28`

**Problem:** `sessionCueResetTask` and `cycleCompletionCelebrationTask` are `@State Task` objects cancelled only in `onDisappear`. If SwiftUI recreates the view due to an identity change in a parent (without calling `onDisappear` on the old instance), the running Tasks are dropped without cancellation. In practice this is unlikely in this app's simple hierarchy, but it is a latent fragility.

**Recommended fix:** Use `.task(id:)` modifier instead of manually managing Task lifecycle, or wrap the cancellation in the Task's own `onCancel` handler. Alternatively, accept the risk given the app's flat view hierarchy and leave a code comment noting the assumption.

**Verification:** Low-priority — only relevant if the view hierarchy becomes more complex.

- [ ] Fixed

---

### 6. Timer callback creates unstructured Task on every tick

**File:** `PomodoroViewModel.swift:155-158`

**Problem:** Each Timer fire creates `Task { @MainActor in self?.tick() }`. These Tasks are untracked. Under extreme main-thread pressure, multiple tick Tasks could queue and execute, though the Date-based sync makes this functionally harmless. It is still unnecessary overhead.

**Recommended fix:** Since the ViewModel is already `@MainActor`, consider using `Timer.publish` with a Combine pipeline or an `AsyncStream`-based timer that naturally runs on the MainActor without spawning new Tasks each second.

**Verification:** Optional — profile with Instruments to confirm no Task accumulation under normal use.

- [ ] Fixed

---

### 7. Notification permission denial is silently ignored

**File:** `SessionFeedbackManager.swift:37`

**Problem:** `requestAuthorization` completion handler is `{ _, _ in }`. If the user denies notification permission, the app silently fails to schedule session-end notifications when backgrounded. There is no UI to inform the user or guide them to Settings to re-enable.

**Recommended fix:** Track authorisation status. When the user backgrounds the app with a running timer and notifications are denied, show a subtle banner or alert explaining that session-end notifications require permission, with a button that opens the app's Settings page:
```swift
UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
```

**Verification:** Deny notification permission in Settings, background the app with a running timer, and confirm the user sees guidance.

- [ ] Fixed

---

### 8. No iPad keyboard shortcut support

**File:** `ContentView.swift`

**Problem:** The app targets iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) but provides no keyboard shortcuts. iPad users with external keyboards expect at minimum Space to start/pause. This is a polish gap.

**Recommended fix:** Add `.keyboardShortcut` modifiers to the primary actions:
```swift
Button("Start Session") { viewModel.start() }
    .keyboardShortcut(.space, modifiers: [])
```
Consider adding `R` for reset, `S` for skip, and `,` for preferences (standard macOS convention).

**Verification:** Connect a hardware keyboard to an iPad simulator and test shortcuts.

- [ ] Fixed

---

## P3 — Minor hardening

### 9. `ringColors[0]` force-indexed without guard

**File:** `ContentView.swift:700`

**Problem:** `session.ringColors[0]` is safe today (all cases return 2-element arrays) but is a latent crash if `ringColors` is ever modified to return an empty array.

**Recommended fix:** Use `session.ringColors.first ?? .accentColor` for defensive access.

- [ ] Fixed

---

### 10. Ring animation re-enable timing is fragile

**File:** `ContentView.swift:160-162`

**Problem:** `animateRing` is set to `false`, state is synced, then `DispatchQueue.main.async { animateRing = true }` re-enables animation on the next run loop pass. This relies on SwiftUI processing the `false` state before the `true` arrives — undocumented timing behaviour that could fail under main-thread congestion.

**Recommended fix:** Use a brief `Task.sleep` or `.transaction` modifier to explicitly suppress animation during the sync rather than toggling a boolean across run loop iterations:
```swift
var transaction = Transaction()
transaction.disablesAnimations = true
withTransaction(transaction) {
    viewModel.syncAfterForeground()
}
```

- [ ] Fixed

---

### 11. Unnecessary iOS 15 availability check

**File:** `SessionFeedbackManager.swift:52-55`

**Problem:** The `if #available(iOS 15.0, *)` check around `interruptionLevel` and `relevanceScore` is dead code since the deployment target is iOS 26. It is harmless but misleading.

**Recommended fix:** Remove the availability check and set the properties unconditionally.

- [ ] Fixed
