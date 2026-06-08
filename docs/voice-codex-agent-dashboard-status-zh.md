# RustDesk Agent Dashboard 状态

更新时间：2026-06-08

## 当前结论

Agent Dashboard 已经从“聊天面板改造”进入“结构化 agent 工作台”阶段。

当前 Dashboard 主链路不再以 `/agent ...` 聊天文本为主要设计目标，而是通过 RustDesk session 发送正式 `AgentCommand`，再消费结构化 `AgentResult` 和 bridge task snapshot。

## 已完成

### 1. 工作台 UI

已落地：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`
- `flutter/lib/common/widgets/agent_task_status_bubble_overlay.dart`

当前页面能力：

- conversation 列表
- Chat / Timeline / Sessions / Context / Skills
- project / profile / session 控制
- history context 开关
- terminal transcript context 开关
- 状态卡片
- full page 和 floating 预览
- floating 最小化入口
- task status bubble overlay

### 2. 会话模型

已落地：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`

当前模型能力：

- 会话搜索
- project 筛选
- pin / unpin
- rename
- delete
- selected skill 管理
- sessionRef 绑定
- Codex session 恢复
- task snapshot 应用
- runtime status recovery
- requestId / conversationId 路由

### 3. 结构化 Agent 结果

当前结果链路：

```text
AgentCommand
-> desktop bridge
-> AgentResult
-> AgentDashboardModel.handleAgentResultEvent()
-> conversation state / timeline / bubble
```

已完成的收敛：

- 通过 `request_id` 归属到 conversation
- task snapshot 可驱动状态恢复
- structured result 有 dedupe
- transport failure 可尝试从 task status 恢复
- 确认 token 不进入普通聊天消息文本

### 4. 任务状态气泡

已落地：

- `AgentTaskStatusBubble`
- `visibleTaskStatusBubbles`
- `openTaskStatusBubble()`
- `dismissTaskStatusBubble()`
- `AgentTaskStatusBubbleOverlay`

当前行为：

- `done` / `failed` / `needs_confirmation` 会产生气泡
- 同一 `request_id + status` 去重
- 最多保留 2 个可见气泡
- 点击气泡会打开并选中对应 conversation
- 选中 conversation 后会清理对应气泡
- 等待确认气泡是 sticky，完成和失败气泡有 TTL

已有测试覆盖：

- structured done result creates one task status bubble
- same request id and status does not duplicate task status bubble
- openTaskStatusBubble selects routed conversation and clears its bubbles
- selectConversation clears task status bubbles for that conversation
- text agent status creates confirmation bubble
- task status bubbles keep only the latest two items
- structured confirmation token stays out of chat message text

## 当前行为边界

### 正式路径

正式 Dashboard 任务发送应优先走：

```text
sessionSendAgentCommand
-> AgentCommand
-> AgentResult
```

### 兼容路径

`/agent`、`/agent-confirm`、`/agent-cancel` 仍保留，主要用于旧入口、调试和 fallback。公开文档不再把它描述为 Dashboard 主路径。

### 本地持久化

Flutter 本地持久化只应保留 UI 元数据，例如：

- draft
- pin / archive
- selected profile
- selected skill ids
- 临时视图状态

Codex session history、session paging 和 task snapshot 由桌面 bridge 作为权威源。

## 仍需验证

1. Android 真机横屏和竖屏下的 Dashboard 密度。
2. 远控工具栏、安全区、输入法区域和 task bubble 的避让。
3. 真远控链路下 task status bubble 是否在所有状态里稳定出现。
4. 长 session 恢复时的性能和分页交互。
5. 移动端语音入口和桌面 STT 配置闭环。

## 不再成立的旧判断

以下旧说法已经过时：

- “当前发送仍复用兼容 `/agent` 命令”
- “结果归属仍是启发式”
- “仍主要依赖聊天文本兼容路由”
- “任务状态气泡只是延期需求”

这些内容已由结构化 `AgentCommand` / `AgentResult`、requestId 路由和 task status bubble 实现取代。
