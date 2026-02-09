# Issues To Fix

Fragility and reliability issues identified across device form factors and iOS configurations. Work through these top-down — P0 items first.

---

## P2 — Edge cases that reduce reliability

### 1. Unstructured Tasks may leak if view identity changes

**File:** `ContentView.swift:24, 28`

**Problem:** `sessionCueResetTask` and `cycleCompletionCelebrationTask` are `@State Task` objects cancelled only in `onDisappear`. If SwiftUI recreates the view due to an identity change in a parent (without calling `onDisappear` on the old instance), the running Tasks are dropped without cancellation. In practice this is unlikely in this app's simple hierarchy, but it is a latent fragility.

**Recommended fix:** Use `.task(id:)` modifier instead of manually managing Task lifecycle, or wrap the cancellation in the Task's own `onCancel` handler. Alternatively, accept the risk given the app's flat view hierarchy and leave a code comment noting the assumption.

**Verification:** Low-priority — only relevant if the view hierarchy becomes more complex.

- [ ] Fixed

---

### 2. Timer callback creates unstructured Task on every tick

**File:** `PomodoroViewModel.swift:155-158`

**Problem:** Each Timer fire creates `Task { @MainActor in self?.tick() }`. These Tasks are untracked. Under extreme main-thread pressure, multiple tick Tasks could queue and execute, though the Date-based sync makes this functionally harmless. It is still unnecessary overhead.

**Recommended fix:** Since the ViewModel is already `@MainActor`, consider using `Timer.publish` with a Combine pipeline or an `AsyncStream`-based timer that naturally runs on the MainActor without spawning new Tasks each second.

**Verification:** Optional — profile with Instruments to confirm no Task accumulation under normal use.

- [ ] Fixed

---

### 3. Notification permission denial is silently ignored

**File:** `SessionFeedbackManager.swift:37`

**Problem:** `requestAuthorization` completion handler is `{ _, _ in }`. If the user denies notification permission, the app silently fails to schedule session-end notifications when backgrounded. There is no UI to inform the user or guide them to Settings to re-enable.

**Recommended fix:** Track authorisation status. When the user backgrounds the app with a running timer and notifications are denied, show a subtle banner or alert explaining that session-end notifications require permission, with a button that opens the app's Settings page:
```swift
UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
```

**Verification:** Deny notification permission in Settings, background the app with a running timer, and confirm the user sees guidance.

- [ ] Fixed

---

### 4. No iPad keyboard shortcut support

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

### 5. `ringColors[0]` force-indexed without guard

**File:** `ContentView.swift:700`

**Problem:** `session.ringColors[0]` is safe today (all cases return 2-element arrays) but is a latent crash if `ringColors` is ever modified to return an empty array.

**Recommended fix:** Use `session.ringColors.first ?? .accentColor` for defensive access.

- [ ] Fixed

---

### 6. Ring animation re-enable timing is fragile

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

### 7. Unnecessary iOS 15 availability check

**File:** `SessionFeedbackManager.swift:52-55`

**Problem:** The `if #available(iOS 15.0, *)` check around `interruptionLevel` and `relevanceScore` is dead code since the deployment target is iOS 26. It is harmless but misleading.

**Recommended fix:** Remove the availability check and set the properties unconditionally.

- [ ] Fixed
