<p align="center">
  <img src="docs/assets/pocket-codex-logo.jpg" alt="Pocket-Codex logo" width="140">
</p>

<h1 align="center">Pocket-Codex</h1>

<p align="center">
  Keep Codex running on the desktop, then guide it from a phone when life pulls you away from the keyboard.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="docs/assets/pocket-codex-hero.jpg" alt="Pocket-Codex keeps desktop Codex work available from mobile">
</p>

Pocket-Codex is a mobile-to-desktop agent workflow built on top of RustDesk. It keeps code execution, project files, terminal access, credentials, and Codex CLI on the desktop, while the phone becomes a lightweight control panel for starting work, reviewing progress, and approving sensitive actions.

This repository is a public product fork for that workflow. It is not a general-purpose replacement for upstream RustDesk. Upstream RustDesk remains the remote desktop foundation; Pocket-Codex adds an agent bridge, dashboard, and self-hosted workflow around desktop Codex execution.

## Who It Is For

Pocket-Codex is designed for people who:

- keep a desktop, workstation, or home lab machine online
- already use Codex CLI in real local project workspaces
- want to keep long-running development tasks moving while away from the desk
- prefer phone-based review and approval over phone-based development
- want execution to stay on machines they own or administer

If the goal is only remote desktop, upstream RustDesk is the right starting point. If the goal is letting a trusted desktop continue Codex work while a phone provides direction and approvals, Pocket-Codex is the focused path.

## Product Model

The phone is the control panel. The desktop is the worker.

That means:

- code stays on the desktop
- Codex runs on the desktop
- project allowlists are enforced on the desktop
- write-capable actions can require confirmation
- dashboard state is task-oriented, not just another chat transcript
- desktop Codex session history is the source of truth for session restore

The aim is not to turn a phone into a developer workstation. The aim is to keep the real workstation useful when the user is away from the keyboard.

## Core Workflow

1. Run Pocket-Codex on the desktop.
2. Configure which local projects Codex may access.
3. Connect from the phone through the RustDesk transport.
4. Open Agent Dashboard.
5. Select a project, profile, session, and context.
6. Send a task to the desktop.
7. Watch status, approve write-capable work when needed, and review the result.

## Main Components

### Codex Agent Bridge

Codex Agent Bridge is the desktop-side runtime that connects remote sessions to local Codex CLI execution.

It provides:

- local bridge service on the controlled desktop
- project allowlist checks
- read-only and workspace-write execution modes
- confirmation flow for write-capable work
- run, confirm, cancel, and task-status handling
- desktop Codex session listing, detail restore, and history paging
- task snapshots for dashboard recovery and resume
- incremental bridge events for dashboard sync
- local skill catalog endpoints for dashboard selection
- voice transcribe and voice run paths
- task result return through the remote session

Main code:

- `src/agent_bridge.rs`
- `src/server/connection.rs`
- `libs/hbb_common/protos/message.proto`

### Agent Dashboard

Agent Dashboard is the mobile-facing task workspace for agent runs.

It provides:

- project, profile, and session controls
- conversation-style task spaces
- session restore from desktop Codex history
- task recovery from the same bridge task source used by live debug
- bridge-backed session and task state shared across web debug and mobile runtime
- optional conversation history context
- optional terminal transcript context
- running, confirmation, completed, and failed states
- full-page and floating dashboard development modes

Main code:

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`

## Web-First Development

Dashboard work is intentionally web-first. The dashboard implementation lives under `flutter/lib/`, while a separate harness provides a faster way to validate layout, session restore, task state, and bridge behavior before packaging mobile builds.

Main harness:

- `tools/agent_dashboard_harness/`

Useful commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent_dashboard_harness/run-web.ps1 -Mode floating
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent_dashboard_harness/run-web-live.ps1 -Mode floating
```

`run-web.ps1` is for mock-only UI work. `run-web-live.ps1` starts a local debug bridge on `127.0.0.1:17331`, reads real desktop Codex sessions from `~/.codex`, and proxies task-oriented calls to the local Pocket-Codex bridge on `127.0.0.1:17321`.

The web harness is a debug shell, not a second dashboard implementation. Shared Dart dashboard code should continue to live under `flutter/lib/`, so browser validation and packaged mobile builds exercise the same model and widgets.

## Mobile And Desktop Packaging

Pocket-Codex keeps the public app branding separate from compatibility-sensitive internal identifiers.

Current public branding uses:

