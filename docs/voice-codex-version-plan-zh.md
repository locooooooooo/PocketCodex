# 语音 Codex 版 RustDesk 版本管理与执行计划

## 仓库策略

当前本地仓库以用户 fork 作为主远端：

- `origin`: `https://github.com/locooooooooo/rustdesk.git`
- `upstream`: `https://github.com/rustdesk/rustdesk.git`

后续规则：

- 所有自定义开发进入 `origin`，不要直接在官方 `upstream` 上做业务改造。
- 定期从 `upstream/master` 合并或 rebase，保持远控安全补丁和平台兼容更新。
- 每个阶段使用独立 feature 分支，阶段完成后合并到 `main` 或 `master`。
- 自定义功能统一挂 `voice-agent`、`codex-bridge`、`agent-command` 前缀，避免和 RustDesk 原有命名混淆。

推荐分支：

```text
master
  upstream-sync/YYYYMMDD
  feature/voice-agent-phase0-chat-bridge
  feature/codex-bridge-local
  feature/agent-command-protocol
  feature/mobile-voice-agent-ui
```

## 版本节奏

### v0.1：文字指令闭环

目标：先不用语音，证明手机 RustDesk 能把一句 agent 指令送到 PC/Mac 的 Codex，再把结果回到手机。

范围：

- 新增桌面端本机 `codex-bridge`。
- RustDesk 被控端识别聊天前缀 `/agent`。
- bridge 调用 `codex exec`。
- 执行结果以普通聊天消息回传。

默认安全策略：

- 只允许项目白名单路径。
- 默认 `--sandbox read-only`。
- 修改文件必须二次确认，不在 v0.1 自动执行。

验收：

- 手机连接 Windows/Mac RustDesk 后发送 `/agent project=<PROJECT_ID> status`。
- 桌面 bridge 收到请求并写审计日志。
- Codex 在指定目录执行只读分析。
- 手机收到最终结果或明确错误。

### v0.2：本机 bridge 服务化

目标：把临时脚本变成稳定本机服务。

范围：

- bridge 支持 `POST /agent/run`、`GET /agent/tasks/{id}`、`POST /agent/cancel`。
- 支持 Windows 和 macOS。
- 支持任务 ID、状态流、超时、取消。
- 支持配置文件：

```json
{
  "projects": [
    { "id": "rustdesk", "path": "E:\\rustDesk", "defaultMode": "read-only" }
  ],
  "codex": {
    "command": "codex",
    "defaultSandbox": "read-only"
  }
}
```

验收：

- RustDesk 重启后 bridge 仍可被自动发现。
- bridge 不监听局域网地址，只监听 `127.0.0.1` 或本机 IPC。
- 任务失败时手机端能看到失败原因，不只显示超时。

### v0.3：正式 AgentCommand 协议

目标：不再长期复用聊天协议，把 agent 指令作为正式远控能力。

范围：

- 在 `libs/hbb_common/protos/message.proto` 增加 `AgentCommand`、`AgentCancel` 和 `AgentResult`。
- 在 Rust 层添加发送、接收、回传逻辑。
- 在 Flutter bridge 暴露 `sessionSendAgentCommand` 和 `sessionSendAgentCancel`。
- 控制端先把 `AgentResult` 转成可见消息，后续再升级为 `AgentModel` 任务列表。

验收：

- 普通聊天和 agent 任务互不影响。
- 每条 agent 请求都有 `request_id`。
- 手机能展示 `started/running/needs_confirmation/done/failed/cancelled`。
- 旧客户端连接新客户端时不崩溃。

当前落地状态：

- 已完成 proto 定义和 Rust 路由入口。
- 已保留 `/agent` 聊天命令作为旧客户端兼容路径。
- 正式 `AgentCommand` 路径已能走 bridge 并回传 `AgentResult`。
- `cargo check --locked --lib --features flutter --offline` 已通过。
- Dart 正式绑定已通过 `flutter_rust_bridge_codegen 1.80.1` 生成。
- Flutter `AgentModel`、Windows Flutter Release 和真机双端验收仍未完成。

### v0.4：手机端语音入口

目标：把文字输入升级为语音优先。

当前准备状态：

- Windows Rust 库级 check 和 release library 构建已通过。
- Flutter/Dart SDK 通过本机 `FLUTTER_BIN` 或 PATH 配置，FRB Rust/Dart/header 绑定已正式生成。
- 当前剩余桌面端打包缺口是 Windows symlink 权限：需要开启 Developer Mode 或使用管理员终端完成 Flutter Windows Release。
- Android SDK 尚未安装；只影响后续魔改 Android APK，不影响当前 Windows 桌面端 release。

