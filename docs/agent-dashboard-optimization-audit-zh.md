# Agent Dashboard / Codex Bridge 优化审计与重构任务

更新时间：2026-06-06

## 目的

本文件用于沉淀当前 `Agent Dashboard`、`Codex Bridge`、`会话同步` 相关实现的稳定性与性能审计结果，并将后续工作明确拆解为可执行任务。

本轮只做审计结论沉淀，不执行优化改造。

## 当前结论

当前问题的主要矛盾不是语言本身，而是：

1. 会话读取路径存在明显的全量扫描与重复读取。
2. bridge 事件推送、状态查询、前端轮询三套机制叠加，状态链路重复。
3. Flutter 侧模型职责过重，恢复会话、状态恢复、草稿、存储、runtime 协议都堆在同一个模型中。
4. 当前实现可以继续基于 Rust 收敛，不建议引入 Zig 重写。

结论判断：

- 不建议做 Zig 版本重写。
- 不建议做全量 Rust 重写。
- 仅做零散性能 patch 不够。
- 建议继续保留 Rust，实现一次中等规模的结构性重构。

## 已识别风险

### 1. Session 读取路径性能风险

当前 bridge 的 `/agent/sessions/:id` 和 `/agent/sessions/:id/page` 路径存在以下问题：

- 每次 detail/page 请求都会重新读取 `session_index.jsonl`
- 每次都会递归扫描 `~/.codex/sessions`
- 找到文件后仍然整文件读入，再在内存中分页

风险：

- Codex session 数量增多后，恢复速度会显著下降
- 移动端切换会话或恢复首屏时卡顿概率上升
- 多端并发恢复时会造成不必要的磁盘 IO 放大

### 2. Dashboard 会话恢复过重

当前 Flutter 侧对 session 的恢复逻辑存在以下特点：

- 空白首屏会自动挂接到最新 session
- 首次恢复后会继续自动翻页直到把历史全部补齐
- 每次补页都会重建消息列表并推动 conversation 更新

风险：

- 首屏加载成本高
- 长对话会导致移动端明显卡顿
- 多窗口切换时容易出现恢复抖动、列表刷新不稳定

### 3. 状态链路重复

当前状态同步实际上存在三层：

1. Rust bridge 主响应
2. Rust `send_agent_protocol_response` 在需要补 snapshot 的路径上仍可能补查 task 状态
3. Flutter web / io runtime 再启动定时轮询状态

当前已做的收敛：

- 第五轮优化已先收掉“远端显式 `status` 请求”里的 bridge 重复自查：
  在 `spawn_agent_status()` 已拿到 task 的情况下，生成 snapshot 时直接复用该 task，
  不再额外再查一次 `/agent/tasks/{id}`。
- 第六轮优化已再收掉 transport failure 恢复场景里的一处 Flutter 即时补查叠加：
  当 runtime 自己已经有活跃 status poller 时，`AgentDashboardModel`
  不再立刻额外调用一次 `requestTaskStatus()`，优先复用现有 poller。
- 第七轮优化已再收掉 deferred recovery 在等待窗口里的冗余继续执行：
  一旦同一 request 收到新的结构化状态事件，就立刻清理旧恢复尝试，让挂起中的
  `_recoverTaskStatus()` 自动退出。
- 第八轮优化已再收掉普通消息分支的一次重复 listener 通知：
  `_appendMessage()` 已经会触发保存和通知，外层不再重复调用一次
  `notifyListeners()`。
- 第九轮优化已再收掉结构化结果热路径里的一处重复 recovery map 操作：
  到达带 `requestId` 的结构化状态后，统一直接清理一次
  `_statusRecoveryAttempts`，不再先 `containsKey` 再重复 `remove`。
- 第十轮优化已再收掉多个 detail 分支里对空 `requestId` 的无效 request 映射清理：
  仅在 `requestId` 非空时才执行 `_requestToConversation.remove(requestId)`。
- 第十一轮优化已再收掉 `task_snapshot` 事件链里的一次重复 session 绑定：
  `_applyTaskSnapshot()` 已经会绑定 `sessionRef`，外层不再对同一个
  `sessionId` 再次调用 `updateConversationSettings()`。
- 第十二轮优化已再收掉 `updateConversationSettings()` 在 session reset 路径里的一次
  重复会话遍历和重复保存调度：消息清空直接并入同一次 conversation 更新，不再额外
  再走一次 `_replaceConversationMessages()`。
- 第十三轮优化已再收掉 `restoreSessionIntoConversation()` 在空 session 路径上的
  第二套重复 reset：空 session restore 现在直接复用
  `updateConversationSettings(sessionRef: '', threadMode: 'new')`，
  不再额外重复清理 timeline / rawEvents / 消息和通知。
- 第十四轮优化已再收掉正常 `restoreSessionIntoConversation()` 路径里的一次
  重复 hydration 触发：session restore 自己负责 detail + history 加载时，
  不再同时通过 `updateConversationSettings()` 再额外自动触发一次
  `_ensureConversationHydrated()`。
- 第十五轮优化已再收掉正常 paged session restore / hydration 链里的多次持久化调度：
  detail 首屏、分页追加和 restore 起点设置先只更新内存，整条 restore 完成后再统一
  保存一次最终结果。
- 第十六轮优化已再收掉 `task_snapshot done` 和 `codexResult done` 路径里
  session 绑定后的重复 hydration / refresh 触发：done 分支现在只保留自己显式负责的
  那一次 session 读取链，不再先由绑定动作自动读一遍。
- 第十七轮优化已再收掉 `task_snapshot done` 和 `codexResult done` 路径里
  session 绑定后的重复持久化调度：session 绑定先只更新内存，done 分支显式
  refresh / hydration 完成后再统一保存一次最终结果。
- 第十八轮优化已再收掉 `ensureLoaded()` 首屏自动挂接最新 session 链里的重复保存：
  不再先落盘空白初始会话，也不再为首次标记已读额外保存，首屏自动挂接只保留最终
  restore 结果那一次保存。
- 第十九轮优化已再收掉 `deleteConversation()` 在切换到替代会话时的重复保存：
  替代会话的已读标记先只更新内存，删除链最后再统一保存一次最终 conversation 列表。
- 第二十轮优化已再收掉 restore / hydration 链里的中间重复排序：
  首屏 detail 和历史分页追加先只更新内存，整条 restore / hydration 完成前只在最终
  保存前统一排序一次。
- 第二十一轮优化已再收掉 `_markConversationRead()` 在已读会话上的无效写入：
  会话本来就没有未读时，不再更新时间，也不再触发额外保存和通知。
- 第二十二轮优化已再收掉 `updateConversationSettings()` 在完全相同设置输入下的无效写入：
  当 title / profile / sessionRef / flags 等目标状态与当前会话一致，且本轮也不会触发
  session reset 时，直接跳过 `updatedAt` 刷新、保存和通知。
- 第二十三轮优化已再收掉 `restoreSessionIntoConversation(sessionId: '')` 在目标会话已经是空白
  `new` 状态时的重复 reset：
  会话本来就没有 sessionRef、messages、timeline、rawEvents 和历史游标时，直接返回，
  不再额外刷新 `updatedAt`、保存和通知。