- Android app label: `Pocket-Codex`
- Android accessibility service label: `Pocket-Codex Input`
- iOS and macOS display name: `Pocket-Codex`
- Windows product metadata: `Pocket-Codex`
- app icon assets based on the Pocket-Codex visual identity

Some lower-level identifiers intentionally remain compatible with the RustDesk base, including package identifiers, executable names, selected internal class names, driver names, dependency URLs, and the legacy `rustdesk://` deep link scheme. New builds also expose `pocket-codex://` where platform support is available.

## Current Status

Pocket-Codex is an active prototype. It is suitable for development and controlled testing, not yet a polished public release.

Working now:

- desktop bridge runtime
- bridge run / confirm / cancel / task status flow
- RustDesk-session transport for agent requests and results
- dashboard model and dashboard UI shell
- web mock harness and live desktop-session harness
- desktop Codex session listing, detail restore, and history paging
- bridge-backed task snapshots for dashboard recovery
- bridge incremental event sync through the dashboard path
- Android and Windows debug packaging with Pocket-Codex branding
- helper scripts for bridge checks, dashboard development, Windows build, Android build, and self-hosted setup

Still being finalized:

- stronger request-id ownership across every result and restore path
- durable task state after bridge restart
- reduced duplicate push/poll status paths
- performance improvements for long session history restore
- voice input and STT polish
- public onboarding
- release-grade packaging

## Repository Guide

Start here for Pocket-Codex product work:

- `src/agent_bridge.rs`
- `src/server/connection.rs`
- `libs/hbb_common/protos/message.proto`
- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/`
- `tools/restart-rustdesk-from-source.ps1`
- `agent/codex-bridge/scripts/`

Current docs:

- [Project introduction (ZH)](docs/project-introduction-zh.md)
- [Technical status (ZH)](docs/voice-codex-agent-tech-status-zh.md)
- [Dashboard status (ZH)](docs/voice-codex-agent-dashboard-status-zh.md)
- [Dashboard dev flow (ZH)](docs/agent-dashboard-dev-flow-zh.md)
- [Task status bubble implementation status (ZH)](docs/agent-dashboard-task-status-bubble-tech-plan-zh.md)
- [Local agent configuration (ZH)](docs/local-agent-configuration-zh.md)
- [Self-hosted server configuration (ZH)](docs/rustdesk-selfhosted-status-zh.md)

Historical and audit archives:

- [Dashboard optimization baseline (ZH)](docs/agent-dashboard-optimization-baseline-zh.md)
- [Dashboard optimization audit (ZH)](docs/agent-dashboard-optimization-audit-zh.md)

## Development Rules For Dashboard Work

Keep one authority boundary:

- the desktop bridge owns Codex session history, session paging, and task snapshots
- dashboard-local persistence owns UI metadata such as drafts, pins, archive state, selected profile, and temporary view state
- future sync work should extend bridge-fed session/task data or bridge incremental events before adding another transcript store

Use this local loop:

1. Iterate UI in mock mode with `run-web.ps1`.
2. Validate real sessions and task state with `run-web-live.ps1`.
3. Rebuild mobile only after shared Dart changes are validated.
4. Refresh the installed desktop runtime after Rust-side bridge changes.
5. Record optimization evidence in the baseline/audit docs instead of turning the README into a change log.

## Trust And Safety

Pocket-Codex is intended for machines the user owns or is authorized to administer.

The current design keeps sensitive execution on the desktop:

- project paths are configured locally
- Codex credentials remain on the desktop
- write-capable execution can require confirmation
- bridge execution is scoped to configured projects

Remote access software can be misused. Do not use Pocket-Codex for unauthorized access, surveillance, or control of systems you do not own or administer.

## Relationship To Upstream

This repository is based on [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk).

RustDesk remains the upstream source for the remote desktop foundation. Pocket-Codex builds a separate mobile-to-desktop Codex workflow on top of that foundation.

For upstream RustDesk:

- [Upstream repository](https://github.com/rustdesk/rustdesk)
- [Official build docs](https://rustdesk.com/docs/en/dev/build/)
- [RustDesk server](https://rustdesk.com/server)

## Contributing

The most useful contributions make the mobile-to-desktop agent workflow easier to run, safer to trust, or clearer to understand.

Good first areas:

- bridge protocol cleanup
- dashboard task flow cleanup
- mobile UX for long-running agent work
- setup automation
- self-hosted deployment docs
- tests around routing, confirmation, cancellation, session restore, and result ownership

Avoid broad upstream RustDesk refactors unless they directly serve the Pocket-Codex workflow. This fork should stay focused on the phone-controlled desktop agent path.