范围：

- 远控页面添加按住说话按钮。
- 支持录音、转写、转写预览。
- 用户确认后发送 agent 指令。
- 支持项目选择和执行模式选择。

验收：

- Android 手机按住说话后能看到转写文本。
- 误识别时可以编辑再发送。
- 手机锁屏/切后台恢复后不会留下卡死录音状态。

### v0.5：执行确认与移动端任务面板

目标：让手机端可以安全控制写操作。

范围：

- bridge 返回 `needs_confirmation`。
- 手机端展示 Codex 计划、待修改文件、风险提示。
- 用户确认后再进入 `workspace-write`。
- 支持取消任务。

验收：

- Codex 要改文件时手机必须确认。
- 拒绝确认后任务结束且不修改文件。
- 任务结果能复制、展开日志、重新发送。

### v1.0：个人工作流可用版

目标：日常可用，而不是 demo。

范围：

- Windows/macOS bridge 安装和自启动。
- 多项目白名单。
- 多设备授权。
- 审计日志查询。
- Codex CLI 优先，预留 Codex App/App Server 适配器。
- 错误恢复：断线、bridge 未启动、Codex 未登录、项目不存在。

验收：

- 手机远控状态下能稳定发起 Codex 任务。
- PC/Mac 能按项目路由。
- 失败有可操作提示。
- 默认配置不会造成远程任意命令执行。

## 第一阶段开发任务拆分

### 任务 1：建立 bridge 最小服务

建议位置：

```text
agent/
  codex-bridge/
    README.md
    config.example.json
    src/
```

先用 Rust 或 Node 都可以。为了贴近主仓库，长期建议 Rust；为了快速验证，Node/TypeScript 更快。

最小接口：

```http
POST /agent/run
Content-Type: application/json

{
  "request_id": "uuid",
  "project": "rustdesk",
  "prompt": "分析这个仓库的构建入口",
  "mode": "dry-run"
}
```

返回：

```json
{
  "request_id": "uuid",
  "status": "done",
  "text": "Codex final answer"
}
```

### 任务 2：RustDesk 聊天前缀路由

临时验证逻辑：

- 被控端收到 `ChatMessage`。
- 如果文本以 `/agent ` 开头，不作为普通聊天展示。
- 解析 project/mode/prompt。
- 请求本机 bridge。
- 将结果作为聊天消息回发控制端。

涉及文件：

- `src/server/connection.rs`
- `src/ipc.rs`
- 可能需要新增 `src/agent_bridge.rs`

### 任务 3：配置与审计

bridge 必须记录：

- 请求时间。
- 远端设备 ID。
- 项目 ID。
- 原始 prompt。
- 执行命令。
- sandbox 模式。
- 退出码。
- 最终摘要。

日志先写本地 JSONL，后续再做 UI。

### 任务 4：本地验证脚本

新增脚本：

```text
agent/codex-bridge/scripts/smoke-test.ps1
```

验证：

- bridge 启动。
- 白名单项目可执行。
- 非白名单项目被拒绝。
- Codex 未登录时返回明确错误。

## 开发原则

- 先跑通价值闭环，再改正式协议。
- RustDesk 核心只做消息路由，不承载 agent 业务复杂度。
- Codex 调用和项目策略都在 bridge 中实现。
- 默认只读，写操作必须确认。
- 手机端体验保持“语音 -> 文字确认 -> 执行状态 -> 结果”四步。

## 近期操作顺序

1. 创建 `feature/voice-agent-phase0-chat-bridge`。
2. 新增 `agent/codex-bridge` 最小服务。
3. 加 `/agent` 聊天前缀解析。
4. 本机用 `curl` 验证 bridge。
5. 两台 RustDesk 客户端连起来验证手机到桌面的闭环。
6. 成功后再做正式 protobuf 和移动端语音 UI。

## v0.1 落地实现记录

### CodeGraph 结果