- 第二十四轮优化已再收掉 `deleteConversation()` 在传入不存在会话 id 时的无效删除链：
  当目标 id 不存在时，直接返回，不再额外排序、同步草稿、保存和通知。
- 第二十五轮优化已再收掉 `visibleConversations` getter 的重复排序：
  在补齐 demo seed / reset 路径的显式排序后，getter 只保留过滤，不再每次访问都重排一次可见列表。
- 第二十六轮优化已再收掉 unread 统计链里的重复会话查找：
  在保留 `conversationHasUnread(String id)` 外部接口不变的前提下，内部改为复用已拿到的会话对象，
  避免 `unreadConversationCount` 和 `_markConversationRead()` 里的重复 `_findConversation()` 扫描。
- 第二十七轮优化已再收掉 `deleteConversation()` 在真实删除路径上的双重遍历：
  将 `any() + where()` 收敛为 `indexWhere()` 定位后再 `removeAt(index)`，保持删除语义不变。
- 第二十八轮优化已再收掉 `resetDemoState()` 中对 demo 状态 map 的重复清空：
  不再在外层先 `clear()` 一次，再交给 `_applyDemoStatuses()` 二次清空，保持 demo 状态恢复结果不变。
- 第二十九轮优化已再收掉 `deleteConversation()` 在真实删除后的重复排序：
  基于 `_conversations` 已是有序源的前提，删除一个元素后不再额外对剩余列表再排序一次。
- 第三十轮优化已再收掉 `_markConversationRead()` 在真实已读更新路径上的整表重建：
  在确认目标会话存在未读后，改为定位索引后只替换一个元素，不再 `map()` 整份 `_conversations`。
- 第三十一轮优化已再收掉 `_appendMessage()` 在消息追加热路径上的整表重建：
  将每次追加消息时的整表 `map()` 收敛为定位索引后只替换一个元素，保持标题更新、排序、保存和通知语义不变。
- 第三十二轮优化已再收掉 `_handleComposerChanged()` 在草稿输入热路径上的整表重建：
  将每次 draft 输入变更时的整表 `map()` 收敛为定位当前选中会话索引后只替换一个元素，保持延迟保存语义不变。
- 第三十三轮优化已再收掉 `_applySessionDetail()` 在 session detail / paging 热路径上的整表重建：
  将每次 session detail 合并时的整表 `map()` 收敛为定位目标会话索引后只替换一个元素，保持消息合并、排序和保存语义不变。
- 第三十四轮优化已再收掉 `updateConversationSettings()` 在单会话更新路径上的整表重建：
  将 metadata 更新和 session reset / clear 路径里的整表 `map()` 收敛为定位目标会话索引后只替换一个元素，保持保存、通知和 hydration 语义不变。
- 第三十五轮优化已再收掉 `updateConversationSettings()` 内部对目标会话的重复线性查找：
  将先 `_findConversation()`、后 `indexWhere()` 的双查找收敛为入口一次 `indexWhere()`，复用同一个索引完成 next 值计算和单点替换。
- 第三十六轮优化已再收掉 pinned / archived 包装方法与统一设置入口之间的重复线性查找：
  `toggleConversationPinned()` 与 `toggleConversationArchived()` 不再先 `_findConversation()`、
  再进入 `updateConversationSettings()` 二次定位同一会话，而是一次 `indexWhere()` 后复用同一索引。
- 第三十七轮优化已再收掉 `_markConversationRead()` 内部对目标会话的重复线性查找：
  从先 `_findConversation()`、后 `indexWhere()` 收敛为入口一次 `indexWhere()`，
  复用同一索引完成未读判定与单点已读更新。
- 第三十八轮优化已再收掉 `restoreSessionIntoConversation(sessionId: '')`
  空 session reset 分支里的重复线性查找：
  由先 `_findConversation()`、再进入 `updateConversationSettings()` 二次定位，
  收敛为入口一次 `indexWhere()` 后复用同一索引完成 no-op 判定与 reset。
- 第三十九轮优化已再收掉草稿输入热路径里的重复选中会话定位：
  `_handleComposerChanged()` 不再先通过 `selectedConversation` 扫描会话列表、
  再 `indexWhere()` 二次定位，而是复用统一的 `_selectedConversationIndex()`。
- 第四十轮优化已再收掉 `conversationHasUnread(String id)` 入口里的对象查找包装：
  不再先 `_findConversation()` 拿目标会话对象，而是入口直接一次 `indexWhere()`，
  然后复用现有 `_conversationHasUnread(conversation)` 判定逻辑。
- 第四十一轮优化已再收掉 `_ensureConversationHydrated()` 前置检查阶段的对象查找包装：
  不再先 `_findConversation()` 拿目标会话对象，而是入口直接一次 `indexWhere()`，
  保持原有前置检查和异步 hydration 链不变。
- 第四十二轮优化已再收掉 `loadMoreSessionHistory()` 前置检查阶段的对象查找包装：
  不再先 `_findConversation()` 拿目标会话对象，而是入口直接一次 `indexWhere()`，
  保持原有 `sessionRef` / `cursor` 检查、分页加载和错误处理逻辑不变。
- 第四十三轮优化已再收掉 `_syncComposerWithSelectedConversation()` 里的选中会话读取包装：
  不再经由 `selectedConversation` 间接读取当前 draft，而是直接复用
  `_selectedConversationIndex()` 定位并同步 `textController`。
- 第四十四轮优化已再收掉 `_maybeAttachLatestSession()` 里的选中会话读取包装：
  不再经由 `selectedConversation` 间接读取当前会话，而是直接复用
  `_selectedConversationIndex()` 完成 latest-session auto-attach 前置检查。
- 第四十五轮优化已再收掉 `createConversation()` 里的模板会话读取包装：
  不再经由 `selectedConversation` 间接读取当前模板，而是直接复用
  `_selectedConversationIndex()` 完成会话创建前的模板继承判断。
- 第四十六轮优化已再收掉 `_selectedConversationIndex()` 在首项命中场景下的一次不必要线性扫描：
  当前选中本来就是列表首项时，直接返回 `0`，其余场景仍沿用原有查找和 fallback 逻辑。
- 第四十七轮优化已再收掉 `sendCurrentPrompt()` 里的当前会话读取包装：
  不再经由 `selectedConversation` 间接读取当前会话，而是直接复用
  `_selectedConversationIndex()` 完成发送前的当前会话定位。
- 第四十八轮优化已再收掉 `sendCurrentPrompt()` 本地追加消息链里的一次重复定位：
  在已经拿到当前会话索引后，直接通过 `_appendMessageAtIndex()` 复用同一索引，
  不再把同一个会话 id 传回 `_appendMessage()` 再做一次 `indexWhere()`。
- 第四十九轮优化已再收掉 `AgentDashboardModel` 内部分散的按 id 定位索引实现：
  通过 `_conversationIndexById()` 统一收敛会话设置、删除、已读、load-more、
  hydration 前置检查等同步路径里的重复 `indexWhere()` 写法。
