# Pocket-Codex 项目介绍

> 让桌面上的 Codex 持续工作，让手机只负责调度、确认和查看结果。

`Pocket-Codex` 是基于 `rustdesk/rustdesk` 的公开产品分支。它不是通用 RustDesk 的替代品，也不是把 Codex 简单搬到手机上运行。

这个项目的目标是：当真实仓库、终端、依赖和 Codex CLI 都在桌面端时，用户仍然可以通过手机远程发起 agent 任务、跟踪状态、处理确认，并回到同一条桌面 Codex 工作线索。

## 这是什么

上游 RustDesk 解决远程桌面连接问题。Pocket-Codex 在这个基础上增加两层能力：

- `Codex Agent Bridge`
- `Agent Dashboard`

两者共同把“远控桌面”扩展成“远控桌面上的 agent 工作流”。

## 产品定位

普通远控解决的是“看到桌面、点到桌面”。Pocket-Codex 解决的是：

- 手机连接桌面后，可以直接调度桌面端 Codex
- 桌面端继续在真实项目目录、真实终端环境和真实账号状态里执行
- 手机端负责选择项目、选择 session、发送任务、查看状态、确认或取消
- 结果继续回到 RustDesk 会话和 Agent Dashboard

手机不是开发机，桌面才是执行端。手机是桌面 agent 的控制面板。

## 核心组件

### Codex Agent Bridge

`Codex Agent Bridge` 运行在被控桌面端，负责把来自控制端的结构化 agent 请求转成桌面本机对 Codex CLI 的调用。

主要代码入口：

- `src/agent_bridge.rs`
- `src/server/connection.rs`
- `src/ui_session_interface.rs`
- `src/flutter_ffi.rs`
- `libs/hbb_common/protos/message.proto`

当前能力：

- 启动本机 bridge 服务
- 限制 agent 只能访问配置过的本地项目
- 支持 `read-only`、`workspace-write`、`status`、`cancel`
- 支持写入类任务的确认流程
- 提供 run / confirm / cancel / task status API
- 提供 Codex session 列表、详情恢复和历史分页
- 提供 task snapshot，用于 Dashboard 恢复任务状态
- 对公开响应做路径、token、raw event 脱敏

### Agent Dashboard

`Agent Dashboard` 是手机端面向 agent 任务的工作台，不再把 agent 入口停留在普通聊天框里。

主要代码入口：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`
- `flutter/lib/common/widgets/agent_task_status_bubble_overlay.dart`

当前能力：

- 以 conversation 组织任务工作区
- 选择 project / profile / session / skill
- 从桌面 Codex session 恢复历史
- 用 `request_id` 关联 agent 结果和 conversation
- 展示 running / needs confirmation / completed / failed 状态
- 提供任务状态气泡，支持完成、失败、等待确认等状态提醒
- 支持 full page 和 floating dashboard 两种开发预览模式
- 支持 Web mock harness 和 live debug bridge

## 当前进展

已经可用：

- 桌面 bridge 运行时
- bridge HTTP 接口和任务状态流
- RustDesk 会话中的正式 `AgentCommand` / `AgentResult` / `AgentCancel`
- Dashboard model 和 Dashboard UI shell
- Web mock harness 和 live desktop-session harness
- Codex session 列表、详情恢复和分页读取
- task snapshot 驱动的 Dashboard 状态恢复
- 任务状态气泡 model、overlay、点击打开、关闭、去重和 TTL
- 本地配置文档和自建 RustDesk server 配置模板
- debug bridge 日志、路径、token、raw event 的公开发布脱敏边界

仍在收口：

- 移动端语音采集、远程传输和桌面 STT 配置闭环
- 手机真机上的 Dashboard 横竖屏、安全区、输入法和远控工具栏验证
- 将所有历史和恢复路径继续收敛到桌面 Codex session 权威源
- 进一步拆分 `AgentDashboardModel` 的职责密度

## 适合谁

这个项目更适合下面这类用户：

- 有长期在线的桌面开发机
- 已经在桌面环境里使用 Codex CLI
- 希望离开电脑时仍能调度桌面上的 agent 任务
- 希望用手机做“调度、确认、查看”，而不是在手机上模拟完整开发环境

如果目标只是远程控制桌面，上游 RustDesk 已经足够。如果目标是“人不在桌前，但桌面上的 Codex 继续在真实项目里工作”，Pocket-Codex 才有意义。

## 文档入口

当前主要文档：

- `docs/voice-codex-agent-tech-status-zh.md`
- `docs/voice-codex-agent-dashboard-status-zh.md`
- `docs/agent-dashboard-dev-flow-zh.md`
- `docs/agent-dashboard-task-status-bubble-tech-plan-zh.md`
- `docs/local-agent-configuration-zh.md`
- `docs/rustdesk-selfhosted-status-zh.md`

历史和审计归档：

- `docs/agent-dashboard-optimization-baseline-zh.md`
- `docs/agent-dashboard-optimization-audit-zh.md`

## 公开仓库边界

公开仓库不保存本机路径、真实设备 ID、server key、真实 `.env`、debug bridge 日志、Codex 会话目录或 Google/Firebase 私有配置。

用户需要按文档自行配置：

- 本地工具链路径和 Android 设备 ID
- 自建 RustDesk server 的 Host IP / 域名和 server key
- `infra/rustdesk-server-oss/.env`
- `flutter/ios/Runner/GoogleService-Info.plist`

## 和上游的关系

这个仓库基于 [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk)。RustDesk 仍然是远程桌面基础能力来源，Pocket-Codex 是在该基础上探索桌面 agent 工作流。

如果要找原始项目、官方发布或通用构建文档，请看：

- 上游仓库：https://github.com/rustdesk/rustdesk
- 官方构建文档：https://rustdesk.com/docs/en/dev/build/
- RustDesk Server：https://rustdesk.com/server
