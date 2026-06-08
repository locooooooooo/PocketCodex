# RustDesk Voice Codex Agent 技术状态

更新时间：2026-06-04

## 当前结论

当前主链路已经从“聊天字符串转发”升级到“结构化 Agent Dashboard + Rust bridge + Codex CLI”。

已经确认可用的主路径是：

`Flutter Dashboard`
-> `sessionSendAgentCommand`
-> `src/flutter_ffi.rs::session_send_agent_command`
-> `src/ui_session_interface.rs::send_agent_command`
-> `src/server/connection.rs::handle_agent_command / spawn_agent_run`
-> `src/agent_bridge.rs::send_run_request`
-> 本机 Codex CLI

这条链路已经能承载：

- 项目路由
- 线程恢复
- skills 选择
- history / terminal context 注入
- 结构化 `AgentResult`
- 本机 Codex session 恢复

但“移动端语音”还没有真正落地，原因不是单点 bug，而是闭环还缺最后几段。

## 第一性原理

如果目标是“手机按住说话，桌面端 Codex 在指定项目和线程里继续工作，并且手机上看到同一条会话历史”，那么系统最少必须同时满足 5 个条件：

1. `Capture`
   手机必须能稳定采集语音，并拿到可上传的音频数据。
2. `Transport`
   音频必须走 RustDesk 已建立的受信任远控会话，而不是让手机自己去连被控端本机 `127.0.0.1`。
3. `Transcribe`
   被控端桌面必须有可执行的本地转写能力，至少要有 `whisper.cpp` 命令和模型。
4. `Route`
   转写结果必须继续走同一个 `project + thread` 路由，而不是落到一条旁路聊天链。
5. `Continuity`
   手机端显示的消息历史必须以桌面 Codex 线程为权威，而不是各自保存一份互相漂移的本地副本。

只要这 5 个条件里有一条缺失，语音功能就不能算真正落地。

## CodeGraph 记录

本轮继续先用 CodeGraph 建立上下文，再动文档和实现判断。

- `codegraph_context`
  - 目标：确认 Dashboard -> FFI -> Session -> Connection -> Bridge 的调用链。
  - 结论：结构化主入口已经不是 `/agent ...` 文本分支，而是 `handleAgentResultEvent()` 和 `sessionSendAgentCommand()`。
- `codegraph_impact handle_agent_command`
  - 影响集中在 `src/server/connection.rs`
  - 结论：文本 agent、普通聊天、文件传输和连接管理仍然共存，语音方案应尽量复用现有 `AgentCommand` 入口，而不是再扩一条独立协议。

## 已完成

### 1. 桌面端 Rust bridge 已具备独立工作台基础能力

已落地在 [`src/agent_bridge.rs`](../src/agent_bridge.rs)：

- bridge 配置项：
  - `codex-bridge-enabled`
  - `codex-bridge-port`
  - `codex-bridge-command`
  - `codex-bridge-require-confirmation`
  - `codex-bridge-projects`
  - `codex-bridge-whisper-command`
  - `codex-bridge-whisper-model`
- session 能力：
  - `GET /agent/sessions`
  - `GET /agent/sessions/:id`
  - `GET /agent/sessions/:id/page`
- task 能力：
  - `POST /agent/run`
  - `POST /agent/confirm`
  - `POST /agent/cancel`
  - `GET /agent/tasks/:request_id`
- skills 能力：
  - `GET /agent/skills`
  - `POST /agent/skills`
  - `DELETE /agent/skills/:id`
  - `POST /agent/skills/sync`
- 语音能力骨架：
  - `POST /agent/voice/transcribe`
  - `POST /agent/voice/run`
  - 本地 `whisper.cpp` 调用骨架

### 2. RustDesk 正式 AgentResult 事件已经打通到 Flutter

已落地在：

- [`src/ui_session_interface.rs`](../src/ui_session_interface.rs)
- [`src/flutter_ffi.rs`](../src/flutter_ffi.rs)
- [`src/server/connection.rs`](../src/server/connection.rs)
- [`src/client/io_loop.rs`](../src/client/io_loop.rs)
- [`src/flutter.rs`](../src/flutter.rs)

当前行为：

- Flutter 发送正式 `AgentCommand`
- 被控端桌面执行 bridge
- 结果以 `AgentResult` 回到控制端
- `detail_json` 可被 Dashboard 消费
- Flutter 侧已经有 transport failure recovery 和 structured result dedupe

### 3. Flutter Dashboard 已经不是旧聊天页

已落地在：

- [`flutter/lib/models/agent_dashboard_model.dart`](../flutter/lib/models/agent_dashboard_model.dart)
- [`flutter/lib/common/widgets/agent_dashboard_page.dart`](../flutter/lib/common/widgets/agent_dashboard_page.dart)
- [`flutter/lib/models/chat_model.dart`](../flutter/lib/models/chat_model.dart)

当前能力：

- 会话列表
- `project / threadMode / sessionRef / profile / selectedSkillIds`
- `Timeline / Sessions / Context / Skills`
- 本机 Codex session 恢复
- `request_id -> conversation` 归属
- mock/dev shell 预览
- Android 远控页浮动窗口入口

