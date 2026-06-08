# RustDesk `/agent` 直连 Codex 定向状态

更新时间：2026-06-03

## 当前结论

本轮先把手机端已经打通的打字链路，直接接到本机 `codex`。先支持：

- 指定项目
- 指定 Codex 会话
- 指定 Codex profile

`minister` 先不硬接。原因很直接：当前仓库内已经有稳定的本地 Codex bridge，而本机 `minister` 侧暂时没有确认过的“单条消息注入指定项目/线程”的本地接口，直接猜协议会把链路做脆。

## CodeGraph 记录

本轮修改前已使用 CodeGraph 确认入口和影响范围：

- 控制端聊天发送：`flutter/lib/models/chat_model.dart`
- Rust 会话发送：`src/ui_session_interface.rs`
- 被控端聊天拦截：`src/server/connection.rs::try_handle_agent_chat`
- bridge 请求发送：`src/server/connection.rs::spawn_agent_run`
- 本机 bridge 执行：`src/agent_bridge.rs::send_run_request` -> `run_codex_process`
- 控制端结果回传：`src/client/io_loop.rs`

结论：

- `/agent` 拦截只发生在被控端 `Misc(ChatMessage)` 处理分支。
- 普通聊天链路仍走原有 `ChatMessage` 路径。
- 本轮没有改 `send_to_cm` 主体，也没有改文件传输、连接管理、普通聊天协议。

## 本轮已完成

- `src/agent_bridge.rs`
  - 支持项目级目标配置扩展字段：
    - `executor`
    - `profile`
    - `session`
    - `resume_last`
  - bridge 执行 Codex 时支持：
    - 新会话执行
    - `resume --last`
    - `resume <session_id>`
  - 审计日志补充：
    - `executor`
    - `profile`
    - `session`
    - `resume_last`

- `src/server/connection.rs`
  - `/agent` 聊天命令支持定向参数：
    - `session=...`
    - `thread=...`
    - `dialog=...`
    - `profile=...`
    - `executor=...`
  - 参数写法只在 prompt 前生效。
  - 未识别的 `key=value` 会视为 prompt 开始，不会误吃掉正文。

- `agent/codex-bridge/scripts/configure-local-agent.ps1`
  - 支持写入：
    - `executor`
    - `profile`
    - `session`
    - `resume_last`

## 手机端现在可直接用的命令

最基础：

```text
/agent rustdesk 分析构建入口
```

继续上一个 Codex 会话：

```text
/agent rustdesk session=@last 继续刚才那个会话，分析启动链路
```

继续指定会话：

```text
/agent rustdesk session=019e815c-78ce-7553-a264-6310ed2c75e9 继续处理刚才的问题
```

指定 profile：

```text
/agent rustdesk profile=default 分析当前仓库的配置读写入口
```

组合使用：

```text
/agent rustdesk profile=default session=@last 继续刚才那个线程，整理结论
```

`thread=` 和 `dialog=` 是 `session=` 的别名，例如：

```text
/agent rustdesk dialog=@last 继续刚才的对话
```

## 本地配置示例

只配置项目：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/configure-local-agent.ps1 `
  -ProjectId rustdesk `
  -ProjectPath <PROJECT_PATH>
```

默认绑定到上一次会话：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/configure-local-agent.ps1 `
  -ProjectId rustdesk `
  -ProjectPath <PROJECT_PATH> `
  -ResumeLast
```

默认绑定到固定会话：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/configure-local-agent.ps1 `
  -ProjectId rustdesk `
  -ProjectPath <PROJECT_PATH> `
  -Session 019e815c-78ce-7553-a264-6310ed2c75e9
```

## 当前未完成

- `executor=minister` 目前只是预留字段，bridge 还没有真正调用本地 `minister`。
- Flutter 移动端 UI 还没有正式任务面板，当前主要仍通过聊天文字入口驱动。
- `AgentCommand` protobuf 还没有加入 `session/profile/executor` 字段；当前“指定会话”主要靠聊天兼容入口完成。

## 需要你手动处理的事项

- 确认本机 `codex` CLI 已登录，并且能在目标项目目录执行：

```powershell
codex exec --cd <PROJECT_PATH> --sandbox read-only "ping"
```

- 如果你想固定某个对话框，需要先拿到该 Codex 会话 ID，再写进：
  - `session=<id>` 聊天命令
  - 或 `configure-local-agent.ps1 -Session <id>`

- 如果你后续坚持走 `minister` 分发，需要你决定一条明确接口：
  - 直接给 `minister` 增加本地 HTTP API
  - 或明确现有可复用的本地 IPC / CLI 调用方式