- 第五十轮优化已再收掉 `_applySessionDetail()` 会话详情合并路径里的剩余重复定位：
  session detail / page 合并在进入单元素替换前，改为复用 `_conversationIndexById()`，
  不再单独保留一份按 `conversationId` 的直接 `indexWhere()` 实现。
- 第五十一轮优化已再收掉 `renameConversation()` 轻包装入口里的一次重复定位：
  标题重命名在确认输入非空后，直接复用 `_conversationIndexById()` +
  `_updateConversationSettingsAtIndex()`，不再先走统一设置入口再二次定位同一会话。
- 第五十二轮优化已再收掉 `_applyTaskSnapshot()` session 绑定路径里的一次重复定位：
  task snapshot 在 timeline / rawEvents 写入后，如需绑定 `sessionRef`，直接复用
  `_conversationIndexById()` + `_updateConversationSettingsAtIndex()`，
  不再先进入 `updateConversationSettings()` 再二次定位同一会话。
- 第五十三轮优化已再收掉 `restoreSessionIntoConversation()` 正常 session 分支里的一次重复定位：
  在确认 `sessionId` 非空后，先复用 `_conversationIndexById()` +
  `_updateConversationSettingsAtIndex()` 完成 continue 绑定，
  不再先进入 `updateConversationSettings()` 再二次定位同一会话。
- 第五十四轮优化已再收掉 `codexResult` session 绑定路径里的一次重复定位：
  在 detail 带有效 `sessionId` 时，直接复用 `_conversationIndexById()` +
  `_updateConversationSettingsAtIndex()` 完成 continue 绑定，
  不再先进入 `updateConversationSettings()` 再二次定位同一会话。
- 第五十五轮优化已再收掉 `selectConversation()` 重复选中分支里的选中 id 包装读取：
  当本次选中的本来就是当前会话时，直接复用 `_selectedConversationIndex()` 拿到
  当前会话，再继续已读和 hydration 链，不再把同一个 id 原样传回两条按 id 入口。
- 第五十六轮优化已再收掉 `selectConversation()` 主分支里的 fallback 选中包装读取：
  在切换会话前先确定目标索引和最终选中 id，再继续草稿同步、已读和 hydration，
  不再把原始入参 id 直接传给后续按 id 入口后再依赖 fallback 语义二次解析。
- 第五十七轮优化已再收掉 `selectConversation()` 选中链里的已读重复定位：
  在已经拿到当前或目标会话索引后，直接复用 `_markConversationReadAtIndex()`，
  不再把同一会话 id 传回 `_markConversationRead()` 再做一次按 id 定位。
- 第五十八轮优化已再收掉 `selectConversation()` 选中链里的 hydration 重复定位：
  在已经拿到当前或目标会话索引后，直接复用 `_ensureConversationHydratedAtIndex()`，
  不再把同一会话 id 传回 `_ensureConversationHydrated()` 再做一次按 id 定位。
- 第五十九轮优化已再收掉 `selectConversation()` 主分支里的 composer 同步包装读取：
  在已经拿到目标会话索引后，直接复用该会话的 draft 同步 `textController`，
  不再先进入 `_syncComposerWithSelectedConversation()` 再由选中态二次解析目标会话。
- 第六十轮优化已再收掉 `createConversation()` 新建后 composer 同步包装读取：
  在已经拿到新建会话对象且其 draft 固定为空后，直接将 `textController` 归零，
  不再先进入 `_syncComposerWithSelectedConversation()` 再由选中态二次解析目标会话。
- 这只是缩小一处重复查询，不代表 push / poll / snapshot 三层职责已经收口。

风险：

- 同一任务产生重复状态事件
- 同一 request 产生重复 UI 更新
- 会话数量多时，网络/IPC 请求量不必要增加
- 更难判断真正的权威状态源

### 4. Bridge 并发模型过于原始

当前 bridge 是：

- blocking socket
- 每个请求 `std::thread::spawn`
- 没有并发上限
- 没有背压控制

风险：

- 本地单机调试可接受
- 后续如果增加更多 dashboard 事件/状态同步场景，线程模型会变脆

### 5. Task Store 复制成本偏高

当前任务状态存储仍使用全局 `Mutex<HashMap<...>>`。第三轮优化已经把
`timeline` / `raw_events` 的整体 clone 改成了原地更新，但当前容器模型仍然有这些特征：

- 所有 task 更新仍串行经过同一把全局锁
- `timeline.remove(0)` / `raw_events.remove(0)` 仍是线性成本
- 高频状态事件下，容器级争用仍可能放大

风险：

- 高频事件下锁竞争仍会放大
- 如果后续任务事件更密集，当前容器模型会继续成为热点

### 6. Flutter Model 职责过重

`AgentDashboardModel` 当前同时承担：

- conversation storage
- runtime dispatch
- session hydration
- task status recovery
- skill catalog state
- UI draft/read state
- structured event fallback

风险：

- 后续改动 blast radius 过大
- 很难单独验证一个子链路
- UI bug 与 runtime bug 会彼此耦合

### 7. Voice 临时文件未清理

当前 voice transcribe 流程已增加保守清理策略：bridge 会在写入新的 base64 临时 wav 前，
清理同目录下超过 1 小时的旧 `voice-*.wav`。但更细粒度的即时回收、可配置阈值和暴露路径
策略仍未收口。

风险：

- 当前只做保守清理，不保证立刻消除所有历史文件
- `audioPath` 仍然暴露当前临时文件路径

## 技术路线判断

### 为什么不建议 Zig

原因不是 Zig 不行，而是当前问题不在语言层：

- RustDesk 现有桌面、bridge、FFI、Flutter 接入都已建立在 Rust 边界上
- 当前主要问题是数据路径与状态职责设计，而不是 Rust 性能不够
- Zig 重写会引入新的 FFI、构建链、维护与调试成本
- 迁移成本远高于当前问题本身

所以 Zig 方案不符合当前阶段的投入产出比。

### 为什么不建议全量重写 Rust

当前实现虽然结构偏重，但并没有坏到必须推倒：

- session source 已经接通
- task snapshot 已经有基础模型
- bridge 已经具备可扩展入口
- web harness 已经能支撑 UI/UX 联调

更合理的方式是：

- 保留现有接口边界
- 重构内部读取、缓存、状态与 hydration 机制
- 用阶段性收敛替代重来

## 建议重构目标

### 第一阶段：收敛权威状态源

目标：

- 明确 task 状态唯一权威来源
- 明确 session detail 唯一权威来源
- 避免 bridge 自查 + 前端轮询重复叠加

建议：

- `push` 为主，`poll` 为兜底
- 仅保留一层 snapshot 补全机制
- request_id -> conversation_id 映射改为更稳定的状态表

### 第二阶段：优化 session 读取路径

目标：

- 会话恢复只读取必要页
- 不再每次 detail/page 都全量扫盘

建议：

- 在 bridge 进程内缓存 session index
- session_id -> file path 做缓存
- session detail 改为真正分页读取，而不是整文件读入后分页

