# Agent Dashboard Harness

This is an external Flutter app for fast Agent Dashboard UI debugging.

It intentionally uses the package name `flutter_hbb` and tiny export wrappers in
`lib/` so the dashboard files under `../../flutter/lib/` remain the single source
of truth. Do not copy dashboard widgets into this harness.

Run from this directory:

```powershell
flutter pub get
.\run-web.ps1 -Mode floating
.\run-web.ps1 -Mode full
.\run-web-live.ps1 -Mode floating
.\run-web-live.ps1 -Mode full
```

Use Chrome device emulation for quick portrait/landscape checks. Use the real
RustDesk app only after the UI is already validated here.

`run-web.ps1` stays in pure mock mode for UI-only work.

`run-web-live.ps1` starts a separate local debug bridge on `127.0.0.1:17331`
that reads Codex sessions from the configured local Codex data directory and proxies
run/task/skills calls to the currently running RustDesk bridge on
`127.0.0.1:17321`. This is the fast path for validating session sync and
conversation continuity in Web before touching mobile packaging.

Edit the real dashboard files, not this harness:

- `../../flutter/lib/common/widgets/agent_dashboard_page.dart`
- `../../flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`
- `../../flutter/lib/models/agent_dashboard_model.dart`
