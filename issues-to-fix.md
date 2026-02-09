# Issues To Fix

Fragility and reliability issues identified across device form factors and iOS configurations. Work through these top-down — P0 items first.

---

## P3 — Minor hardening

### 1. `ringColors[0]` force-indexed without guard

**File:** `ContentView.swift:700`

**Problem:** `session.ringColors[0]` is safe today (all cases return 2-element arrays) but is a latent crash if `ringColors` is ever modified to return an empty array.

**Recommended fix:** Use `session.ringColors.first ?? .accentColor` for defensive access.

- [ ] Fixed

---

### 2. Ring animation re-enable timing is fragile

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

### 3. Unnecessary iOS 15 availability check

**File:** `SessionFeedbackManager.swift:52-55`

**Problem:** The `if #available(iOS 15.0, *)` check around `interruptionLevel` and `relevanceScore` is dead code since the deployment target is iOS 26. It is harmless but misleading.

**Recommended fix:** Remove the availability check and set the properties unconditionally.

- [ ] Fixed
