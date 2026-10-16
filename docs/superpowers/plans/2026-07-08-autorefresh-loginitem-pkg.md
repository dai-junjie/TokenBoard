# Labforge Menu Bar Auto Refresh And Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5-minute background refresh, register the app to launch at login, and produce an installable `.pkg` artifact.

**Architecture:** Keep the existing SwiftPM app structure. Add a small app-level refresh scheduler that runs independently of the popup, a tiny login-item registration service that enables launch-at-login when the packaged app first runs, and packaging scripts that assemble the `.app` bundle then wrap it into a `.pkg`.

**Tech Stack:** SwiftUI, AppKit, ServiceManagement, SwiftPM, `pkgbuild`

---

### Task 1: Add an app-level refresh scheduler

**Files:**
- Create: `Sources/LabforgeMenuBarApp/AutoRefreshScheduler.swift`
- Modify: `Sources/LabforgeMenuBarApp/AppViewModel.swift`
- Modify: `Sources/LabforgeMenuBarApp/LabforgeMenuBarApp.swift`
- Test: `Tests/LabforgeMenuBarAppTests/AutoRefreshSchedulerTests.swift`

- [ ] Write a failing scheduler test for repeated execution and stop behavior.
- [ ] Run the test and confirm it fails because the scheduler type does not exist yet.
- [ ] Implement the minimal scheduler and wire it into `AppViewModel.start()`.
- [ ] Run the scheduler test again and confirm it passes.

### Task 2: Enable launch at login for packaged app runs

**Files:**
- Create: `Sources/LabforgeMenuBarApp/LoginItemService.swift`
- Modify: `Sources/LabforgeMenuBarApp/AppViewModel.swift`

- [ ] Add a tiny login-item service around `SMAppService.mainApp`.
- [ ] Register at startup only when running from an `.app` bundle.
- [ ] Verify the app still builds in both `swift run` and bundled modes.

### Task 3: Build an installable package artifact

**Files:**
- Create: `scripts/build_app_bundle.sh`
- Create: `scripts/build_pkg.sh`
- Modify: `scripts/build_dmg.sh`

- [ ] Extract app bundle assembly into a reusable script.
- [ ] Add a `.pkg` builder that installs into `/Applications`.
- [ ] Re-run packaging scripts and verify the `.app`, `.dmg`, and `.pkg` artifacts exist.