### 第三阶段：拆分 Flutter Model

目标：

- 降低 `AgentDashboardModel` 的职责密度
- 将 UI 状态、session store、runtime transport 分离

建议拆分：

- `AgentDashboardViewState`
- `AgentDashboardSessionStore`
- `AgentDashboardTaskState`
- `AgentDashboardRuntimeClient`

### 第四阶段：优化首屏恢复策略

目标：

- 减轻移动端首屏负载
- 提升多会话切换稳定性

建议：

- 不自动全量 hydration
- 默认只恢复最近一页
- 历史由用户显式触发“加载更多”
- 最新 session 自动挂接逻辑增加可控开关

### 第五阶段：补齐资源清理与并发控制

目标：

- 避免长期运行后状态与资源退化

建议：

- 清理 voice 临时文件
- 降低 task store clone 成本
- 视需要将 bridge 从 thread-per-request 收敛为受控 worker 或 async 模式

## 任务拆解

### A. 架构收敛任务

- [ ] 定义 agent task 状态链路的唯一权威源
- [ ] 定义 session 恢复链路的唯一权威源
- [ ] 明确 push / poll 的职责边界

### B. Rust Bridge 任务

- [x] 为 `session_index.jsonl` 增加缓存层
- [x] 为 `session_id -> session file path` 增加缓存层
- [x] 将 session detail/page 改为真正分页读取
- [x] 降低 `TASKS` 更新时的 clone 成本
- [x] 增加 voice 临时文件清理策略
- [x] 去掉远端显式 `status` 路径的一次重复 task 查询
- [ ] 评估 bridge 是否需要 async 化或 worker 化

### C. Flutter Dashboard 任务

- [ ] 拆分 `AgentDashboardModel`
- [ ] 将 session hydration 变为按需加载
- [ ] 去掉首屏自动全量历史恢复
- [ ] 梳理 requestId / conversationId / sessionRef 映射关系
- [ ] 收敛 runtime status recovery 逻辑
- [ ] 收敛 `updateConversationSettings()` 的排序 / 存储 / 通知 / hydration 副作用边界
- [ ] 收敛 `restoreSessionIntoConversation()` 正常加载路径与 hydration 副作用边界
- [ ] 评估 `restoreSessionIntoConversation()` 是否还需要继续拆分“空 session reset”和“真实 session restore”两类职责
- [ ] 评估 `restoreSessionIntoConversation()` 其他分支里是否仍存在“包装层先查、统一设置入口再查”的重复扫描
- [ ] 收敛 `_ensureConversationHydrated()` 在首屏自动挂接和手动切换路径里的加载策略
- [ ] 评估首屏自动挂接最新 session 是否需要改成按需历史加载
- [ ] 拆分 detail 分支里“session 绑定”和“session refresh”两类职责
- [ ] 继续收敛 detail 分支里“session 绑定 / refresh / save / notify”四类副作用边界
- [ ] 决定首屏自动挂接最新 session 是否继续保留“自动全量历史 hydration”
- [ ] 继续梳理 conversation 列表管理路径里的 create/select/delete/save 副作用边界
- [ ] 评估 conversation 列表排序是否需要从“分散在各 mutation 路径手动维护”收敛成更集中的不变量约束
- [ ] 评估 `deleteConversation()` 是否还需要继续拆分“真实删除”和“替代选中/已读同步”两类职责
- [ ] 评估会话列表是否需要为按 id 定位引入更直接的索引结构，以避免更多路径上的重复线性查找
- [ ] 评估删除/替代选中路径是否还存在可以继续收掉的重复草稿同步或已读处理副作用
- [ ] 评估 demo/runtime 状态是否需要从“reset 时即席重建”收敛成更清晰的初始化边界
- [ ] 评估 restore/hydration 链里的最终统一排序是否还能继续缩小影响面
- [ ] 评估 unread/read 状态更新链是否需要从时间戳比较转为更稳定的消息游标语义
- [ ] 评估 unread 统计是否需要进一步从按次遍历计算收敛为更集中维护的派生状态
- [ ] 评估 unread/read 更新链是否还存在更多“单元素更新却整表重建”的路径
- [ ] 评估 unread/read 更新链里是否还存在“先按 id 找对象、后再次按 id/索引查找同一对象”的重复扫描
- [ ] 评估消息追加、session detail 合并等热路径是否还存在更多“单元素更新却整表重建”的路径
- [ ] 评估 draft 输入、会话设置更新等 UI 热路径是否还存在更多“单元素更新却整表重建”的路径
- [ ] 评估 `selectedConversation` 的 fallback 语义是否仍应长期保留，还是需要改成更显式的选中状态约束
- [ ] 评估 restore/hydration 链里的 session 绑定、消息合并、timeline/rawEvents 更新职责是否需要继续拆分
- [ ] 评估 `updateConversationSettings()` 是否还需要继续拆分 metadata 更新、session reset、排序/保存/通知、hydrate 触发四类职责
- [ ] 评估会话更新链里是否还存在“先按 id 找对象、后再次按 id/索引查找同一对象”的重复扫描
- [ ] 评估 `renameConversation()` 与其他轻包装入口是否仍存在同类“包装层先查、统一设置入口再查”的重复扫描
- [ ] 评估 `updateConversationSettings()` 是否还需要继续拆分“纯 metadata 更新”和“session reset / hydration 入口”两类职责

- 第六十一轮优化已再收掉 `_maybeAttachLatestSession()` 自动挂接链里的一次重复定位：
  在已知选中会话索引和最新 session id 的前提下，直接复用 `_updateConversationSettingsAtIndex(...)`
  完成 continue 绑定，再把 session detail / hydration / save / 状态文案回写复用到
  `_restoreSessionIntoConversationAfterBinding(...)` 后半段 helper，保持 auto-attach 的异步触发和最终单次保存语义不变。

- 第六十二轮优化已再收掉 `deleteConversation()` 删除后替代选中链里的一次包装读取：
  在删除后已经知道 replacement 会话索引的场景下，直接复用该索引同步 composer draft，
  并复用 `_markConversationReadAtIndex(...)` 做已读更新，保持删除后的单次保存和替代选中语义不变。

- 第六十三轮优化已再收掉 `_updateConversationSettingsAtIndex()` 在选中会话 draft 更新链里的一次包装读取：
  在当前就是选中会话且本轮已算出 `nextDraft` 的前提下，直接同步 `textController`，
  不再先进入 `_syncComposerWithSelectedConversation()` 再由选中态二次解析同一个 draft。

- 第六十四轮已先关闭 `_updateConversationSettingsAtIndex()` 在排序后的 hydration 目标失配风险：
  continue session reset 会先刷新 `updatedAt` 并触发排序，因此不能直接复用旧 `index`；
  当前改为在触发 hydration 前，基于 `conversationId` 在当前列表中重新稳定解析一次目标索引，
  再进入 `_ensureConversationHydratedAtIndex(...)`。

