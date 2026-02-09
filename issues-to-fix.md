# Issues To Fix

Fragility and reliability issues identified across device form factors and iOS configurations. Work through these top-down — P0 items first.

---

## P3 — Minor hardening

### 1. Unnecessary iOS 15 availability check

**File:** `SessionFeedbackManager.swift:52-55`

**Problem:** The `if #available(iOS 15.0, *)` check around `interruptionLevel` and `relevanceScore` is dead code since the deployment target is iOS 26. It is harmless but misleading.

**Recommended fix:** Remove the availability check and set the properties unconditionally.

- [ ] Fixed
