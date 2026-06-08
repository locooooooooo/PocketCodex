# RustDesk Voice Codex Agent 技术状态

更新时间：2026-06-08

## 当前结论

文字 agent 主链路已经从“聊天字符串转发”升级到“结构化 Agent Dashboard + RustDesk session + Rust bridge + Codex CLI”。

当前主路径是：

```text
Flutter Agent Dashboard
-> sessionSendAgentCommand
-> src/flutter_ffi.rs::session_send_agent_command
-> src/ui_session_interface.rs::send_agent_command
-> src/server/connection.rs::handle_agent_command / spawn_agent_run
-> src/agent_bridge.rs::send_run_request
-> desktop Codex CLI
-> AgentResult
-> Flutter AgentDashboardModel.handleAgentResultEvent()
```

该链路已经承载：

- project 路由
- thread / session 续接
- skill 选择
- history / terminal context 注入
- 结构化 `AgentCommand`
- 结构化 `AgentResult`
- `request_id -> conversation` 归属
- task snapshot 恢复
- Codex session 列表、详情和分页恢复

旧的 `/agent ...` 聊天文本路径仍可作为兼容入口和调试 fallback，但不再是 Dashboard 的主要设计方向。

## 已完成能力

### 1. 桌面端 Rust bridge

已落地在 [`src/agent_bridge.rs`](../src/agent_bridge.rs)。

配置项：

- `codex-bridge-enabled`
- `codex-bridge-port`
- `codex-bridge-command`
- `codex-bridge-require-confirmation`
- `codex-bridge-projects`
- `codex-bridge-whisper-command`
- `codex-bridge-whisper-model`

HTTP 能力：

- `POST /agent/run`
- `POST /agent/confirm`
- `POST /agent/cancel`
- `GET /agent/tasks/:request_id`
- `GET /agent/sessions`
- `GET /agent/sessions/:id`
- `GET /agent/sessions/:id/page`
- `GET /agent/skills`
- `POST /agent/skills`
- `DELETE /agent/skills/:id`
- `POST /agent/skills/sync`
- `POST /agent/voice/transcribe`
- `POST /agent/voice/run`

发布边界：

- 对外 task/session view 使用 allowlist 和 redaction
- 默认不返回本机绝对路径
- 默认不透传 raw event
- token 不进入普通 chat message 文本

### 2. RustDesk session 结构化事件

已落地在：

- [`src/ui_session_interface.rs`](../src/ui_session_interface.rs)
- [`src/flutter_ffi.rs`](../src/flutter_ffi.rs)
- [`src/server/connection.rs`](../src/server/connection.rs)
- [`src/client/io_loop.rs`](../src/client/io_loop.rs)
- [`src/flutter.rs`](../src/flutter.rs)

当前行为：

- Flutter 通过 `sessionSendAgentCommand()` 发送 `AgentCommand`
- 被控端通过 bridge 执行 Codex
- 结果以 `AgentResult` 回到控制端
- `detail_json` 携带 task snapshot / conversation detail 等结构化数据
- Flutter 侧做 structured result dedupe 和 transport failure recovery
- `AgentCancel` 已有正式结构化通道

### 3. Flutter Dashboard

已落地在：

- [`flutter/lib/models/agent_dashboard_model.dart`](../flutter/lib/models/agent_dashboard_model.dart)
- [`flutter/lib/models/agent_dashboard_runtime_io.dart`](../flutter/lib/models/agent_dashboard_runtime_io.dart)
- [`flutter/lib/models/agent_dashboard_runtime_web.dart`](../flutter/lib/models/agent_dashboard_runtime_web.dart)
- [`flutter/lib/common/widgets/agent_dashboard_page.dart`](../flutter/lib/common/widgets/agent_dashboard_page.dart)
- [`flutter/lib/common/widgets/agent_task_status_bubble_overlay.dart`](../flutter/lib/common/widgets/agent_task_status_bubble_overlay.dart)

当前能力：

- conversation 列表和状态跟踪
- `project / threadMode / sessionRef / profile / selectedSkillIds`
- `Timeline / Sessions / Context / Skills`
- Codex session 恢复
- `request_id -> conversation` 路由
- task snapshot 恢复
- task status bubble 通知
- mock / live dev shell 预览
- Android 远控页浮动 Dashboard 入口

### 4. 自建 RustDesk server

相关文档和脚本：

- [`docs/rustdesk-selfhosted-status-zh.md`](rustdesk-selfhosted-status-zh.md)
- [`agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1`](../agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1)
- [`agent/codex-bridge/scripts/open-rustdesk-selfhosted-firewall.ps1`](../agent/codex-bridge/scripts/open-rustdesk-selfhosted-firewall.ps1)
- [`infra/rustdesk-server-oss/.env.example`](../infra/rustdesk-server-oss/.env.example)

真实 Host IP、server key 和运行 `.env` 都是本地配置，不进入公开仓库。

## 仍未闭环的关键问题

### 1. 移动端语音仍未落地

语音功能还缺少完整闭环，不是单点 bug。

缺口：

- 手机端录音按钮、录音中状态、停止录音和音频编码尚未成为可用 UI 流
- 手机端不能直接访问被控桌面的 `127.0.0.1`
- 语音 envelope 需要通过现有 RustDesk session 发送到被控端
- 桌面端需要配置 `whisper.cpp` 命令和模型
- 转写结果需要继续进入同一个 `AgentResult` / conversation / session 路径

语音 v1 的最小路线应是：

```text
Android recording
-> voice_run envelope
-> sessionSendAgentCommand
-> desktop bridge
-> whisper.cpp
-> AgentResult
-> current conversation
```

### 2. Codex session 权威源仍需继续收敛

当前 Dashboard 已经能读取桌面 Codex session，并把 session 恢复到 conversation。Flutter 本地仍保留 UI 元数据，例如草稿、pin、archive、selected profile 和临时视图状态。

后续目标：

- 桌面 bridge 继续作为 Codex session history、session paging、task snapshot 的权威源
- Flutter 本地只保留 UI 元数据
- 不再新增第二套 transcript 存储

### 3. 兼容入口仍需清理边界

当前正式 Dashboard 主链路已经是结构化 `AgentCommand` / `AgentResult`。仍保留的兼容入口主要用于旧 UI、调试和 fallback：

- `/agent`
- `/agent-confirm`
- `/agent-cancel`

后续应继续减少正式用户流对聊天文本命令的依赖，但不要破坏旧入口和调试能力。

## 当前不应走的路线

1. 不应让手机直接请求被控桌面 bridge 的 `127.0.0.1`。
2. 不应把语音结果再包装成普通聊天字符串解析。
3. 不应在桌面 STT 未配置前，只做表面录音按钮。
4. 不应把确认 token 写进普通聊天消息或持久化 transcript。

## 发布前验证记录

最近一次隐私整改验证已覆盖：

```powershell
node --check tools/agent_dashboard_harness/debug-bridge/server.mjs
cd flutter; flutter test test/agent_dashboard_model_test.dart --plain-name "structured confirmation token stays out of chat message text"
cargo test -q public_session_detail_redacts_paths_tokens_and_raw_events --lib -- --test-threads=1
cargo test -q task_snapshot_detail_uses_public_task_view --lib -- --test-threads=1
```

说明：Rust 测试仍可能输出项目既有 warning，本轮不处理 warning。