- 第六十五轮优化已再收掉 `ensureLoaded()` 末尾选中会话 hydration 触发链里的一次包装定位：
  在已经建立选中态并能直接拿到 `_selectedConversationIndex()` 的前提下，优先复用
  `_ensureConversationHydratedAtIndex(...)`，只把按 id 的 `_ensureConversationHydrated(...)`
  保留给兜底分支。
- 第六十六轮优化已再收掉 `handleAgentResultEvent()` 里结构化结果 done 分支的
  refresh / persist 尾链重复实现：
  `task_snapshot done` 与 `codexResult done` 现在复用同一个
  `_finalizeStructuredSessionRefresh(...)` helper，统一维护
  `refresh / 可选 history hydration / sort / save`
  这条共同尾链；request cleanup 和 notify 仍保留在各自调用点，避免扩大副作用边界。
- 第六十七轮优化已再收掉 `ensureLoaded()` 初始选中链里的两处包装读取：
  在已经拿到 `_selectedConversationIndex()` 的前提下，直接复用该索引完成首屏 draft 同步，
  并直接复用 `_markConversationReadAtIndex(...)` 完成首屏已读同步；
  仅把 `_syncComposerWithSelectedConversation()` 和 `_markConversationRead(...)`
  保留给兜底分支。
- 第六十八轮优化已再收掉 `resetDemoState()` 恢复选中链里的一次 composer 包装读取：
  在已经把 `_selectedConversationId` 设为恢复后的首个 demo 会话后，直接复用
  `_selectedConversationIndex()` 完成 draft -> `textController` 同步，
  仅把 `_syncComposerWithSelectedConversation()` 保留给兜底分支。
- 第六十九轮优化已再收掉 `selectConversation()` 主分支里的一次目标会话重复读取：
  在已经拿到 `nextSelectedIndex` 的前提下，先解析一次
  `nextSelectedConversation`，再复用这份对象完成 id / draft 读取；
  `nextSelectedIndex == -1` 的 fallback 分支仍保留原有包装入口。
- 第七十轮优化已再收掉 `ensureLoaded()` 当前不变量下的三条不可达兜底分支：
  在首屏会话列表与 `_selectedConversationId` 已稳定建立后，
  `selectedIndex` 分支直接承担首屏 draft / read / hydrate 入口，
  不再额外保留 `_syncComposerWithSelectedConversation()`、
  `_markConversationRead(...)` 和 `_ensureConversationHydrated(...)`
  这三条当前结构下不命中的回退分支。
- 第七十一轮优化已再收掉 `resetDemoState()` 当前不变量下的一条不可达 composer 兜底分支：
  在 demo 会话列表已重建且 `_selectedConversationId` 已显式指向首项后，
  `selectedIndex` 分支即可直接完成恢复后的 draft 同步，
  不再额外保留 `_syncComposerWithSelectedConversation()`
  这条当前结构下不命中的回退分支。
- 第七十二轮优化已再收掉 `deleteConversation()` 当前不变量下的两条不可达兜底分支：
  在删除成功后会话列表仍保持非空，且替代选中要么直接落到 `0`，要么继续复用
  `_selectedConversationIndex()` 的前提下，`replacementIndex` 分支即可直接完成
  删除后的 draft / read 同步，不再额外保留
  `_syncComposerWithSelectedConversation()` 和 `_markConversationRead(...)`
  这两条当前结构下不命中的回退分支。
- 第七十三轮优化已再收掉 `_updateConversationSettingsAtIndex()` 当前不变量下的一条
  不可达 hydration guard：
  在 helper 入口已经确认 `conversationId -> index` 有效，且本轮只做单会话替换与排序、
  不会删除目标会话的前提下，排序后重新解析出来的 `hydrationIndex`
  直接进入 `_ensureConversationHydratedAtIndex(...)`，
  不再额外保留 `hydrationIndex != -1` 这条当前结构下不命中的 guard。
- 第七十四轮优化已再收掉 `_maybeAttachLatestSession()` 当前不变量下的一条
  不可达 selected-index guard：
  在该 helper 只会从 `ensureLoaded()` 已建立非空会话列表和有效选中态之后进入的前提下，
  `_selectedConversationIndex()` 解析出的 `index` 直接进入首屏 auto-attach 判断，
  不再额外保留 `index == -1` 这条当前结构下不命中的 guard。
- 第七十五轮优化已再收掉 `ensureLoaded()` 当前不变量下的一组
  不可达 trailing hydration guard：
  在首屏会话列表、选中态、runtime catalogs 以及可选 latest-session auto-attach
  都已完成之后，末尾重解析出的 `selectedIndex` 直接进入
  `_ensureConversationHydratedAtIndex(...)`，
  不再额外保留 `selectedId != null` / `selectedIndex != -1`
  这两层当前结构下不命中的 guard。
- 第七十六轮优化已再收掉 `ensureLoaded()` 当前不变量下的一条
  不可达 initial selected-index guard：
  在首屏会话列表和 `_selectedConversationId` 已建立之后，
  `_selectedConversationIndex()` 解析出的 `selectedIndex`
  直接进入 draft / read 同步链，
  不再额外保留 `selectedIndex != -1` 这条当前结构下不命中的 guard。
- 第七十七轮优化已再收掉 `restoreSessionIntoConversation()` 入口里的一次
  重复会话定位：
  空 session reset 分支和真实 session restore 分支现在共用同一个
  `_conversationIndexById(conversationId)` 结果，
  不再在同一调用上下文里对同一 `conversationId` 重复扫描两次。
- 第七十八轮优化已再收掉结构化结果链里的重复 session 绑定实现：
  `_applyTaskSnapshot()` 与 `codexResult` 分支在拿到 `sessionId` 后，
  现在共用 `_bindSessionRefAtConversation(...)`，
  不再各自重复实现同一段 `conversationId -> index -> update settings`
  的 continue 绑定逻辑。
- 第七十九轮优化已再收掉 `task_snapshot` 与 `session_detail/page`
  链里的重复 timeline/rawEvents 存储实现：
  `_applyTaskSnapshot()` 与 `_applySessionDetail()` 现在共用
  `_storeTimelineAndRawEvents(...)`，
  不再各自重复实现同一段 `timeline/rawEvents -> conversation state map`
  的写回逻辑。
- 第八十轮优化已再收掉多条链里的重复 draft -> composer 同步实现：
  `ensureLoaded()`、`selectConversation()` 主分支、
  `_updateConversationSettingsAtIndex()`、`deleteConversation()`、
  `resetDemoState()` 现在共用 `_syncComposerDraft(...)`，
  不再各自重复实现同一段 `TextEditingValue` 同步逻辑。
- 第八十一轮优化已继续收掉 `createConversation()` 里的重复 composer 清空实现：
  新建会话后不再单独手写一段 `_syncingComposer + TextEditingValue('')`，
  改为直接复用 `_syncComposerDraft('')`，
  保持“新建后清空输入框并选中新会话”的现有语义不变。
