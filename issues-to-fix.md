# Issues To Fix

Fragility and reliability issues identified across device form factors and iOS configurations. Work through these top-down — P0 items first.

---

## P2 — Edge cases that reduce reliability

### 1. Notification permission denial is silently ignored

**File:** `SessionFeedbackManager.swift:37`

**Problem:** `requestAuthorization` completion handler is `{ _, _ in }`. If the user denies notification permission, the app silently fails to schedule session-end notifications when backgrounded. There is no UI to inform the user or guide them to Settings to re-enable.

**Recommended fix:** Track authorisation status. When the user backgrounds the app with a running timer and notifications are denied, show a subtle banner or alert explaining that session-end notifications require permission, with a button that opens the app's Settings page:
```swift
UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
```

**Verification:** Deny notification permission in Settings, background the app with a running timer, and confirm the user sees guidance.

- [ ] Fixed

---

### 2. No iPad keyboard shortcut support

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

### 3. `ringColors[0]` force-indexed without guard

**File:** `ContentView.swift:700`

**Problem:** `session.ringColors[0]` is safe today (all cases return 2-element arrays) but is a latent crash if `ringColors` is ever modified to return an empty array.

**Recommended fix:** Use `session.ringColors.first ?? .accentColor` for defensive access.

- [ ] Fixed

---

### 4. Ring animation re-enable timing is fragile

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

### 5. Unnecessary iOS 15 availability check

**File:** `SessionFeedbackManager.swift:52-55`

**Problem:** The `if #available(iOS 15.0, *)` check around `interruptionLevel` and `relevanceScore` is dead code since the deployment target is iOS 26. It is harmless but misleading.

**Recommended fix:** Remove the availability check and set the properties unconditionally.

- [ ] Fixed