### 4. 自建 RustDesk server 路线已经是当前正式方向

相关脚本和文档已经在仓库中：

- [`docs/rustdesk-selfhosted-status-zh.md`](rustdesk-selfhosted-status-zh.md)
- [`agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1`](../agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1)
- [`agent/codex-bridge/scripts/open-rustdesk-selfhosted-firewall.ps1`](../agent/codex-bridge/scripts/open-rustdesk-selfhosted-firewall.ps1)

## 未完成的关键问题

### 1. 移动端语音没有落地的真实原因

这不是单一 bug，而是 4 个缺口叠加。

#### 缺口 A：手机端没有真正的录音采集链

当前 Flutter Dashboard 只有语音相关 runtime 接口和 bridge 接口，没有真正可用的：

- 录音按钮
- 录音中状态
- 停止录音
- 音频编码
- 音频上传

也就是说，UI 和原生 Android 录音采集还没有闭环。

#### 缺口 B：移动端不能直接走本机 `127.0.0.1`

当前 `RustDeskAgentDashboardRuntime.transcribeVoice()` 只支持本机直连 bridge。

这在被控桌面本机上没问题，但在手机控制端是错误路径，因为：

- 手机的 `127.0.0.1` 是手机自己
- Codex bridge 运行在被控端桌面

所以移动端语音必须复用现有远控 session，把语音 envelope 通过 `AgentCommand.prompt` 发到被控端，而不是继续调用手机本地回环地址。

#### 缺口 C：桌面端 STT 运行时尚未配置完成

bridge 已经有：

- `whisper_command`
- `whisper_model`
- `voice_language`

但当前环境检查结果显示：

- `whisper-cli` 不在当前 PATH
- 活跃 RustDesk 配置里没有 `codex-bridge-whisper-model`

这意味着即使手机端能把录音发过去，桌面 bridge 也大概率只会返回 `not_configured`，不会产生有效 transcript。

#### 缺口 D：会话权威源仍然分裂

当前 Dashboard 已经能恢复本机 Codex session，但日常消息仍然部分保存在 Flutter 本地会话文件里。

所以它还没有完全满足“手机端聊天记录要和桌面 Codex 保持一致”的目标。

更准确地说：

- 本地 Flutter 会话目前仍是 UI 容器
- 本机 Codex session 目前已经可读取，但还不是唯一权威源

这也是后续必须继续收敛的方向。

### 2. 确认/取消流仍有兼容层残留

当前系统虽然有正式 `AgentCancel` 和 `AgentResult`，但还保留：

- `/agent`
- `/agent-confirm`
- `/agent-cancel`

这对调试有价值，但对正式 Dashboard 用户流来说，结构不够干净。

### 3. 文档编码曾出现污染

仓库里已有几份中文文档曾出现过编码污染和乱码展示问题。

本轮文档会按 UTF-8 重写收口，后续新增中文文档都应继续保持 UTF-8。

## 当前判断

### 可以明确下结论的事

1. 文字 agent 主链路已经不是问题核心。
2. 移动端语音未落地，核心不是 bridge 后端没做，而是“手机采集 + 远程运输 + 桌面 STT 配置”三件事没闭环。
3. 语音 v1 不需要马上发明新的 protobuf。
4. 最小可行路线应该是：
   - Android 本地录音
   - 录音打包成 `voice_run` envelope
   - 通过现有 `sessionSendAgentCommand` 发到被控端
   - 被控端 bridge 调 `whisper.cpp`
   - 结果继续进入现有 `AgentResult` 和当前会话

### 目前不应再走的路线

1. 不应让手机直接请求桌面 bridge 的 `127.0.0.1`
2. 不应把语音当成普通聊天字符串再重新解析
3. 不应在没有确定桌面 STT 配置前，就只盯着 Flutter UI 做表面按钮

## 需要你手动处理的事项

### 1. 桌面端 STT 运行时

你需要在被控端桌面准备：

- `whisper.cpp` 可执行命令
- 模型文件路径
- 对应 RustDesk 配置项

至少要补这几个配置：

- `codex-bridge-whisper-command`
- `codex-bridge-whisper-model`
- `voice_language`（可选，但建议补）

### 2. 如果要用安装版 Windows RustDesk 做联调

当前安装目录的 DLL/Service 仍可能被系统服务占用。

所以联调优先建议使用：

- `<REPO_ROOT>\flutter\build\windows\x64\runner\Release\rustdesk.exe`

如果一定要替换安装版：

- 先停 `RustDesk Service`
- 再替换安装目录的 `librustdesk.dll`

## 下一步建议

下一步不要再同时扩很多面，按这个顺序推进最稳：

1. 先做移动端语音最小闭环
   - Android 录音
   - `voice_run` 远程路由
   - transcript / failure 状态回显
2. 再收敛“手机端历史 = 桌面 Codex 历史”
   - Codex session 做权威
   - Flutter 本地只保留 UI 元数据
3. 最后再清理 confirm/cancel 兼容层
   - 彻底从聊天命令切到结构化确认流