- 第八十二轮优化已继续收掉 `selectConversation()` 主分支里一组分散的
  “目标索引已知后的副作用”实现：
  在已拿到 `nextSelectedIndex` 的前提下，composer draft 同步和已读同步
  现在共用 `_syncSelectedConversationSideEffects(...)`，
  但 fallback 分支以及“重复点击当前已选会话不主动重同步 composer”的
  现有兼容语义保持不变。
- 第八十三轮优化已继续收掉 `ensureLoaded()` 与 `deleteConversation()` 里
  一组同类的“目标索引已知后的副作用”实现：
  首屏初始化选中链与删除替代选中链现在也共用
  `_syncSelectedConversationSideEffects(...)`，
  但继续保留 `notifyRead: false` / `persistRead: false`
  的原参数语义，不改首屏初始化与删除后的兼容行为。
- 第八十四轮优化已继续收掉 `resetDemoState()` 当前不变量下的一条
  不可达 `selectedIndex` guard：
  在 demo 会话列表已重建且 `_selectedConversationId` 已显式指向首项后，
  `_selectedConversationIndex()` 当前应可稳定解析到有效索引，
  因而不再额外保留 `selectedIndex != -1` 这条当前结构下不命中的 guard。
- 第八十五轮优化已继续收掉三条 settings 薄包装入口里的重复
  `conversationId -> index -> _updateConversationSettingsAtIndex(...)`
  转发路径：
  `renameConversation()`、`toggleConversationPinned()`、
  `toggleConversationArchived()` 现在共用
  `_updateConversationSettingsById(...)`，
  但各自的标题校验、pin/archive 切换和缺失 id 直接返回语义保持不变。
- 第八十六轮优化已继续收掉公有 `updateConversationSettings()` 入口里的同类
  `conversationId -> index -> _updateConversationSettingsAtIndex(...)`
  转发路径：
  该入口现在也复用 `_updateConversationSettingsById(...)`，
  但缺失 id 直接返回、参数透传、保存与 hydration 语义保持不变。
- 第八十七轮优化已继续收掉 `_maybeAttachLatestSession()` 与
  `restoreSessionIntoConversation(sessionId != '')` 里的同类 continue session
  绑定实现：
  这两条链现在也共用 `_bindSessionRefAtConversation(...)`，
  但继续保留 `hydrateIfNeeded: false` / `persist: false`
  的原参数语义，不改空 session reset 与后续 restore/hydration 行为。
- 第八十八轮优化已继续收掉 `_maybeAttachLatestSession()` 当前已知索引场景下的
  一次重复 `conversationId -> index` 定位：
  自动挂接链现在直接复用 `_bindSessionRefAtIndex(...)`，
  而 `_bindSessionRefAtConversation(...)` 保留原有语义，仅内部改为复用该 helper。
- 第八十九轮优化已继续收掉 `restoreSessionIntoConversation(sessionId != '')`
  当前已知索引场景下的一次重复 `conversationId -> index` 定位：
  正常 session restore 链现在也直接复用 `_bindSessionRefAtIndex(...)`，
  保持 `hydrateIfNeeded: false` / `persist: false` 的原参数语义不变，
  不改空 session reset、restore 后半段和最终保存时序。
- 第九十轮优化已继续收掉 `toggleConversationPinned()` 与
  `toggleConversationArchived()` 当前已知索引场景下的一次重复
  `conversationId -> index` 定位：
  这两条 pin/archive 切换链现在直接复用 `_updateConversationSettingsAtIndex(...)`，
  保持 pinned / archived 取反、`lastReadAt` 写入、保存和通知时序不变。
- 第九十一轮优化已继续收掉 `selectConversation()` 当前无可选会话对象场景下的
  两条 no-op 包装调用：
  当 `nextSelectedConversation == null` 时，不再额外触发
  `_markConversationRead(...)` 与 `_ensureConversationHydrated(...)`
  这两条只会立即返回的无效查找链；同时删除随之失去引用的
  `_markConversationRead(...)`、`_ensureConversationHydrated(...)`、
  `_syncComposerWithSelectedConversation()` 三条私有包装，
  保留 composer 清空、通知和已有会话 fallback 语义不变。
- 第九十二轮优化已继续收掉 `agent_dashboard_page.dart` 展示层在同一 build
  作用域里的重复 by-id 状态读取：
  `_ConversationLauncher`、`_ConversationTile`、`_ConversationDetail`
  现在在局部先缓存 `statusLabel`、`statusDetail`、`unread`、`status`，
  再复用到 badge / hint / 文案渲染，不改 UI 文案、交互和状态判定语义。
- 第九十三轮优化已继续收掉 `_WorkspaceTopBar` 当前同一 build 作用域里的
  重复状态读取：
  顶部状态 badge 现在先在局部缓存 `status` 与 `statusLabel`，
  再复用到同一个 `_StatusBadge`，不改 badge 文案、颜色和 header 展示语义。
- 第九十四轮优化已继续收掉 `_ConversationRail` 列表渲染里当前 build 作用域的
  重复选中态读取：
  列表开始前先缓存 `selectedConversationId`，每个 `itemBuilder`
  直接复用该局部值判断 `selected`，不改列表布局、选中态语义和点击交互。
- 第九十五轮优化已继续收掉 `_SendButton` 当前 build 作用域里的一次
  by-id 包装状态读取：
  发送按钮现在先在局部缓存 `status`，再用与原先等价的
  `running / needsConfirmation` 判定计算 `busy`，
  不改按钮图标、颜色和点击语义。
- 第九十六轮优化已继续收掉 `_ConversationTile` 渲染链里的一层
  重复状态标签包装读取：
  tile 在已拿到 `status` 后，先通过
  `statusLabelForStatus(status)` 生成局部 `statusLabel`，
  再复用到 rich / compact 两条渲染分支，不改 badge 文案、颜色和点击语义。
- 第九十七轮优化已继续收掉 `_ConversationTile` rich / compact 分支里的
  unread 包装读取：
  tile 在外层先缓存 `unread`，再复用到两条展示分支，不改未读圆点、
  详情文案和点击语义。
- 第九十八轮优化已继续收掉 `_ConversationLauncher` 当前 build 作用域里的
  一次 `statusLabel` 包装状态读取：
  launcher 现在先在局部缓存 `status` 与 `statusLabel`，
  再复用到 subtitle 文案，不改 project/status 文案、未读数量和点击交互语义。
- 第九十九轮优化已继续收掉 `AgentDashboardDevShell` mock 窗口头里的
  一次 `statusLabel` 包装状态读取：
  dev shell 头部现在直接复用 `statusForConversation(...)` +
  `statusLabelForStatus(status)` 生成 subtitle 状态文案，
  不改 `'Ready'` fallback、project/status 文案和最小化/关闭交互语义。
- 第一百轮优化已继续收掉 overlay 浮窗头里的
  一次 `statusLabel` 包装状态读取：
  overlay 头部现在直接复用 `statusForConversation(...)` +
  `statusLabelForStatus(status)` 生成状态文案，
  不改 `'idle'` fallback、头部布局和拖拽交互语义。
