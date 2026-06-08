# Agent Dashboard 任务状态气泡技术方案

更新时间：2026-06-05

## 背景

当前 Agent Dashboard 已经能在 Web harness 中快速调试悬浮窗口、会话切换和 agent 状态卡片。后续用户希望参考 Codex pet 的体验：当 agent 任务完成、失败或等待确认时，用悬浮气泡展示对应会话的状态，并支持点击回到该会话。

本方案只定义实现边界，不在当前 UI 收尾阶段接入功能。

## 目标

1. 任务状态变化时，展示轻量气泡，而不是要求用户一直打开 Dashboard。
2. 气泡必须能指向具体 conversation，点击后打开 Dashboard 并选中对应会话。
3. Web harness、移动端悬浮 Dashboard、未来 Codex pet 风格入口复用同一份状态数据。
4. 气泡不写入聊天记录，避免把通知 UI 和 conversation transcript 混在一起。

## 非目标

- 本阶段不做宠物动画、不做系统托盘通知、不做后台常驻服务。
- 不改变当前 `/agent` bridge 协议主链路。
- 不把气泡状态持久化为长期历史；长期历史仍由 conversation 和 session timeline 承担。

## 数据模型

建议新增一个轻量事件类型：

```dart
class AgentTaskStatusBubble {
  final String id;
  final String conversationId;
  final String projectId;
  final AgentConversationStatus status;
  final String title;
  final String summary;
  final DateTime createdAt;
  final Duration ttl;
}
```

`id` 优先使用 agent `requestId`；没有 requestId 时使用 `conversationId + status + createdAt`。这样可以防止同一任务重复弹多次。

## 状态来源

事件由 `AgentDashboardModel` 统一产出，推荐挂在这些状态入口：

- `sendCurrentPrompt()`：进入 `running` 时可选展示短暂 “Thinking” 气泡。
- `handleAgentResultEvent()`：收到结构化 agent result 时触发 `completed` / `failed` / `needsConfirmation`。
- `tryHandleAgentText()` 或 agent 文本解析链路：兼容 `[Agent:project] status:` 这种文本状态。
- `requestTaskStatus()`：主动刷新到新状态时补发气泡，但需要按 `requestId` 去重。

## 控制器

建议在 model 内部维护一个瞬态队列：

- `List<AgentTaskStatusBubble> visibleBubbles`
- `StreamController<AgentTaskStatusBubble>` 或 `ChangeNotifier` 派发
- `dismissBubble(String id)`
- `openBubble(String id)`：选中 conversation，并通知 UI 打开 Dashboard

队列规则：

- 同屏最多显示 2 个，超出后保留最新。
- 默认 TTL：完成 5 秒、失败 8 秒、等待确认不自动消失或 12 秒后弱化。
- 选中对应 conversation 后自动清掉该 conversation 的气泡。

## UI 呈现

Web harness 和移动端可以先复用一个 widget：

- `AgentTaskStatusBubbleOverlay`
- 放在 `AgentDashboardDevShell` / 移动端远控页的最外层 `Stack`
- 位置：优先右上或左上，避开 RustDesk 底部工具栏和安全区
- 内容：状态图标、状态标题、conversation 标题、1 行 summary
- 点击：展开/打开 floating Dashboard，并选中对应 conversation
- 长按或关闭按钮：手动 dismiss

颜色语义沿用当前状态卡：

- Thinking：蓝色
- Needs approval：黄色
- Done：绿色
- Failed：红色

## 移动端同步

Web harness 改的是 `flutter/lib/common/widgets` 和 `flutter/lib/models` 的共享源码，因此 UI 逻辑会自然同步到移动端，不需要复制代码。

移动端仍需要额外做两件验证：

1. 真机横竖屏检查气泡是否避开远控工具栏、安全区和输入法区域。
2. 真远控链路下确认 bridge 状态事件能正确驱动同一个 model。

## 分阶段实现

### Phase 1：Web harness 原型

- 只接 mock runtime。
- 在 `Simulate read-only / confirm / failure` 后触发气泡。
- 验证点击气泡能打开对应 conversation。

### Phase 2：共享 model 接入

- `AgentDashboardModel` 增加气泡事件队列。
- `handleAgentResultEvent()` 和文本状态解析共同产出气泡。
- 加 requestId 去重。

### Phase 3：移动端远控页接入

- 在移动端 Dashboard 外层或 remote page overlay 层挂载气泡。
- 处理 safe area、底部 toolbar、输入法遮挡。
- 真机横竖屏 smoke test。

### Phase 4：Codex pet 风格扩展

- 如果后续真的做宠物入口，只消费同一份 `AgentTaskStatusBubble`。
- 宠物层只负责表现，不重新解析 agent 状态。

## 验证清单

- Web harness：完成、失败、等待确认三类状态都能弹气泡。
- 点击气泡后，Dashboard 打开并选中正确 conversation。
- 同一 requestId 不重复弹。
- 多 conversation 同时完成时，气泡不会遮挡主要操作区。
- 移动端横屏和竖屏都不遮挡 RustDesk 底部工具栏。
