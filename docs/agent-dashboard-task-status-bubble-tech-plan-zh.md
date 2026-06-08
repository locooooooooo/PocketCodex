# Agent Dashboard 任务状态气泡实现状态

更新时间：2026-06-08

## 当前结论

任务状态气泡已经从技术方案进入实现状态。它不再只是后续规划，而是已经接入 `AgentDashboardModel`、Flutter / harness overlay 和 focused tests。

气泡的目标是：当 agent 任务完成、失败或等待确认时，不要求用户一直展开 Dashboard，也能通过轻量通知回到对应 conversation。

## 已落地代码

共享 model：

- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`

共享 UI：

- `flutter/lib/common/widgets/agent_task_status_bubble_overlay.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_task_status_bubble_overlay.dart`

挂载位置：

- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_dev_shell.dart`
- `flutter/lib/models/chat_model.dart`

测试：

- `flutter/test/agent_dashboard_model_test.dart`

## 当前数据模型

`AgentTaskStatusBubble` 包含：

- `id`
- `conversationId`
- `requestId`
- `projectId`
- `status`
- `title`
- `summary`
- `createdAt`
- `expiresAt`
- `sticky`

可见气泡由 `visibleTaskStatusBubbles` 提供。当前最多保留 2 个可见气泡。

## 当前触发来源

气泡由 `AgentDashboardModel` 统一产生，来源包括：

- structured `AgentResult`
- `task_snapshot`
- 兼容文本状态解析中的完成、失败、等待确认状态

当前触发状态：

- `completed` -> `Done`
- `failed` -> `Failed`
- `needsConfirmation` -> `Needs approval`

`running` 当前不弹长期气泡，避免频繁任务状态噪声。

## 当前交互

已实现：

- 点击气泡：调用 `openTaskStatusBubble()`，选中对应 conversation，并清理该 conversation 的气泡。
- 关闭气泡：调用 `dismissTaskStatusBubble()`。
- 选择 conversation：自动清理该 conversation 的气泡。
- 去重：同一 `requestId + status` 不重复弹。
- 容量限制：只保留最新 2 个气泡。
- TTL：完成和失败气泡自动过期；等待确认气泡保持 sticky。

## 非目标

- 不把气泡写入聊天记录。
- 不把气泡作为长期任务历史。
- 不重新解析 Codex 原始日志。
- 不绕过 `AgentDashboardModel` 另建一套状态源。

长期历史仍由 conversation、timeline、Codex session 和 task snapshot 承担。

## 已覆盖测试

当前测试覆盖：

- structured done result creates one task status bubble
- same request id and status does not duplicate task status bubble
- openTaskStatusBubble selects routed conversation and clears its bubbles
- selectConversation clears task status bubbles for that conversation
- text agent status creates confirmation bubble
- task status bubbles keep only the latest two items

隐私相关测试：

- structured confirmation token stays out of chat message text

## 仍需验证

### Web / harness

- mock 模式下完成、失败、等待确认三类状态都能显示气泡。
- live debug bridge 模式下，真实 structured result 能驱动同一个 model。

### 移动端

- Android 真机横屏、竖屏下气泡位置合理。
- 气泡避开远控工具栏、安全区和输入法区域。
- 点击气泡后 Dashboard 展开并选中正确 conversation。

### 后续扩展

如果后续增加 Codex pet 风格入口，pet 层只消费同一份 `AgentTaskStatusBubble`，不重新解析 agent 状态。