- 第一百零一轮优化已继续收掉 shared dashboard 页与 harness 页
  `_ConversationTile` build 入口里的一次 `unread` 包装读取：
  tile 现在直接复用 `conversationHasUnreadForConversation(conversation)`，
  不改未读圆点、compact details 文案和点击交互语义。
- 第一百零二轮优化已继续收掉 shared dashboard 页与 harness 页
  `_ChatWorkspace` build 入口里的一次 `statusDetail` 包装读取：
  workspace 头部现在直接复用 `statusDetailForConversationObject(conversation)`，
  不改顶部状态说明文案、布局和交互语义。
- 第一百零三轮优化已继续收掉 shared dashboard 页与 harness 页
  `_InspectorPanel` build 入口里的一次 `statusDetail` 包装读取：
  inspector 现在直接复用 `statusDetailForConversationObject(conversation)`，
  不改状态说明文案、preview 展示和设置交互语义。
- 第一百零四轮优化已继续收掉 shared dashboard 页与 harness 页
  `_TimelinePanel` build 入口里的一次 `timeline` 包装读取：
  timeline 现在直接复用 `timelineForConversationObject(conversation)`，
  不改时间线空态文案、事件列表和展示语义。
- 第一百零五轮优化已继续收掉 shared dashboard 页与 harness 页
  `_SessionsPanel` build 入口里的一次 load-more 包装读取：
  sessions 面板现在直接复用 `canLoadMoreSessionHistoryForConversation(conversation)`，
  不改 session 列表展示和加载历史交互语义。
- 第一百零六轮优化已继续收掉 shared dashboard 页与 harness 页
  `_SendButton` build 入口里的一次 status 包装读取：
  发送按钮现在直接复用 `statusForConversationObject(conversation)`，
  不改 busy 判定、按钮图标和点击交互语义。
- 第一百零七轮优化已继续收掉 shared dashboard 页与 harness 页
  `_WorkspaceTopBar` build 入口里的一次 status 包装读取：
  top bar 现在直接复用 `statusForConversationObject(conversation)`，
  不改顶部 badge 文案、颜色和布局语义。
- 第一百零八轮优化已继续收掉 shared dashboard 页与 harness 页
  `_ConversationLauncher` build 入口里的一次 status 包装读取：
  launcher 现在直接复用 `statusForConversationObject(conversation)`，
  不改 subtitle 文案、布局和点击交互语义。
- 第一百零九轮优化已继续收掉 shared dashboard 页与 harness 页
  `_ConversationTile` build 入口里的一次 status 包装读取：
  tile 现在直接复用 `statusForConversationObject(conversation)`，
  不改状态文案、未读标记、rich/compact 布局和点击交互语义。
- 第一百一十轮优化已继续收掉 overlay 浮窗头里的一次 status 包装读取：
  overlay 头部现在直接复用 `statusForConversationObject(conversation)`，
  不改 `idle` fallback 文案、拖拽手势和窗口控制交互语义。
- 第一百一十一轮优化已继续收掉 desktop `runtime_io` 状态轮询停止条件里的一次
  status 包装读取：
  runtime_io 现在直接复用 `statusForConversationObject(conversation)`，
  不改轮询频率、bridge `status` 请求方式和停止条件语义。
- 第一百一十二轮优化已继续收掉 overlay 浮窗头里的一次 `statusLabel` 包装读取：
  overlay 头部现在直接复用 `statusLabelForConversationObject(conversation)`，
  不改 `idle` fallback 文案、拖拽手势和窗口控制交互语义。
- 第一百一十三轮优化已继续收掉 `_SendButton` build 入口里的一次 `busy` 包装判定：
  发送按钮现在直接复用 `isConversationBusyForConversation(conversation)`，
  不改按钮图标、颜色和点击交互语义。
- 第一百一十四轮优化已继续收掉 `_ChatWorkspace` 输入提示里的一次
  `needsConfirmation` 包装判定：
  输入提示现在直接复用
  `conversationNeedsConfirmationForConversation(conversation)`，
  不改提示文案本身、优先级和输入区交互配置。
- 第一百一十五轮优化已继续收掉 runtime 轮询停止条件里的一次终止判定包装：
  runtime web/io 现在直接复用
  `shouldStopStatusTrackingForConversation(conversation)`，
  不改轮询频率、bridge `status` 请求方式和终止条件语义。
- 第一百一十六轮优化已继续收掉 desktop `runtime_io` 调用点里的一次终止判定包装：
  runtime_io 现在直接复用
  `shouldStopStatusTrackingForConversation(conversation)`，
  不改轮询频率、bridge `status` 请求方式和终止条件语义。
- 第一百一十七轮优化已继续补齐 `rawEvents` 会话读取链里的对象级 helper：
  `rawEventsForConversation(conversationId)` 现在复用
  `rawEventsForConversationObject(conversation)`，
  同时空 session reset 的“已是空白会话”短路判定也改为复用
  `timelineForConversationObject(conversation)` 与
  `rawEventsForConversationObject(conversation)`，
  不改 `rawEvents` 写入来源、session reset 语义和 storage write 行为。
- 第一百一十八轮优化已继续收掉空 session reset 短路判定里的最后一处 paging 读取包装：
  `restoreSessionIntoConversation(sessionId: '')` 现在复用
  `canLoadMoreSessionHistoryForConversation(conversation)`，
  不改空白会话短路条件、session reset 语义、历史分页语义和 storage write 行为。
- 第一百一十九轮优化已继续收掉 `loadMoreSessionHistory()` 调用点里的 session
  cursor 读取包装：
  分页入口现在复用 `sessionNextCursorForConversationObject(conversation)`，
  不改分页加载顺序、空 cursor 直接返回语义、错误状态写入和 listener 行为。
- 第一百二十轮优化已继续收掉 `_hydrateRemainingSessionHistory()` paging loop
  里的 session cursor 读取包装：
  hydration loop 现在也复用
  `sessionNextCursorForConversationObject(_conversations[index])`，
  不改 hydration 分页顺序、cursor 为空退出语义、消息 merge 和 persist 时序。
- 第一百二十一轮优化已继续收掉 `_applySessionDetail()` 里的 session cursor
  字段解析包装：
  detail 写回分页状态时现在复用 `sessionNextCursorFromDetail(detail)`，
  不改 `next_cursor / nextCursor` 双字段兼容、分页恢复顺序和 cursor 生命周期语义。
- 第一百二十二轮优化已继续收掉 `codexResult` 分支里的 timeline/rawEvents
  容器读写包装：
  `codexResult` 事件现在复用 `timelineForConversation(...)`、
  `rawEventsForConversation(...)` 和 `_storeTimelineAndRawEvents(...)`，
  不改 done/failed 阶段判断、raw event 内容和后续 session refresh 语义。
- 第一百二十三轮优化已继续收掉 `task_snapshot` 链里的 session id
  字段解析包装：
  `task_snapshot` 事件现在复用 `taskSnapshotSessionIdFromDetail(detail)`，
  不改 `sessionId / session_id` 双字段兼容、snapshot session 绑定、
  done refresh、通知次数和持久化语义。
