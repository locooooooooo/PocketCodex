# 发布前隐私整改文档（当前 P1）

本文只记录当前仍需要关注的隐私整改事项。已完成的 P0 细节不再展开，避免文档继续堆积已经关闭的整改内容。

## 发布边界

- `.codex/` 不属于仓库发布内容：不删除、不修改、不 stage、不提交。
- debug bridge 日志只允许本地生成：`.logs/` 和日志文件不能进入 Git。
- 本机路径、设备 ID、服务地址、key、确认 token 只能存在于本地配置、内存态或 ignored runtime 文件中。
- Git 仓库必须告诉用户如何配置自己的本地值：见 `docs/local-agent-configuration-zh.md`、`docs/rustdesk-selfhosted-status-zh.md` 和 `infra/rustdesk-server-oss/.env.example`。

## 已关闭项

以下项已完成代码或文档整改，只保留发布前门禁复查：

| 项 | 当前状态 |
| --- | --- |
| P0 debug bridge 日志目录不进入 Git | 已关闭，`.gitignore` 覆盖 `.logs/`。 |
| P0 自建服务文档模板化 | 已关闭，真实部署值改为占位符和 `.env.example`。 |
| P0 构建/安装脚本本机路径外置 | 已关闭，改为参数、环境变量或 repo-relative。 |
| P0 自建服务 HostIp 写死 | 已关闭，改为 `-HostIp` 或 `RUSTDESK_HOST_IP`。 |
| P1 debug bridge `/health` 和启动日志路径暴露 | 已整改，`/health` 不返回完整 `CODEX_HOME`，启动日志使用占位符。 |
| P1 Agent Dashboard 普通消息包含确认 token | 已整改，token 不再拼进普通聊天消息文本。 |
| P1 Agent Bridge session/task 默认输出 raw event 和本机路径 | 已整改，公开响应走 allowlist/redaction，raw event 默认不透传。 |

## 当前 P1 残余项

### P1-1 优化类文档复查

状态：待复查。

涉及文件：
- `docs/agent-dashboard-optimization-baseline-zh.md`
- `docs/agent-dashboard-optimization-audit-zh.md`

整改标准：
- 不写具体 home 目录、本机 session 路径或真实调试证据。
- 只描述“本地调试模式读取用户配置的 Codex data directory”。
- 如果保留 `rawEvents`、`task_snapshot`、`session_detail` 等术语，必须是架构术语，不得包含真实事件 payload。

### P1-2 token/password/key 关键词命中分类

状态：待发布前人工分类。

允许保留：
- UI 文案、字段名、类型定义。
- 空测试值、假测试值、占位符。
- 上游公开示例，且确认不是当前部署真实值。

必须整改：
- 真实 key、真实 token、真实 cookie、真实私钥。
- 带本机路径、设备 ID、局域网地址的运行日志或历史会话内容。
- 普通 UI 文本、timeline、raw event 或持久化 message body 中的确认 token。

### P1-3 确认按钮结构化 token 通道

状态：后续增强。

当前已完成“token 不进普通消息文本”。后续如果要在 Agent Dashboard 内提供确认/取消按钮，必须通过结构化状态字段或运行时 API 读取 token，不能再从聊天文本里解析 `Token:`。

## 当前已完成的 P1 代码整改

### debug bridge

涉及文件：
- `tools/agent_dashboard_harness/debug-bridge/server.mjs`

已完成：
- `/health` 改为 `codexHomeConfigured`、`codexHomeSource`、`upstreamConfigured`，不返回完整本机目录。
- 启动日志使用 `<configured-codex-home>`、`<configured-upstream>`。
- session list/detail、fallback project 和 raw event 输出使用占位路径或 redaction。
- session message 文本中的 token 和本机 Windows 路径会脱敏。

### Agent Dashboard

涉及文件：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

已完成：
- `_agentEventText()` 不再接收或拼接 token。
- structured `needs_confirmation` event 的 token 不进入普通聊天消息文本。
- 新增 focused test 覆盖确认 token 不进入 chat message。

### Agent Bridge

涉及文件：
- `src/agent_bridge.rs`

已完成：
- `/agent/config` 对外返回占位项目路径，不返回真实配置路径。
- `/agent/sessions`、`/agent/sessions/:id`、`/agent/sessions/:id/page` 对外返回公开 session view。
- task snapshot 对外使用公开 task view，不序列化 token 和 raw_events。
- session detail 默认清空 raw_events，timeline raw 字段置空。
- message、timeline summary、detail_json 中的 token 和 Windows 本机路径会脱敏。
- 新增 focused Rust tests 覆盖 session detail 和 task snapshot 的公开输出边界。

## 发布前门禁

提交或打包前必须运行：

```powershell
git status --short --untracked-files=all
git ls-files .codex
git ls-files | rg "(\.log$|\.err\.log$|\.out\.log$|/\.logs/)"
```

检查已知本机私有值：

```powershell
rg -n --hidden -S "<PRIVATE_HOME_PATH>|<PRIVATE_WORKSPACE_PATH>|<PRIVATE_DEVICE_ID>|<PRIVATE_ACCOUNT_ID>|<PRIVATE_TOKEN_FRAGMENT>" `
  -g "!**/.git/**" `
  -g "!**/target/**" `
  -g "!**/build/**" `
  -g "!**/.dart_tool/**" `
  -g "!**/node_modules/**" `
  -g "!docs/pre-release-privacy-remediation-zh.md"
```

检查 token、密钥和认证关键词：

```powershell
rg -n --hidden -S "(?i)(api[_-]?key|secret|password|passwd|token|bearer|authorization|client[_-]?secret|private[_-]?key|access[_-]?key|cookie|BEGIN (RSA |OPENSSH |EC |)PRIVATE KEY)" `
  -g "!**/.git/**" `
  -g "!**/target/**" `
  -g "!**/build/**" `
  -g "!**/.dart_tool/**" `
  -g "!**/node_modules/**" `
  -g "!**/vendor/**" `
  -g "!docs/pre-release-privacy-remediation-zh.md"
```

通过标准：
- `.codex/` 没有进入 Git。
- debug bridge `.logs/`、debug log、runtime data 没有进入 Git。
- 公开仓库不包含当前开发机路径、当前局域网部署值、真实 key、真实设备 ID、真实确认 token。
- 关键词扫描残余命中均已归类为字段名、UI 文案、占位符、空测试值、假测试值或上游公开示例。

## 本轮验证记录

已通过：

```powershell
node --check tools/agent_dashboard_harness/debug-bridge/server.mjs
git diff --check -- src/agent_bridge.rs flutter/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart flutter/test/agent_dashboard_model_test.dart tools/agent_dashboard_harness/debug-bridge/server.mjs
cd flutter; flutter test test/agent_dashboard_model_test.dart --plain-name "structured confirmation token stays out of chat message text"
cargo test -q public_session_detail_redacts_paths_tokens_and_raw_events --lib -- --test-threads=1
cargo test -q task_snapshot_detail_uses_public_task_view --lib -- --test-threads=1
```

说明：
- Rust 测试仍会输出项目既有 warning，本轮未处理。
- 本文档只保留当前 P1 进度和门禁，不再展开已完成 P0 的整改过程。