- 已在仓库初始化并更新 `.codegraph` 索引。
- `codegraph_context` 用于确认 `/agent` 聊天路由、被控端连接处理、Flutter/Rust 事件桥和配置入口。
- `codegraph_impact send_to_cm` 显示影响集中在 `src/server/connection.rs` 的连接管理、文件传输、语音通话和选项更新调用点；本次只在 `Misc(ChatMessage)` 分支前置拦截 `/agent ` 与 `/agent-confirm `，普通聊天仍走原 `send_to_cm(ipc::Data::ChatMessage)`。
- `codegraph_callers send_to_cm` 确认调用方包括 `try_start_cm`、`send_fs`、`on_message`、`handle_voice_call`、`close_voice_call`、`update_options`，因此没有修改 `send_to_cm` 本体，避免影响连接管理和文件传输。

### 已落地入口

- `src/agent_bridge.rs`：新增本机 Rust Codex Bridge，监听 `127.0.0.1:17321`，提供 `/health`、`/agent/run`、`/agent/confirm`。
- `src/core_main.rs`：新增 `--codex-bridge` 子命令，bridge 不单独安装服务。
- `src/server/connection.rs`：被控端收到 `/agent <project> <prompt>` 后拦截，不进入普通聊天 UI；自动拉起 bridge 并把 started/done/failed/needs confirmation 回传为聊天消息。
- `flutter/lib/common.dart`：复用 `MessageBox`，`agent-confirm` 弹窗提供 Confirm/Cancel；Confirm 会发送内部 `/agent-confirm <token>`。
- `flutter/windows/runner/main.cpp`：把 `--codex-bridge` 加入 Windows Flutter runner 多实例参数白名单，避免已有主窗口时 bridge 子进程被 URI 分发逻辑拦截。

### 配置示例

```powershell
rustdesk --option codex-bridge-enabled Y
rustdesk --option codex-bridge-port 17321
rustdesk --option codex-bridge-command codex
rustdesk --option codex-bridge-require-confirmation Y
rustdesk --option codex-bridge-projects '[{"id":"rustdesk","path":"E:\\rustDesk"}]'
```

### 本机 smoke test

启动 bridge：

```powershell
rustdesk --codex-bridge
```

基础验证，不执行 Codex：

```powershell
agent/codex-bridge/scripts/smoke-test.ps1
```

配置好项目白名单且 Codex 已登录后，再执行只读请求：

```powershell
agent/codex-bridge/scripts/smoke-test.ps1 -RunCodex -Project rustdesk -Prompt "分析构建入口，不要修改文件"
```

验证确认 token，但不调用 `workspace-write`：

```powershell
agent/codex-bridge/scripts/smoke-test.ps1 -RunCodex -TestConfirmation -Project rustdesk
```

### v0.1 限制

- 写入确认弹窗基于现有 `MessageBox` 和内部 `/agent-confirm` 聊天命令实现，后续正式版本应改为 protobuf `AgentCommand/AgentCancel/AgentResult`。
- bridge HTTP 读取已按 `Content-Length` 读完整请求，但仍是 v0.1 简单本地 HTTP 解析；后续应替换为正式 HTTP 框架或 IPC。
- Rust 库级编译检查已通过：`cargo check --locked --lib --features flutter --offline`。剩余打包阻塞是 Flutter/Dart SDK 未安装、正式 Flutter Rust Bridge 绑定未重新生成。

## v0.2 落地实现记录

### 已落地能力

- bridge 增加内存任务表，记录 `request_id/project/status/text/sandbox/exit_code/error/token/cancel_requested`。
- 新增 `GET /agent/config`，返回 bridge 当前配置、项目白名单和路径存在性。
- 新增 `GET /agent/tasks/<request_id>`，返回任务状态。
- 新增 `POST /agent/cancel`，支持取消待确认 token 和标记运行中任务取消。
- Codex 执行从 `Command::output()` 调整为 `spawn + wait`，运行中任务收到取消标记后会 kill 子进程。
- 被控端新增 `/agent-cancel <request_id_or_token>` 聊天命令，用于从控制端发起取消。
- smoke-test 脚本覆盖 health、config、非法 project、只读执行、task status、pending confirmation cancel。
- 新增技术状态文档：`docs/voice-codex-agent-tech-status-zh.md`。

### v0.2 未完成或保留问题

- `/agent/run` 仍是同步 HTTP 请求；任务表提供可观测性，但还不是真正异步任务队列。
- 任务表是内存态，bridge 重启后丢失。
- cancel 通过 kill Codex 子进程实现，不保证 Codex 已触发的外部动作全部回滚。
- v0.3 已开始接入正式 protobuf；`/agent`、`/agent-confirm`、`/agent-cancel` 仍作为旧客户端兼容命令保留。