- 第一百二十四轮优化已继续收掉 `codexResult` 分支里的 error
  字段解析包装：
  `codexResult` timeline 生成现在复用 `codexResultErrorText(detail)`，
  不改 failed/done 阶段判断、错误摘要、raw event 内容和后续 refresh 语义。
- 第一百二十五轮优化已继续收掉 `codexResult` 分支里的 `sessionId`
  字段解析包装：
  `codexResult` 的 session 绑定与 done refresh 入口现在复用
  `codexResultSessionIdFromDetail(detail)`，
  不改空 sessionId 跳过语义、非空 sessionId 的 refresh、通知和 request cleanup 语义。
- 第一百二十六轮优化已继续收掉 `task_snapshot` envelope 里的 nested detail map
  解析包装：
  `task_snapshot` 的 detail map 读取现在复用 `taskSnapshotDetailFromEnvelope(detail)`，
  不改 nested detail 存在性判定、snapshot session 绑定、done refresh、通知和持久化语义。
- 第一百二十七轮优化已继续收掉结构化事件 envelope 里的 `conversationId`
  字段解析包装：
  结构化事件的 detail `conversationId` 读取现在复用
  `detailConversationIdFromEnvelope(detail)`，
  不改 request map、detail conversation、active request 和 selected fallback 的路由优先级语义。
- 第一百二十八轮优化已继续收掉结构化 detail envelope 里的 `kind`
  字段解析包装：
  `handleAgentResultEvent()` 与 `_applyDetailJson()` 现在共用
  `detailKindFromEnvelope(detail)`，
  不改 `sessions / skills / session_detail / session_page / task_snapshot`
  的既有分发语义。
- 第一百二十九轮优化已继续收掉结构化 detail envelope 里的 `item`
  map 解析包装：
  `_applyDetailJson()` 的 `session_detail / session_page` 与 `task_snapshot`
  分支现在共用 `detailItemFromEnvelope(detail)`，
  不改 session 明细写回与 task snapshot 写回语义。
- 第一百三十轮优化已继续收掉结构化 detail envelope 里的 `items`
  列表解析包装：
  `_applyDetailJson()` 的 `sessions` 与 `skills` 分支现在共用
  `detailItemsFromEnvelope(detail)`，
  不改 session summary / skill catalog 装载与 loaded 标记语义。
- 第一百三十一轮优化已继续收掉 `handleAgentResultEvent()` 里一组结构化
  detail kind 分类判定：
  `sessions / session_detail / session_page / skills`
  现在共用 `isStructuredDetailCatalogOrSessionKind(kind)`，
  不改 request cleanup、通知时机和 fallback 语义。
- 第一百三十二轮优化已继续收掉 `task_snapshot done` 的一组重复 suppress
  布尔判定：
  `suppressTaskSnapshotHydration` 与 `suppressTaskSnapshotPersist`
  现在共用 `shouldSuppressTaskSnapshotHydrationOrPersist(...)`，
  不改 detail-only refresh、通知与持久化语义。
- 第一百三十三轮优化已继续收掉 `codexResult` 分支里一组
  `status != 'done'` 重复布尔判定：
  `hydrateIfNeeded` 与 `persist` 现在共用
  `shouldBindCodexResultSessionWithoutImmediateRefresh(status)`，
  不改运行中 session 绑定、done refresh、通知与 cleanup 语义。
- 第一百三十四轮优化已继续收掉 `task_snapshot` 分支里一组
  “非 `running / started` 时 cleanup request”状态判定：
  request cleanup 入口现在共用
  `shouldCleanupTaskSnapshotRequestForStatus(status)`，
  不改 running / started 保留 request 映射、
  failed / done / cancelled cleanup、done refresh、通知与 fallback 路由语义。
- 第一百三十五轮优化已继续收掉结构化 session refresh 入口里一组
  `status == 'done'` 重复布尔判定：
  `task_snapshot` 与 `codexResult` 的 refresh 入口现在共用
  `shouldRefreshStructuredSessionDetailForStatus(status)`，
  不改 done refresh、failed 不触发 finalize refresh、
  request cleanup、session 绑定和通知语义。
- 第一百三十六轮优化已继续收掉结构化结果链里一组
  `requestId -> conversationId` cleanup 的重复副作用包装：
  `task_snapshot`、`codexResult + done` 与
  `sessions / session_detail / session_page / skills`
  分支现在共用 `clearRequestConversationMapping(requestId)`，
  不改 cleanup 时机、fallback 路由、done refresh 和通知语义。
- 第一百三十七轮优化已继续收掉 `handleAgentResultEvent()` 里一组
  `_activeRequestConversationId` 清理时机的终态状态判定：
  active request 清理入口现在共用
  `shouldClearActiveRequestConversationForStatus(status)`，
  不改 `done / failed / cancelled` 的清理时机、
  plain 结果路由、request cleanup、done refresh 和通知语义。
- 第一百三十八轮优化已继续收掉 `_applyDetailJson()` 里一组
  `session_detail / session_page` 的 kind 分类判定：
  session 明细分发入口现在共用
  `isStructuredSessionDetailOrPageKind(kind)`，
  不改 session 明细写回、older messages append、
  `nextCursor` 恢复和通知语义。
- 第一百三十九轮优化已继续收掉 status recovery 链里一组
  `_statusRecoveryAttempts.remove(requestId)` 的 cleanup 副作用包装：
  普通 runtime 结果路径与 `_recoverTaskStatus()` 的 fallback / catch fallback
  路径现在共用 `clearStatusRecoveryAttempt(requestId)`，
  不改 bridge transport failure 判定、deferred recovery、
  fallback 路由和 failed/done 状态展示语义。
- 第一百四十轮优化已继续收掉 `_recoverTaskStatus()` 里一组
  status recovery attempt 有效性守卫判定：
  延迟恢复、deferred query 和 catch fallback
  三处守卫现在共用
  `isCurrentStatusRecoveryAttempt(requestId: ..., attempt: ...)`，
  不改 attempt 计数、延迟查询顺序、cleanup 时机和 fallback 路由语义。

### D. UX / 联调任务

- [ ] 明确首屏默认会话挂接策略
- [ ] 明确“加载更多历史”交互
- [ ] 明确任务状态展示模型
- [ ] 为后续气泡状态展示预留统一事件模型

## 推荐执行顺序

### Phase 1

- 定义状态权威源
- 收敛 push / poll 关系

### Phase 2

- 优化 Rust bridge session 读取路径
- 引入 index/path cache

### Phase 3

- 拆 Flutter `AgentDashboardModel`
- 将 hydration 与 UI 状态解耦

### Phase 4

- 调整首屏恢复策略
- 补齐资源清理和并发控制

## 本轮不做的事

本轮明确不执行：

- 不做实际性能优化代码改造
- 不做 Rust 全量重写
- 不做 Zig 版本探索或迁移
- 不做 bridge async 化落地

## 备注

当前代码编译验证结论：

- `cargo check -q --bin rustdesk --features flutter` 已通过
- `flutter analyze` 已通过

因此当前主要问题是结构和运行时路径，而不是基本可编译性。
