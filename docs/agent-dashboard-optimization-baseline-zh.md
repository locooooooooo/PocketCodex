# Agent Dashboard / Codex Bridge 优化前基线

更新时间：2026-06-06

## 目的

这份文档用于冻结当前 `Agent Dashboard`、`Codex Agent Bridge`、`Web Harness`
在优化前的真实功能边界，作为后续性能优化和结构重构的回归对照基线。

本阶段只记录现状，不修改运行逻辑。

## 基线范围

本次基线只覆盖当前与移动端 Agent Dashboard 直接相关的三层：

1. Rust bridge API 与任务状态模型
2. Flutter dashboard model / runtime transport
3. Web-first 调试 harness 与 live debug bridge

不在本轮基线范围内的内容：

- RustDesk 原生远控核心功能
- 上游通用 Flutter 页面
- 非 Agent Dashboard 相关的打包或发布流程

## 基线冻结点

- 最近一轮已落地功能提交：`f6f7da2` `feat: land agent dashboard bridge sync and audit plan`
- 当前工作树仅继续补充 README 和优化前基线文档，不引入运行逻辑变化

## 当前功能模块

### 1. Rust bridge API 面

当前 bridge 已经提供以下能力，且是 dashboard 侧的主数据入口：

- `GET /health`
- `GET /agent/config`
- `POST /agent/run`
- `POST /agent/confirm`
- `POST /agent/cancel`
- `GET /agent/tasks/:id`
- `GET /agent/sessions`
- `GET /agent/sessions/:id`
- `GET /agent/sessions/:id/page`
- `GET /agent/skills`
- `POST /agent/skills`
- `PUT /agent/skills/:id`
- `DELETE /agent/skills/:id`
- `POST /agent/skills/sync`
- `POST /agent/voice/transcribe`
- `POST /agent/voice/run`

主要证据：

- `src/agent_bridge.rs`
- `src/server/connection.rs`

### 2. 任务状态与快照模型

当前任务状态模型已经具备：

- `PENDING` 待确认任务表
- `TASKS` 任务快照表
- `detail_json` 结构化附加数据
- `timeline` 时间线摘要
- `raw_events` 原始事件片段
- `/agent/run` 异常后的 task status 恢复路径

这意味着 dashboard 已经不只是拿一段文本，而是可以基于任务快照恢复状态。

主要证据：

- `src/agent_bridge.rs`

### 3. 桌面 Codex 会话同步

当前 bridge 和 web debug bridge 都已经可以读取桌面 Codex session 历史：

- 会话列表来自 `session_index.jsonl`
- 会话详情来自真实 session `jsonl`
- 支持首屏详情和旧历史分页
- dashboard 可将真实 session 恢复到当前 conversation

当前双端一致性的主方向已经不是本地自维护一份聊天记录，而是通过
`/agent/sessions`、`/agent/sessions/:id`、`/agent/sessions/:id/page`
对接桌面 Codex 历史。

主要证据：

- `src/agent_bridge.rs`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`
- `tools/agent_dashboard_harness/debug-bridge/server.mjs`

### 4. Flutter runtime transport

当前 runtime transport 分成两条路径：

- `agent_dashboard_runtime_io.dart`
  - 有活跃 RustDesk 远端会话时，通过远端 session 发 envelope
  - 在被控桌面本地调试时，直接访问 `http://127.0.0.1:17321`
- `agent_dashboard_runtime_web.dart`
  - Web harness 直接访问 bridge
  - live 模式默认接 `http://127.0.0.1:17331`

这一层已经实现的能力包括：

- run / confirm / cancel
- sessions list / detail / page
- skills list / upsert / delete / sync
- voice transcribe
- task status polling

主要证据：

- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`

### 5. Flutter dashboard model

当前 `AgentDashboardModel` 同时承担以下职责：

- conversation 列表与元数据
- `threadMode`、`profile`、`sessionRef`
- `selectedSkillIds`
- `pinned`、`archived`
- `draft`
- `includeConversationHistory`
- `includeTerminalContext`
- requestId 到 conversation 的归属映射
- 结构化结果处理
- session restore / hydration / 分页追加
- task status recovery
- skills catalog 本地状态

当前已具备的关键行为：

- 可以将指定 session 恢复进当前 conversation
- 可以在任务完成后重新同步 session 内容
- 可以在 bridge 结果不完整时主动补查 task status
- 可以处理结构化 agent result，而不只靠文本消息

主要证据：

- `flutter/lib/models/agent_dashboard_model.dart`

关键方法：

- `loadSessions()`
- `loadSessionDetail()`
- `requestTaskStatus()`
- `restoreSessionIntoConversation()`
- `handleAgentResultEvent()`

### 6. Web-first 调试链路

当前 dashboard 调试已经明确分成两种模式：

- `tools/agent_dashboard_harness/run-web.ps1`
  - mock-only
  - 适合纯 UI / UX 调整
- `tools/agent_dashboard_harness/run-web-live.ps1`
  - live 模式
  - 启动独立 debug bridge：`127.0.0.1:17331`
  - 读取真实 `~/.codex` session
  - 将 run / task / skills / voice 请求代理到本机 RustDesk bridge `127.0.0.1:17321`

这个 harness 与主工程是调试隔离的，但 dashboard 核心代码仍然共用
`flutter/lib/` 作为单一事实源。

主要证据：

- `tools/agent_dashboard_harness/README.md`
- `tools/agent_dashboard_harness/run-web.ps1`
- `tools/agent_dashboard_harness/run-web-live.ps1`
- `tools/agent_dashboard_harness/debug-bridge/server.mjs`

## 优化前验证清单

后续任何优化完成后，至少需要逐项回归下面这些行为：

1. 会话列表可正常加载，且按最近更新时间排序
2. 选中某个 session 后，可恢复到对应 conversation
3. 旧历史分页可继续向前加载，不丢消息顺序
4. live web harness 可读到真实桌面 Codex session
5. mock web harness 仍可独立用于纯 UI 调试
6. 本地 bridge `run / confirm / cancel / tasks` 路径可用
7. skills 列表、增删改、sync 路径可用
8. voice transcribe 路径可用
9. 任务完成后，conversation 的 `sessionRef` 能同步到真实 session
10. 结构化 agent result 和 task snapshot 仍可驱动状态恢复

## 优化前后对比模板

后续每一轮优化都应至少补一份以下格式的对比记录：

| 模块 | 优化前行为 | 本轮改动 | 回归结果 | 风险备注 |
| --- | --- | --- | --- | --- |
| sessions list/detail | 通过 bridge 读取真实 Codex sessions |  |  |  |
| task snapshot | `TASKS` 提供 detail/timeline/raw_events |  |  |  |
| dashboard hydration | `restoreSessionIntoConversation()` 恢复并补历史 |  |  |  |
| runtime transport | io/web 两套 runtime 指向统一 bridge source |  |  |  |
| web harness | mock/live 双模式 |  |  |  |

## 第一轮优化记录

### 目标

第一轮只收敛 Rust bridge 的 session 读取路径，不改外部接口，不改 Flutter
调用方式，不改 Web harness 协议。

### 本轮改动

模块：`sessions list/detail`

- 为 `session_index.jsonl` 增加进程内缓存
- 缓存键使用文件路径、修改时间和文件长度
- 为 `session_id -> session file path` 增加进程内缓存
- 当缓存的 session 文件已失效时，自动清理并重新扫描
- 补充 `updated_at` / `updatedAt` 双格式兼容
- 修正 session file cache 查询中的同锁重入死锁点

主要代码：

- `src/agent_bridge.rs`

### 优化前行为

- 每次 `GET /agent/sessions` 都重新读取并解析 `session_index.jsonl`
- 每次 `GET /agent/sessions/:id` / `page` 都重新读取 index
- 每次详情分页都递归扫描 `~/.codex/sessions` 找目标文件

### 优化后行为

- index 文件未变化时，重复请求直接复用内存中的 session 列表
- session 文件路径命中缓存时，不再重复递归扫描目录
- session 文件路径失效后，仍可自动回退到重新扫描，不改变对外行为
- 仍保持原有 REST 路径、返回结构、分页语义不变

### 回归验证

已完成：

1. `cargo check -q --bin rustdesk --features flutter`
2. `cargo test -q parse_codex_session_index_sorts_and_fills_missing_title --lib -- --test-threads=1 --nocapture`
3. `cargo test -q load_codex_session_index_invalidates_cache_on_file_change --lib -- --test-threads=1 --nocapture`
4. `cargo test -q find_session_file_cached_recovers_when_cached_path_disappears --lib -- --test-threads=1 --nocapture`

额外验证结论：

- 本机真实 `~/.codex/session_index.jsonl` 当前使用的是 `updated_at` 字段，已确认并兼容
- 本机 Windows 环境下，如果并发启动多个 `cargo test`，会因为 `lib test` 产物被残留测试进程占用而出现 `LNK1104`；串行执行并清理残留 `librustdesk-*.exe` 进程后，目标用例可正常通过

### 风险备注

- 这轮只减少重复读取和目录扫描，没有处理“整文件读入后分页”的成本
- Flutter 首屏自动 hydration 仍然存在
- Web debug bridge `server.mjs` 仍保留自己的一套 session 读取实现，尚未同步到同类缓存策略

## 第二轮优化记录

### 目标

第二轮继续收敛 Rust bridge 的 session detail/page 路径，把“整文件读入后分页”
改为真正的按行索引分页读取，保持 REST 路径和返回结构不变。

### 本轮改动

模块：`sessions detail/page`

- 为 session 文件增加按行偏移索引缓存
- 索引缓存键使用文件路径、修改时间和文件长度
- `load_codex_session_detail()` 改为先计算页范围，再按 span 回读目标行
- 空白行仍被忽略，消息顺序和 `next_cursor` 语义保持不变

主要代码：

- `src/agent_bridge.rs`

### 优化前行为

- 每次详情分页都会整文件读入内存
- 再通过 `raw.lines()` 生成全部行切片后做页截取

### 优化后行为

- 先建立 session 行索引，只保留非空行的 byte span
- 详情分页仅回读当前页需要的行
- 不再为每次 detail/page 请求构建整份文本切片

### 回归验证

已完成：

1. `cargo test -q load_session_line_index_ignores_blank_lines --lib -- --test-threads=1 --nocapture`
2. `cargo test -q load_codex_session_detail_reads_requested_page_without_full_text_split --lib -- --test-threads=1 --nocapture`
3. `cargo check -q --bin rustdesk --features flutter`

### 风险备注

- 当前仍然会解析当前页内的每一条 JSON 行，但已经不再整文件读入
- Web debug bridge `server.mjs` 仍未同步到相同的行索引分页策略
- Flutter 侧自动 hydration 行为仍未收敛，长会话恢复成本还会继续受前端策略影响

## 第三轮优化记录

### 目标

第三轮只收敛 Rust bridge 内部 `TASKS` 快照更新路径，减少高频状态更新时的
clone 成本，不改 task 对外结构，不改 REST 路径，不改 Flutter 消费方式。

### 本轮改动

模块：`task snapshot`

- `upsert_task()` 改为基于 `HashMap::entry()` 原地更新已有任务
- 已存在任务不再在每次更新时整体 clone `timeline`
- 已存在任务不再在每次更新时整体 clone `raw_events`
- 未提供新 `detail_json` 时，继续保留旧值
- 保留既有 `started_at`、`cancel_requested` 语义不变
- 继续沿用原有 timeline / raw_events 的上限裁剪策略

主要代码：

- `src/agent_bridge.rs`

### 优化前行为

- 每次 `upsert_task()` 都会重新取出旧 task
- 旧 task 的 `timeline` / `raw_events` 会被 clone 后再重建
- 未传入 `detail_json` 时，也会通过读取旧 task 再生成新结构
- 高频状态更新时，task store 的分配和复制成本偏高

### 优化后行为

- 已存在 task 在 map 内原地更新
- `timeline` / `raw_events` 仅做必要的 push 和裁剪，不再整体 clone
- `detail_json` 仅在有新值时覆写，否则保持原值
- `started_at`、`cancel_requested`、REST 返回结构和状态恢复语义保持不变

### 回归验证

已完成：

1. `cargo test -q upsert_task_updates_existing_task_in_place --lib -- --test-threads=1 --nocapture`
2. `cargo test -q upsert_task_bounds_timeline_and_raw_events_without_resetting_task --lib -- --test-threads=1 --nocapture`
3. `cargo test -q parse_codex_session_index_sorts_and_fills_missing_title --lib -- --test-threads=1 --nocapture`
4. `cargo test -q load_codex_session_index_invalidates_cache_on_file_change --lib -- --test-threads=1 --nocapture`
5. `cargo test -q find_session_file_cached_recovers_when_cached_path_disappears --lib -- --test-threads=1 --nocapture`
6. `cargo test -q load_session_line_index_ignores_blank_lines --lib -- --test-threads=1 --nocapture`
7. `cargo test -q load_codex_session_detail_reads_requested_page_without_full_text_split --lib -- --test-threads=1 --nocapture`
8. `cargo check -q --bin rustdesk --features flutter`

额外验证结论：

- 这轮新增测试覆盖了已有 task 原地更新时 `started_at`、`cancel_requested`、
  `detail_json` 保持不变的关键语义
- 这轮新增测试覆盖了 timeline / raw_events 达到上限后的裁剪窗口语义，确认没有因为
  原地更新而重置窗口
- 第二轮的 session detail/page 用例复跑通过，确认第三轮没有破坏已有分页读取路径

### 风险备注

- 当前 `TASKS` 仍然是全局 `Mutex<HashMap<...>>`，只是降低了单次更新时的复制成本
- `timeline.remove(0)` / `raw_events.remove(0)` 仍然是线性成本；如后续需要继续优化，
  再评估是否换成更合适的数据结构
- task 状态的 push / poll / snapshot 权责边界仍未收敛，这一轮不处理

## 第四轮优化记录

### 目标

第四轮只收敛 Rust bridge 的 voice 临时音频文件生命周期，减少长期运行时的垃圾文件累积，
不改 voice API 路径，不改返回字段，不改 STT 触发条件。

### 本轮改动

模块：`voice transcribe`

- base64 音频仍然会落盘为 bridge 本地 wav 文件
- 在生成新的 bridge voice 临时文件前，清理同目录下过期的 `voice-*.wav`
- 外部显式传入的 `audio_path` 继续直接使用，不参与 bridge 临时文件清理
- 非 `voice-*.wav` 文件不会被误删

主要代码：

- `src/agent_bridge.rs`

### 优化前行为

- `audio_base64` 每次都会落成新的 `voice-*.wav`
- bridge 本地目录没有任何清理策略
- 无论 voice 是否配置完成、转写是否成功，历史临时文件都会持续累积

### 优化后行为

- `audio_base64` 仍然落成本地 wav，`audioPath` 返回语义保持不变
- 在当前文件写入前，会清理同目录下超过 1 小时的旧 `voice-*.wav`
- 显式 `audio_path` 模式完全不变，不会触发 bridge 本地音频清理
- 仅收敛 bridge 自己生成的临时文件，不扩大到用户显式提供的音频路径

### 回归验证

已完成：

1. `cargo test -q materialize_voice_audio_cleans_stale_bridge_temp_files --lib -- --test-threads=1 --nocapture`
2. `cargo test -q materialize_voice_audio_keeps_explicit_audio_path_untouched --lib -- --test-threads=1 --nocapture`
3. `cargo test -q materialize_voice_audio_base64_writes_current_voice_file --lib -- --test-threads=1 --nocapture`
4. `cargo check -q --bin rustdesk --features flutter`

额外验证结论：

- 当前文件的 `audioPath` 仍然保持可见，不因为清理策略而提前失效
- 清理逻辑限定在 `voice-*.wav` 命名范围内，普通旁路文件不会被误删
- 显式 `audio_path` 仍然走原路径，不引入额外副作用

### 风险备注

- 目前清理阈值固定为 1 小时，是保守策略，不保证立即回收所有旧文件
- 当前未把“过期阈值”做成配置项，这一轮不扩 scope
- `audioPath` 仍然会暴露桥接目录中的当前临时文件路径，只是减少长期堆积

## 第五轮优化记录

### 目标

第五轮只收敛远端显式 `status` 请求路径里的重复 bridge 自查，不改 Flutter 侧
polling 逻辑，不改 bridge 主响应结构，不改 task snapshot 的对外协议形状。

### 本轮改动

模块：`task status / protocol response`

- 增加 `task_snapshot_detail_json_for_response()` 辅助函数
- `send_agent_protocol_response()` 改为委托给带 `task_override` 的内部实现
- `spawn_agent_status()` 在已经拿到 `send_task_status_request()` 返回 task 后，
  直接复用该 task 生成 snapshot detail_json
- 远端显式 `status` 路径不再在发送协议响应时额外重复查询一次 `/agent/tasks/{id}`

主要代码：

- `src/server/connection.rs`

### 优化前行为

- 远端显式 `status` 会先调用一次 `send_task_status_request(&request_id)`
- 然后 `send_agent_protocol_response()` 会再次调用
  `send_task_status_request(&response.request_id)` 生成 snapshot
- 同一个显式状态请求在 bridge 内部会发生两次 task 查询

### 优化后行为

- 远端显式 `status` 仍先查询一次 task，并继续返回同样的主响应字段
- 生成 task snapshot 时优先复用已拿到的 task，不再重复查询 bridge task store
- 非显式 `status` 的其他调用路径仍保持原有行为
- `AgentResult` 主响应 + `task_snapshot` 补发的协议形状保持不变

### 回归验证

已完成：

1. `cargo test -q task_snapshot_detail_json_for_response_uses_task_override --lib -- --test-threads=1 --nocapture`
2. `cargo test -q task_snapshot_detail_json_for_response_skips_non_snapshot_status --lib -- --test-threads=1 --nocapture`
3. `cargo check -q --bin rustdesk --features flutter`
4. `dart analyze flutter/lib/models/agent_dashboard_model.dart flutter/lib/models/agent_dashboard_runtime_io.dart flutter/lib/models/agent_dashboard_runtime_web.dart`

额外验证结论：

- 新增单测直接覆盖“有 task override 时不再依赖二次查询”的 helper 语义
- 非 snapshot 状态不会额外拼装 detail_json，避免扩大协议副作用
- 当前轮次没有修改 Flutter runtime 的 poll / recovery 路径

### 风险备注

- 这轮只减少 bridge 侧一处重复查询，不等于已经完成状态链路收敛
- Flutter runtime 仍会在需要时继续主动轮询 task status
- bridge 仍会继续发送主响应 + snapshot 双结果；是否进一步合并协议职责，保留到后续轮次

## 第六轮优化记录

### 目标

第六轮只收敛 Flutter `status recovery` 在 transport failure 场景下的一处重复补查，
不改 runtime poller 的存在方式，不改 bridge 协议，不改失败兜底文案和最终 fallback 行为。

### 本轮改动

模块：`runtime status recovery`

- 在 `AgentDashboardRuntime` 增加 `hasActiveStatusTracking(requestId)` 能力
- io / web runtime 直接复用现有 `_statusPollers` 暴露“当前请求是否已被 runtime 跟踪”
- `handleAgentResultEvent()` 在识别到 bridge transport failure 后：
  - 若 runtime 已有活跃 tracking，则不再立刻发起一次额外 `requestTaskStatus()`
  - 改为先保持“Recovering task status...”状态，等待现有 poller 推进
  - 只有等待窗口后仍未恢复时，才走原有 fallback 查询 / 失败兜底

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`

### 优化前行为

- 当收到 `failed + Failed to send /agent/run to codex bridge` 事件时，
  `AgentDashboardModel` 会立即启动 `_recoverTaskStatus()`
- 如果 runtime 侧此时已经有 `_statusPollers` 在按 2 秒轮询，
  model 仍会额外立刻主动打一次 `requestTaskStatus()`
- transport failure 恢复阶段会形成“runtime poller + model 即时补查”叠加

### 优化后行为

- transport failure 事件仍然进入“Recovering task status...”状态
- 如果 runtime 已有活跃 tracking，则优先复用现有 poller，不再立刻重复补查
- 如果 runtime 没有活跃 tracking，仍保持原有“立即请求一次 task status”的行为
- 等待窗口结束后，如仍未恢复，仍会继续走原有 fallback 查询 / 失败兜底，不改变最终容错语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- runtime 已有活跃 tracking 时，不会立即调用 `requestTaskStatus()`
- runtime 没有活跃 tracking 时，仍会立即调用 `requestTaskStatus()`

### 风险备注

- 这轮只减少 transport failure 场景下的一次即时补查，不等于 runtime status recovery 已收口完成
- runtime poller 仍然存在，bridge 主响应和 snapshot 双结果也仍然存在
- 当前等待窗口仍固定为 4 秒，未引入新的配置项

## 第七轮优化记录

### 目标

第七轮只收敛 deferred recovery 在等待窗口里的冗余继续执行，不改 transport failure
判定条件，不改 runtime poller，不改成功/失败最终状态语义。

### 本轮改动

模块：`runtime status recovery`

- `handleAgentResultEvent()` 在收到带 `requestId` 的结构化结果后，
  会先清理该 request 对应的恢复尝试标记
- 这样一来，如果等待窗口期间已经收到了新的 `running` / `done` / `failed`
  结构化状态，之前挂起的 `_recoverTaskStatus()` 就会在后续检查中自动退出
- 不再让旧的 deferred recovery 在已有新状态推进后继续补发一次多余查询或 fallback

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- transport failure 触发 deferred recovery 后，会记录一次 `_statusRecoveryAttempts`
- 即使等待窗口期间已经收到新的结构化 `running` 事件，
  旧的 deferred recovery 仍可能继续走到后续检查 / 补查分支
- 这会让“已经被新状态推进的恢复协程”在后台继续占着一次恢复尝试

### 优化后行为

- 只要该 request 收到新的结构化结果事件，就先清理对应的恢复尝试标记
- 挂起中的 deferred recovery 检查到 attempt 已失效后，会直接退出
- recovery 成功后的 completed/failed 语义保持不变
- transport failure 的 UI 文案和 fallback 入口保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 等待窗口期间收到新的结构化 `running` 事件后，deferred recovery 不会再继续触发额外补查
- 恢复成功后，最终状态仍然会更新到 `completed`

### 风险备注

- 这轮只收敛了等待窗口内“旧恢复协程继续执行”的冗余，不等于整条 status recovery 链已经收口
- runtime poller、bridge snapshot 双结果和 4 秒固定等待窗口仍然保留
- requestId / conversationId / sessionRef 的整体职责边界还未重构

## 第八轮优化记录

### 目标

第八轮只收敛 `handleAgentResultEvent()` 普通消息分支的一次重复 `notifyListeners()`，
不改消息文本，不改状态写入，不改保存行为。

### 本轮改动

模块：`event handling / listener notifications`

- 普通消息分支仍通过 `_appendMessage()` 追加 assistant 消息
- `_appendMessage()` 本身已经会触发保存和 `notifyListeners()`
- 去掉外层紧跟着的第二次 `notifyListeners()`，避免同一事件造成一次额外 rebuild

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 普通结构化结果走不到 `detail_json` 快速返回分支时，会进入普通消息分支
- 该分支先调用 `_appendMessage()`，内部已经 `notifyListeners()`
- 随后外层还会再调用一次 `notifyListeners()`
- 同一条普通 agent 结果会触发两次连续通知

### 优化后行为

- 普通消息仍然照常追加到 conversation
- conversation 状态仍然照常更新到 `running / done / failed / needsConfirmation`
- 保存行为不变
- 同一条普通 agent 结果只保留 `_appendMessage()` 内部那一次通知

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 普通 agent 结果会追加一条消息
- 普通消息分支只触发一次 listener notification
- 最终状态仍会正常更新到 `completed`

### 风险备注

- 这轮只减少普通消息分支的一次重复通知，不等于 `handleAgentResultEvent()` 整体副作用已经最小化
- detail_json 分支里的 `updateConversationSettings()`、session refresh、额外通知仍然存在
- 长会话恢复和状态职责边界问题仍然保留到后续轮次

## 第九轮优化记录

### 目标

第九轮只收敛 `handleAgentResultEvent()` 在结构化状态结果路径里的一处重复 map 操作，
不改 recovery 语义，不改状态判定，不改 UI 表现。

### 本轮改动

模块：`runtime status recovery`

- 原实现会在结构化结果到达后：
  - 先判断 `requestId` 是否在 `_statusRecoveryAttempts` 里
  - 再按状态再次 `remove(requestId)`
- 现在统一收成“只要当前事件带 `requestId`，就直接清理一次恢复尝试”
- 避免同一热路径里重复做 `containsKey + remove + remove`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 结构化结果到达时，会先查一次 `_statusRecoveryAttempts.containsKey(requestId)`
- 然后无论状态是不是 `running` / `started`，后面仍可能再次 `remove(requestId)`
- 同一路径里存在一次无收益的重复 map 操作

### 优化后行为

- 结构化结果只要带 `requestId`，统一直接清理一次恢复尝试
- `running` 结构化结果仍能正确终止旧恢复协程
- `done/failed/cancelled` 结构化结果仍保持原有恢复收口语义
- 对 conversation 状态、消息和 UI 表现没有变化

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `running` 状态结果仍会清掉立即恢复尝试
- deferred recovery 的既有取消语义保持不变
- 恢复成功后仍然会更新到 `completed`

### 风险备注

- 这轮只是热路径里的微型去冗余，不影响更大的状态链路职责问题
- `task_snapshot` / `codexResult` 分支的通知叠加与 session refresh 链路仍未收口
- runtime poller、bridge snapshot 双结果和固定等待窗口仍然保留

## 第十轮优化记录

### 目标

第十轮只收敛 detail 分支里对空 `requestId` 的无效 map 清理，不改 request 归属逻辑，
不改 detail 处理结果，不改通知行为。

### 本轮改动

模块：`requestId -> conversation cleanup`

- `task_snapshot` 分支在结束时仅在 `requestId` 非空时才清理 `_requestToConversation`
- `codexResult` 的 `done` 分支同样仅在 `requestId` 非空时再清理
- `sessions / session_detail / session_page / skills` 分支也加上同样的空值守卫

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 多个 detail 分支都会无条件执行 `_requestToConversation.remove(requestId)`
- 当 `requestId` 本身就是空字符串时，这次 `remove('')` 没有实际收益
- 热路径里会出现多次无效 map 写操作

### 优化后行为

- 只有在 `requestId` 非空时，才会执行 `_requestToConversation.remove(requestId)`
- 空 `requestId` 的 detail 事件仍照常更新 skills / sessions / session detail 数据
- request 归属逻辑、事件通知和 UI 表现不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 空 `requestId` 的 `skills` detail 事件仍会正常更新 skill catalog
- 事件通知次数保持正常

### 风险备注

- 这轮只是 request 映射表上的微型去冗余，不触碰更大的 request 归属边界
- `_requestToConversation` 的生命周期管理仍然分散在多个分支里，后续如要继续收口，需要先补更细的行为测试
- status recovery、session refresh、detail 分支通知链仍然是后续风险项

## 第十一轮优化记录

### 目标

第十一轮只收敛 `task_snapshot` 事件链里的一次重复 session 绑定，不改 session 恢复结果，
不改 timeline / rawEvents 更新，不改 done 后的 session refresh 行为。

### 本轮改动

模块：`task_snapshot / session binding`

- `task_snapshot` 事件原本会：
  - 先在 `_applyTaskSnapshot()` 里把 conversation 绑定到 `sessionRef`
  - 回到 `handleAgentResultEvent()` 后，再次对同一个 `sessionId`
    调 `updateConversationSettings()`
- 现在删除后者，保留 `_applyTaskSnapshot()` 内部的那次绑定

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 单条 `task_snapshot` 事件会在同一条处理链里对同一个 `sessionId`
  调用两次 `updateConversationSettings()`
- 第二次绑定不改变最终结果，但会带来一次额外的设置写入 / 通知链

### 优化后行为

- `task_snapshot` 仍会把 conversation 绑定到对应 `sessionRef`
- `done` 状态下仍会继续走 session refresh 和历史 hydration
- timeline / rawEvents / UI 状态保持不变
- 同一条 `task_snapshot` 不再重复绑定两次同一个 `sessionId`

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `task_snapshot` 事件仍会把 conversation 绑定到 `sessionRef`
- `threadMode` 仍会更新为 `continue`
- `running` 状态表现不变

### 风险备注

- 这轮只去掉了 `task_snapshot` 链上的第二次重复绑定，不等于 detail 分支副作用已经全部收口
- `codexResult`、session refresh、detail 分支通知链仍然存在进一步收口空间
- 长会话 hydration 和状态链职责边界仍然保留在后续轮次

## 第十二轮优化记录

### 目标

第十二轮只收敛 `updateConversationSettings()` 在 session 重绑 / 重置路径里的一次重复会话遍历
和重复持久化调度，不改 session restore 结果，不改 hydration 触发条件，不改 conversation
设置接口语义。

### 本轮改动

模块：`conversation settings / session reset`

- `updateConversationSettings()` 原本会：
  - 先遍历 `_conversations`，更新 conversation 设置
  - 如果判断需要重置 session 状态，再调用 `_replaceConversationMessages()`
  - `_replaceConversationMessages()` 会再次遍历 `_conversations`，并再次触发一次保存调度
- 现在把“重置消息为空列表”直接并入 `updateConversationSettings()` 的同一次
  `copyWith()` 更新里
- 保留 timeline / rawEvents / nextCursor / hydration in-flight 的清理逻辑不变
- 保留 `threadMode == continue && sessionRef.isNotEmpty` 时继续触发 hydration 的逻辑不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 当 `updateConversationSettings()` 触发 session 状态重置时：
  - 会先更新一次 conversation 设置
  - 再额外走一次 `_replaceConversationMessages(conversationId, const [])`
- 同一条设置链里存在一次额外的 `_conversations` 遍历
- 同一条设置链里会额外调度一次保存

### 优化后行为

- session 重绑 / 重置时，conversation 设置更新与消息清空在同一次遍历里完成
- 会话消息仍然会被清空
- `sessionRef` / `threadMode` 更新结果保持不变
- session reset 后的 hydration 补齐行为保持不变
- 同一路径不再额外调度第二次保存

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- session 重绑后，conversation 消息仍会被清空
- `sessionRef` 仍会正确更新
- 同一次 session reset 仅新增一次 storage write

### 风险备注

- 这轮只收掉了 session reset 链里的一次内部重复遍历和重复保存调度，不等于
  `updateConversationSettings()` 的整体副作用边界已经收口
- `updateConversationSettings()` 仍然同时承担排序、持久化、通知和 hydration 触发职责
- `AgentDashboardModel` 的职责拆分仍然是后续结构性优化任务

## 第十三轮优化记录

### 目标

第十三轮只收敛 `restoreSessionIntoConversation()` 在“清空 session 绑定”路径里对
session reset 的重复清理，不改空 session restore 的最终结果，不改 session 清空后的
conversation 语义，不改 hydration 正常分支。

### 本轮改动

模块：`restore session / empty session reset`

- `restoreSessionIntoConversation()` 原本在 `sessionId` 为空时会：
  - 先调用 `updateConversationSettings(sessionRef: '', threadMode: 'new')`
  - 然后再次手动清理 timeline / rawEvents / nextCursor
  - 再次手动清空消息
  - 再额外触发一次 `notifyListeners()`
- 现在保留 `updateConversationSettings()` 作为空 session reset 的唯一入口
- 删除这条空路径后面重复的 session state 清理、消息清空和额外通知
- 顺手删除已无调用方的 `_replaceConversationMessages()`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 清空 session 绑定时，同一条 reset 链会重复走两套状态清理
- 同一条 reset 链里会重复做消息清空和额外通知
- `_replaceConversationMessages()` 只为这条旧链路保留，形成死代码候选

### 优化后行为

- 清空 session 绑定时，仍会把 `sessionRef` 设为空、`threadMode` 设为 `new`
- conversation 消息仍会被清空
- session 相关 timeline / rawEvents / nextCursor 清理仍保持生效
- 同一路径不再重复执行第二套 reset 清理
- `_replaceConversationMessages()` 已删除，不再保留无调用方 helper

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `restoreSessionIntoConversation(..., sessionId: '')` 后，conversation 消息仍为空
- `sessionRef` 仍会被清空，`threadMode` 仍会回到 `new`
- 同一次清空 session restore 仅新增一次 storage write

### 风险备注

- 这轮只收掉了“空 session restore”路径上的重复 reset，不等于整个 session restore
  流程已经完成副作用收口
- `updateConversationSettings()` 仍然是 reset 权责中心，后续若继续拆分，需要先补更多
  场景测试
- 正常 session restore 的 hydration 成本和长会话加载策略仍保留在后续轮次

## 第十四轮优化记录

### 目标

第十四轮只收敛 `restoreSessionIntoConversation()` 正常 session restore 路径里的
重复 hydration 触发，不改 session restore 的最终结果，不改外部调用
`updateConversationSettings()` 时的默认自动 hydration 语义。

### 本轮改动

模块：`restore session / normal hydration trigger`

- `updateConversationSettings()` 新增可选参数 `hydrateIfNeeded`，默认仍为 `true`
- `restoreSessionIntoConversation(sessionId != '')` 在先设置
  `sessionRef + threadMode: continue` 时，显式传入 `hydrateIfNeeded: false`
- 这样正常 restore 路径只保留 `restoreSessionIntoConversation()` 自己后续显式执行的：
  - `_refreshConversationFromSession(...)`
  - `_hydrateRemainingSessionHistory(...)`
- 其他调用 `updateConversationSettings()` 的路径默认行为保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 正常 session restore 时，会先调用 `updateConversationSettings(... continue ...)`
- 该设置链默认会自动触发 `_ensureConversationHydrated(conversationId)`
- 随后 `restoreSessionIntoConversation()` 自己又显式执行一次
  `_refreshConversationFromSession()` 和历史 hydration
- 同一路径存在一次重复 hydration 触发机会

### 优化后行为

- 正常 session restore 时，仍会先把 conversation 绑定到目标 `sessionRef`
- session detail 仍会被加载，历史仍会继续 hydration
- 但这条路径只保留 `restoreSessionIntoConversation()` 自己负责的那一次 restore 链
- 外部直接调用 `updateConversationSettings()` 时，默认自动 hydration 行为不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 正常 `restoreSessionIntoConversation(sessionId != '')` 只触发一次 `loadSessionDetail()`
- restore 后 `sessionRef` 仍会正确更新
- restore 后 conversation 消息仍会正常加载

### 风险备注

- 这轮只收掉了正常 restore 路径里的一次重复 hydration 触发机会，不等于整个
  session restore / hydration 策略已经收口
- `_ensureConversationHydrated()` 仍然服务于其他入口，后续如继续收口，需要分别验证
  首屏自动挂接、手动切换会话、task done 后 refresh 等路径
- 长会话全量 hydration 和分页加载策略仍保留在后续轮次

## 第十五轮优化记录

### 目标

第十五轮只收敛正常 session restore / hydration 链路里的重复持久化调度，不改
session restore 的最终结果，不改分页加载结果，不改最终 UI 通知语义。

### 本轮改动

模块：`session restore / paged hydration persistence`

- `updateConversationSettings()` 新增可选参数 `persist`，默认仍为 `true`
- `restoreSessionIntoConversation(sessionId != '')` 在 restore 起点设置
  `sessionRef + threadMode: continue` 时，显式传入 `persist: false`
- `_applySessionDetail()` / `_refreshConversationFromSession()` /
  `_hydrateRemainingSessionHistory()` 增加可选参数 `persist`
- 正常 restore 链路改为：
  - 首屏 detail 只更新内存，不立即保存
  - 旧历史分页追加只更新内存，不逐页保存
  - 整条 restore / hydration 完成后统一 `await _save()` 一次
- `_ensureConversationHydrated()` 同步沿用同样策略：整条 hydration 链最后只保存一次

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 正常 restore 到带分页历史的 session 时：
  - 起点 `updateConversationSettings()` 会调度一次保存
  - 首屏 detail 应用会调度一次保存
  - 每次 `nextCursor` 翻页追加都会再调度一次保存
- 单次 restore 的内存结果虽然只在最后统一通知 UI，但存储层会被多次抖动

### 优化后行为

- 正常 restore 时，session 绑定、首屏 detail、历史分页追加仍全部照常完成
- 多页 hydration 仍会按原顺序合并消息
- 整条 restore / hydration 链只在最终结果稳定后保存一次
- 最终 UI 通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 带 `nextCursor` 的 paged session restore 仍会加载两页 detail
- restore 完成后 conversation 仍会拿到完整两页消息
- 整条 paged restore / hydration 链只新增一次 storage write

### 风险备注

- 这轮只收掉了 restore / hydration 链上的重复保存调度，不等于 session restore
  的全部副作用边界已经收口
- 当前仍然是“全量历史自动 hydration 到 끝”，只是减少了中间保存抖动
- 如果后续继续做按需加载，需要继续区分首屏自动挂接、手动 restore、task done refresh
  三条入口

## 第十六轮优化记录

### 目标

第十六轮只收敛 `task_snapshot done` 和 `codexResult done` 路径里 session 绑定后的
重复 session refresh / hydration 触发，不改 done 后的最终 session 恢复结果，不改
普通 `running` / `started` 路径的自动 hydration 语义。

### 本轮改动

模块：`done session refresh / duplicate hydration`

- `_applyDetailJson()` 新增可选参数 `hydrateTaskSnapshotSession`
- `_applyTaskSnapshot()` 新增可选参数 `hydrateIfNeeded`
- 当 `handleAgentResultEvent()` 处理 `task_snapshot + status == done` 时：
  - 先绑定 `sessionRef`
  - 但不再让绑定动作自动触发 `_ensureConversationHydrated()`
  - 后面只保留 done 分支自己显式执行的 session refresh + history hydration
- 当处理 `codexResult + status == done` 时：
  - 绑定 `sessionRef` 时显式传入 `hydrateIfNeeded: false`
  - 后面只保留 done 分支自己显式执行的 session refresh

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `task_snapshot done` 路径会：
  - 先在 session 绑定时自动触发一次 hydration
  - 再在 done 分支显式 refresh / hydrate 一次
- `codexResult done` 路径也会：
  - 先在 session 绑定时自动触发一次 hydration
  - 再在 done 分支显式 refresh 一次
- 这两条 done 路径都存在一次重复读取 session detail 的机会

### 优化后行为

- `task_snapshot done` 仍会正确绑定 `sessionRef`
- `codexResult done` 仍会正确绑定 `sessionRef`
- done 后的最终 session refresh / history hydration 结果保持不变
- 这两条 done 路径都只保留各自显式负责的那一次 session 读取链
- 普通 `running` / `started` 路径的自动 hydration 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `task_snapshot + done` 路径只触发一次 `loadSessionDetail()`
- `codexResult + done` 路径只触发一次 `loadSessionDetail()`
- 两条路径最终都仍会更新 `sessionRef` 并加载消息

### 风险备注

- 这轮只收掉了 done 路径上的重复 session 读取机会，不等于 detail 分支整体副作用已经收口
- `running` / `started` 路径仍然保留自动 hydration，后续如要继续收口，需要分路径验证
- 长会话自动全量 hydration 仍然是后续要处理的主风险项

## 第十七轮优化记录

### 目标

第十七轮只收敛 `task_snapshot done` 和 `codexResult done` 路径里的重复持久化调度，
不改 done 后最终 session 恢复结果，不改普通非 done detail 路径的默认保存语义。

### 本轮改动

模块：`done detail session binding / persistence`

- `_applyDetailJson()` 新增可选参数 `persistTaskSnapshotSession`
- `_applyTaskSnapshot()` 新增可选参数 `persist`
- 当 `handleAgentResultEvent()` 处理 `task_snapshot + status == done` 时：
  - session 绑定先只更新内存，不立即保存
  - 后续 done 分支显式 refresh / hydration 完成后统一保存一次
- 当处理 `codexResult + status == done` 时：
  - `updateConversationSettings(sessionRef, threadMode)` 先只更新内存，不立即保存
  - 后续 done 分支显式 refresh 完成后统一保存一次

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 第十六轮已经把 done 路径的重复 session 读取收掉，但：
  - `task_snapshot done` 绑定 `sessionRef` 时仍会保存一次
  - done 分支显式 refresh / hydration 完成后还会再保存一次
  - `codexResult done` 也存在同样的“双次保存”链路
- done 路径仍会出现一次无收益的额外 storage write

### 优化后行为

- `task_snapshot done` 仍会正确绑定 `sessionRef`
- `codexResult done` 仍会正确绑定 `sessionRef`
- done 后最终 session refresh / hydration 结果保持不变
- 两条 done 路径都只保留一次最终保存
- 普通非 done detail 路径的保存语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `task_snapshot + done` 路径只新增一次 storage write
- `codexResult + done` 路径只新增一次 storage write
- 两条路径仍然只读取一次 session detail，并最终拿到消息

### 风险备注

- 这轮只收掉了 done detail 路径上的重复保存，不等于 detail 分支所有副作用已经统一
- `running` / `started` / 非 session detail 分支仍沿用原有保存策略
- 首屏自动挂接最新 session 的全量 hydration 仍然是更大的后续风险项

## 第十八轮优化记录

### 目标

第十八轮只收敛 `ensureLoaded()` 首屏自动挂接最新 session 时的重复持久化调度，
不改“自动挂接最新 session”的默认产品行为，不改自动挂接后仍会加载 session 内容的结果。

### 本轮改动

模块：`initial load / auto-attach latest session persistence`

- `ensureLoaded()` 新增 `createdInitialConversation` 跟踪
- `_loadRuntimeCatalogs()` 现在返回是否成功触发了“自动挂接最新 session”
- `_maybeAttachLatestSession()` 改为返回 `bool`
- 当是全新空白会话并且已经自动挂接到最新 session 时：
  - 不再先把空白初始会话保存一次
  - 而是等自动挂接 restore 链完成后，再保存最终结果
- `_markConversationRead()` 新增可选参数 `persist`
- `ensureLoaded()` 首屏初始化里把“标记已读”的那次保存也关掉，避免首屏自动挂接链再多一次写入

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 首次 `ensureLoaded()` 且本地没有已有 conversation 时：
  - 会先创建并保存一个空白初始会话
  - 再自动挂接最新 session 并保存最终 restore 结果
  - `markConversationRead()` 还会再触发一次保存
- 首屏自动挂接最新 session 的整条初始化链存在多次 storage write

### 优化后行为

- 首次 `ensureLoaded()` 且自动挂接到最新 session 时：
  - 不再先保存空白初始会话
  - 不再为首次“标记已读”额外保存一次
  - 只保留自动挂接 restore 完成后的最终保存
- 自动挂接最新 session 的默认行为保持不变
- 自动挂接后 conversation 仍会拿到正确的 `sessionRef` 和消息

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `ensureLoaded()` 自动挂接最新 session 时仍会正确加载 session detail
- 自动挂接完成后最终只新增一次 storage write
- `sessionRef` 和消息仍会正确落到当前 conversation

### 风险备注

- 这轮只收掉了首屏自动挂接链里的重复保存，不等于首屏自动挂接策略本身已经最优
- 当前仍然会自动挂接最新 session，也仍然会继续走现有的历史 hydration 策略
- “首屏只拿首段、历史按需加载”仍然是下一阶段更大的优化项

## 第十九轮优化记录

### 目标

第十九轮只收敛 `deleteConversation()` 在切换到替代会话时的重复持久化调度，
不改删除后的选中逻辑，不改替代会话的已读标记语义，不改删除后的 UI 通知行为。

### 本轮改动

模块：`delete conversation / replacement read state persistence`

- `deleteConversation()` 原本在选中会话被删除后会：
  - 先调用 `_markConversationRead(_selectedConversationId, notify: false)`
  - `_markConversationRead()` 内部先保存一次
  - 然后 `deleteConversation()` 自己再显式 `_save()` 一次
- 现在把删除链里的 `_markConversationRead()` 改为 `persist: false`
- 删除后的整条替代会话切换链只保留最后那一次显式 `_save()`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 删除当前选中会话时，替代会话仍会被选中并同步已读状态
- 但这条删除链会先因 `_markConversationRead()` 触发一次保存
- 随后 `deleteConversation()` 自己再触发一次保存
- 同一路径存在一次无收益的额外 storage write

### 优化后行为

- 删除当前选中会话时，替代会话仍会被选中
- 替代会话仍会同步已读状态
- 删除后的 conversation 列表保存结果保持不变
- 整条删除链只保留一次最终保存

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 删除当前会话后仍会切换到替代会话
- 替代会话切换链只新增一次 storage write

### 风险备注

- 这轮只收掉了删除链里的重复保存，不等于 conversation 列表管理路径已经整体收口
- `createConversation()`、`selectConversation()`、`toggleConversationArchived()` 等路径仍沿用原有保存策略
- 首屏自动挂接最新 session 的全量历史 hydration 仍然是更大的后续风险项

## 第二十轮优化记录

### 目标

第二十轮只收敛 session restore / hydration 链里的重复 conversation 排序，
不改消息恢复结果，不改分页顺序，不改最终列表排序结果。

### 本轮改动

模块：`session detail apply / repeated sorting`

- `_applySessionDetail()` 新增可选参数 `sort`
- `_refreshConversationFromSession()` 在 restore / hydration 链里，当 `persist: false` 时，
  同步关闭中间页的即时排序
- `restoreSessionIntoConversation()`、`_ensureConversationHydrated()`、
  `task_snapshot done`、`codexResult done` 这些“先整条内存更新、最后统一保存”的路径里，
  改为在最终保存前只手动 `_sortConversations()` 一次

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- session restore / hydration 链已经把“多次保存”压成了最终一次
- 但首屏 detail 和每次历史分页追加，仍会在 `_applySessionDetail()` 内部立即排序一次
- 对同一条 restore / hydration 链来说，会出现多次中间排序

### 优化后行为

- restore / hydration 链的中间页更新先只改内存，不再每页即时排序
- 最终保存前仍会统一排序一次
- conversation 列表最终顺序保持不变
- 消息页数、分页追加顺序和最终 session 内容保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 带分页的 session restore 仍会恢复完整两页消息
- restore 完成后，被恢复的 conversation 仍会排到列表前面
- 最终 storage write 次数保持上一轮的单次保存约束

### 风险备注

- 这轮只收掉了 restore / hydration 链里的中间重复排序，不等于 conversation 列表管理整体已经收口
- 非 restore 场景下的即时排序策略仍沿用原有实现
- 首屏自动挂接最新 session 的“自动全量历史 hydration”仍然是更大的后续风险项

## 第二十一轮优化记录

### 目标

第二十一轮只收敛 `_markConversationRead()` 在会话本来就已读时的无效持久化和通知，
不改 unread 判定语义，不改真正从“未读 -> 已读”的状态更新结果。

### 本轮改动

模块：`mark conversation read / no-op persistence`

- `_markConversationRead()` 现在会先找出目标会话
- 如果会话不存在，直接返回
- 如果 `conversationHasUnread(conversationId)` 已经是 `false`，直接返回
- 只有在会话确实存在未读消息时，才继续更新时间、保存和通知

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 只要调用 `_markConversationRead()` 且找到目标会话，就会更新 `lastReadAt`
- 即使该会话本来就没有未读消息，也会继续保存并可能通知
- 像“再次选中当前已读会话”这类路径，会产生无收益的 storage write

### 优化后行为

- 已读会话再次走 `_markConversationRead()` 时，不再更新时间
- 已读会话再次选中时，不再产生额外保存
- 真正从未读切到已读时，仍然会正常保存一次并清掉未读状态
- unread 判定逻辑保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 再次选中已读会话时，不会新增 storage write
- 选中存在未读消息的会话时，仍会新增一次 storage write
- 选中后该会话的 unread 状态会正确清除

### 风险备注

- 这轮只收掉了 `_markConversationRead()` 的 no-op 写入，不等于所有 unread / read 状态链都已经收口
- unread 仍然依赖 `messages.first.createdAt` 与 `lastReadAt` 的比较语义
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十二轮优化记录

### 目标

第二十二轮只收敛 `updateConversationSettings()` 在输入设置与当前会话完全一致时的无效更新时间、
持久化和通知，不改真正配置变更时的保存语义，不改 session reset / hydration 触发条件。

### 本轮改动

模块：`conversation settings / no-op persistence`

- `updateConversationSettings()` 现在会先计算目标会话的下一状态
- 当 title、project、threadMode、profile、sessionRef、skills、pinned、archived、draft、
  include flags、lastReadAt 都与当前值一致，且本轮也不会触发 session reset 时，直接返回
- 只有在配置确实发生变化，或本轮本来就需要执行 reset 时，才继续更新时间、保存、通知和后续 hydration 判断

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 只要外部调用 `updateConversationSettings()`，目标会话就会刷新 `updatedAt`
- 即使传入值与当前会话完全一致，也会继续保存并通知
- 像“同一个 continue session 再次写回相同 sessionRef”这类路径，会产生无收益的 storage write

### 优化后行为

- 完全相同的会话设置再次写回时，不再刷新 `updatedAt`
- 完全相同的会话设置再次写回时，不再产生额外保存
- 真正的 title / profile / sessionRef / flags 变更，仍然会正常保存一次
- session reset、消息清空、hydration 触发条件保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- continue 会话再次写入相同 `sessionRef` 时，不会新增 storage write
- 相同设置重复写回时，`updatedAt` 不再被无意义刷新
- 真正修改会话标题时，仍会新增一次 storage write

### 风险备注

- 这轮只收掉了 `updateConversationSettings()` 的 no-op 写入，不等于该函数的所有副作用边界已经完全收口
- 该函数仍同时承担排序、reset、保存、通知和可选 hydration 触发职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十三轮优化记录

### 目标

第二十三轮只收敛 `restoreSessionIntoConversation(sessionId: '')` 在目标会话本来就已经是空白
`new` 状态时的重复 reset / 保存，不改真正“continue 会话清空回 new 会话”的恢复语义。

### 本轮改动

模块：`blank session restore / no-op reset`

- `restoreSessionIntoConversation()` 在 `sessionId` 为空时，先判断目标会话是否已经是空白 `new` 状态
- 只有当目标会话确实仍残留 sessionRef、messages、timeline、rawEvents 或历史分页游标时，才继续走 reset
- 如果目标会话本来就是空白 `new` 状态，直接返回，不再触发额外保存

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 只要调用 `restoreSessionIntoConversation(sessionId: '')`，都会进入 `updateConversationSettings()`
- 即使目标会话本来就是空白 `new` 状态，也会继续刷新 `updatedAt`、保存并通知
- “空会话再次清空”会产生无收益的 storage write

### 优化后行为

- 已经是空白 `new` 状态的会话再次清空时，不再刷新 `updatedAt`
- 已经是空白 `new` 状态的会话再次清空时，不再产生额外保存
- 从 continue 会话真正清空回 `new` 会话时，仍然会正常保存一次
- 真正的 session 清空结果、消息清空语义和后续 UI 状态保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 已经是空白 `new` 状态的会话再次清空时，不会新增 storage write
- 已经是空白 `new` 状态的会话再次清空时，`updatedAt` 不再被无意义刷新
- 原有“continue 会话清空回 new 会话”路径仍然只保存一次

### 风险备注

- 这轮只收掉了空白会话重复 reset 的 no-op 保存，不等于 session restore / reset 边界已经完全收口
- `restoreSessionIntoConversation()` 仍同时承担 session 绑定、首屏 detail 读取、历史 hydration 和状态提示职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十四轮优化记录

### 目标

第二十四轮只收敛 `deleteConversation()` 在传入不存在的会话 id 时的无效排序、保存和通知，
不改真正删除存在会话时的替代选中、已读处理和单次持久化语义。

### 本轮改动

模块：`conversation delete / missing-id no-op`

- `deleteConversation()` 现在会先判断目标会话是否真实存在
- 只有会话存在时，才继续删除、替代选中、已读标记和保存流程
- 如果目标会话不存在，直接返回，不再触发额外排序、草稿同步、保存和通知

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 只要调用 `deleteConversation()` 且当前会话列表非空，就会继续往下执行
- 即使传入的 `conversationId` 不存在，也会重新生成列表、排序、同步草稿并保存
- “删除一个不存在的会话”会产生无收益的 storage write

### 优化后行为

- 删除不存在的会话 id 时，不再改动会话列表
- 删除不存在的会话 id 时，不再产生额外保存
- 当前选中会话和列表顺序保持不变
- 真正删除存在会话时，仍然只保存一次，并保持既有替代选中语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 删除不存在的会话 id 时，不会新增 storage write
- 删除不存在的会话 id 时，会话数量和当前选中项保持不变
- 原有“删除真实会话只保存一次”的路径继续通过

### 风险备注

- 这轮只收掉了不存在 id 的 no-op 删除，不等于 conversation 列表管理路径已经完全收口
- `deleteConversation()` 仍同时承担删除、替代选中、已读处理、草稿同步和持久化职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十五轮优化记录

### 目标

第二十五轮只收敛 `visibleConversations` getter 中对过滤结果的重复排序，
不改会话列表排序规则，不改 pinned / archived / updatedAt 的展示顺序。

### 本轮改动

模块：`conversation list / redundant getter sort`

- 将 `_conversations` 的有序性补成显式不变量：
  - `ensureLoaded()` 的 demo seed 路径在构建 demo 会话后立即排序
  - `resetDemoState()` 在重建 demo 会话后立即排序
- `visibleConversations` getter 保留过滤逻辑，但不再对过滤结果再次调用 `sort`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_conversations` 在大多数变更路径里已经会主动排序
- 但 `visibleConversations` getter 每次访问时，仍会把过滤结果重新排序一次
- 对于底层列表本来就已保持有序的正常路径，这一步是重复 CPU 开销

### 优化后行为

- `_conversations` 继续作为唯一有序源
- `visibleConversations` 只做过滤，不再重复排序
- 会话列表在 pinned、archived、updatedAt 规则下的最终显示顺序保持不变
- demo 初始状态和 `resetDemoState()` 后的可见顺序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- demo 初始 `visibleConversations` 顺序仍然保持 pinned 优先和既有更新时间顺序
- `resetDemoState()` 后 `visibleConversations` 顺序仍然恢复为同样结果
- 原有依赖 `visibleConversations.first` 的 restore / delete / unread 测试继续通过

### 风险备注

- 这轮依赖 `_conversations` 始终作为有序源的前提，因此后续新增会话变更路径时必须继续显式维护排序
- `visibleConversations` 仍然会在每次访问时构建过滤结果列表，只是去掉了重复排序
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十六轮优化记录

### 目标

第二十六轮只收敛 unread 统计与已读标记路径里的重复会话查找，
不改 unread 判定语义，不改外部 `conversationHasUnread(String id)` 接口。

### 本轮改动

模块：`unread evaluation / repeated conversation lookup`

- 新增基于 `AgentConversation` 对象的内部 helper，复用 unread 判定逻辑
- `unreadConversationCount` 不再为每个会话都通过 id 再次 `_findConversation()`
- `_markConversationRead()` 在已拿到目标会话对象后，不再额外通过 id 重复查找一次 unread 状态
- `conversationHasUnread(String conversationId)` 对外接口保持不变，继续作为基于 id 的查询入口

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `unreadConversationCount` 在遍历 `_conversations` 时，会对每个会话再次通过 id 调用 `conversationHasUnread()`
- `conversationHasUnread()` 内部又会调用 `_findConversation()`，形成重复线性查找
- `_markConversationRead()` 已经先拿到了目标会话对象，但判断 unread 时仍再次按 id 回扫列表

### 优化后行为

- unread 判定规则仍然完全基于 `messages.first.createdAt` 与 `lastReadAt`
- `unreadConversationCount` 直接复用当前遍历到的会话对象，不再重复全表查找
- `_markConversationRead()` 直接复用已找到的目标会话对象判断 unread
- 外部 `conversationHasUnread(String id)` 的调用结果保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- demo 数据下的 unread 会话数量保持不变
- 选中未读会话后，unread 会话数量会从 1 正确降到 0
- 原有“选中已读/未读会话”的持久化测试继续通过

### 风险备注

- 这轮只消除了 unread 统计链里的重复查找，不等于 unread/read 状态模型已经完全收口
- unread 仍然依赖 `messages.first.createdAt` 与 `lastReadAt` 的时间戳语义
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十七轮优化记录

### 目标

第二十七轮只收敛 `deleteConversation()` 在删除真实存在会话时的重复列表遍历，
不改删除结果、不改替代选中逻辑、不改持久化次数。

### 本轮改动

模块：`conversation delete / duplicate traversal`

- `deleteConversation()` 不再先 `any()` 判断存在、再 `where()` 生成新列表
- 改为先用 `indexWhere()` 定位目标会话
- 命中后复制一次当前列表并 `removeAt(index)`，未命中则直接返回

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 删除真实存在的会话时，会先做一次 `any()` 全表遍历确认存在
- 然后再做一次 `where()` 全表遍历生成移除后的新列表
- 对于正常删除路径，存在可避免的双重列表扫描

### 优化后行为

- 删除真实存在的会话时，改为一次定位目标索引，再基于副本执行 `removeAt`
- 删除不存在 id 的会话时，仍然直接返回
- 删除后会话列表、替代选中、已读处理和单次持久化语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有“删除真实会话只保存一次”的测试继续通过
- 原有“删除不存在会话 id 时不保存”的测试继续通过

### 风险备注

- 这轮只收掉了真实删除路径里的双重遍历，不等于 `deleteConversation()` 的职责边界已经完全收口
- `deleteConversation()` 仍同时承担删除、替代选中、已读处理、草稿同步和持久化职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十八轮优化记录

### 目标

第二十八轮只收敛 `resetDemoState()` 中对 demo 状态 map 的重复清空，
不改 demo 重置后的排序、选中会话、runtime 状态和持久化语义。

### 本轮改动

模块：`demo reset / duplicate status clear`

- `resetDemoState()` 不再先手动清空 `_runtimeStatuses` 和 `_runtimeStatusDetails`
- demo 状态 map 的清空与重建继续统一由 `_applyDemoStatuses()` 负责

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `resetDemoState()` 会先手动 `clear()` 两个 runtime 状态 map
- 紧接着 `_applyDemoStatuses()` 内部又会再次 `clear()` 同样的两个 map
- 同一条 demo reset 链里存在重复 map 清空

### 优化后行为

- demo reset 时，runtime 状态 map 只由 `_applyDemoStatuses()` 清空并重建一次
- demo 会话顺序、默认选中项和三条 demo runtime 状态保持不变
- `resetDemoState()` 的单次保存和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- `resetDemoState()` 后的可见会话顺序仍然恢复为 demo 默认顺序
- `resetDemoState()` 后三条 demo runtime 状态仍然分别恢复为 completed / needsConfirmation / running

### 风险备注

- 这轮只收掉了 demo reset 链里的重复 clear，不等于 demo/runtime 状态管理已经整体收口
- `_applyDemoStatuses()` 仍同时承担清空和重建 demo 状态 map 的职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第二十九轮优化记录

### 目标

第二十九轮只收敛 `deleteConversation()` 在真实删除后对剩余会话列表的重复排序，
不改删除后的顺序、不改替代选中、不改持久化语义。

### 本轮改动

模块：`conversation delete / redundant post-delete sort`

- `deleteConversation()` 在删除目标会话后，不再对剩余 `_conversations` 再调用一次 `_sortConversations()`
- 依据当前列表不变量，删除一个元素不会改变剩余元素的相对顺序，因此最终排序结果天然保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_conversations` 在进入 `deleteConversation()` 前已经保持有序
- 删除目标会话后，剩余元素的相对顺序本来不会变化
- 但函数仍会对整个剩余列表再调用一次 `_sortConversations()`

### 优化后行为

- 删除目标会话后，剩余列表直接复用删除后的现有顺序
- 删除后的可见会话顺序保持不变
- 替代选中、已读处理、单次保存和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

新增测试覆盖：

- 删除首个可见会话后，剩余 `visibleConversations` 的首项仍然是原来的第二项
- 删除后剩余顺序保持不变，且被删除的会话不再出现在列表中
- 原有“删除真实会话只保存一次”和“删除不存在 id 不保存”的测试继续通过

### 风险备注

- 这轮依赖 `_conversations` 在删除前已经是有序源的前提
- `deleteConversation()` 仍同时承担删除、替代选中、已读处理、草稿同步和持久化职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十轮优化记录

### 目标

第三十轮只收敛 `_markConversationRead()` 在真实已读更新路径上的整表重建，
不改 unread 判定语义，不改保存和通知行为。

### 本轮改动

模块：`mark conversation read / whole-list rebuild`

- `_markConversationRead()` 不再通过 `map()` 重建整份 `_conversations`
- 改为先定位目标会话索引，再只替换该索引上的一个元素
- 已读时间仍然在真正存在未读时才更新

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_markConversationRead()` 在确认目标会话存在未读后，会 `map()` 整个 `_conversations`
- 即使只更新一个会话的 `lastReadAt`，也会重建整份列表
- 对正常“未读 -> 已读”路径来说，存在可避免的整表重建成本

### 优化后行为

- `_markConversationRead()` 改为定位目标索引后只替换一个元素
- unread 判定语义、`lastReadAt` 更新时机、保存和通知行为保持不变
- 已读会话再次选中仍然不会保存；未读会话选中后仍然只保存一次

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有“再次选中已读会话不保存”的测试继续通过
- 原有“选中未读会话只保存一次”的测试继续通过
- 原有 unread 计数变化测试继续通过

### 风险备注

- 这轮只收掉了已读更新路径里的整表重建，不等于 unread/read 状态模型已经完全收口
- unread 仍然依赖 `messages.first.createdAt` 与 `lastReadAt` 的时间戳语义
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十一轮优化记录

### 目标

第三十一轮只收敛 `_appendMessage()` 在消息追加热路径上的整表重建，
不改消息追加结果、不改标题更新、不改排序/保存/通知时机。

### 本轮改动

模块：`append message / whole-list rebuild`

- `_appendMessage()` 不再通过 `map()` 重建整份 `_conversations`
- 改为先定位目标会话索引，再只替换该索引上的一个元素
- 目标会话的标题更新、归档复位、draft 同步、`updatedAt`、`lastReadAt` 和消息追加逻辑保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_appendMessage()` 每次追加一条消息时，都会 `map()` 整个 `_conversations`
- 即使只更新一个会话，也会重建整份列表
- 这是发送消息和接收 agent 结果的热路径，整表重建成本更敏感

### 优化后行为

- `_appendMessage()` 改为定位目标索引后只替换一个元素
- 消息条数增加、标题更新、已选中会话的 draft / `lastReadAt` 更新语义保持不变
- 排序、保存和 `notifyListeners()` 时机保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有“plain agent result appends a message with one listener notification”测试继续通过
- 原有消息条数递增测试继续通过
- 原有分页恢复和列表顺序测试继续通过

### 风险备注

- 这轮只收掉了消息追加热路径里的整表重建，不等于所有单元素更新路径已经整体收口
- `_appendMessage()` 仍同时承担标题更新、归档复位、draft 同步、排序、保存和通知职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十二轮优化记录

### 目标

第三十二轮只收敛 `_handleComposerChanged()` 在草稿输入热路径上的整表重建，
不改 draft 判定、不改延迟保存逻辑、不改会话切换后的 draft 恢复语义。

### 本轮改动

模块：`draft input / whole-list rebuild`

- `_handleComposerChanged()` 不再通过 `map()` 重建整份 `_conversations`
- 改为先定位当前选中会话索引，再只替换该索引上的一个元素
- draft 变化判断、`_draftSaveTimer` 重置和延迟保存逻辑保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 每次输入变化命中 `_handleComposerChanged()` 时，都会 `map()` 整个 `_conversations`
- 即使只是更新当前选中会话的 `draft`，也会重建整份列表
- 这条路径会随着用户输入频繁触发，整表重建成本不必要

### 优化后行为

- 草稿输入改为定位当前选中会话索引后只替换一个元素
- draft 变化判断和 `220ms` 延迟保存语义保持不变
- 会话切换后的 draft 恢复、删除替代选中后的草稿同步、消息追加时的 draft 逻辑保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded()`、会话切换、删除替代选中、消息追加、demo reset 等测试继续通过
- 现有测试集已覆盖与 draft 同步紧密相关的列表与会话切换路径

### 风险备注

- 这轮只收掉了草稿输入热路径里的整表重建，不等于所有 draft 相关副作用已经整体收口
- `_handleComposerChanged()` 仍依赖当前 selected conversation 与 `textController` 的同步边界
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十三轮优化记录

### 目标

第三十三轮只收敛 `_applySessionDetail()` 在 session restore / paging 热路径上的整表重建，
不改消息合并语义，不改 title/sessionRef/threadMode 更新，不改 sort/save 行为。

### 本轮改动

模块：`session detail merge / whole-list rebuild`

- `_applySessionDetail()` 不再通过 `map()` 重建整份 `_conversations`
- 改为先定位目标会话索引，再只替换该索引上的一个元素
- timeline/rawEvents 更新、历史分页消息合并、title/sessionRef/threadMode 写回、sort/persist 逻辑保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_applySessionDetail()` 每次处理 session detail 或分页结果时，都会 `map()` 整个 `_conversations`
- 即使只更新一个 conversation，也会重建整份列表
- 这条路径会出现在 session restore、分页 hydration、task snapshot done、codex result done 等流程里

### 优化后行为

- `_applySessionDetail()` 改为定位目标会话索引后只替换一个元素
- session 消息合并、分页追加、title/sessionRef 恢复、`threadMode: continue`、sort/persist 语义保持不变
- session detail 热路径不再为单会话更新重建整份列表

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session restore loads detail once without duplicate hydration` 测试继续通过
- 原有 `paged session restore persists once after full hydration` 测试继续通过
- 原有 `task snapshot done refreshes session detail once` 与 `codex result done refreshes session detail once` 测试继续通过

### 风险备注

- 这轮只收掉了 session detail 合并热路径里的整表重建，不等于 restore/hydration 职责边界已经整体收口
- `_applySessionDetail()` 仍同时承担 timeline/rawEvents、消息合并、session 绑定和可选排序/保存职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十四轮优化记录

### 目标

第三十四轮只收敛 `updateConversationSettings()` 在单会话更新路径上的整表重建，
不改 metadata 更新语义，不改 session reset / clear，不改 save / notify / hydrate 触发条件。

### 本轮改动

模块：`conversation settings update / whole-list rebuild`

- `updateConversationSettings()` 不再通过 `map()` 重建整份 `_conversations`
- 改为先定位目标会话索引，再只替换该索引上的一个元素
- `shouldResetSessionState`、`updatedAt`、messages 清空、排序、保存、通知和可选 hydration 逻辑保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `updateConversationSettings()` 在确认存在实际变更后，会 `map()` 整个 `_conversations`
- 即使只修改一个会话的 title / profile / sessionRef / flags，也会重建整份列表
- 这条路径会被重命名、置顶/归档、session 绑定、session 清空等多处复用

### 优化后行为

- `updateConversationSettings()` 改为定位目标会话索引后只替换一个元素
- metadata 更新、session reset / clear、保存、通知和 hydration 触发条件保持不变
- 与该函数相关的 no-op 检测和单次保存约束保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session rebinding still clears messages and only schedules one storage write` 测试继续通过
- 原有 `clearing session restore still resets conversation state with one storage write` 测试继续通过
- 原有 `updating conversation with unchanged continue session skips write` 与 `updating conversation title still persists once` 测试继续通过
- 原有 `task snapshot still binds conversation session once` 测试继续通过

### 风险备注

- 这轮只收掉了 conversation settings 更新链里的整表重建，不等于该函数的职责边界已经完全收口
- `updateConversationSettings()` 仍同时承担 metadata 更新、session reset、排序、保存、通知和可选 hydration 触发职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十五轮优化记录

### 目标

第三十五轮只收敛 `updateConversationSettings()` 内部对目标会话的重复线性查找，
不改 next 值计算，不改 no-op 检测，不改 session reset / save / notify / hydrate 语义。

### 本轮改动

模块：`conversation settings update / duplicate lookup`

- `updateConversationSettings()` 不再先 `_findConversation()` 再 `indexWhere()`
- 改为一开始只做一次 `indexWhere()`，并直接复用该索引对应的 `currentConversation`
- 后续 next 值计算、no-op 检测、session reset、保存、通知和 hydration 逻辑保持不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `updateConversationSettings()` 会先通过 `_findConversation(conversationId)` 查找目标会话
- 在确认有实际变更后，又会再执行一次 `indexWhere()` 定位同一个会话
- 对每次真正命中的设置更新来说，存在重复线性扫描

### 优化后行为

- `updateConversationSettings()` 只在入口做一次 `indexWhere()` 查找
- 目标会话对象与后续单点替换共用同一个索引
- next 值计算、no-op 检测、session reset / clear、保存、通知和 hydration 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session rebinding still clears messages and only schedules one storage write` 测试继续通过
- 原有 `clearing session restore still resets conversation state with one storage write` 测试继续通过
- 原有 `updating conversation with unchanged continue session skips write` 与 `updating conversation title still persists once` 测试继续通过

### 风险备注

- 这轮只收掉了 `updateConversationSettings()` 内部的重复查找，不等于该函数的职责边界已经完全收口
- `updateConversationSettings()` 仍同时承担 metadata 更新、session reset、排序、保存、通知和可选 hydration 触发职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十六轮优化记录

### 目标

第三十六轮只收敛会话设置包装方法里的重复目标会话查找，
不改 pinned / archived 切换语义，不改保存、已读同步、排序和通知行为。

### 本轮改动

模块：`conversation settings wrappers / duplicate lookup`

- 为 `updateConversationSettings()` 增加私有索引入口 `_updateConversationSettingsAtIndex()`
- `toggleConversationPinned()` 不再先 `_findConversation()` 再进入 `updateConversationSettings()`
- `toggleConversationArchived()` 不再先 `_findConversation()` 再进入 `updateConversationSettings()`
- 两个包装方法改为一次 `indexWhere()` 后复用同一个索引与会话对象

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `toggleConversationPinned()` 会先 `_findConversation(conversationId)` 查目标会话
- `toggleConversationArchived()` 会先 `_findConversation(conversationId)` 查目标会话
- 随后两者都会调用 `updateConversationSettings()`，而后者内部又会再做一次 `indexWhere()`
- 因此每次真实命中的 pinned / archived 切换都存在两次线性查找

### 优化后行为

- `toggleConversationPinned()` 改为一次 `indexWhere()` 后直接复用索引与会话对象
- `toggleConversationArchived()` 改为一次 `indexWhere()` 后直接复用索引与会话对象
- pinned / archived 的目标值计算保持不变
- archived 切换时附带写入 `lastReadAt: DateTime.now()` 的语义保持不变
- 会话排序、保存、通知和后续 `updateConversationSettings()` 副作用保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `toggling pinned and archived still persists once per change` 测试通过
- 原有 `updating conversation title still persists once` 测试继续通过
- 原有会话切换、删除替代选中、已读统计和 session restore 相关测试继续通过

### 风险备注

- 这轮只收掉了 pinned / archived 包装方法与设置入口之间的重复查找，不等于会话更新链的职责边界已经收口
- `renameConversation()` 仍然通过外层包装后进入统一设置入口，后续仍可继续审计是否有同类重复扫描
- `updateConversationSettings()` 仍同时承担 metadata 更新、session reset、排序、保存、通知和可选 hydration 触发职责

## 第三十七轮优化记录

### 目标

第三十七轮只收敛 `_markConversationRead()` 内部对目标会话的重复线性查找，
不改未读判定，不改 `lastReadAt` 更新语义，不改保存和通知条件。

### 本轮改动

模块：`read state update / duplicate lookup`

- `_markConversationRead()` 不再先 `_findConversation()` 再 `indexWhere()`
- 改为入口只做一次 `indexWhere()`，并复用同一个索引拿到目标会话对象
- 在确认会话存在未读后，仍然只替换该索引上的单个元素

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_markConversationRead()` 会先 `_findConversation(conversationId)` 查找目标会话
- 随后在确认存在未读时，又会再执行一次 `indexWhere()` 定位同一个会话
- 因此每次真实命中的已读更新都存在两次线性查找

### 优化后行为

- `_markConversationRead()` 只在入口做一次 `indexWhere()`
- 目标会话对象与后续单点替换共用同一个索引
- 未读判定仍基于 `_conversationHasUnread(conversation)`，语义保持不变
- `lastReadAt` 更新、保存和通知条件保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `selecting unread conversation still keeps lastReadAt semantics` 测试通过
- 原有 `selecting an already-read conversation does not persist again` 测试继续通过
- 原有 `selecting a conversation with unread messages persists once` 与 `selecting unread conversation updates unread count once` 测试继续通过

### 风险备注

- 这轮只收掉了 `_markConversationRead()` 内部的重复查找，不等于 unread/read 状态链已经完全收口
- unread 统计当前仍按遍历 + 时间戳比较派生，后续是否要引入更稳定的游标语义仍需单独评估
- 会话列表按 id 的高频定位目前仍主要依赖线性扫描，是否需要更直接的索引结构仍保留在后续审计项里

## 第三十八轮优化记录

### 目标

第三十八轮只收敛 `restoreSessionIntoConversation(sessionId == '')`
空 session reset 分支里的重复目标会话查找，不改空白会话 no-op 判定，不改 reset 语义和保存行为。

### 本轮改动

模块：`empty session restore / duplicate lookup`

- `restoreSessionIntoConversation()` 在 `sessionId` 为空时不再先 `_findConversation()` 再进入统一设置入口
- 改为入口一次 `indexWhere()`，同时复用该索引完成“是否已是空白会话”的判定
- 真正需要 reset 时，直接复用同一索引调用 `_updateConversationSettingsAtIndex()`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 空 `sessionId` 分支会先 `_findConversation(conversationId)` 查找目标会话
- 若会话当前不是空白状态，则继续调用 `updateConversationSettings()`
- 而 `updateConversationSettings()` 内部又会再次通过 `indexWhere()` 定位同一个会话
- 因此每次真实命中的空 session reset 都存在两次线性查找

### 优化后行为

- 空 `sessionId` 分支改为只做一次 `indexWhere()`
- “已是空白会话”的 no-op 判定与真正 reset 共用同一个索引和会话对象
- reset 后仍然回到 `threadMode: 'new'`、`sessionRef: ''`
- 保存、通知、timeline/rawEvents 清理和消息清空语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `clearing session restore still preserves blank timeline state with one write` 测试通过
- 原有 `clearing session restore still resets conversation state with one storage write` 测试继续通过
- 原有 `clearing an already blank conversation skips storage write` 测试继续通过

### 风险备注

- 这轮只收掉了空 session reset 分支里的重复查找，不等于 `restoreSessionIntoConversation()` 两类职责已经完全拆开
- 正常 session restore 路径仍然承担 session 绑定、detail 加载、分页 hydration、排序、保存和状态提示等多类职责
- 首屏自动挂接最新 session 的自动全量历史 hydration 仍然是更大的后续风险项

## 第三十九轮优化记录

### 目标

第三十九轮只收敛草稿输入热路径里的重复选中会话定位，
不改 draft 比较逻辑，不改 `220ms` 延迟保存语义，不改选中会话 fallback 语义。

### 本轮改动

模块：`composer draft hot path / duplicate lookup`

- 引入 `_selectedConversationIndex()` 统一选中会话定位
- `selectedConversation` 改为复用 `_selectedConversationIndex()`，保持“找不到选中 id 时回退到首个会话”的语义
- `_handleComposerChanged()` 不再先通过 `selectedConversation` 扫列表，再 `indexWhere()` 二次扫描
- 草稿输入改为一次定位索引后复用同一会话对象与同一索引完成 draft 更新

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_handleComposerChanged()` 会先通过 `selectedConversation` 查找当前选中会话
- `selectedConversation` 内部会遍历 `_conversations` 找 `_selectedConversationId`
- 若 draft 需要更新，`_handleComposerChanged()` 又会再执行一次 `indexWhere()` 定位同一个会话
- 因此每次真实命中的 draft 输入都会存在两次线性扫描

### 优化后行为

- `_handleComposerChanged()` 改为一次 `_selectedConversationIndex()` 定位后复用同一索引与会话对象
- `selectedConversation` 也复用同一套索引 helper，但保留原有 fallback 语义
- draft 比较、单会话 draft 更新和 `220ms` 延迟保存语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `composer draft change still persists selected conversation once` 测试通过
- 原有会话切换、session restore、已读状态、pinned/archived 切换相关测试继续通过

### 风险备注

- 这轮只收掉了选中会话定位链里的重复扫描，不等于 draft 输入、副作用时序和 composer 同步边界已经完全收口
- `selectedConversation` 仍然保留“选中 id 丢失时回退到首个会话”的兼容语义，后续是否继续保留这一隐式 fallback 需要单独评估
- 草稿保存当前仍依赖 `Timer` 延迟落盘，后续是否需要更明确的 draft 状态边界仍保留在审计项里

## 第四十轮优化记录

### 目标

第四十轮只收敛 `conversationHasUnread(String id)` 入口里的目标会话定位，
不改 unread 判定逻辑，不改缺失会话时返回 `false` 的语义。

### 本轮改动

模块：`unread lookup entry / duplicate object lookup path`

- `conversationHasUnread(String conversationId)` 不再通过 `_findConversation()` 拿会话对象
- 改为入口直接一次 `indexWhere()` 定位目标会话
- 命中后仍然复用既有 `_conversationHasUnread(conversation)` 逻辑做 unread 判定

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `conversationHasUnread()` 会先 `_findConversation(conversationId)` 线性查找目标会话
- 找到后再把会话对象传给 `_conversationHasUnread(conversation)`
- 对外语义虽然简单，但仍保留一层单独的对象查找包装

### 优化后行为

- `conversationHasUnread()` 改为入口直接做一次 `indexWhere()`
- 未命中时仍然返回 `false`
- 命中时仍然复用 `_conversationHasUnread(conversation)`，unread 判定语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `missing conversation unread lookup still returns false` 测试通过
- 原有 `demo unread conversation count stays consistent` 测试继续通过
- 原有 `selecting a conversation with unread messages persists once` 与
  `selecting unread conversation updates unread count once` 测试继续通过

### 风险备注

- 这轮只收掉了 `conversationHasUnread()` 入口的会话定位包装，不等于 unread/read 状态模型已经收口
- unread 统计当前仍基于列表遍历和时间戳比较，是否继续演进为更稳定的消息游标语义仍需后续单独评估
- 会话按 id 定位目前仍主要依赖线性扫描，是否需要更直接的索引结构仍保留在后续审计项里

## 第四十一轮优化记录

### 目标

第四十一轮只收敛 `_ensureConversationHydrated()` 前置检查阶段的目标会话定位，
不改 hydration 触发条件，不改异步 session detail / 分页加载语义。

### 本轮改动

模块：`hydration precheck / conversation lookup`

- `_ensureConversationHydrated()` 不再先 `_findConversation(conversationId)` 拿目标会话对象
- 改为入口直接一次 `indexWhere()` 定位目标会话
- 命中后仍然复用原有的 `sessionRef`、`messages.isNotEmpty` 和 `_sessionHydrationInFlight` 前置检查

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_ensureConversationHydrated()` 会先 `_findConversation(conversationId)` 查找目标会话
- 找到后再基于该对象判断 session 是否为空、消息是否已存在
- 之后才进入原有异步 hydration 链

### 优化后行为

- `_ensureConversationHydrated()` 改为入口直接一次 `indexWhere()` 定位会话
- 未命中时仍然直接返回
- 命中后仍然沿用原有的前置检查和后续异步 hydration 逻辑

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `selecting missing conversation still keeps fallback selection without write` 测试通过
- 原有 `session restore loads detail once without duplicate hydration` 测试继续通过
- 原有 `paged session restore persists once after full hydration` 与
  `ensureLoaded auto-attached latest session persists only final state` 测试继续通过

### 风险备注

- 这轮只收掉了 `_ensureConversationHydrated()` 前置检查的对象查找包装，不等于 hydration 链整体职责已经收口
- 真正的异步 `loadSessionDetail -> _refreshConversationFromSession -> _hydrateRemainingSessionHistory` 链没有动，后续仍需单独审计
- `selectConversation()` 在传入缺失 id 时仍然会保留当前的 fallback 语义，这属于现有兼容行为，不在本轮修改范围内

## 第四十二轮优化记录

### 目标

第四十二轮只收敛 `loadMoreSessionHistory()` 前置检查阶段的目标会话定位，
不改分页加载语义，不改错误处理与通知行为。

### 本轮改动

模块：`load more history precheck / conversation lookup`

- `loadMoreSessionHistory()` 不再先 `_findConversation(conversationId)` 拿目标会话对象
- 改为入口直接一次 `indexWhere()` 定位目标会话
- 命中后仍然沿用原有的 `sessionRef`、`cursor` 前置检查

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `loadMoreSessionHistory()` 会先 `_findConversation(conversationId)` 查找目标会话
- 找到后再读取 `sessionRef` 和 `_sessionNextCursorByConversation[conversationId]`
- 之后才进入原有的分页 session detail 加载链

### 优化后行为

- `loadMoreSessionHistory()` 改为入口直接一次 `indexWhere()` 定位会话
- 未命中时仍然直接返回
- 命中后仍然沿用原有的 `sessionRef` / `cursor` 检查、分页加载、异常写状态和通知逻辑

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `loading more history for missing conversation still skips write` 测试通过
- 原有 `paged session restore persists once after full hydration` 测试继续通过
- 原有 `session restore loads detail once without duplicate hydration` 与
  `ensureLoaded auto-attached latest session persists only final state` 测试继续通过

### 风险备注

- 这轮只收掉了 `loadMoreSessionHistory()` 前置检查阶段的对象查找包装，不等于分页加载链整体职责已经收口
- 真正的分页读取仍然在异步 `_refreshConversationFromSession()` 链里执行，后续如要继续收敛，需要单独评估时序与索引安全性
- 缺失 conversation id 时当前仍保留“静默返回、不写状态”的兼容语义，这属于现有行为，不在本轮修改范围内

## 第四十三轮优化记录

### 目标

第四十三轮只收敛 `_syncComposerWithSelectedConversation()` 里的选中会话读取，
不改 draft 同步结果，不改切换会话时的持久化行为。

### 本轮改动

模块：`composer sync / selected conversation lookup`

- `_syncComposerWithSelectedConversation()` 不再通过 `selectedConversation` 读取当前 draft
- 改为直接复用 `_selectedConversationIndex()` 定位当前选中会话
- 未命中时仍然回退为空字符串，保持原有 composer 清空语义

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_syncComposerWithSelectedConversation()` 会先通过 `selectedConversation` 获取当前选中会话
- `selectedConversation` 内部再通过 `_selectedConversationIndex()` 做一次定位
- 之后再读取 draft 并决定是否更新 `textController`

### 优化后行为

- `_syncComposerWithSelectedConversation()` 改为直接调用 `_selectedConversationIndex()`
- 命中时仍然读取目标会话 draft
- 未命中时仍然回退到空字符串
- `textController` 同步逻辑和 `_syncingComposer` 保护逻辑保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `switching conversation still syncs composer draft and keeps one write` 测试通过
- 原有 `composer draft change still persists selected conversation once` 测试继续通过
- 原有会话切换、已读状态、session restore 和分页 restore 相关测试继续通过

### 风险备注

- 这轮只收掉了 composer 同步路径里的选中会话读取包装，不等于 draft/composer 状态边界已经完全收口
- `selectedConversation` 的 fallback 语义仍被其他调用点依赖，后续是否继续保留仍需单独评估
- 切换到未读会话时仍然会保留当前“已读同步带来一次写入”的既有行为，本轮只验证 draft 同步结果保持不变，不做调整

## 第四十四轮优化记录

### 目标

第四十四轮只收敛 `_maybeAttachLatestSession()` 里的当前选中会话读取，
不改“已有 draft / session / messages 时不自动挂接最新 session”的语义。

### 本轮改动

模块：`latest session auto-attach precheck / selected conversation lookup`

- `_maybeAttachLatestSession()` 不再通过 `selectedConversation` 间接读取当前会话
- 改为直接复用 `_selectedConversationIndex()` 定位当前选中会话
- 命中后仍沿用原有的 `sessionRef`、`messages`、`draft` 前置检查

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_maybeAttachLatestSession()` 会先通过 `selectedConversation` 获取当前选中会话
- `selectedConversation` 内部再通过 `_selectedConversationIndex()` 做一次定位
- 之后才检查当前会话是否已有 sessionRef、messages 或 draft，并决定是否自动挂接最新 session

### 优化后行为

- `_maybeAttachLatestSession()` 改为直接调用 `_selectedConversationIndex()`
- 命中时仍然检查同样的 `sessionRef` / `messages` / `draft` 条件
- 未命中时仍然返回 `false`
- 自动挂接成功时仍然走现有的 `restoreSessionIntoConversation()` 链

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `ensureLoaded still skips auto-attach when selected conversation has draft` 测试通过
- 原有 `ensureLoaded auto-attached latest session persists only final state` 测试继续通过
- 原有 session restore、分页 restore、draft 同步和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉了 latest-session auto-attach 前置检查里的选中会话读取包装，不等于首屏 auto-attach 策略本身已经收口
- 当前“已有 draft 就不自动挂接最新 session”仍然是既有行为，本轮只验证保持，不做产品层调整
- 首屏是否应该继续自动挂接最新 session，仍然是文档里保留的后续体验与架构议题

## 第四十五轮优化记录

### 目标

第四十五轮只收敛 `createConversation()` 里的模板会话读取，
不改新建会话继承当前选中模板的语义。

### 本轮改动

模块：`conversation creation / template lookup`

- `createConversation()` 不再通过 `selectedConversation` 间接读取模板会话
- 改为直接复用 `_selectedConversationIndex()` 定位当前选中模板
- 未命中时仍然回退到 `null` 模板，保持原有默认值路径

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `createConversation()` 会先通过 `selectedConversation` 获取当前模板会话
- `selectedConversation` 内部再通过 `_selectedConversationIndex()` 做一次定位
- 然后再决定新会话是否继承当前模板的 project/profile/skills/history flags

### 优化后行为

- `createConversation()` 改为直接调用 `_selectedConversationIndex()`
- 命中时仍然读取同一个模板会话
- 未命中时仍然走原有的默认 project / threadMode / profile / skill / history 路径
- 新会话插入、排序、选中、保存和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `creating conversation still inherits selected template settings` 测试通过
- 原有 draft 同步、latest-session auto-attach、session restore 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉了新建会话模板读取包装，不等于会话创建策略本身已经收口
- 当前“默认 projectId 等于 `defaultProjectId` 时复用模板 project”的既有行为仍然保留，本轮只验证保持，不做产品层调整
- 模板继承字段当前仍分散在 `createConversation()` 内部，后续如果要做结构性收口，应该单独提炼模板解析职责

## 第四十六轮优化记录

### 目标

第四十六轮只收敛 `_selectedConversationIndex()` 在“当前选中即首项”场景下的查找开销，
不改未命中时回退首项的兼容语义。

### 本轮改动

模块：`selected conversation index / first-item fast path`

- `_selectedConversationIndex()` 新增首项快路径：
  当 `_selectedConversationId` 正好等于 `_conversations.first.id` 时，直接返回 `0`
- 其余场景仍走原有 `indexWhere()` 和 fallback 逻辑

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_selectedConversationIndex()` 会在 `_selectedConversationId` 非空时直接执行一次 `indexWhere()`
- 即使当前选中的本来就是列表首项，也会完整走一遍线性扫描
- 未命中时再回退到首项索引 `0`

### 优化后行为

- 当当前选中本来就是列表首项时，`_selectedConversationIndex()` 直接返回 `0`
- 其他场景仍然沿用原有 `indexWhere()` 查找
- 未命中时仍然回退到首项索引 `0`
- 空列表或空选中 id 时的返回语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `selected conversation still resolves first visible item by default` 测试通过
- 原有 `visible conversations keep demo order without getter-side sort` 测试继续通过
- 原有 draft 同步、latest-session auto-attach、session restore 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉了 `_selectedConversationIndex()` 在首项命中场景下的一次不必要扫描，不等于选中状态模型已经收口
- 当前“选中 id 缺失时回退到首项”的兼容语义仍然保留，本轮只验证保持，不做产品层调整
- 若后续要继续优化选中链路，应该整体评估是否需要显式索引结构，而不是继续堆更多局部快路径

## 第四十七轮优化记录

### 目标

第四十七轮只收敛 `sendCurrentPrompt()` 里的当前会话读取，
不改 prompt 发送、本地消息追加和 running 状态更新语义。

### 本轮改动

模块：`prompt dispatch / selected conversation lookup`

- `sendCurrentPrompt()` 不再通过 `selectedConversation` 间接读取当前会话
- 改为直接复用 `_selectedConversationIndex()` 定位当前选中会话
- 未命中时仍然直接返回，保持原有空选中防护语义

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `sendCurrentPrompt()` 会先通过 `selectedConversation` 获取当前会话
- `selectedConversation` 内部再通过 `_selectedConversationIndex()` 做一次定位
- 之后才构造 envelope、清空 composer、更新 running 状态并追加本地消息

### 优化后行为

- `sendCurrentPrompt()` 改为直接调用 `_selectedConversationIndex()`
- 命中时仍然读取同一个当前会话
- 未命中时仍然直接返回
- envelope 构造、composer 清空、本地消息追加、running/failed 状态更新和 dispatch 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `sendCurrentPrompt still appends local message and dispatches once` 测试通过
- 原有 `plain agent result appends a message with one listener notification` 测试继续通过
- 原有 draft 同步、latest-session auto-attach、session restore 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉了 prompt 发送入口的当前会话读取包装，不等于发送链路整体职责已经收口
- `sendCurrentPrompt()` 当前仍同时承担 envelope 构造、UI 状态切换、本地消息追加和 runtime dispatch 多类职责
- 若后续要继续优化发送链路，应该单独评估是否拆分本地 UI 变更和 runtime 发送职责

## 第四十八轮优化记录

### 目标

第四十八轮只收敛 `sendCurrentPrompt()` 到 `_appendMessage()` 之间的重复目标会话定位，
不改标题更新、本地消息追加和 running 状态语义。

### 本轮改动

模块：`prompt dispatch / append message index reuse`

- 为 `_appendMessage()` 补充私有索引入口 `_appendMessageAtIndex()`
- `sendCurrentPrompt()` 在已经拿到当前会话索引后，不再把同一个会话 id 传回 `_appendMessage()` 再做一次 `indexWhere()`
- 其他调用点仍继续走原有 `_appendMessage()` 入口

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `sendCurrentPrompt()` 会先通过 `_selectedConversationIndex()` 定位当前会话
- 构造 envelope 并更新本地运行状态后，又调用 `_appendMessage(conversation.id, ...)`
- `_appendMessage()` 内部会再次 `indexWhere()` 定位同一个会话
- 因此发送 prompt 的本地追加消息链里存在一次重复定位

### 优化后行为

- `sendCurrentPrompt()` 直接复用当前已拿到的 `conversationIndex`
- 通过 `_appendMessageAtIndex()` 直接对同一索引上的会话追加本地消息
- `_appendMessage()` 对其他调用点的入口语义保持不变
- 标题更新、本地消息追加、running/failed 状态更新和保存通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `sendCurrentPrompt still appends local message and dispatches once` 测试继续通过
- 新增 `sendCurrentPrompt still updates title from prompt` 测试通过
- 原有 draft 同步、latest-session auto-attach、session restore 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉了 prompt 发送链里的一次重复定位，不等于 `_appendMessage()` 热路径整体职责已经收口
- `_appendMessage()` 当前仍同时承担标题更新、草稿同步、已读时间更新、排序、保存和通知职责
- 若后续继续优化消息追加链路，应该考虑拆分“消息写入”和“UI 派生字段更新”职责，而不是继续只加局部索引入口

## 第四十九轮优化记录

### 目标

第四十九轮只收敛 `AgentDashboardModel` 内部按会话 id 定位索引的重复实现，
不改缺失 id 时各入口静默返回的语义，不引入新的索引缓存结构。

### 本轮改动

模块：`conversation id lookup / helper consolidation`

- 新增私有 helper：`_conversationIndexById(String conversationId)`
- 将多处直接 `indexWhere((conversation) => conversation.id == ...)` 收敛到同一个 helper
- 继续保留“首项命中直接返回 0”的快路径
- 未命中时仍然统一返回 `-1`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 多个同步入口各自直接写一遍 `indexWhere((conversation) => conversation.id == ...)`
- 包括会话设置、置顶/归档、删除、空 session reset、load more、消息追加、hydration 前置检查、已读更新等路径
- 首项快路径只存在于 `_selectedConversationIndex()` 自己内部

### 优化后行为

- 这些路径统一复用 `_conversationIndexById()`
- helper 内部保留首项命中快路径
- 未命中时仍然返回 `-1`，各入口原有的静默返回语义保持不变
- 本轮没有引入 map/index cache，也没有改异步链时序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `missing conversation mutation entrypoints still keep state unchanged` 测试通过
- 原有 `missing conversation unread lookup still returns false`、`loading more history for missing conversation still skips write`、`deleteConversation with missing id skips storage write` 测试继续通过
- 原有 send prompt、draft、auto-attach、session restore 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉了按 id 定位索引的重复实现，不等于会话索引策略已经演进为显式缓存结构
- 当前 helper 仍然是线性扫描，只是把实现集中起来，后续如果继续优化 lookup 成本，应该单独评估是否引入稳定索引结构
- 会话按 id 定位相关入口虽然现在共用一处 helper，但各自的副作用职责边界并没有因此自动收口

## 第五十轮优化记录

### 目标

第五十轮只收敛 `_applySessionDetail()` 会话详情合并路径里剩下的一次按 `conversationId`
重复定位，不改 session detail / page 合并、分页、排序、保存和静默返回语义。

### 本轮改动

模块：`session detail apply / conversation lookup reuse`

- 将 `_applySessionDetail()` 里的直接
  `indexWhere((conversation) => conversation.id == conversationId)` 改为复用
  `_conversationIndexById(conversationId)`
- 其余 detail 合并逻辑保持原样：
  - 先更新 `timeline` / `rawEvents` / `nextCursor`
  - 再合并 `restoredMessages`
  - 命中后仅替换目标会话
  - 根据原有参数决定是否排序、是否持久化

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_applySessionDetail()` 在前几轮已经把整表 `map()` 收敛成“定位索引后单元素替换”
- 但它自己仍单独保留了一次
  `indexWhere((conversation) => conversation.id == conversationId)` 直接查找
- 因而 session detail / page 合并热路径里，仍有一处没有收敛到统一 helper 的按 id 定位实现

### 优化后行为

- `_applySessionDetail()` 改为直接复用 `_conversationIndexById(conversationId)`
- 命中首项时继续走 helper 的首项快路径；未命中时仍然返回 `-1` 并直接静默返回
- session detail / page 合并出来的消息、标题、`sessionRef`、`threadMode`、
  `updatedAt`、排序和保存语义保持不变
- 本轮没有引入新的索引缓存，也没有改动异步时序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session restore loads detail once without duplicate hydration` 测试继续通过
- 原有 `paged session restore persists once after full hydration` 测试继续通过
- 原有 `task snapshot done refreshes session detail once`、`codex result done refreshes session detail once` 测试继续通过
- 原有缺失会话 id、draft、auto-attach 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉 `_applySessionDetail()` 里剩余的一次重复定位，不等于 session detail 合并链整体职责已经拆分完成
- `_applySessionDetail()` 当前仍同时承担 timeline/rawEvents 写入、消息恢复、标题/sessionRef 衍生、排序和持久化职责
- 如果后续继续优化 detail 热路径，应该单独评估是否拆分“会话绑定”和“detail merge / persist”职责，而不是在同一轮继续扩散改动

## 第五十一轮优化记录

### 目标

第五十一轮只收敛 `renameConversation()` 轻包装入口里的一次重复会话定位，
不改空标题保护、缺失会话 id 静默返回、标题更新持久化和排序通知语义。

### 本轮改动

模块：`rename conversation / wrapper lookup reuse`

- `renameConversation()` 在完成 `trim()` 和空字符串过滤后，
  直接调用 `_conversationIndexById(conversationId)`
- 命中后直接复用 `_updateConversationSettingsAtIndex()` 完成标题更新
- 不再先调用 `updateConversationSettings()` 再由统一入口第二次定位同一会话

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `renameConversation()` 会先做标题 `trim()` 和空字符串保护
- 非空时调用 `updateConversationSettings(conversationId: ..., title: ...)`
- `updateConversationSettings()` 内部再通过 `_conversationIndexById()` 定位目标会话
- 因而标题重命名这条轻包装入口里，仍存在一次“包装层进入统一入口后再做定位”的间接查找

### 优化后行为

- `renameConversation()` 在标题非空后，直接用 `_conversationIndexById()` 定位目标会话
- 未命中时仍然静默返回；命中后直接调用 `_updateConversationSettingsAtIndex()`
- 标题更新后的 `updatedAt`、排序、持久化、通知以及空标题保护语义保持不变
- 本轮没有引入新的缓存结构，也没有改动异步保存时序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `updating conversation title still persists once` 测试继续通过
- 原有 `missing conversation mutation entrypoints still keep state unchanged` 测试继续通过
- 原有 `resetDemoState restores visible conversation order` 测试继续通过
- 原有 pinned/archived、session restore、send prompt 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉 `renameConversation()` 轻包装入口里的一次重复定位，不等于所有包装型 mutation 入口都已经完成同类收敛
- `renameConversation()` 仍然把真正的副作用边界留在 `_updateConversationSettingsAtIndex()`，这轮没有继续拆 metadata 更新、排序、保存和通知职责
- 如果后续继续优化轻包装入口，应继续一轮只收一个入口，避免把“统一入口职责拆分”和“重复定位收敛”混在同一轮

## 第五十二轮优化记录

### 目标

第五十二轮只收敛 `_applyTaskSnapshot()` 在 session 绑定路径里的一次重复会话定位，
不改 task snapshot 的 timeline/rawEvents 写入、`sessionRef` 绑定、持久化和通知语义。

### 本轮改动

模块：`task snapshot / session binding lookup reuse`

- `_applyTaskSnapshot()` 在完成 timeline / rawEvents 写入后，
  若 detail 内带有效 `sessionId`，先调用 `_conversationIndexById(conversationId)`
- 命中后直接复用 `_updateConversationSettingsAtIndex()` 完成 `sessionRef` 和
  `threadMode: 'continue'` 绑定
- 不再先调用 `updateConversationSettings()` 再由统一入口二次定位同一会话

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_applyTaskSnapshot()` 会先写入 snapshot 的 `timeline` 和 `rawEvents`
- 当 detail 内带 `sessionId` 时，再调用
  `updateConversationSettings(conversationId: ..., sessionRef: ..., threadMode: 'continue')`
- `updateConversationSettings()` 内部再通过 `_conversationIndexById()` 定位目标会话
- 因而 task snapshot 的 session 绑定路径里，仍存在一次“包装层进入统一入口后再做定位”的间接查找

### 优化后行为

- `_applyTaskSnapshot()` 在写完 snapshot 数据后，直接用 `_conversationIndexById()` 定位目标会话
- 命中时直接调用 `_updateConversationSettingsAtIndex()` 完成 session 绑定
- 未命中时仍然维持原有“timeline/rawEvents 已写入，但不触发会话绑定”的结果
- task snapshot 的状态恢复、`sessionRef` 绑定、持久化、通知和后续 hydration 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `task snapshot still binds conversation session once` 测试继续通过
- 原有 `task snapshot done refreshes session detail once` 测试继续通过
- 原有 `codex result done refreshes session detail once`、`session restore loads detail once without duplicate hydration` 测试继续通过
- 原有缺失会话 id、标题重命名、pinned/archived 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉 `_applyTaskSnapshot()` session 绑定路径里的一次重复定位，不等于 snapshot 链整体职责已经拆分完成
- `_applyTaskSnapshot()` 当前仍同时承担 timeline/rawEvents 写入和 session 绑定入口职责
- 如果后续继续优化 snapshot 链，应单独评估“snapshot 数据写入”和“会话 metadata 绑定”是否需要拆分，而不是在同一轮继续扩散副作用边界

## 第五十三轮优化记录

### 目标

第五十三轮只收敛 `restoreSessionIntoConversation()` 正常 session 分支里的一次重复会话定位，
不改 continue 绑定、session detail 拉取、分页 hydration、排序、保存和失败处理语义。

### 本轮改动

模块：`session restore / continue binding lookup reuse`

- `restoreSessionIntoConversation()` 在确认 `sessionId.trim()` 非空后，
  先调用 `_conversationIndexById(conversationId)`
- 命中后直接复用 `_updateConversationSettingsAtIndex()` 完成
  `sessionRef` + `threadMode: 'continue'` 绑定
- 不再先调用 `updateConversationSettings()` 再由统一入口二次定位同一会话

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `restoreSessionIntoConversation()` 在 `sessionId` 非空时，
  会先调用 `updateConversationSettings(... sessionRef: normalizedSessionId, threadMode: 'continue')`
- `updateConversationSettings()` 内部再通过 `_conversationIndexById()` 定位目标会话
- 然后再进入 `_refreshConversationFromSession()`、`_hydrateRemainingSessionHistory()`、
  最终排序和保存链路
- 因而正常 session restore 入口里，仍存在一次“包装层进入统一入口后再做定位”的间接查找

### 优化后行为

- `restoreSessionIntoConversation()` 在 `sessionId` 非空后，直接用 `_conversationIndexById()` 定位目标会话
- 命中后直接调用 `_updateConversationSettingsAtIndex()` 完成 continue 绑定
- 未命中时现在会在进入 detail 拉取前直接返回；对现有已覆盖场景，仍保持“缺失会话 id 不写入状态”的结果
- 后续 session detail 拉取、分页 hydration、统一排序、单次保存和失败状态更新语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session restore loads detail once without duplicate hydration` 测试继续通过
- 原有 `paged session restore persists once after full hydration` 测试继续通过
- 原有 `clearing session restore still resets conversation state with one storage write`、`clearing an already blank conversation skips storage write` 测试继续通过
- 原有缺失会话 id、task snapshot、标题重命名和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉正常 session restore 入口里的一次重复定位，不等于 restore/hydration 链整体职责已经拆分完成
- `restoreSessionIntoConversation()` 当前仍同时承担 continue 绑定、detail 拉取、历史 hydration、状态文案和失败处理职责
- 如果后续继续优化 restore 链，应单独评估“continue 绑定入口”和“session 拉取 / hydration / 状态更新”是否需要拆分，而不是在同一轮继续扩大改动面

## 第五十四轮优化记录

### 目标

第五十四轮只收敛 `codexResult` 事件链里 session 绑定路径的一次重复会话定位，
不改 `done` / 非 `done` 分支的 continue 绑定、refresh、保存和通知语义。

### 本轮改动

模块：`codex result / session binding lookup reuse`

- `handleAgentResultEvent()` 进入 `kind == 'codexResult'` 分支后，
  当 detail 内带有效 `sessionId` 时，先调用 `_conversationIndexById(conversationId)`
- 命中后直接复用 `_updateConversationSettingsAtIndex()` 完成
  `sessionRef` + `threadMode: 'continue'` 绑定
- 不再先调用 `updateConversationSettings()` 再由统一入口二次定位同一会话

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `codexResult` 分支在拿到有效 `sessionId` 后，
  会先调用 `updateConversationSettings(... sessionRef: sessionId, threadMode: 'continue')`
- `updateConversationSettings()` 内部再通过 `_conversationIndexById()` 定位目标会话
- 非 `done` 分支在这里结束，`done` 分支再继续进入
  `_refreshConversationFromSession()`、统一排序和保存链路
- 因而 `codexResult` 的 session 绑定路径里，仍存在一次“包装层进入统一入口后再做定位”的间接查找

### 优化后行为

- `codexResult` 分支在拿到有效 `sessionId` 后，直接用 `_conversationIndexById()` 定位目标会话
- 命中后直接调用 `_updateConversationSettingsAtIndex()` 完成 continue 绑定
- `done` 分支仍继续做一次显式 session refresh、排序、保存和通知；非 `done` 分支仍保持原有 continue 绑定语义
- 对当前已覆盖场景，缺失会话 id 仍然不会产生有效会话写入结果

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `codex result done refreshes session detail once` 测试继续通过
- 原有 `task snapshot done refreshes session detail once` 测试继续通过
- 原有 `detail event without request id still updates session detail path`、`session restore loads detail once without duplicate hydration` 测试继续通过
- 原有缺失会话 id、标题重命名、task snapshot 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉 `codexResult` session 绑定路径里的一次重复定位，不等于 detail 事件链整体职责已经拆分完成
- `codexResult` 的 `done` 分支当前仍同时承担 continue 绑定、显式 refresh、排序、保存和 request 映射清理职责
- 如果后续继续优化 detail/result 事件链，应单独评估“session 绑定入口”和“done refresh / save / notify”职责边界，而不是在同一轮继续扩散改动

## 第五十五轮优化记录

### 目标

第五十五轮只收敛 `selectConversation()` 在“重复选中当前会话”分支里的一次选中 id 包装读取，
不改已读标记、hydration 触发、缺失会话 fallback 和通知语义。

### 本轮改动

模块：`select conversation / same-selection reuse`

- `selectConversation()` 在 `_selectedConversationId == conversationId` 的分支里，
  先复用 `_selectedConversationIndex()`
- 命中后直接取当前会话的 `id`，再继续走 `_markConversationRead()` 和
  `_ensureConversationHydrated()` 现有链路
- 不再把传入的同一个 `conversationId` 原样回传给两条按 id 的后续入口

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 当用户再次点中当前已选会话时，`selectConversation()` 会直接进入短路分支
- 该分支随后继续调用 `_markConversationRead(conversationId)` 和
  `_ensureConversationHydrated(conversationId)`
- 这两条后续入口内部都会再按 id 检查当前会话状态
- 因而“重复选中当前会话”路径里，仍存在一次对当前已知选中结果的包装读取

### 优化后行为

- 当再次点中当前已选会话时，先复用 `_selectedConversationIndex()` 拿到当前选中会话
- 命中后用该会话的 `id` 继续走原有 `_markConversationRead()` 和
  `_ensureConversationHydrated()` 链路
- 现有“已读则不持久化”“未 hydration 才加载”“缺失会话则直接返回”的语义保持不变
- 本轮没有改动切换到其他会话的主分支，也没有改动已读和 hydration 的内部逻辑

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `selecting an already-read conversation does not persist again` 测试继续通过
- 原有 `selecting unread conversation updates unread count once`、`selecting unread conversation still keeps lastReadAt semantics` 测试继续通过
- 原有 `switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 原有缺失会话 id、session restore、task snapshot 和 `codexResult done` 相关测试继续通过

### 风险备注

- 这轮只收掉 `selectConversation()` 重复选中分支里的包装读取，不等于选中链整体职责已经拆分完成
- `selectConversation()` 当前仍同时承担选中状态切换、草稿同步、已读更新、通知和 hydration 入口职责
- 如果后续继续优化选中链，应单独评估“同一会话重复选中”和“切换到新会话”两类分支是否需要进一步拆分，而不是在同一轮继续扩大影响面

## 第五十六轮优化记录

### 目标

第五十六轮只收敛 `selectConversation()` 切换主分支里的一次 fallback 选中包装读取，
不改缺失 id 回退、草稿同步、已读标记、通知和 hydration 语义。

### 本轮改动

模块：`select conversation / target id reuse`

- `selectConversation()` 在进入主分支后，先调用 `_conversationIndexById(conversationId)`
- 命中时直接使用目标会话 id；未命中且列表非空时，继续沿用原有 fallback 语义，改为显式选中 `_conversations.first.id`
- 后续 `_syncComposerWithSelectedConversation()`、`_markConversationRead()` 和
  `_ensureConversationHydrated()` 统一复用这个已经确定的 `nextSelectedConversationId`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `selectConversation()` 在切换到新会话时，会先把 `_selectedConversationId` 直接设成入参 `conversationId`
- 随后依次调用 `_syncComposerWithSelectedConversation()`、`_markConversationRead(conversationId)`、
  `_ensureConversationHydrated(conversationId)`
- 当入参 id 不存在时，真正生效的选中结果依赖 `_selectedConversationIndex()` 的 fallback-to-first 语义
- 因而主分支里，后续链路拿到的还是原始入参 id，而不是已经确定的最终选中会话 id

### 优化后行为

- `selectConversation()` 在主分支里先显式算出 `nextSelectedConversationId`
- 命中时就是目标会话 id；未命中且列表非空时，显式复用原有 fallback 结果 `_conversations.first.id`
- 后续草稿同步、已读标记和 hydration 统一复用这个最终选中 id
- 现有“缺失 id 时仍保持选中首个可见会话”“未读才持久化”“未 hydration 才继续加载”的语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `selecting missing conversation still keeps fallback selection without write` 测试继续通过
- 原有 `selecting a conversation with unread messages persists once`、`selecting unread conversation updates unread count once`、`selecting unread conversation still keeps lastReadAt semantics` 测试继续通过
- 原有 `switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 原有 session restore、task snapshot、`codexResult done` 和已读无写入相关测试继续通过

### 风险备注

- 这轮只收掉 `selectConversation()` 主分支里的 fallback 包装读取，不等于选中链整体职责已经拆分完成
- 当前主分支仍同时承担选中状态更新、草稿同步、已读更新、通知和 hydration 入口职责
- 如果后续继续优化选中链，应单独评估是否拆分“目标选中解析”和“选中后的副作用链”，而不是在同一轮继续扩大结构改动

## 第五十七轮优化记录

### 目标

第五十七轮只收敛 `selectConversation()` 选中链里的已读重复定位，
不改已读判定、持久化、通知、缺失 id fallback 和 hydration 语义。

### 本轮改动

模块：`select conversation / read-mark index reuse`

- 为 `_markConversationRead()` 补充索引入口 `_markConversationReadAtIndex(...)`
- `selectConversation()` 在“重复选中当前会话”分支里，已知当前索引后直接复用 `_markConversationReadAtIndex()`
- `selectConversation()` 主分支在已算出 `nextSelectedIndex` 后，也直接复用 `_markConversationReadAtIndex()`
- `_markConversationRead(String? conversationId, ...)` 仍保留原入口语义，只是在命中后委托给索引入口

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `selectConversation()` 在同一会话分支和切换主分支里，虽然已经分别拿到了当前索引或目标索引
- 但后续仍调用 `_markConversationRead(conversationId)`，由它内部再次通过 `_conversationIndexById()` 定位同一会话
- 因而选中链里的已读更新路径，仍存在一次“已知索引后再按 id 重查”的重复定位

### 优化后行为

- `selectConversation()` 在已知索引的分支里，直接复用 `_markConversationReadAtIndex()`
- `_markConversationRead()` 对其它仍只持有 id 的入口保持原有外部语义不变
- 现有“无未读则不写入”“有未读则单次持久化”“缺失 id 时静默返回”和 fallback-to-first 语义保持不变
- hydration 触发链路没有改动

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `selecting an already-read conversation does not persist again` 测试继续通过
- 原有 `selecting a conversation with unread messages persists once`、`selecting unread conversation updates unread count once`、`selecting unread conversation still keeps lastReadAt semantics` 测试继续通过
- 原有 `selecting missing conversation still keeps fallback selection without write`、`switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 原有 session restore、task snapshot、`codexResult done` 和 demo unread 相关测试继续通过

### 风险备注

- 这轮只收掉选中链里已读更新的一次重复定位，不等于 `selectConversation()` 整体职责已经拆分完成
- `_markConversationReadAtIndex()` 只是索引复用入口，没有改变 unread 判定或持久化策略
- 如果后续继续优化选中链，应继续把“已知索引复用”和“hydration / notify / composer 同步职责拆分”分开处理，避免同轮扩大改动面

## 第五十八轮优化记录

### 目标

第五十八轮只收敛 `selectConversation()` 选中链里的 hydration 重复定位，
不改 hydration 前置检查、session detail 拉取、分页加载、保存和通知语义。

### 本轮改动

模块：`select conversation / hydration index reuse`

- 为 `_ensureConversationHydrated()` 补充索引入口 `_ensureConversationHydratedAtIndex(int index)`
- `selectConversation()` 在“重复选中当前会话”分支里，已知当前索引后直接复用 `_ensureConversationHydratedAtIndex(index)`
- `selectConversation()` 主分支在已算出 `nextSelectedIndex` 后，也直接复用 `_ensureConversationHydratedAtIndex(nextSelectedIndex)`
- `_ensureConversationHydrated(String conversationId)` 仍保留原入口语义，只是在命中后委托给索引入口

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `selectConversation()` 在重复选中分支和切换主分支里，虽然已经拿到了当前或目标会话索引
- 但后续仍调用 `_ensureConversationHydrated(conversationId)`，由它内部再次通过 `_conversationIndexById()` 定位同一会话
- 因而选中链里的 hydration 入口，仍存在一次“已知索引后再按 id 重查”的重复定位

### 优化后行为

- `selectConversation()` 在已知索引的分支里，直接复用 `_ensureConversationHydratedAtIndex(...)`
- `_ensureConversationHydrated()` 对其它只持有 id 的入口保持原有外部语义不变
- 现有“无 sessionRef 不加载”“已有消息不加载”“进行中不重复加载”“加载后统一保存和通知”的语义保持不变
- 选中链里的已读处理、草稿同步和 fallback 语义没有改动

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `selecting missing conversation still keeps fallback selection without write` 测试继续通过
- 原有 `switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 原有 `ensureLoaded auto-attached latest session persists only final state`、`ensureLoaded still skips auto-attach when selected conversation has draft` 测试继续通过
- 原有 session restore、task snapshot、`codexResult done`、已读无写入和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉选中链里 hydration 入口的一次重复定位，不等于 hydration 链整体职责已经拆分完成
- `_ensureConversationHydratedAtIndex()` 只是索引复用入口，没有改变 hydration 的前置条件和后续副作用
- 如果后续继续优化 hydration 链，应把“索引复用”和“加载策略/副作用边界调整”继续拆开，避免同轮扩大改动

## 第五十九轮优化记录

### 目标

第五十九轮只收敛 `selectConversation()` 主分支里的 composer 同步包装读取，
不改 draft 同步、选中状态切换、已读、hydration、通知和 fallback 语义。

### 本轮改动

模块：`select conversation / composer sync index reuse`

- `selectConversation()` 主分支在已经拿到 `nextSelectedIndex` 后，
  直接从 `_conversations[nextSelectedIndex].draft` 同步 `textController`
- 只有在 `nextSelectedIndex == -1` 的兜底场景下，才继续走原有 `_syncComposerWithSelectedConversation()`
- 现有 `_syncComposerWithSelectedConversation()` 入口本身不改，继续服务其它仍只依赖当前选中态的路径

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `selectConversation()` 主分支在确定目标选中会话后，会统一调用 `_syncComposerWithSelectedConversation()`
- `_syncComposerWithSelectedConversation()` 内部再通过 `_selectedConversationIndex()` 解析当前选中会话，并读取其 draft
- 因而切换主分支里，虽然已经知道目标会话索引，composer 同步仍存在一次“通过选中态再解析目标会话”的包装读取

### 优化后行为

- `selectConversation()` 主分支在已知 `nextSelectedIndex` 时，直接读取目标会话 draft 并同步 `textController`
- `nextSelectedIndex == -1` 的兜底场景仍沿用 `_syncComposerWithSelectedConversation()`
- 现有“草稿相同不重复写值”“切换后 `textController` 对齐目标 draft”“缺失 id fallback 保持首会话”的语义保持不变
- 已读、hydration、通知和后续持久化链路没有改动

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 原有 `composer draft change still persists selected conversation once` 测试继续通过
- 原有 `selecting missing conversation still keeps fallback selection without write`、`selecting a conversation with unread messages persists once` 测试继续通过
- 原有 auto-attach、session restore、task snapshot、`codexResult done` 相关测试继续通过

### 风险备注

- 这轮只收掉选中链里 composer 同步的一次包装读取，不等于 composer 同步职责已经和选中链彻底解耦
- 当前主分支里仍然把选中状态切换、composer 同步、已读、hydration 和通知串在一起
- 如果后续继续优化选中链，应继续把“已知索引复用”和“副作用拆分”分轮处理，避免同轮扩大影响面

## 第六十轮优化记录

### 目标

第六十轮只收敛 `createConversation()` 新建会话后的 composer 同步包装读取，
不改模板继承、排序、保存、通知和新会话空草稿语义。

### 本轮改动

模块：`create conversation / composer sync reuse`

- `createConversation()` 在新建会话后，已知新会话 `draft` 固定为空字符串
- 将原来的 `_syncComposerWithSelectedConversation()` 改成直接把 `textController` 同步为空
- 只在当前 `textController.text` 非空时才执行这次同步，保持无变化时不重复写值

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `createConversation()` 在新建会话、排序并切换选中后，会调用 `_syncComposerWithSelectedConversation()`
- `_syncComposerWithSelectedConversation()` 内部再通过 `_selectedConversationIndex()` 解析当前选中会话并读取其 draft
- 但新建会话的 `draft` 在当前实现里固定就是空字符串
- 因而“新建后同步 composer”这一步，仍存在一次对已知结果的包装读取

### 优化后行为

- `createConversation()` 在新建会话后，直接把 `textController` 同步到空字符串
- 当 `textController` 本来就是空时，不会额外写值
- 新会话仍然保持空 draft，模板继承、排序、保存、通知和选中切换语义保持不变
- 本轮没有改动 `createConversation()` 的模板选择、`threadMode`、`profile`、`selectedSkillIds` 或持久化时序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `creating conversation still inherits selected template settings` 测试继续通过
- 原有 `switching conversation still syncs composer draft and keeps one write`、`composer draft change still persists selected conversation once` 测试继续通过
- 原有 auto-attach、session restore、task snapshot、`codexResult done` 和 fallback 相关测试继续通过

### 风险备注

- 这轮只收掉 `createConversation()` 新建后 composer 同步的一次包装读取，不等于创建链整体职责已经拆分完成
- 当前 `createConversation()` 仍同时承担模板继承、新会话插入、选中切换、保存和通知职责
- 如果后续继续优化创建链，应继续把“已知新会话默认值复用”和“创建后的副作用链拆分”分开处理，避免同轮扩大改动面

## 第六十一轮优化记录

### 目标

第六十一轮只收敛 `_maybeAttachLatestSession()` 自动挂接链里的会话重复定位，
不改首屏自动挂接条件、异步触发方式、session detail 拉取、分页 hydration、保存和失败回写语义。

### 本轮改动

模块：`auto attach latest session / restore tail reuse`

- 从 `restoreSessionIntoConversation()` 中提取“continue 绑定完成之后的 session detail 拉取、分页 hydration、排序、保存和状态文案回写”后半段，形成 `_restoreSessionIntoConversationAfterBinding(...)`
- `restoreSessionIntoConversation()` 在非空 session 分支里，仍先按原有方式完成 continue 绑定，再委托给这个后半段 helper
- `_maybeAttachLatestSession()` 在已经拿到目标会话索引、会话 id 和最新 session id 后，直接复用 `_updateConversationSettingsAtIndex(...)` 完成 continue 绑定
- 自动挂接后续仍通过 `unawaited(...)` 异步进入同一份 restore 后半段逻辑，保持首屏 `ensureLoaded()` 不等待完整 hydration 的现有时序

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_maybeAttachLatestSession()` 在已拿到当前选中会话索引和最新 session id 后，仍调用 `restoreSessionIntoConversation(conversationId, sessionId)`
- `restoreSessionIntoConversation()` 进入非空 session 分支后，会再次通过 `_conversationIndexById(conversationId)` 定位同一会话，然后才做 continue 绑定
- 因而首屏自动挂接最新 session 这条链里，仍存在一次“已知索引后再按 id 重查”的重复定位

### 优化后行为

- `_maybeAttachLatestSession()` 在已知索引场景下，直接完成 continue 绑定，再异步复用统一的 restore 后半段
- `restoreSessionIntoConversation()` 对外入口和空 session reset 分支语义保持不变；非空 session 分支只是把后半段加载逻辑抽出复用
- 现有“只有空白新会话才自动挂接最新 session”“自动挂接后仍异步加载 detail / 历史”“最终只持久化一次完整状态”的语义保持不变
- 失败时仍由同一条 restore 后半段写回 `failed` 状态和错误详情

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state` 测试继续通过
- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`、`session restore loads detail once without duplicate hydration` 测试继续通过
- 原有 paged session restore、task snapshot、`codexResult done`、fallback 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉自动挂接链里 continue 绑定前的一次重复定位，不等于 `restoreSessionIntoConversation()` 整体职责已经拆分完成
- `_restoreSessionIntoConversationAfterBinding(...)` 只是提取共享后半段，没有改变 session detail 拉取、分页 hydration、排序、保存和失败状态回写策略
- 如果后续继续优化 restore/auto-attach 链，应继续把“索引复用”和“首屏自动挂接策略调整”拆开处理，避免同轮改变现有行为

## 第六十二轮优化记录

### 目标

第六十二轮只收敛 `deleteConversation()` 删除后替代选中链里的 composer 同步包装读取，
不改删除语义、替代选中规则、已读处理、保存次数和通知时序。

### 本轮改动

模块：`delete conversation / replacement composer sync reuse`

- `deleteConversation()` 在完成真实删除后，显式计算替代会话索引：要么是新建 replacement，要么是删除后首项，要么是当前保留选中项
- 在已知替代会话索引时，直接从 `_conversations[replacementIndex].draft` 同步 `textController`
- 删除后替代会话的已读处理也直接复用 `_markConversationReadAtIndex(...)`
- 只在无法得到替代索引的兜底场景下，才继续保留 `_syncComposerWithSelectedConversation()` 和 `_markConversationRead(...)` 原有入口

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `deleteConversation()` 在删除后已经明确知道替代选中会话要么是新建项、要么是删除后首项、要么是现有选中项
- 但后续 composer 同步仍统一调用 `_syncComposerWithSelectedConversation()`
- `_syncComposerWithSelectedConversation()` 内部再通过 `_selectedConversationIndex()` 解析当前选中会话并读取其 draft
- 因而删除后的替代选中链里，仍存在一次“已知结果后再通过选中态包装读取”的重复访问

### 优化后行为

- `deleteConversation()` 在已知替代索引时，直接同步 replacement draft，并直接复用索引入口做已读处理
- 现有“删除后仍只保存一次最终状态”“删除首项后剩余会话顺序不变”“缺失 id 时静默返回”的语义保持不变
- 删除后如果 replacement draft 非空，`textController` 仍会与 replacement 保持一致
- 只有兜底场景才继续走原有包装入口，避免扩大本轮改动面

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `deleteConversation persists replacement selection once`、`deleteConversation preserves remaining conversation order`、`deleteConversation with missing id skips storage write` 测试继续通过
- 新增 `deleteConversation still syncs composer draft from replacement conversation` 测试通过
- 原有 `switching conversation still syncs composer draft and keeps one write`、auto-attach、session restore、task snapshot 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉删除后替代选中链里的 composer 包装读取，不等于 `deleteConversation()` 整体副作用边界已经拆分完成
- 当前 `deleteConversation()` 仍同时承担真实删除、替代选中、已读同步、保存和通知职责
- 如果后续继续优化删除链，应继续把“已知索引复用”和“删除后副作用拆分”分开处理，避免同轮扩大影响面

## 第六十三轮优化记录

### 目标

第六十三轮只收敛 `_updateConversationSettingsAtIndex()` 在选中会话 draft 更新时的 composer 包装读取，
不改 metadata 更新、session reset、保存、通知和 hydration 触发语义。

### 本轮改动

模块：`update conversation settings / selected draft sync reuse`

- `_updateConversationSettingsAtIndex()` 在已知当前就是选中会话且本轮显式传入 `draft` 时
  直接复用已经算出的 `nextDraft` 同步 `textController`
- 只有当 `textController.text` 与 `nextDraft` 不一致时才执行这次同步，保持无变化时不重复写值
- 其它仍依赖当前选中态解析的路径保持不动，本轮不改 `_syncComposerWithSelectedConversation()` 对外入口
- 补了一条针对 `updateConversationSettings(... draft: ...)` 的测试，锁住 composer 与持久化语义

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_updateConversationSettingsAtIndex()` 在本轮已经算出 `nextDraft` 并完成会话替换后
- 如果当前会话正好是选中会话，且调用方显式传入了 `draft`
- 仍会统一调用 `_syncComposerWithSelectedConversation()`
- `_syncComposerWithSelectedConversation()` 内部再通过 `_selectedConversationIndex()` 解析当前选中会话并读取其 draft
- 因而“更新选中会话 draft”这条链里，仍存在一次对已知 `nextDraft` 的包装读取

### 优化后行为

- `_updateConversationSettingsAtIndex()` 在已知 `nextDraft` 的场景下，直接同步 composer
- 现有“草稿变化仍只持久化一次”“未变化时不重复写 composer”“选中态之外不影响 composer”的语义保持不变
- metadata 更新、session reset、保存、通知和 hydration 触发时序没有改动
- `_syncComposerWithSelectedConversation()` 仍保留给其它还需要通过选中态读取 draft 的路径

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `composer draft change still persists selected conversation once`、`switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 新增 `updating selected conversation draft still syncs composer and persists once` 测试通过
- 原有 update settings、delete conversation、auto-attach、session restore、task snapshot 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉选中会话 draft 更新链里的一次包装读取，不等于 `updateConversationSettings()` 的副作用边界已经拆分完成
- 当前 `updateConversationSettings()` / `_updateConversationSettingsAtIndex()` 仍同时承担 metadata 更新、session reset、排序、保存、通知和 hydration 入口职责
- 如果后续继续优化这条链，应继续把“已知 next 值复用”和“副作用拆分”分轮处理，避免同轮扩大影响面

## 第六十四轮优化记录

### 目标

第六十四轮优先关闭 `_updateConversationSettingsAtIndex()` 在 continue session reset 后的 hydration 目标失配风险，
不改 settings 更新、session reset、保存、通知和 hydration 触发条件语义。

### 本轮改动

模块：`update conversation settings / hydration target stabilization`

- `_updateConversationSettingsAtIndex()` 在排序和通知之后，触发 hydration 前不再直接复用旧 `index`
- 改为在当前列表状态下再次通过 `conversationId` 稳定解析一次 `hydrationIndex`，再进入 `_ensureConversationHydratedAtIndex(...)`
- 补了一条通过 seed 两个会话复现“排序后旧索引失效”的测试，锁住 hydration 仍落到原会话而不是错会话/空跑
- 保留 `_ensureConversationHydratedAtIndex(...)` 作为真正执行 hydration 的入口，不扩散到其它链路

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_updateConversationSettingsAtIndex()` 在 continue session reset 后，会先更新 `updatedAt` 并 `_sortConversations()`
- 如果目标会话因为排序发生位置变化，之前持有的旧 `index` 就可能失效
- 在这种情况下，后续 hydration 如果直接按旧索引进入 `_ensureConversationHydratedAtIndex(...)`，就可能落到错误会话，甚至因为该位置会话没有 `sessionRef` 而直接空跑
- 因而 settings 更新后的 hydration 触发链，在“排序改变会话位置”场景下存在真实目标失配风险

### 优化后行为

- `_updateConversationSettingsAtIndex()` 在触发 hydration 前，先基于当前列表状态重新解析 `hydrationIndex`
- 现有“只有 continue + 非空 sessionRef + shouldResetSessionState 才触发 hydration”的语义保持不变
- 现有 detail 拉取、分页 hydration、settings 更新保存与 hydration 完成后的保存/通知语义保持不变
- 即使会话因为排序前移，hydration 仍会落到原来的 `conversationId`

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session rebinding still clears messages and only schedules one storage write`、`updating conversation with unchanged continue session skips write` 测试继续通过
- 原有 `updating conversation continue session still hydrates selected conversation once` 测试继续通过
- 新增 `updating conversation continue session still hydrates the same conversation after sort` 测试通过
- 原有 session restore、auto-attach、delete conversation、draft 同步、task snapshot 和 unread 相关测试继续通过

### 风险备注

- 这轮优先关闭了 hydration 目标失配风险，不等于 `updateConversationSettings()` / hydration 策略边界已经整体拆分完成
- 当前触发链仍然同时涉及排序、保存、通知和后续 hydration 副作用
- 如果后续继续优化这条链，应继续把“目标稳定解析”和“hydration 策略/副作用边界调整”拆开处理，避免同轮扩大影响面

## 第六十五轮优化记录

### 目标

第六十五轮只收敛 `ensureLoaded()` 末尾选中会话 hydration 触发链里的包装入口，
不改首屏加载、默认选中、auto-attach、保存和 hydration 条件语义。

### 本轮改动

模块：`ensureLoaded / selected hydration index reuse`

- `ensureLoaded()` 在已经完成初始会话加载、排序和选中态建立后
  触发首屏 hydration 时，先尝试直接复用 `_selectedConversationIndex()`
- 在能拿到有效索引时，直接进入 `_ensureConversationHydratedAtIndex(selectedIndex)`
- 只有极少数兜底场景下，才继续保留 `_ensureConversationHydrated(selectedId)` 这条按 id 的包装入口
- 补了一条 seeded continue 会话的测试，锁住 `ensureLoaded()` 末尾这条 hydration 触发链的现有行为

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `ensureLoaded()` 在完成初始会话准备后，已经知道 `_selectedConversationId`
- 且正常路径下也基本能直接解析当前选中会话索引
- 但末尾 hydration 触发仍统一调用 `_ensureConversationHydrated(selectedId)`
- `_ensureConversationHydrated()` 内部再通过 `_conversationIndexById(selectedId)` 重新定位同一会话
- 因而首屏选中会话 hydration 触发链里，仍存在一次“已知选中态后再走按 id 包装入口”的重复定位

### 优化后行为

- `ensureLoaded()` 在能直接拿到当前选中会话索引时，复用 `_ensureConversationHydratedAtIndex(...)`
- 现有“首屏加载后仍尝试 hydration 选中会话”“已有消息不重复加载”“auto-attach 路径仍保持原语义”的行为保持不变
- 只有兜底场景才继续走 `_ensureConversationHydrated(selectedId)`，避免同轮扩大改动面
- 这轮没有改动首屏保存时序、默认选中策略或 auto-attach 判断

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`、`ensureLoaded still skips auto-attach when selected conversation has draft` 测试继续通过
- 新增 `ensureLoaded still hydrates seeded selected continue conversation once` 测试通过
- 原有 session restore、settings 更新、delete conversation、draft 同步、task snapshot 和 unread 相关测试继续通过

### 风险备注

- 这轮只收掉 `ensureLoaded()` 末尾 hydration 触发入口的一次包装定位，不等于首屏加载链整体职责已经拆分完成
- 当前 `ensureLoaded()` 仍同时承担项目加载、初始会话建立、catalog 加载、默认选中、auto-attach 和首屏 hydration 触发职责
- 如果后续继续优化首屏链，应继续把“已知索引复用”和“首屏加载策略调整”拆开处理，避免同轮扩大影响面

## 第六十六轮优化记录

### 目标

第六十六轮只收敛 `handleAgentResultEvent()` 里结构化结果完成后的 session refresh / persist 尾链，
不改 request 归属、session 绑定、排序、保存、通知次数和历史 hydration 语义。

### 本轮改动

模块：`structured result done / session refresh finalization reuse`

- 在 `handleAgentResultEvent()` 中，`task_snapshot done` 和 `codexResult done`
  原本各自内联维护一段相似的 session refresh 收尾链
- 本轮新增 `_finalizeStructuredSessionRefresh(...)`，只复用同一套
  `detail refresh -> 可选 history hydration -> sort -> save`
  顺序
- `task_snapshot done` 保持“刷新首屏后继续补齐剩余历史”的原语义，
  通过 `hydrateRemainingHistory: true` 显式保留
- `codexResult done` 仍只刷新当前 session detail 首屏，不额外扩散到全量 history hydration
- request cleanup 和 `notifyListeners()` 保持留在各自调用点，避免 helper 收口扩大副作用边界
- 补了 `task_snapshot done` / `codexResult done` 的通知次数测试，锁住当前“绑定一次 + done 收尾一次”
  的双通知现状不回退

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `handleAgentResultEvent()` 在 `task_snapshot done` 分支里，会内联执行
  `refresh -> hydrate history -> sort -> save`，随后继续走该分支自己的 request cleanup 和 notify
- `handleAgentResultEvent()` 在 `codexResult done` 分支里，会内联执行
  `refresh -> sort -> save`，随后继续走该分支自己的 request cleanup 和 notify
- 两条链的主要差异只在于是否继续补历史，但它们共有的 refresh / persist 尾链仍是重复实现

### 优化后行为

- `task_snapshot done` 和 `codexResult done` 统一复用 `_finalizeStructuredSessionRefresh(...)`
  处理共同的 refresh / persist 尾链
- `task_snapshot done` 仍会刷新首屏 detail、补齐历史、排序、保存，并继续由原分支自己做 request cleanup 和 notify
- `codexResult done` 仍只刷新首屏 detail、排序、保存，并继续由原分支自己做 request cleanup 和 notify
- 当前 done 路径上的通知次数保持不变：session 绑定一次，done 收尾再一次
- 现有 request 归属、session 绑定、done 后刷新时机和最终保存/通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `task snapshot done refreshes session detail once`、`codex result done refreshes session detail once` 测试继续通过
- 原有 `task snapshot done request cleanup still routes later updates to selection` 测试继续通过
- 新增 `task snapshot done still notifies listeners twice`、`codex result done still notifies listeners twice` 测试通过
- 原有 session restore、ensureLoaded、settings 更新、delete conversation、draft 同步、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只收掉结构化结果 done 分支里的 refresh / persist 尾链重复实现，不等于
  `handleAgentResultEvent()` 的结构化分支职责已经拆分完成
- 当前 `handleAgentResultEvent()` 仍同时承担 request 归属、runtime 状态更新、
  detail 应用、结果收尾和消息兜底职责
- 当前 done 分支的双通知现状已被测试锁住；是否要继续收敛通知边界，应单独作为后续轮次处理
- 如果后续继续优化这条链，应继续把“refresh / persist 尾链复用”和“结构化结果分发/副作用边界拆分”
  拆开处理，避免同轮扩大影响面

## 第六十七轮优化记录

### 目标

第六十七轮只收敛 `ensureLoaded()` 初始选中会话链里的包装读取，
不改首屏选中、草稿同步、已读同步、保存和 hydration 语义。

### 本轮改动

模块：`ensureLoaded / initial selected draft and read sync reuse`

- `ensureLoaded()` 在初始会话准备和 `_selectedConversationId` 建立之后，
  先直接复用 `_selectedConversationIndex()`
- 在能拿到有效索引时，直接读取该会话 draft 同步 `textController`
- 同时直接复用 `_markConversationReadAtIndex(...)` 做首屏已读同步
- 只有极少数兜底场景才继续保留 `_syncComposerWithSelectedConversation()` 和
  `_markConversationRead(...)` 这两条包装入口
- 在已有 seeded draft 会话的测试里，补充断言 `textController` 仍与会话 draft 保持一致

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `ensureLoaded()` 在完成首屏会话准备后，已经知道 `_selectedConversationId`
- 且正常路径下也基本能直接解析当前选中会话索引
- 但草稿同步仍统一调用 `_syncComposerWithSelectedConversation()`
- 已读同步仍统一调用 `_markConversationRead(_selectedConversationId, ...)`
- 上述两个包装入口内部会再次通过选中态或会话 id 重新定位同一会话
- 因而 `ensureLoaded()` 初始选中链里，仍存在一次“已知索引后再走包装入口”的重复定位

### 优化后行为

- `ensureLoaded()` 在能直接拿到当前选中会话索引时，直接复用该索引完成 draft 同步和已读同步
- 现有“首屏 draft 仍同步到 composer”“首屏已读仍只做内存更新”“首屏保存和后续 hydration 时机保持不变”的行为保持不变
- 只有兜底场景才继续走 `_syncComposerWithSelectedConversation()` 和 `_markConversationRead(...)`
- 这轮没有改动默认选中策略、auto-attach 判断或首屏 hydration 触发条件

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`、`ensureLoaded still skips auto-attach when selected conversation has draft`、`ensureLoaded still hydrates seeded selected continue conversation once` 测试继续通过
- `ensureLoaded still skips auto-attach when selected conversation has draft` 现已额外确认 `textController` 与 seeded draft 保持一致
- 原有 session restore、settings 更新、delete conversation、draft 同步、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只收掉 `ensureLoaded()` 初始选中链里的两处包装读取，不等于首屏加载职责已经继续拆分完成
- 当前 `ensureLoaded()` 仍同时承担项目加载、初始会话建立、catalog 加载、默认选中、auto-attach、首屏草稿同步、已读同步和 hydration 触发职责
- 如果后续继续优化首屏链，应继续把“已知索引复用”和“首屏副作用边界/策略调整”拆开处理，避免同轮扩大影响面

## 第六十八轮优化记录

### 目标

第六十八轮只收敛 `resetDemoState()` 恢复选中 demo 会话后的 composer 同步包装入口，
不改 demo 会话重建、状态恢复、保存和通知语义。

### 本轮改动

模块：`resetDemoState / restored selection draft sync reuse`

- `resetDemoState()` 在 `_selectedConversationId` 已明确指向恢复后的首个 demo 会话后
  先直接复用 `_selectedConversationIndex()`
- 在能拿到有效索引时，直接读取该会话 draft 同步 `textController`
- 只有极少数兜底场景才继续保留 `_syncComposerWithSelectedConversation()` 包装入口
- 补了一条 `resetDemoState()` 后 composer 与 restored selection draft 保持一致的测试

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `resetDemoState()` 在重建 demo 会话、排序并设置 `_selectedConversationId` 为首项之后
- 已经知道当前选中会话通常就是可直接解析的首项
- 但 composer 同步仍统一调用 `_syncComposerWithSelectedConversation()`
- `_syncComposerWithSelectedConversation()` 内部再通过选中态重新解析同一会话 draft
- 因而 demo reset 链里，仍存在一次“已知选中索引后再走包装入口”的重复读取

### 优化后行为

- `resetDemoState()` 在能直接拿到当前选中 demo 会话索引时，直接复用该索引同步 composer
- 现有“reset 后仍恢复 demo 首项选中”“composer 仍跟随恢复后的首项 draft”“保存和通知时机保持不变”的行为保持不变
- 只有兜底场景才继续走 `_syncComposerWithSelectedConversation()`，避免同轮扩大改动面
- 这轮没有改动 demo runtime 状态恢复、会话排序或持久化逻辑

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `resetDemoState restores visible conversation order`、`resetDemoState restores demo runtime statuses` 测试继续通过
- 新增 `resetDemoState still syncs composer draft from restored selection` 测试通过
- 原有 ensureLoaded、session restore、settings 更新、delete conversation、draft 同步、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只收掉 `resetDemoState()` 恢复选中链里的一次 composer 包装读取，不等于 demo reset 边界已经继续拆分完成
- 当前 `resetDemoState()` 仍同时承担 demo 会话重建、排序、状态恢复、默认选中、composer 同步、保存和通知职责
- 如果后续继续优化 demo/reset 链，应继续把“已知索引复用”和“demo 状态初始化边界调整”拆开处理，避免同轮扩大影响面

## 第六十九轮优化记录

### 目标

第六十九轮只收敛 `selectConversation()` 主分支里目标会话对象的重复读取，
不改 fallback 选中语义、草稿同步、已读同步、通知和 hydration 时序。

### 本轮改动

模块：`selectConversation / resolved target conversation reuse`

- `selectConversation()` 在主分支里拿到 `nextSelectedIndex` 后，
  先解析一次 `nextSelectedConversation`
- 后续 `nextSelectedConversationId`、draft 同步、已读同步与 hydration 触发条件，
  都复用这份已解析的目标会话对象
- `nextSelectedIndex == -1` 的 fallback 分支继续保留原有按 id 的包装入口，
  不改异常态和兜底语义
- 没有新增测试，继续复用现有会话切换、missing id、unread 和 fallback 相关测试覆盖

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `selectConversation()` 在主分支里先通过 `nextSelectedIndex` 确定目标位置
- 但后续仍会分别再次通过 `_conversations[nextSelectedIndex]`
  读取目标会话的 `id` 和 `draft`
- 因而这条主分支里，仍存在一次“已知目标索引后再重复取同一对象”的重复读取

### 优化后行为

- `selectConversation()` 在主分支里先复用 `nextSelectedConversation`
- 现有“切换后仍同步目标 draft”“切换未读会话仍只持久化一次”“fallback 选中仍保持原语义”的行为保持不变
- 只有 `nextSelectedIndex == -1` 的兜底场景才继续走原有按 id 的包装入口
- 这轮没有改动 `notifyListeners()` 或 `_ensureConversationHydrated...` 的触发顺序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `switching conversation still syncs composer draft and keeps one write` 测试继续通过
- 原有 `selecting missing conversation still keeps fallback selection without write`、`selecting a conversation with unread messages persists once`、`selecting unread conversation still keeps lastReadAt semantics` 测试继续通过
- 原有 ensureLoaded、resetDemoState、session restore、settings 更新、delete conversation、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只收掉 `selectConversation()` 主分支里的一次目标会话对象重复读取，不等于切换链的 fallback 语义或副作用边界已经调整完成
- 当前 `selectConversation()` 仍同时承担选中切换、composer 同步、已读同步、通知和 hydration 触发职责
- 如果后续继续优化这条链，应继续把“主分支已知对象复用”和“fallback / 副作用边界调整”拆开处理，避免同轮扩大影响面

## 第七十轮优化记录

### 目标

第七十轮只收敛 `ensureLoaded()` 首屏选中链里当前不可达的兜底包装分支，
不改默认选中、草稿同步、已读同步、保存和 hydration 语义。

### 本轮改动

模块：`ensureLoaded / unreachable fallback removal`

- `ensureLoaded()` 在完成首屏会话准备后，当前实现已经保证：
  `_conversations` 非空且 `_selectedConversationId` 指向其中一个有效会话
- 基于这一不变量，`selectedIndex` 命中后即可直接完成首屏 draft 同步和已读同步
- 本轮删除了该链里当前不可达的 `_syncComposerWithSelectedConversation()` /
  `_markConversationRead(...)` 兜底分支
- 同时删除了末尾 hydration 触发里当前不可达的
  `_ensureConversationHydrated(selectedId)` 兜底分支
- 没有新增测试，继续复用现有 `ensureLoaded`、首屏选中和 hydration 相关测试验证不变量

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `ensureLoaded()` 在当前控制流下，正常会先保证有会话列表并建立 `_selectedConversationId`
- 之后再通过 `_selectedConversationIndex()` 解析当前选中会话索引
- 但即使在这一不变量下，代码仍保留三条按包装入口回退的分支：
  - `_syncComposerWithSelectedConversation()`
  - `_markConversationRead(_selectedConversationId, ...)`
  - `_ensureConversationHydrated(selectedId)`
- 因而首屏选中链里，仍存在一组当前结构下理论可达但实际不命中的兜底包装分支

### 优化后行为

- `ensureLoaded()` 在现有不变量成立时，直接复用已解析的 `selectedIndex`
- 现有“首屏仍建立默认选中”“草稿仍同步到 composer”“首屏已读和 hydration 触发语义保持不变”的行为保持不变
- 这轮没有改动默认选中策略、auto-attach 判断、保存时机或 hydration 触发顺序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`、`ensureLoaded still skips auto-attach when selected conversation has draft`、`ensureLoaded still hydrates seeded selected continue conversation once` 测试继续通过
- 原有 `selected conversation still resolves first visible item by default` 测试继续通过，继续证明首屏选中不变量成立
- 原有 session restore、settings 更新、delete conversation、resetDemoState、draft 同步、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `ensureLoaded()` 当前不变量下的不可达兜底分支，不等于首屏加载职责已经继续拆分完成
- 如果后续首屏恢复策略、会话初始化边界或 fallback 语义发生变化，这些不变量需要重新审计
- 后续如果继续优化首屏链，应继续把“不可达分支清理”和“首屏策略调整”拆开处理，避免同轮扩大影响面

## 第七十一轮优化记录

### 目标

第七十一轮只收敛 `resetDemoState()` 恢复 demo 会话链里当前不可达的 composer 兜底分支，
不改 demo 会话重建、默认选中、草稿同步、保存和通知语义。

### 本轮改动

模块：`resetDemoState / unreachable fallback removal`

- `resetDemoState()` 当前实现会先重建 demo 会话列表，并立即把
  `_selectedConversationId` 设为 `_conversations.first.id`
- `_buildDemoConversations()` 当前固定返回非空 demo 列表，而
  `_selectedConversationIndex()` 在列表非空时也不会返回 `-1`
- 基于这一不变量，`selectedIndex` 分支已经足以完成 demo 恢复后的 draft 同步
- 本轮删除了该链里当前不可达的 `_syncComposerWithSelectedConversation()` 兜底分支
- 同时新增一条窄测试，确认 `resetDemoState()` 后仍恢复到首个可见 demo 会话选中

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `resetDemoState()` 会先重建并排序 demo 会话，再把 `_selectedConversationId`
  指向首个 demo 会话
- 随后再通过 `_selectedConversationIndex()` 解析当前选中索引
- 但即使在“demo 列表非空且已显式选中首项”的不变量下，代码仍保留
  `_syncComposerWithSelectedConversation()` 这条按包装入口回退的兜底分支
- 因而 demo 重置链里，仍存在一条当前结构下理论保留但实际不命中的 composer fallback

### 优化后行为

- `resetDemoState()` 在现有不变量成立时，直接复用 `selectedIndex`
  完成 demo 恢复后的 draft -> composer 同步
- 现有“重置后仍恢复 demo 列表顺序”“仍恢复首个 demo 会话选中”“仍同步恢复后的 draft”
  “仍恢复 demo runtime 状态”的行为保持不变
- 这轮没有改动 `_save()`、`notifyListeners()`、demo 状态注入或排序时机

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `resetDemoState restores visible conversation order`、
  `resetDemoState still syncs composer draft from restored selection`、
  `resetDemoState restores demo runtime statuses` 测试继续通过
- 新增 `resetDemoState still restores first visible conversation as selection`
  测试通过，继续钉住本轮使用的选中不变量
- 原有 ensureLoaded、selectConversation、deleteConversation、session restore、
  unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `resetDemoState()` 当前不变量下的不可达 composer fallback，
  不等于 demo 初始化边界已经继续拆分完成
- 如果后续 demo 会话生成策略、默认选中策略或 `_selectedConversationIndex()`
  fallback 语义发生变化，这条不变量需要重新审计
- 后续如果继续优化 demo/reset 链，应继续把“不可达分支清理”和“demo 初始化策略调整”
  拆开处理，避免同轮扩大影响面

## 第七十二轮优化记录

### 目标

第七十二轮只收敛 `deleteConversation()` 删除后替代选中链里当前不可达的
composer / read 兜底分支，不改删除语义、替代选中、草稿同步、已读同步、保存和通知语义。

### 本轮改动

模块：`deleteConversation / unreachable fallback removal`

- `deleteConversation()` 删除成功后，当前实现总会把会话列表维持为非空：
  - 原列表删空时会立即补一个 `_newConversation()`
  - 删除当前选中会话时会把 `_selectedConversationId` 指向新的首项
  - 删除未选中会话时则继续保留现有 `_selectedConversationId`
- 在这一前提下，`replacementIndex` 要么直接被设为 `0`，要么复用
  `_selectedConversationIndex()` 在非空列表里的当前解析结果
- 基于这组不变量，`replacementIndex` 分支已经足以承担删除后的 draft 同步与已读同步
- 本轮删除了该链里当前不可达的 `_syncComposerWithSelectedConversation()` /
  `_markConversationRead(...)` 兜底分支
- 同时新增一条窄测试，确认删除未选中会话时仍保持当前选中和 composer draft 不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `deleteConversation()` 删除完成后，会先决定替代选中目标：
  - 删空列表时补新会话并设为选中
  - 删除当前选中会话时切到新首项
  - 删除未选中会话时继续复用当前选中态
- 随后通过 `replacementIndex` 决定删除后要同步的 draft 和已读状态
- 但即使在“删除后列表非空且选中态仍可解析”的不变量下，代码仍保留
  `_syncComposerWithSelectedConversation()` 和 `_markConversationRead(...)`
  这两条按包装入口回退的兜底分支
- 因而删除链里，仍存在一组当前结构下理论保留但实际不命中的 fallback

### 优化后行为

- `deleteConversation()` 在现有不变量成立时，直接复用 `replacementIndex`
  完成删除后的 draft 同步和已读同步
- 现有“删除当前会话后仍替换到新选中会话”“删除未选中会话仍保持当前选中”
  “composer draft 仍与替代选中保持一致”“仍只触发原有保存和通知语义”的行为保持不变
- 这轮没有改动删除入口、替代选中策略、`_save()` 时机或 `notifyListeners()` 顺序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `deleteConversation persists replacement selection once`、
  `deleteConversation preserves remaining conversation order`、
  `deleteConversation still syncs composer draft from replacement conversation`、
  `deleteConversation with missing id skips storage write` 测试继续通过
- 新增 `deleteConversation on unselected conversation still keeps current selection`
  测试通过，继续钉住删除未选中会话路径上的选中不变量
- 原有 ensureLoaded、resetDemoState、selectConversation、session restore、
  unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `deleteConversation()` 当前不变量下的不可达 fallback，
  不等于删除链的职责拆分已经完成
- 如果后续允许“无选中会话”状态、调整 `_selectedConversationIndex()` fallback 语义，
  或改变删除后替代选中策略，这组不变量需要重新审计
- 后续如果继续优化删除链，应继续把“不可达分支清理”和“删除职责拆分”
  拆开处理，避免同轮扩大影响面

## 第七十三轮优化记录

### 目标

第七十三轮只收敛 `_updateConversationSettingsAtIndex()` 在
continue-session reset 后 hydration 触发链里当前不可达的索引兜底判断，
不改 settings 更新、排序、保存、通知和 hydration 语义。

### 本轮改动

模块：`updateConversationSettings / hydration index unreachable guard removal`

- `_updateConversationSettingsAtIndex()` 当前只会在调用方已经用同一个
  `conversationId` 成功解析到 `index` 后进入
- helper 内部只做单会话替换和 `_sortConversations()`，不会删除目标会话
- 因而在 `shouldResetSessionState` 成立后，再次通过
  `_conversationIndexById(conversationId)` 解析 hydration 目标时，
  当前结构下不应再出现 `-1`
- 本轮删除了 `hydrationIndex != -1` 的兜底判断，直接复用已重解析出的
  hydration 目标索引进入 `_ensureConversationHydratedAtIndex(...)`
- 同时收紧现有排序后 hydration 回归测试，继续明确更新后目标会话已排到列表首位

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_updateConversationSettingsAtIndex()` 在完成单会话替换和排序后，
  若本轮需要 continue-session hydration，会再次通过 `conversationId`
  解析一次当前列表里的 hydration 目标索引
- 但即使当前 helper 调用前已经保证 `conversationId -> index` 可解析，
  且 helper 内部本轮不会删除该会话，代码仍保留
  `hydrationIndex != -1` 这条兜底判断
- 因而 settings 更新链里，仍存在一条当前结构下理论保留但实际不命中的
  hydration guard

### 优化后行为

- `_updateConversationSettingsAtIndex()` 在现有不变量成立时，直接复用
  重解析后的 `hydrationIndex` 进入 hydration
- 现有“continue session 更新后仍只 hydrate 一次”“排序后仍 hydrate 同一会话”
  “保存、通知和 session reset 语义不变”的行为保持不变
- 这轮没有改动外部 `updateConversationSettings()` 入口，也没有改动
  `_ensureConversationHydratedAtIndex(...)` 的异步触发顺序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `updating conversation continue session still hydrates selected conversation once`
  测试继续通过
- 原有 `updating conversation continue session still hydrates the same conversation after sort`
  测试继续通过，并额外确认更新后目标会话已排序到列表首位
- 原有 settings 更新、ensureLoaded、selectConversation、deleteConversation、
  resetDemoState、session restore、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `_updateConversationSettingsAtIndex()` 当前不变量下的一条不可达
  hydration guard，不等于 settings 更新职责已经拆分完成
- 如果后续允许 helper 在排序前后跨越更复杂的列表替换，或引入会话删除/过滤语义，
  这条不变量需要重新审计
- 后续如果继续优化 settings 链，应继续把“不可达 guard 清理”和“settings 职责拆分”
  拆开处理，避免同轮扩大影响面

## 第七十四轮优化记录

### 目标

第七十四轮只收敛 `_maybeAttachLatestSession()` 首屏自动挂接链里当前不可达的
选中索引兜底判断，不改 auto-attach 判断、session 绑定、恢复、保存和通知语义。

### 本轮改动

模块：`maybeAttachLatestSession / selected index unreachable guard removal`

- `_maybeAttachLatestSession()` 当前只会从 `ensureLoaded()` 的
  `_loadRuntimeCatalogs()` 链里进入
- 而 `ensureLoaded()` 在进入 runtime catalogs 之前，当前实现已经保证：
  - 会话列表非空
  - `_selectedConversationId` 已建立
  - `_selectedConversationIndex()` 在这一阶段可稳定解析当前选中会话
- 基于这一不变量，本轮删除了 `_maybeAttachLatestSession()` 里当前不可达的
  `index == -1` guard，直接复用已解析的首屏选中索引
- 没有新增测试，继续复用现有 ensureLoaded / auto-attach 回归测试验证语义不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_maybeAttachLatestSession()` 在首屏加载时，会先检查 session summaries 是否非空
- 然后再通过 `_selectedConversationIndex()` 解析当前选中会话
- 但即使这条链只会在 `ensureLoaded()` 已建立非空会话列表和有效选中态之后进入，
  代码仍保留 `index == -1` 这条兜底判断
- 因而首屏 auto-attach 链里，仍存在一条当前结构下理论保留但实际不命中的
  selected-index guard

### 优化后行为

- `_maybeAttachLatestSession()` 在现有不变量成立时，直接复用已解析的
  首屏选中索引进入 auto-attach 前置检查
- 现有“首屏空白会话仍可自动挂接最新 session”“有 draft 时仍跳过 auto-attach”
  “自动挂接后仍只保留最终保存结果”的行为保持不变
- 这轮没有改动 `ensureLoaded()` 顺序，也没有改动首屏 hydrate / save / notify 语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`
  测试继续通过
- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过
- 原有 `ensureLoaded still hydrates seeded selected continue conversation once`、
  `selected conversation still resolves first visible item by default` 等测试继续通过，
  继续证明本轮依赖的首屏选中不变量成立
- 原有 settings 更新、selectConversation、deleteConversation、resetDemoState、
  session restore、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `_maybeAttachLatestSession()` 当前不变量下的一条不可达
  selected-index guard，不等于首屏 auto-attach 策略已经继续拆分完成
- 如果后续调整 `ensureLoaded()` 顺序、允许首屏出现“无选中会话”状态，
  或改变首屏 session 自动挂接策略，这条不变量需要重新审计
- 后续如果继续优化首屏 auto-attach 链，应继续把“不可达 guard 清理”和
  “首屏策略调整”拆开处理，避免同轮扩大影响面

## 第七十五轮优化记录

### 目标

第七十五轮只收敛 `ensureLoaded()` 末尾首屏 hydration 触发链里当前不可达的
选中态兜底判断，不改首屏加载、auto-attach、草稿同步、保存、通知和 hydration 语义。

### 本轮改动

模块：`ensureLoaded / trailing hydration unreachable guard removal`

- `ensureLoaded()` 当前在进入末尾 hydration 触发前，已经完成：
  - 会话列表初始化或恢复
  - `_selectedConversationId` 建立
  - 首屏 draft / read 同步
  - runtime catalogs 加载及可选 latest-session auto-attach
- 在这一阶段，`_selectedConversationIndex()` 当前应可稳定解析首屏选中会话
- 基于这组不变量，本轮删除了 `ensureLoaded()` 末尾的
  `selectedId != null` / `selectedIndex != -1` 双层 guard，
  直接复用已解析的首屏选中索引进入 `_ensureConversationHydratedAtIndex(...)`
- 没有新增测试，继续复用现有 ensureLoaded / 首屏选中 / seeded continue hydration
  相关回归测试验证语义不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `ensureLoaded()` 在完成首屏准备后，会在末尾尝试对当前选中会话触发 hydration
- 但即使这一阶段当前实现已经保证会话列表非空且 `_selectedConversationId`
  已建立，代码仍保留：
  - `selectedId != null`
  - `selectedIndex != -1`
  这两层兜底判断
- 因而首屏加载尾链里，仍存在一组当前结构下理论保留但实际不命中的
  trailing hydration guard

### 优化后行为

- `ensureLoaded()` 在现有不变量成立时，直接复用首屏选中索引触发末尾 hydration
- 现有“首屏仍建立默认选中”“seeded continue 会话仍只 hydrate 一次”
  “latest-session auto-attach 仍保持原有保存语义”的行为保持不变
- 这轮没有改动 `ensureLoaded()` 入口顺序，也没有改动 `_ensureConversationHydratedAtIndex(...)`
  的异步触发时机

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`
  测试继续通过
- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过
- 原有 `ensureLoaded still hydrates seeded selected continue conversation once`、
  `selected conversation still resolves first visible item by default` 等测试继续通过，
  继续证明本轮依赖的首屏选中不变量成立
- 原有 settings 更新、selectConversation、deleteConversation、resetDemoState、
  session restore、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `ensureLoaded()` 当前不变量下的一组不可达 trailing hydration guard，
  不等于首屏加载职责已经继续拆分完成
- 如果后续调整 `ensureLoaded()` 顺序、允许首屏出现“无选中会话”状态，
  或改变首屏 hydration / auto-attach 策略，这组不变量需要重新审计
- 后续如果继续优化首屏加载链，应继续把“不可达 guard 清理”和“首屏策略调整”
  拆开处理，避免同轮扩大影响面

## 第七十六轮优化记录

### 目标

第七十六轮只收敛 `ensureLoaded()` 首段首屏 draft/read 同步链里当前不可达的
选中索引兜底判断，不改首屏初始化、draft 同步、已读同步、保存和后续 runtime catalogs 语义。

### 本轮改动

模块：`ensureLoaded / initial selected index unreachable guard removal`

- `ensureLoaded()` 当前在进入首屏 draft/read 同步前，已经完成：
  - 会话列表初始化或恢复
  - `_selectedConversationId` 建立
- 在这一阶段，`_selectedConversationIndex()` 当前应可稳定解析首屏选中会话
- 基于这组不变量，本轮删除了首段 `selectedIndex != -1` guard，
  直接复用首屏选中索引完成：
  - draft -> `textController` 同步
  - `_markConversationReadAtIndex(...)`
- 没有新增测试，继续复用现有 ensureLoaded / 首屏选中 / auto-attach / seeded continue
  相关回归测试验证语义不变

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `ensureLoaded()` 在会话列表和 `_selectedConversationId` 建立后，
  会先通过 `_selectedConversationIndex()` 解析当前首屏选中会话
- 但即使这一阶段当前实现已经保证首屏选中态存在，代码仍保留
  `selectedIndex != -1` 这条兜底判断
- 因而首屏初始化前半段里，仍存在一条当前结构下理论保留但实际不命中的
  initial selected-index guard

### 优化后行为

- `ensureLoaded()` 在现有不变量成立时，直接复用首屏选中索引完成
  draft 同步和首屏已读同步
- 现有“首屏仍建立默认选中”“有 draft 的 seeded 会话仍同步到 composer”
  “seeded continue 会话仍只 hydrate 一次”“latest-session auto-attach 语义不变”
  的行为保持不变
- 这轮没有改动 `ensureLoaded()` 的整体顺序，也没有改动后续 runtime catalogs /
  auto-attach / trailing hydration 触发时机

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`
  测试继续通过
- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过，并继续覆盖首屏 draft -> composer 同步
- 原有 `ensureLoaded still hydrates seeded selected continue conversation once`、
  `selected conversation still resolves first visible item by default` 等测试继续通过，
  继续证明本轮依赖的首屏选中不变量成立
- 原有 settings 更新、selectConversation、deleteConversation、resetDemoState、
  session restore、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只移除了 `ensureLoaded()` 当前不变量下的一条 initial selected-index guard，
  不等于首屏初始化职责已经继续拆分完成
- 如果后续调整 `ensureLoaded()` 顺序、允许首屏出现“无选中会话”状态，
  或改变首屏 draft/read 同步策略，这条不变量需要重新审计
- 后续如果继续优化首屏加载链，应继续把“不可达 guard 清理”和“首屏策略调整”
  拆开处理，避免同轮扩大影响面

## 第七十七轮优化记录

### 目标

第七十七轮只收敛 `restoreSessionIntoConversation()` 入口里对同一
`conversationId` 的重复定位，不改空 session reset、continue 绑定、
session restore、保存和通知语义。

### 本轮改动

模块：`restoreSessionIntoConversation / repeated lookup deduplication`

- `restoreSessionIntoConversation()` 原先在两个分支里各自重复执行一次
  `_conversationIndexById(conversationId)`：
  - `normalizedSessionId.isEmpty`
  - `normalizedSessionId.isNotEmpty`
- 本轮将这次定位前移到函数入口，只解析一次 `index`
- 空 session reset 分支和真实 session restore 分支继续复用同一个 `index`
- 没有改动 `_updateConversationSettingsAtIndex(...)`、后续
  `_restoreSessionIntoConversationAfterBinding(...)`、save、notify 和异常路径

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `restoreSessionIntoConversation()` 进入后，会先根据 `sessionId` 是否为空分流
- 但两个分支都会再次对同一个 `conversationId` 做一次 `_conversationIndexById(...)`
  定位
- 因而 restore 入口里，仍存在一次“同一调用上下文里重复解析同一会话索引”的重复扫描

### 优化后行为

- `restoreSessionIntoConversation()` 入口只解析一次 `conversationId -> index`
- 现有“空 session 时仍按原语义 reset blank / no-op 判定”
  “真实 session 时仍先绑定 continue 再 restore detail/history”
  “save / notify / failure 语义保持不变”的行为保持不变
- 这轮没有改动 restore 分流条件，也没有改动任何 session hydration 时机

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `clearing session restore still resets conversation state with one storage write`
  测试继续通过
- 原有 `clearing an already blank conversation skips storage write`
  测试继续通过
- 原有 `clearing session restore still preserves blank timeline state with one write`
  测试继续通过
- 原有 `session restore loads detail once without duplicate hydration`、
  `paged session restore persists once after full hydration` 测试继续通过
- 原有 ensureLoaded、settings 更新、selectConversation、deleteConversation、
  resetDemoState、unread 和 task snapshot 相关测试继续通过

### 风险备注

- 这轮只收掉 `restoreSessionIntoConversation()` 入口的一次重复定位，
  不等于 restore 职责已经继续拆分完成
- 如果后续 restore 入口引入更多按分支区分的前置检查，需重新确认这次前移的
  `index` 解析仍与各分支语义保持一致
- 后续如果继续优化 restore 链，应继续把“重复定位收敛”和“restore 职责拆分”
  拆开处理，避免同轮扩大影响面

## 第七十八轮优化记录

### 目标

第七十八轮只收敛结构化结果链里的重复 session 绑定实现，
不改 task snapshot、codex result、refresh、cleanup、保存和通知语义。

### 本轮改动

模块：`structured session binding helper reuse`

- `_applyTaskSnapshot()` 在拿到 `sessionId` 后，会执行一套
  `conversationId -> index -> _updateConversationSettingsAtIndex(...)`
  的 continue 绑定逻辑
- `handleAgentResultEvent()` 的 `codexResult` 分支在拿到 `sessionId` 后，
  也执行一套同构的 continue 绑定逻辑
- 本轮抽出内部 helper `_bindSessionRefAtConversation(...)`，
  统一承载这条 sessionRef 绑定实现
- `_applyTaskSnapshot()` 与 `codexResult` 分支现在共用该 helper，
  其余 refresh / request cleanup / notify 边界仍保留在各自调用点

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 结构化结果链里，`task_snapshot` 与 `codexResult` 在拿到 `sessionId` 后，
  都会重复实现一段相同的 continue session 绑定逻辑
- 这段重复实现包含：
  - `_conversationIndexById(conversationId)`
  - `index == -1` 退出
  - `_updateConversationSettingsAtIndex(...)`
- 因而结构化结果链里，仍存在一段“相同绑定逻辑在两个调用点重复实现”的重复代码

### 优化后行为

- `task_snapshot` 与 `codexResult` 在拿到 `sessionId` 后，统一复用
  `_bindSessionRefAtConversation(...)` 完成 continue session 绑定
- 现有“task snapshot 仍绑定 session”“codex result done 仍 refresh session detail”
  “request cleanup / notify / done 分支后续行为保持不变”的语义保持不变
- 这轮没有改动 `_finalizeStructuredSessionRefresh(...)`，
  也没有扩大 helper 副作用边界

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `task snapshot still binds conversation session once` 测试继续通过
- 原有 `task snapshot done refreshes session detail once`、
  `task snapshot done still notifies listeners twice`、
  `task snapshot done request cleanup still routes later updates to selection`
  测试继续通过
- 原有 `codex result done refreshes session detail once`、
  `codex result done still notifies listeners twice` 测试继续通过
- 原有 ensureLoaded、restoreSessionIntoConversation、settings 更新、
  selectConversation、deleteConversation、resetDemoState、unread 相关测试继续通过

### 风险备注

- 这轮只统一了结构化结果链里的 session 绑定实现，
  不等于 detail / snapshot / codexResult 的职责已经继续拆分完成
- 如果后续 `task_snapshot` 与 `codexResult` 对 session 绑定前后需要不同前置检查，
  需重新确认该 helper 仍适合共用
- 后续如果继续优化结构化结果链，应继续把“重复绑定实现收口”和
  “副作用边界拆分”拆开处理，避免同轮扩大影响面

## 第七十九轮优化记录

### 目标

第七十九轮只收敛 `_applyTaskSnapshot()` 与 `_applySessionDetail()`
 里重复的 timeline/rawEvents 存储实现，不改 session 绑定、消息合并、排序、
 保存和通知语义。

### 本轮改动

模块：`timeline/rawEvents storage helper reuse`

- `_applyTaskSnapshot()` 会把解析出的 `timeline` / `rawEvents`
  写回 `_timelineByConversation` / `_rawEventsByConversation`
- `_applySessionDetail()` 也会把解析出的 `timeline` / `rawEvents`
  写回同一组 map
- 本轮抽出内部 helper `_storeTimelineAndRawEvents(...)`，
  统一承载这段存储实现
- `_applyTaskSnapshot()` 与 `_applySessionDetail()` 现在共用这一个 helper，
  其余 session 绑定、消息合并、排序、save 和 notify 逻辑保持原位

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `task_snapshot` 链和 `session detail/page` 链都会各自重复实现
  `timeline/rawEvents -> map` 的存储逻辑
- 这两段逻辑写入目标一致，都是：
  - `_timelineByConversation[conversationId]`
  - `_rawEventsByConversation[conversationId]`
- 因而这两条链里，仍存在一段完全同类的重复存储实现

### 优化后行为

- `task_snapshot` 与 `session detail/page` 在解析出 `timeline/rawEvents` 后，
  统一复用 `_storeTimelineAndRawEvents(...)` 完成状态写回
- 现有“task snapshot 仍写回 timeline/rawEvents”
  “session restore/detail 仍写回 timeline/rawEvents”
  “消息合并、session 绑定、排序、save / notify 保持不变”的行为保持不变
- 这轮没有改动 `_applyTaskSnapshot()` 和 `_applySessionDetail()` 的外部调用方式

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `task snapshot still binds conversation session once`、
  `task snapshot done refreshes session detail once`、
  `task snapshot done still notifies listeners twice`、
  `task snapshot done request cleanup still routes later updates to selection`
  测试继续通过
- 新增 `task snapshot without session binding still stores timeline and raw events`
  测试通过，直接覆盖本轮 helper 对未绑定 session 的 task snapshot 链状态写回
- 原有 `session restore loads detail once without duplicate hydration`、
  `paged session restore persists once after full hydration` 测试继续通过
- 新增 `session restore still stores empty timeline and raw events from detail`
  测试通过，直接覆盖本轮 helper 对 session detail 链的状态写回
- 原有 ensureLoaded、settings 更新、selectConversation、deleteConversation、
  resetDemoState、unread 和 codex result 相关测试继续通过

### 风险备注

- 这轮只统一了 timeline/rawEvents 的存储实现，
  不等于 detail / snapshot 状态写回职责已经继续拆分完成
- 如果后续 `task_snapshot` 与 `session_detail/page` 对 timeline/rawEvents
  写回前后需要不同预处理，需重新确认该 helper 仍适合共用
- 后续如果继续优化 detail/snapshot 链，应继续把“重复状态写回收口”和
  “状态模型职责拆分”拆开处理，避免同轮扩大影响面

## 第八十轮优化记录

### 目标

第八十轮只收敛多条链路里重复的 draft -> composer 同步实现，
不改选中、保存、通知、已读和 hydration 语义。

### 本轮改动

模块：`composer draft sync helper reuse`

- 当前有多条链会在已知目标 draft 后，把它同步到 `textController`：
  - `ensureLoaded()`
  - `selectConversation()` 主分支
  - `_updateConversationSettingsAtIndex()` 选中会话 draft 更新分支
  - `deleteConversation()` 替代选中分支
  - `resetDemoState()`
- 这些位置原先都各自重复实现同一段
  `_syncingComposer / TextEditingValue / collapsed selection`
  的同步逻辑
- 本轮抽出内部 helper `_syncComposerDraft(String draft)`，
  统一承载这段 draft -> composer 同步实现
- 以上调用点现在共用该 helper；`_syncComposerWithSelectedConversation()`
  仍保留原有 fallback 语义，只改为内部复用 `_syncComposerDraft(...)`

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- 多条已知目标 draft 的链路里，都各自重复实现一段完全同类的
  composer 同步逻辑
- 这段逻辑都包含：
  - `textController.text != draft` 判定
  - `_syncingComposer = true/false`
  - `TextEditingValue(...)`
- 因而 draft 同步这类 UI 热路径里，仍存在一段“相同同步实现分散在多个调用点”的重复代码

### 优化后行为

- 已知目标 draft 的链路现在统一复用 `_syncComposerDraft(...)`
- 现有“首屏 draft 同步”“切换会话仍同步目标 draft”“删除替代选中仍同步 draft”
  “resetDemoState 仍恢复选中 draft”“直接按选中态 fallback 同步的 `_syncComposerWithSelectedConversation()` 语义不变”
  的行为保持不变
- 这轮没有改动任何调用点周围的 save、notify、read 或 hydration 顺序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过
- 原有 `switching conversation still syncs composer draft and keeps one write`
  测试继续通过
- 原有 `updating selected conversation draft still syncs composer and persists once`
  测试继续通过
- 原有 `deleteConversation still syncs composer draft from replacement conversation`
  测试继续通过
- 原有 `resetDemoState still syncs composer draft from restored selection`
  测试继续通过
- 原有 ensureLoaded、restoreSessionIntoConversation、task snapshot、
  codex result、deleteConversation、unread 等测试继续通过

### 风险备注

- 这轮只统一了 draft -> composer 的同步实现，
  不等于 composer/selection 职责已经继续拆分完成
- 如果后续某条链对 composer 同步前后需要额外副作用或不同光标策略，
  需重新确认该 helper 仍适合共用
- 后续如果继续优化 UI 热路径，应继续把“重复 draft 同步收口”和
  “选中/输入职责拆分”拆开处理，避免同轮扩大影响面

## 第八十一轮优化记录

### 目标

第八十一轮只收敛 `createConversation()` 里重复的 composer 清空实现，
不改新建会话的选中、保存、通知和模板继承语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `createConversation()` 在排序并切换到新建会话后，
  仍单独保留一段“如果 `textController.text` 非空，则手动把 composer 清空”的实现
- 这段实现和第八十轮刚统一的 `_syncComposerDraft(...)` 逻辑本质相同，
  仍重复包含：
  - `textController.text.isNotEmpty` / 空字符串同步判断
  - `_syncingComposer = true/false`
  - `TextEditingValue(text: '', selection: collapsed(0))`
- 因而在“已知目标 draft 就是空字符串”的新建会话链路里，
  仍存在一处未收口到统一 helper 的重复实现

### 优化后行为

- `createConversation()` 现在直接复用 `_syncComposerDraft('')`
- 新建会话后 composer 仍会被清空，且光标仍保持在 `0`
- 新建会话后的选中结果、模板继承、持久化次数和 `notifyListeners()` 顺序保持不变
- 本轮不改 `_syncComposerDraft(...)` 的内部实现，也不改其它调用点

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `creating conversation still inherits selected template settings`
  测试继续通过
- 新增 `creating conversation still clears composer draft`
  测试通过，锁定“新建会话后 composer 仍清空”行为
- 原有 `switching conversation still syncs composer draft and keeps one write`
  `updating selected conversation draft still syncs composer and persists once`
  `resetDemoState still syncs composer draft from restored selection`
  等相关 composer / 会话测试继续通过

### 风险备注

- 本轮只是把“新建会话后清空 composer”这条链收口到统一 helper，
  不等于新建会话与 composer 生命周期的职责已经拆清
- 如果后续 `createConversation()` 需要在清空前后追加额外 UI 副作用，
  仍需重新确认 `_syncComposerDraft('')` 是否适合作为唯一入口

## 第八十二轮优化记录

### 目标

第八十二轮只收敛 `selectConversation()` 已拿到目标选中索引后的副作用组织方式，
不改 fallback 选中语义，不改重复点击当前会话时的现有行为。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `selectConversation()` 在切换到一个已知存在的目标会话后，
  会在主分支里分散执行三类副作用：
  - `composer` 草稿同步
  - 已读状态同步
  - 后续 hydration 调度
- 其中前两类副作用在“已拿到目标索引”的前提下，
  仍分散写在主分支里，而不是通过统一 helper 收口
- 同时，“重复点击当前已选会话”这条分支只做已读和 hydration，
  不主动重同步 composer，这一语义已经被现有行为和测试隐含依赖

### 优化后行为

- 新增内部 helper `_syncSelectedConversationSideEffects(...)`
- `selectConversation()` 在主分支里，拿到 `nextSelectedIndex` 后改为复用该 helper
  统一执行：
  - 目标 draft -> composer 同步
  - 目标会话已读同步
- “重复点击当前已选会话”分支继续显式传 `syncComposer: false`，
  保持原有“只做已读和 hydration，不额外同步 composer”的行为
- fallback 分支仍沿用原来的 `_syncComposerWithSelectedConversation()`、
  `_markConversationRead(...)` 和 `_ensureConversationHydrated(...)`
  入口，本轮不改其语义和调用顺序

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `switching conversation still syncs composer draft and keeps one write`
  测试继续通过
- 原有 `selecting an already-read conversation does not persist again`
  测试继续通过
- 原有 `selecting a conversation with unread messages persists once`
  测试继续通过
- 原有 `selecting missing conversation still keeps fallback selection without write`
  测试继续通过，确认 fallback 选中语义未变

### 风险备注

- 本轮只收口了“已拿到目标索引后的副作用组织方式”，
  不等于 `selectConversation()` 的 fallback / 选中状态模型已经完全收清
- 如果后续需要继续压缩该方法，应把“主分支索引已知路径”和
  “fallback-to-first 兼容语义”继续分开处理，避免同轮改变现有兼容行为

## 第八十三轮优化记录

### 目标

第八十三轮只收敛 `ensureLoaded()` 与 `deleteConversation()` 里
“目标选中索引已知后的 composer + 已读同步”重复实现，
不改首屏初始化、删除替代选中和持久化语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `ensureLoaded()` 在已拿到 `selectedIndex` 后，
  仍分开调用：
  - `_syncComposerDraft(_conversations[selectedIndex].draft)`
  - `_markConversationReadAtIndex(..., notify: false, persist: false)`
- `deleteConversation()` 在已拿到 `replacementIndex` 后，
  也仍分开调用同一组副作用
- 而第八十二轮里 `selectConversation()` 主分支已经引入
  `_syncSelectedConversationSideEffects(...)` 统一承载同类逻辑，
  因此这两条链里仍存在同类重复实现

### 优化后行为

- `ensureLoaded()` 与 `deleteConversation()` 现在都直接复用
  `_syncSelectedConversationSideEffects(...)`
- 两处调用继续显式保留原有参数语义：
  - `notifyRead: false`
  - `persistRead: false`
- 这意味着首屏初始化和删除替代选中后的：
  - composer 同步
  - 已读同步
  - 不额外触发已读写盘
  行为保持不变
- 本轮不改后续 hydration 调度，不改 fallback 语义，也不改 helper 内部的
  composer / read 实现

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过
- 原有 `switching conversation still syncs composer draft and keeps one write`
  测试继续通过
- 原有 `deleteConversation still syncs composer draft from replacement conversation`
  测试继续通过
- 原有 `deleteConversation persists replacement selection once`
  测试继续通过，确认删除替代选中后的持久化语义未变

### 风险备注

- 本轮只是继续收口“索引已知后的副作用组织方式”，
  不等于首屏初始化和删除链的职责边界已经完全拆清
- 如果后续继续扩大 `_syncSelectedConversationSideEffects(...)` 的职责，
  需要重新确认它是否仍适合同时服务于初始化链、切换链和删除链

## 第八十四轮优化记录

### 目标

第八十四轮只收敛 `resetDemoState()` 当前不变量下的一条不可达 `selectedIndex` guard，
不改 demo 会话重建、默认选中、草稿同步、保存和通知语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `resetDemoState()` 会先重建 demo 会话列表并排序
- 然后把 `_selectedConversationId` 设为 `_conversations.first.id`
- 再通过 `_selectedConversationIndex()` 解析当前选中索引
- 但即使在这组不变量已经成立的前提下，代码仍额外保留
  `if (selectedIndex != -1)` 这条 guard
- 而根据当前实现：
  - `_buildDemoConversations()` 固定返回非空列表
  - `_selectedConversationId` 会被显式指向首项
  - `_selectedConversationIndex()` 在此阶段当前不应返回 `-1`

### 优化后行为

- `resetDemoState()` 现在直接复用 `selectedIndex`
  完成恢复后的 draft -> composer 同步
- 现有“重置后仍恢复 demo 列表顺序”“仍恢复首个 demo 会话选中”
  “仍同步恢复后的 draft”“仍恢复 demo runtime 状态”的行为保持不变
- 本轮没有改动 `_save()`、`notifyListeners()`、demo 状态注入或排序时机

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `resetDemoState restores visible conversation order`
  测试继续通过
- 原有 `resetDemoState still syncs composer draft from restored selection`
  测试继续通过
- 原有 `resetDemoState still restores first visible conversation as selection`
  测试继续通过
- 原有 `resetDemoState restores demo runtime statuses`
  测试继续通过

### 风险备注

- 这轮只移除了 `resetDemoState()` 当前不变量下的一条不可达 guard，
  不等于 demo/reset 链的职责边界已经继续拆分完成
- 如果后续 `_buildDemoConversations()`、默认选中策略或
  `_selectedConversationIndex()` fallback 语义发生变化，
  这条不变量需要重新审计

## 第八十五轮优化记录

### 目标

第八十五轮只收敛 `renameConversation()`、`toggleConversationPinned()`、
`toggleConversationArchived()` 这三条薄包装入口里的重复
`conversationId -> index -> _updateConversationSettingsAtIndex(...)` 路径，
不改标题更新、pin/archive 切换和缺失 id 时直接返回的现有语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `renameConversation()` 在校验标题非空后，
  仍手动执行一次：
  - `_conversationIndexById(conversationId)`
  - `index == -1` 返回
  - `_updateConversationSettingsAtIndex(...)`
- `toggleConversationPinned()` 与 `toggleConversationArchived()`
  也各自保留同类的 id -> index -> helper 转发实现
- 三条入口虽然业务参数不同，但底层“按 id 找 index 后进入
  `_updateConversationSettingsAtIndex(...)`”的组织方式重复

### 优化后行为

- 新增内部 helper `_updateConversationSettingsById(...)`
- `renameConversation()`、`toggleConversationPinned()`、
  `toggleConversationArchived()` 现在统一复用这条路径
- 三条入口各自保留原有业务语义：
  - `renameConversation()` 仍要求标题非空
  - `toggleConversationPinned()` 仍基于当前会话 `pinned` 状态取反
  - `toggleConversationArchived()` 仍基于当前会话 `archived` 状态取反，
    并继续传入 `lastReadAt: DateTime.now()`
- 缺失 `conversationId` 时仍然直接返回，不触发保存或通知

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `missing conversation mutation entrypoints still keep state unchanged`
  测试继续通过
- 原有 `updating conversation title still persists once`
  测试继续通过
- 原有 `toggling pinned and archived still persists once per change`
  测试继续通过

### 风险备注

- 本轮只统一了三条薄包装入口的转发路径，
  不等于 `updateConversationSettings` 家族的职责边界已经继续拆清
- 如果后续继续压缩 settings 链，应继续把“id -> index 转发统一”和
  “settings 行为语义调整”拆开处理，避免同轮扩大影响面

## 第八十六轮优化记录

### 目标

第八十六轮只收敛公有 `updateConversationSettings()` 入口里重复的
`conversationId -> index -> _updateConversationSettingsAtIndex(...)` 转发路径，
不改 settings 更新、缺失 id 时直接返回、hydration 或持久化语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 公有 `updateConversationSettings()` 入口仍手动执行一次：
  - `_conversationIndexById(conversationId)`
  - `index == -1` 直接返回
  - `_updateConversationSettingsAtIndex(...)`
- 而第八十五轮已经把三条薄包装入口统一到了
  `_updateConversationSettingsById(...)`
- 因此当前 settings 家族里仍保留一条同类的转发重复实现

### 优化后行为

- `updateConversationSettings()` 现在直接复用
  `_updateConversationSettingsById(...)`
- 缺失 `conversationId` 时仍然直接返回，不触发保存、通知或 hydration
- 原有参数透传语义保持不变：
  - `title / projectId / threadMode / profile / sessionRef`
  - `selectedSkillIds / pinned / archived / draft`
  - `includeConversationHistory / includeTerminalContext / lastReadAt`
  - `hydrateIfNeeded / persist`
- 本轮不改 `_updateConversationSettingsAtIndex(...)` 内部的排序、保存、通知和
  hydration 逻辑

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `missing conversation mutation entrypoints still keep state unchanged`
  测试继续通过，并补充覆盖 `updateConversationSettings(conversationId: missing)`
- 原有 `updating conversation with unchanged continue session skips write`
  测试继续通过
- 原有 `updating conversation title still persists once`
  测试继续通过
- 原有 `updating conversation continue session still hydrates selected conversation once`
  测试继续通过
- 原有 `updating selected conversation draft still syncs composer and persists once`
  测试继续通过

### 风险备注

- 本轮只统一了公有 settings 入口的转发路径，
  不等于 settings 链的职责边界或参数组合复杂度已经继续下降
- 如果后续继续优化 settings 链，应继续把“转发统一”“不可达 guard 清理”和
  “真实行为语义调整”拆开处理，避免同轮扩大影响面

## 第八十七轮优化记录

### 目标

第八十七轮只收敛 `_maybeAttachLatestSession()` 与
`restoreSessionIntoConversation(sessionId != '')` 两条 continue session 绑定链里的
重复实现，不改空 session reset、后续 restore/hydration、保存和通知语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_maybeAttachLatestSession()` 在拿到目标会话和 `sessionId` 后，
  仍直接手写一段 continue 绑定：
  - `_updateConversationSettingsAtIndex(...)`
  - `hydrateIfNeeded: false`
  - `persist: false`
- `restoreSessionIntoConversation()` 在 `sessionId.trim().isNotEmpty` 分支里，
  也直接手写同类的 continue 绑定，然后再进入
  `_restoreSessionIntoConversationAfterBinding(...)`
- 而第七十八轮已经存在 `_bindSessionRefAtConversation(...)`
  专门统一结构化结果链里的同类 session 绑定路径

### 优化后行为

- `_maybeAttachLatestSession()` 与
  `restoreSessionIntoConversation(sessionId != '')`
  现在都直接复用 `_bindSessionRefAtConversation(...)`
- 两处调用继续显式保留原有参数语义：
  - `hydrateIfNeeded: false`
  - `persist: false`
- 现有“自动挂接后继续走统一 restore 后半段”
  “正常 session restore 仍先绑定、再拉 detail / hydrate history”的行为保持不变
- 空 session reset 分支保持不变，本轮不改

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过
- 原有 `session restore loads detail once without duplicate hydration`
  测试继续通过
- 原有 `paged session restore persists once after full hydration`
  测试继续通过
- 原有 `clearing session restore still resets conversation state with one storage write`
  测试继续通过，确认空 session reset 分支语义未变

### 风险备注

- 本轮只统一了两条 continue session 绑定链的入口实现，
  不等于 `restoreSessionIntoConversation()` 和自动挂接链的职责已经继续拆清
- 如果后续 `restoreSessionIntoConversation()` 非空分支和自动挂接链
  需要不同的绑定前后语义，需重新确认 `_bindSessionRefAtConversation(...)`
  是否仍适合共用

## 第八十八轮优化记录

### 目标

第八十八轮只收敛 `_maybeAttachLatestSession()` 在已知目标索引场景下的一次
重复 `conversationId -> index` 定位，不改 continue 绑定语义、自动挂接条件、
restore 后半段、保存和通知时序。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_maybeAttachLatestSession()` 已经拿到：
  - 当前选中会话 `index`
  - 当前选中会话 `conversation.id`
  - 最新 `sessionId`
- 但它仍调用 `_bindSessionRefAtConversation(conversationId, sessionId, ...)`
- 后者内部会再次做一次 `_conversationIndexById(conversationId)`
- 因而自动挂接链里仍存在一段“已知索引后再按 id 重查”的重复定位

### 优化后行为

- 新增内部 helper `_bindSessionRefAtIndex(...)`
- `_maybeAttachLatestSession()` 在已知索引场景下直接复用该 helper
- `_bindSessionRefAtConversation(...)` 继续保留原有对外语义，
  只改为内部复用 `_bindSessionRefAtIndex(...)`
- 现有“只有空白新会话才自动挂接最新 session”
  “自动挂接后仍异步进入统一 restore 后半段”
  “最终只持久化一次完整状态”的行为保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `ensureLoaded auto-attached latest session persists only final state`
  测试继续通过
- 原有 `ensureLoaded still skips auto-attach when selected conversation has draft`
  测试继续通过
- 原有 `session restore loads detail once without duplicate hydration`
  测试继续通过

### 风险备注

- 本轮只收掉自动挂接链里当前已知索引场景下的一次重复定位，
  不等于 auto-attach / restore 链的职责边界已经继续拆清
- 如果后续 `_bindSessionRefAtConversation(...)` 与 `_bindSessionRefAtIndex(...)`
  前后需要不同前置检查，需重新确认这两个 helper 的边界

## 第八十九轮优化记录

### 目标

第八十九轮只收敛 `restoreSessionIntoConversation(sessionId != '')`
在已知目标索引场景下的一次重复 `conversationId -> index` 定位，
不改 continue 绑定语义、空 session reset 分支、restore 后半段、保存和通知时序。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `restoreSessionIntoConversation()` 入口一开始已经通过
  `_conversationIndexById(conversationId)` 拿到了目标会话 `index`
- 在 `sessionId != ''` 的正常 restore 分支里，它随后仍调用
  `_bindSessionRefAtConversation(conversationId, sessionId, ...)`
- 后者内部会再次做一次 `_conversationIndexById(conversationId)`
- 因而正常 session restore 链里，仍存在一段“已知索引后再按 id 重查”的重复定位

### 优化后行为

- `restoreSessionIntoConversation()` 在已知索引场景下直接复用
  `_bindSessionRefAtIndex(...)`
- 现有 continue 绑定参数语义保持不变：
  - `hydrateIfNeeded: false`
  - `persist: false`
- 现有“先绑定 sessionRef，再进入统一 restore 后半段”的行为保持不变
- 空 session reset 分支、detail 加载、history hydration、最终保存和通知时序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `session restore loads detail once without duplicate hydration`
  测试继续通过
- 原有 `paged session restore persists once after full hydration`
  测试继续通过
- 原有 `clearing session restore still resets conversation state with one storage write`
  测试继续通过，确认空 session reset 分支语义未变
- 原有 `missing conversation mutation entrypoints still keep state unchanged`
  测试继续通过，确认缺失 id 提前返回语义未变

### 风险备注

- 本轮只收掉正常 session restore 链里当前已知索引场景下的一次重复定位，
  不等于 `restoreSessionIntoConversation()` 的职责边界已经继续拆清
- 如果后续正常 restore 分支与其他 continue 绑定入口需要不同前置检查，
  需重新确认 `_bindSessionRefAtIndex(...)` 与 `_bindSessionRefAtConversation(...)`
  的共用边界

## 第九十轮优化记录

### 目标

第九十轮只收敛 `toggleConversationPinned()` 与
`toggleConversationArchived()` 在已知目标索引场景下的一次重复
`conversationId -> index` 定位，不改 pin/archive 切换语义、`lastReadAt`
写入、保存和通知时序。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `toggleConversationPinned()` 与 `toggleConversationArchived()`
  入口一开始都已经通过 `_conversationIndexById(conversationId)`
  拿到了目标会话 `index`
- 两个入口随后都读取了当前会话对象，用来计算：
  - `!conversation.pinned`
  - `!conversation.archived`
- 但它们之后仍调用 `_updateConversationSettingsById(conversationId, ...)`
- 后者内部会再次做一次 `_conversationIndexById(conversationId)`
- 因而这两条 pin/archive 切换链里，仍存在“已知索引后再按 id 重查”的重复定位

### 优化后行为

- `toggleConversationPinned()` 与 `toggleConversationArchived()`
  在已知索引场景下直接复用 `_updateConversationSettingsAtIndex(...)`
- 现有业务语义保持不变：
  - pinned 仍基于当前值取反
  - archived 仍基于当前值取反
  - archived 仍继续写入 `lastReadAt: DateTime.now()`
- 缺失 `conversationId` 时仍然直接返回，不触发保存或通知
- 保存、排序、通知和后续副作用时序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `toggling pinned and archived still persists once per change`
  测试继续通过
- 原有 `missing conversation mutation entrypoints still keep state unchanged`
  测试继续通过，确认缺失 id 提前返回语义未变
- 原有 `updating conversation title still persists once`
  测试继续通过，确认 `_updateConversationSettingsById(...)`
  仍保留给其他入口使用时语义未变

### 风险备注

- 本轮只收掉 pin/archive 两条薄包装入口里当前已知索引场景下的一次重复定位，
  不等于 `updateConversationSettings()` 相关副作用边界已经继续拆清
- `renameConversation()` 当前仍继续复用 `_updateConversationSettingsById(...)`，
  如果后续要继续调整这组入口的组织方式，需要重新审计三条入口是否仍应保持不同收口策略

## 第九十一轮优化记录

### 目标

第九十一轮只收敛 `selectConversation()` 在当前没有任何会话对象可选中的
no-op fallback 分支，以及这条分支收口后遗留的三条私有 no-op 包装，
不改正常会话切换、fallback 到首个可见会话、保存和通知语义。

主要代码：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `selectConversation()` 的主分支会先根据 `conversationId`
  解析 `nextSelectedConversation`
- 当 `nextSelectedConversation == null` 时，当前实现仍继续走两条包装调用：
  - `_markConversationRead(nextSelectedConversationId, notify: false)`
  - `_ensureConversationHydrated(nextSelectedConversationId)`
- 但在该分支下，当前并没有任何真实会话对象可供已读或 hydration：
  - `_markConversationRead(...)` 会因 id 不存在直接返回
  - `_ensureConversationHydrated(...)` 会因 id 不存在直接返回
- 因而这条分支里，存在一组“只会触发无效查找并立即 no-op”的包装调用
- 同时，这两条包装调用和对应的 `_syncComposerWithSelectedConversation()`
  调整后，模型里还保留了三条只做转发的私有 wrapper：
  - `_markConversationRead(...)`
  - `_ensureConversationHydrated(...)`
  - `_syncComposerWithSelectedConversation()`

### 优化后行为

- `selectConversation()` 在 `nextSelectedConversation == null` 时，
  只保留对 composer 的显式空草稿同步
- 不再额外触发无效的 `_markConversationRead(...)` 和
  `_ensureConversationHydrated(...)` 包装调用
- 上述调用点移除后，三条已无引用的私有 wrapper 也一并删除：
  - `_markConversationRead(...)`
  - `_ensureConversationHydrated(...)`
  - `_syncComposerWithSelectedConversation()`
- 正常会话切换路径保持不变：
  - 真实目标会话仍同步 draft、已读和 hydration
  - 缺失 id 且当前已有会话时，仍 fallback 到首个可见会话
- 保存、通知和选中态写回语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 原有 `selecting missing conversation still keeps fallback selection without write`
  测试继续通过
- 新增 `selecting missing conversation before load stays empty without write`
  测试通过，确认本轮 no-op fallback 分支语义
- 原有 `switching conversation still syncs composer draft and keeps one write`
  测试继续通过，确认正常切换路径未变
- 原有 `selected conversation still resolves first visible item by default`
  测试继续通过，确认已有会话时 fallback 语义未变

### 风险备注

- 本轮只收掉 `selectConversation()` 当前无可选会话对象场景下的两条 no-op 包装调用，
  以及随之失去引用的三条私有包装，不等于 selection / fallback 语义已经继续拆清
- 如果后续 `selectConversation()` 要引入“缺失 id 但保留占位选中态”等新语义，
  需重新审计这条空对象 fallback 分支是否仍应保持纯 no-op

## 第九十二轮优化记录

### 目标

第九十二轮只收敛 `agent_dashboard_page.dart` 展示层在同一 build 作用域里的
重复 by-id 状态读取，不改 widget 布局、展示文案、交互和状态流。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_ConversationLauncher`、`_ConversationTile`、`_ConversationDetail`
  这些 widget 在当前 build 作用域里已经拿到了：
  - `conversation`
  - 或者 `status`
- 但它们仍会在同一作用域里反复通过 `conversation.id` 回到 model 读取：
  - `statusLabelForConversation(conversation.id)`
  - `statusDetailForConversation(conversation.id)`
  - `conversationHasUnread(conversation.id)`
  - `statusForConversation(conversation.id)` / `isConversationBusy(conversation.id)`
- 因而展示层存在一组“同帧内对同一会话状态的重复 by-id 查询”

### 优化后行为

- 在各自的 build / helper 作用域里，先把当前帧已经需要的
  `statusLabel`、`statusDetail`、`unread`、`status`
  缓存到局部变量
- 同一 widget 作用域内后续展示直接复用这些局部值
- widget 结构、文案、交互和状态判断语义保持不变：
  - status badge 文案不变
  - unread 标记展示不变
  - detail header 文案不变
  - 输入框 hint 文案和 busy / confirmation 判定不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 现有 `AgentDashboardModel` 全量 focused tests 继续通过，
  证明本轮没有改动 model 层状态语义
- `dart analyze` 继续通过，确认展示层改动未引入静态问题

### 风险备注

- 本轮只收掉展示层同一 build 作用域里的重复 by-id 读取，
  不等于 `AgentDashboardModel` 的公开查询接口已经需要或不需要继续拆分
- 如果后续 dashboard UI 要引入更细粒度的局部状态缓存，
  需重新审计 widget 层缓存与 model 通知边界是否仍然清晰

## 第九十三轮优化记录

### 目标

第九十三轮只收敛 `_WorkspaceTopBar` 在同一 build 作用域里的重复
`statusLabel` / `status` 读取，不改 header 布局、badge 文案和状态颜色语义。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_WorkspaceTopBar.build()` 当前已经拿到了 `conversation`
- 但在渲染顶部状态 badge 时，仍连续通过 `conversation.id`
  回到 model 做两次读取：
  - `statusLabelForConversation(conversation.id)`
  - `statusForConversation(conversation.id)`
- 这两次读取都服务于同一个 `_StatusBadge`

### 优化后行为

- `_WorkspaceTopBar.build()` 在局部先缓存：
  - `status`
  - `statusLabel`
- 顶部 `_StatusBadge` 直接复用这两个局部值
- header 结构、badge 文案、颜色和其余展示内容保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 model 层状态语义
- `dart analyze` 继续通过，确认 UI 读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_WorkspaceTopBar` 内同一个 badge 的重复状态读取，
  不等于整个 dashboard 页面的展示层读取已经全部收口
- 如果后续继续优化 widget 层读取，应继续按单个 widget / 单个展示块拆轮推进，
  避免一次性扩大到整页缓存策略

## 第九十四轮优化记录

### 目标

第九十四轮只收敛 `_ConversationRail` 列表渲染里当前 build 作用域的
重复选中态读取，不改列表布局、选中态语义和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_ConversationRail.build()` 当前已经进入同一帧的列表渲染作用域
- 但 `ListView.separated` 的每个 `itemBuilder` 里，仍通过
  `model.selectedConversation?.id == item.id` 判断选中态
- 这意味着每个 item 都会经由 `selectedConversation` getter
  再做一次当前选中会话解析

### 优化后行为

- `_ConversationRail.build()` 在列表开始前先缓存 `selectedConversationId`
- 每个 `itemBuilder` 里直接复用这个局部值判断 `selected`
- 列表布局、选中态语义、点击切换和 tile 渲染保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动选中态和 model 层状态语义
- `dart analyze` 继续通过，确认 UI 读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationRail` 当前列表作用域里的重复选中态读取，
  不等于整个列表渲染链的展示层读取已经全部收口
- 如果后续继续优化列表区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把选中态、过滤和排序逻辑混在同一轮改动里

## 第九十五轮优化记录

### 目标

第九十五轮只收敛 `_SendButton` 当前 build 作用域里的一次 by-id 包装状态读取，
不改发送按钮布局、busy 判定语义、图标和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_SendButton.build()` 当前已经拿到了 `conversation`
- 但在决定按钮颜色和图标前，仍通过
  `model.isConversationBusy(conversation.id)` 回到 model
- 而 `isConversationBusy()` 内部又会再次读取
  `statusForConversation(conversation.id)`
- 这意味着同一个发送按钮 build 作用域里仍存在一层 by-id 包装状态读取

### 优化后行为

- `_SendButton.build()` 先在局部缓存 `status`
- `busy` 直接基于该局部 `status` 做与原先完全等价的判定：
  - `running`
  - `needsConfirmation`
- 发送按钮的颜色、图标、点击行为和 busy 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动发送链和状态机语义
- `dart analyze` 继续通过，确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_SendButton` 同一 build 作用域里的一次 by-id 包装状态读取，
  不等于整个 composer 区域的展示层读取已经全部收口
- 如果后续继续优化 composer 区域，应继续按“单个 widget / 单个读取点”拆轮推进，
  避免把发送链、输入框 hint 和状态 badge 混在同一轮改动里

## 第九十六轮优化记录

### 目标

第九十六轮只收敛 `_ConversationTile` 已拿到 `status` 后又重复按 id 读取
`statusLabel` 的这层包装，不改 tile 布局、badge 文案、颜色和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_ConversationTile.build()` 当前已经先拿到了
  `status = model.statusForConversation(conversation.id)`
- 但进入 `_buildRich()` / `_buildCompact()` 后，
  又会通过 `model.statusLabelForConversation(conversation.id)`
  回到 model 再走一层 `conversation.id -> status -> label` 读取
- 这意味着同一个 tile 渲染链里已经有 `status` 的前提下，
  仍存在一层重复的 by-id 状态标签包装查询

### 优化后行为

- `AgentDashboardModel` 增加 `statusLabelForStatus(status)` helper，
  并让 `statusLabelForConversation()` 继续复用同一套映射逻辑
- `_ConversationTile.build()` 先局部缓存：
  - `status`
  - `statusLabel`
- `_buildRich()` / `_buildCompact()` 直接复用该局部值
- tile 的状态 badge 文案、颜色、未读标记、列表布局和点击语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增 `status label helper stays aligned with conversation status mapping`
  测试通过，确认新的 status-label helper 与原有按会话映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 tile 交互和状态机语义
- `dart analyze` 继续通过，确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationTile` 渲染链里一层重复的状态标签包装读取，
  不等于整个会话列表区域的展示层读取已经全部收口
- 如果后续继续优化 tile 区域，应继续按“单个读取点 / 单个 badge 或文案块”拆轮推进，
  避免把 unread、snippet、排序或过滤逻辑混进同一轮

## 第九十七轮优化记录

### 目标

第九十七轮只收敛 `_ConversationTile` 在 rich / compact 分支里对 `unread`
的重复 by-id 读取，不改 tile 布局、未读标记语义和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_ConversationTile.build()` 当前已经统一承担 tile 的渲染入口
- 但进入 `_buildRich()` / `_buildCompact()` 后，
  仍会各自通过 `model.conversationHasUnread(conversation.id)`
  再回到 model 做一次 by-id 未读查询
- 这意味着同一个 tile 渲染链在进入具体展示分支后，
  还存在一层重复的 unread 包装读取

### 优化后行为

- `_ConversationTile.build()` 先在局部缓存 `unread`
- `_buildRich()` / `_buildCompact()` 直接复用该局部值
- rich / compact 两条分支中的未读圆点、详情文案和其余 tile 展示语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 unread 状态语义和 tile 交互
- 第九十六轮新增的 `status label helper stays aligned with conversation status mapping`
  测试继续通过，确认本轮没有破坏上一轮的 tile 状态标签收敛
- `dart analyze` 继续通过，确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationTile` 两条展示分支里的 unread 包装读取，
  不等于 tile 区域的展示层读取已经全部收口
- 如果后续继续优化 tile 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 snippet、已读时间或排序逻辑混进同一轮

## 第九十八轮优化记录

### 目标

第九十八轮只收敛 `_ConversationLauncher` 当前 build 作用域里的一次
`statusLabel` 包装状态读取，不改切换会话入口布局、subtitle 文案和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_ConversationLauncher.build()` 当前已经拿到了 `conversation`
- 但 subtitle 文案仍通过
  `model.statusLabelForConversation(conversation.id)` 回到 model
- 而 `statusLabelForConversation()` 内部又会继续走：
  - `statusForConversation(conversation.id)`
  - `statusLabelForStatus(status)`
- 这意味着同一个 launcher build 作用域里仍存在一层
  `conversation.id -> status -> label` 的包装状态读取

### 优化后行为

- `_ConversationLauncher.build()` 在局部先缓存：
  - `status`
  - `statusLabel`
- subtitle 文案直接复用局部 `statusLabel`
- 会话标题、project 文案、未读数量、展开按钮和点击切换语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`

覆盖确认：

- 第九十六轮新增的
  `status label helper stays aligned with conversation status mapping`
  测试继续通过，确认 launcher 改为复用
  `statusLabelForStatus(status)` 后仍与原有状态标签映射一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动会话选择和状态机语义
- 共享 dashboard 页面与 harness 页面都完成静态分析，确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationLauncher` 当前 subtitle 文案的一层状态标签包装读取，
  不等于整个顶部入口区域的展示层读取已经全部收口
- 如果后续继续优化 launcher / top bar 区域，应继续按“单个展示块 / 单个读取点”拆轮推进，
  避免把未读数量、panel 状态和布局适配混进同一轮

## 第九十九轮优化记录

### 目标

第九十九轮只收敛 `AgentDashboardDevShell` mock 窗口头里的一次
`statusLabel` 包装状态读取，不改 dev shell 头部布局、mock 文案和最小化/关闭交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`

### 优化前行为

- `_buildMockWindowHeader()` 当前已经拿到了 `conversation`
- 但 mock 头部 subtitle 文案仍通过
  `_model.statusLabelForConversation(conversation.id)` 回到 model
- 而 `statusLabelForConversation()` 内部又会继续走：
  - `statusForConversation(conversation.id)`
  - `statusLabelForStatus(status)`
- 这意味着同一个 mock 头部 builder 作用域里仍存在一层
  `conversation.id -> status -> label` 的包装状态读取

### 优化后行为

- `_buildMockWindowHeader()` 在需要真实会话状态时，
  直接复用：
  - `_model.statusForConversation(conversation.id)`
  - `_model.statusLabelForStatus(status)`
- `conversation == null` 时的 `'Ready'` fallback 文案保持不变
- mock 头部标题、project/status subtitle、最小化和关闭交互保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 第九十六轮新增的
  `status label helper stays aligned with conversation status mapping`
  测试继续通过，确认 dev shell 改为复用
  `statusLabelForStatus(status)` 后仍与原有状态标签映射一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动会话状态语义
- `dart analyze` 继续通过，确认 dev shell 展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `AgentDashboardDevShell` mock 窗口头里的一层状态标签包装读取，
  不等于 overlay / dev shell 相关头部展示层读取已经全部收口
- 如果后续继续优化 dev shell 或 overlay 头部，应继续按“单个头部 / 单个文案块”拆轮推进，
  避免把拖拽、最小化状态和 overlay 真实运行态混进同一轮

## 第一百轮优化记录

### 目标

第一百轮只收敛 floating overlay 窗口头里的一次
`statusLabel` 包装状态读取，不改 overlay 头部布局、`idle` fallback 文案和拖拽交互。

主要代码：

- `flutter/lib/common/widgets/overlay.dart`

### 优化前行为

- `_AgentDashboardWindowHeader.build()` 当前已经拿到了 `conversation`
- 但 overlay 头部右侧状态文案仍通过
  `chatModel.agentDashboardModel.statusLabelForConversation(conversation.id)` 回到 model
- 而 `statusLabelForConversation()` 内部又会继续走：
  - `statusForConversation(conversation.id)`
  - `statusLabelForStatus(status)`
- 这意味着同一个 overlay 头部 build 作用域里仍存在一层
  `conversation.id -> status -> label` 的包装状态读取

### 优化后行为

- `_AgentDashboardWindowHeader.build()` 在需要真实会话状态时，
  直接复用：
  - `dashboardModel.statusForConversation(conversation.id)`
  - `dashboardModel.statusLabelForStatus(status)`
- `conversation == null` 时的 `'idle'` fallback 文案保持不变
- overlay 头部标题、拖拽手势和窗口控制交互保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 第九十六轮新增的
  `status label helper stays aligned with conversation status mapping`
  测试继续通过，确认 overlay 头部改为复用
  `statusLabelForStatus(status)` 后仍与原有状态标签映射一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动会话状态语义
- `dart analyze` 继续通过，确认 overlay 展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 overlay 浮窗头里的一层状态标签包装读取，
  不等于 overlay / launcher / dev shell 头部展示层读取已经全部收口
- 如果后续继续优化 overlay 头部，应继续按“单个头部 / 单个文案块”拆轮推进，
  避免把拖拽、尺寸控制和运行态同步混进同一轮

## 第一百零一轮优化记录

### 目标

第一百零一轮只收敛 `_ConversationTile` 当前 build 入口里的一次
`unread` by-id 包装读取，不改 tile 布局、未读语义和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_ConversationTile.build()` 当前已经拿到了 `conversation`
- 但在生成 tile 入口局部 `unread` 值时，仍通过
  `model.conversationHasUnread(conversation.id)` 回到 model
- 而 `conversationHasUnread()` 内部又会继续走：
  - `_conversationIndexById(conversation.id)`
  - `_conversationHasUnread(_conversations[index])`
- 这意味着同一个 tile build 入口在已经持有 `conversation` 的前提下，
  仍存在一层 `conversation.id -> conversation -> unread` 的包装读取

### 优化后行为

- `AgentDashboardModel` 与 harness model 新增
  `conversationHasUnreadForConversation(conversation)` helper，
  继续复用同一套 `_conversationHasUnread(...)` 判定逻辑
- shared dashboard 页与 harness 页的 `_ConversationTile.build()`
  直接复用该对象级 helper 生成局部 `unread`
- tile 的未读圆点、compact details 文案、列表布局和点击语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `unread helper stays aligned with conversation unread mapping`
  测试通过，确认新的对象级 unread helper 与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动未读状态语义和 tile 交互
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationTile` build 入口里的一层 unread 包装读取，
  不等于 tile / conversation list 区域的展示层读取已经全部收口
- 如果后续继续优化 tile 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 snippet、排序或会话选择逻辑混进同一轮

## 第一百零二轮优化记录

### 目标

第一百零二轮只收敛 `_ChatWorkspace` 当前 build 入口里的一次
`statusDetail` by-id 包装读取，不改顶部状态说明文案、布局和交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_ChatWorkspace.build()` 当前已经拿到了 `conversation`
- 但在生成顶部状态说明 `statusDetail` 时，仍通过
  `model.statusDetailForConversation(conversation.id)` 回到 model
- 而 `statusDetailForConversation()` 需要先按 id 回到会话列表，
  再读取对应 runtime detail
- 这意味着同一个 workspace build 入口在已经持有 `conversation` 的前提下，
  仍存在一层 `conversation.id -> conversation -> statusDetail` 的包装读取

### 优化后行为

- `AgentDashboardModel` 与 harness model 新增
  `statusDetailForConversationObject(conversation)` helper，
  继续复用同一套 runtime detail map 读取逻辑
- shared dashboard 页与 harness 页的 `_ChatWorkspace.build()`
  直接复用该对象级 helper 生成局部 `statusDetail`
- 顶部状态说明文案、header 布局和其余 workspace 交互保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `status detail helper stays aligned with conversation detail mapping`
  测试通过，确认新的对象级 detail helper 与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动状态详情语义和 workspace 展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ChatWorkspace` build 入口里的一层状态详情包装读取，
  不等于 inspector / timeline / sessions 区域的展示层读取已经全部收口
- 如果后续继续优化 workspace 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 inspector、timeline 或 session 浏览逻辑混进同一轮

## 第一百零三轮优化记录

### 目标

第一百零三轮只收敛 `_InspectorPanel` 当前 build 入口里的一次
`statusDetail` by-id 包装读取，不改 inspector 文案、布局和设置交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_InspectorPanel.build()` 当前已经拿到了 `conversation`
- 但在生成 inspector 顶部状态说明 `statusDetail` 时，仍通过
  `model.statusDetailForConversation(conversation.id)` 回到 model
- 而当前 model 已经提供了对象级
  `statusDetailForConversationObject(conversation)` helper
- 这意味着同一个 inspector build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> statusDetail` 的包装读取

### 优化后行为

- shared dashboard 页与 harness 页的 `_InspectorPanel.build()`
  直接复用 `statusDetailForConversationObject(conversation)`
- inspector 顶部状态说明文案、history preview、terminal preview、
  project/profile/session 设置交互保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 102 轮新增的
  `status detail helper stays aligned with conversation detail mapping`
  测试继续通过，确认 inspector 复用对象级 detail helper 后仍与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动状态详情语义和 inspector 展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_InspectorPanel` build 入口里的一层状态详情包装读取，
  不等于 timeline / sessions / skills 区域的展示层读取已经全部收口
- 如果后续继续优化 inspector 周边区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 preview 生成、controller 生命周期或设置提交流程混进同一轮

## 第一百零四轮优化记录

### 目标

第一百零四轮只收敛 `_TimelinePanel` 当前 build 入口里的一次
`timeline` by-id 包装读取，不改 timeline 列表文案、布局和事件展示语义。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_TimelinePanel.build()` 当前已经拿到了 `conversation`
- 但在读取 timeline items 时，仍通过
  `model.timelineForConversation(conversation.id)` 回到 model
- 而当前 model 并没有直接复用已拿到 `conversation` 的对象级 timeline 入口
- 这意味着同一个 timeline build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> timeline` 的包装读取

### 优化后行为

- `AgentDashboardModel` 与 harness model 新增
  `timelineForConversationObject(conversation)` helper，
  继续复用同一套 `_timelineByConversation` 读取逻辑
- shared dashboard 页与 harness 页的 `_TimelinePanel.build()`
  直接复用该对象级 helper 生成局部 `items`
- timeline 空态文案、事件列表内容、stage/summary 展示语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `timeline helper stays aligned with conversation timeline mapping`
  测试通过，确认新的对象级 timeline helper 与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 timeline 数据语义和 timeline 展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_TimelinePanel` build 入口里的一层 timeline 包装读取，
  不等于 sessions / skills / raw events 区域的展示层读取已经全部收口
- 如果后续继续优化 timeline 周边区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 timeline 事件整形、排序或 raw event 展示混进同一轮

## 第一百零五轮优化记录

### 目标

第一百零五轮只收敛 `_SessionsPanel` 当前 build 入口里的一次
`canLoadMoreSessionHistory` by-id 包装读取，不改 session 卡片展示和加载历史交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_SessionsPanel.build()` 当前已经拿到了 `conversation`
- 但在决定是否显示 `Load older history` 按钮时，仍通过
  `model.canLoadMoreSessionHistory(conversation.id)` 回到 model
- 这意味着同一个 sessions build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> canLoadMore` 的包装读取

### 优化后行为

- `AgentDashboardModel` 与 harness model 新增
  `canLoadMoreSessionHistoryForConversation(conversation)` helper，
  继续复用同一套 `_sessionNextCursorByConversation` 判定逻辑
- shared dashboard 页与 harness 页的 `_SessionsPanel.build()`
  直接复用该对象级 helper 决定按钮显隐
- session 卡片列表、`Load older history` 点击行为和加载历史语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `load-more helper stays aligned with conversation paging mapping`
  测试通过，确认新的对象级 load-more helper 与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 session 分页语义和 sessions 面板展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_SessionsPanel` build 入口里的一层 load-more 包装读取，
  不等于 sessions / skills / raw events 区域的展示层读取已经全部收口
- 如果后续继续优化 sessions 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 session 列表内容、restore 交互或分页加载流程混进同一轮

## 第一百零六轮优化记录

### 目标

第一百零六轮只收敛 `_SendButton` 当前 build 入口里的一次
`status` by-id 包装读取，不改发送按钮 busy 判定、图标和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`

### 优化前行为

- `_SendButton.build()` 当前已经拿到了 `conversation`
- 但在生成局部 `status` 时，仍通过
  `model.statusForConversation(conversation.id)` 回到 model
- 这意味着同一个 send button build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> status` 的包装读取

### 优化后行为

- `AgentDashboardModel` 与 harness model 新增
  `statusForConversationObject(conversation)` helper，
  继续复用同一套 runtime status map 读取逻辑
- shared dashboard 页与 harness 页的 `_SendButton.build()`
  直接复用该对象级 helper 生成局部 `status`
- busy 判定、按钮颜色、图标和点击发送语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `status helper stays aligned with conversation status mapping`
  测试通过，确认新的对象级 status helper 与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 status 语义和发送按钮展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_SendButton` build 入口里的一层 status 包装读取，
  不等于 actions / skills / raw events 区域的展示层读取已经全部收口
- 如果后续继续优化 composer 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把发送链、输入框提示或状态 badge 混进同一轮

## 第一百零七轮优化记录

### 目标

第一百零七轮只收敛 `_WorkspaceTopBar` 当前 build 入口里的一次
`status` by-id 包装读取，不改顶部 badge 文案、颜色和布局。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_WorkspaceTopBar.build()` 当前已经拿到了 `conversation`
- 但在生成顶部状态 badge 的局部 `status` 时，仍通过
  `model.statusForConversation(conversation.id)` 回到 model
- 而当前 model 已经提供了对象级
  `statusForConversationObject(conversation)` helper
- 这意味着同一个 top bar build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> status` 的包装读取

### 优化后行为

- shared dashboard 页与 harness 页的 `_WorkspaceTopBar.build()`
  直接复用 `statusForConversationObject(conversation)`
- 顶部状态 badge 文案、颜色、标题和整体布局保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 106 轮新增的
  `status helper stays aligned with conversation status mapping`
  测试继续通过，确认 top bar 复用对象级 status helper 后仍与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 status 语义和 top bar 展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_WorkspaceTopBar` build 入口里的一层 status 包装读取，
  不等于 launcher / tile / chat workspace 区域的展示层读取已经全部收口
- 如果后续继续优化 header 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把顶部 badge、会话 launcher 和响应式布局混进同一轮

## 第一百零八轮优化记录

### 目标

第一百零八轮只收敛 `_ConversationLauncher` 当前 build 入口里的一次
`status` by-id 包装读取，不改 launcher 文案、布局和点击交互。

主要代码：

- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_ConversationLauncher.build()` 当前已经拿到了 `conversation`
- 但在生成 launcher subtitle 的局部 `status` 时，仍通过
  `model.statusForConversation(conversation.id)` 回到 model
- 而当前 model 已经提供了对象级
  `statusForConversationObject(conversation)` helper
- 这意味着同一个 launcher build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> status` 的包装读取

### 优化后行为

- shared dashboard 页与 harness 页的 `_ConversationLauncher.build()`
  直接复用 `statusForConversationObject(conversation)`
- launcher subtitle 文案、图标、展开状态和点击切换语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 106 轮新增的
  `status helper stays aligned with conversation status mapping`
  测试继续通过，确认 launcher 复用对象级 status helper 后仍与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 status 语义和 launcher 展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationLauncher` build 入口里的一层 status 包装读取，
  不等于 tile / chat workspace 区域的展示层读取已经全部收口
- 如果后续继续优化 header 区域，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把 launcher、顶部 badge 和响应式布局混进同一轮

## 第一百零九轮优化记录

### 目标

第一百零九轮只收敛 `_ConversationTile` 当前 build 入口里的一次 `status` by-id 包装读取，不改 tile 的布局、点击行为、未读态显示和状态文案。
主要代码：
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`

### 优化前行为

- `_ConversationTile.build()` 当前已经拿到了 `conversation`
- 但在生成 tile 状态文案前，仍通过
  `model.statusForConversation(conversation.id)` 回到 model
- 而当前 model 已经提供了对象级
  `statusForConversationObject(conversation)` helper
- 这意味着同一个 tile build 入口在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> status` 的包装读取

### 优化后行为

- shared dashboard 页与 harness 页的 `_ConversationTile.build()`
  直接复用 `statusForConversationObject(conversation)`
- tile 状态文案、未读标记、rich/compact 两套布局和点击切换语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 106 轮新增的
  `status helper stays aligned with conversation status mapping`
  测试继续通过，确认 tile 复用对象级 status helper 后仍与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 status 语义和 tile 展示行为
- shared dashboard 页面与 harness 页面静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ConversationTile` build 入口里的一层 status 包装读取，
  不等于 `_ChatWorkspace` 等其他展示块的 by-id 状态读取已经全部收口
- 如果后续继续优化会话主区，应继续按“单个读取点 / 单个展示块”拆轮推进，
  避免把顶部、tile 和 workspace 的展示逻辑混进同一轮

## 第一百一十轮优化记录

### 目标

第一百一十轮只收敛 floating overlay 窗口头里的一次 `status` by-id 包装读取，不改 overlay 头部布局、`idle` fallback 文案和拖拽交互。
主要代码：
- `flutter/lib/common/widgets/overlay.dart`

### 优化前行为

- `_AgentDashboardWindowHeader.build()` 当前已经拿到了 `conversation`
- 但 overlay 头部右侧状态文案仍通过
  `dashboardModel.statusForConversation(conversation.id)` 回到 model
- 而当前 model 已经提供了对象级
  `statusForConversationObject(conversation)` helper
- 这意味着同一个 overlay 头部 build 作用域在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> status` 的包装读取

### 优化后行为

- overlay 头部状态读取直接复用
  `statusForConversationObject(conversation)`
- overlay 头部标题、`idle` fallback 文案、拖拽手势和窗口控制交互保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 106 轮新增的
  `status helper stays aligned with conversation status mapping`
  测试继续通过，确认 overlay 头部复用对象级 status helper 后仍与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 status 语义和 overlay 头部展示行为
- `overlay.dart` 相关静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 overlay 头部里的一层 status 包装读取，
  不等于 overlay 相关其他展示读取或运行态链路已经全部收口
- 如果后续继续优化 overlay / runtime 边界，应继续按“单个头部 / 单个文案块”拆轮推进，
  避免把拖拽、窗口层级和 bridge 推送链路混进同一轮

## 第一百一十一轮优化记录

### 目标

第一百一十一轮只收敛 desktop `runtime_io` 状态轮询停止条件里的一次 `status` by-id 包装读取，不改轮询频率、bridge `status` 请求方式和轮询停止条件枚举。
主要代码：
- `flutter/lib/models/agent_dashboard_runtime_io.dart`

### 优化前行为

- `AgentDashboardRuntimeIo._startStatusPolling()` 当前已经持有 `conversation`
- 但每轮轮询完成后，判断是否停止 poller 时，仍通过
  `model.statusForConversation(conversation.id)` 回到 model
- 而当前 model 已经提供了对象级
  `statusForConversationObject(conversation)` helper
- 这意味着同一个 runtime poller 闭包在已经持有 `conversation` 的前提下，
  仍保留了一层 `conversation.id -> conversation -> status` 的包装读取

### 优化后行为

- desktop `runtime_io` 状态轮询停止条件直接复用
  `statusForConversationObject(conversation)`
- 轮询频率、`sessionSendAgentCommand(... mode: 'status')` 调用、
  `completed / failed / needsConfirmation` 停止条件和异常取消语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 106 轮新增的
  `status helper stays aligned with conversation status mapping`
  测试继续通过，确认 runtime_io 轮询停止条件复用对象级 status helper 后仍与原有按 id 映射语义一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 status 语义和 runtime_io 的停止判定行为
- `agent_dashboard_runtime_io.dart` 相关静态分析继续通过，
  确认 runtime 读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `runtime_io` 状态轮询停止条件里的一层 status 包装读取，
  不等于 desktop runtime 的 push / poll / recovery 边界已经全部收口
- 如果后续继续优化 runtime 层，应继续按“单个轮询点 / 单个停止判定块”拆轮推进，
  避免把桥接通信、状态恢复和 UI 展示读路径混进同一轮

## 第一百一十二轮优化记录

### 目标

第一百一十二轮只收敛 floating overlay 窗口头里的一次 `statusLabel` 包装读取，不改 overlay 头部布局、`idle` fallback 文案和拖拽交互。
主要代码：
- `flutter/lib/common/widgets/overlay.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_AgentDashboardWindowHeader.build()` 当前已经拿到了 `conversation`
- 且 model 已经提供了对象级
  `statusLabelForConversationObject(conversation)` helper
- 但 overlay 头部状态文案仍保留了
  `statusForConversationObject(conversation) -> statusLabelForStatus(status)`
  这层手动二段映射
- 这意味着同一个 overlay 头部 build 作用域在已经持有 `conversation` 的前提下，
  仍保留了一层对象状态到状态标签的包装读取

### 优化后行为

- overlay 头部状态文案直接复用
  `statusLabelForConversationObject(conversation)`
- overlay 头部标题、`idle` fallback 文案、拖拽手势和窗口控制交互保持不变
- focused test 新增对象级 `statusLabel` helper 对齐校验，
  确认对象级入口与按 id 入口继续保持同一映射语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `status label object helper stays aligned with status label mapping`
  focused test，确认 `statusLabelForConversationObject(conversation)` 与
  `statusLabelForConversation(conversation.id)` 继续保持一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动状态标签语义和 overlay 头部展示行为
- `overlay.dart` 与 `agent_dashboard_model_test.dart` 相关静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 overlay 头部里的一层 `statusLabel` 包装读取，
  不等于 overlay 相关其他展示读取或运行态链路已经全部收口
- 如果后续继续优化 overlay / runtime 边界，应继续按“单个头部 / 单个文案块”拆轮推进，
  避免把拖拽、窗口层级和 bridge 推送链路混进同一轮

## 第一百一十三轮优化记录

### 目标

第一百一十三轮只收敛 `_SendButton` 当前 build 入口里的一次 `busy` 包装判定，不改发送按钮图标、颜色和点击语义。
主要代码：
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_SendButton.build()` 当前已经拿到了 `conversation`
- 且 model 已经提供了对象级
  `isConversationBusyForConversation(conversation)` helper
- 但发送按钮仍保留了
  `statusForConversationObject(conversation) -> running/needsConfirmation`
  这层手动 busy 判定
- 这意味着同一个 send button build 作用域在已经持有 `conversation` 的前提下，
  仍保留了一层对象状态到 busy 布尔值的包装判定

### 优化后行为

- `_SendButton.build()` 直接复用
  `isConversationBusyForConversation(conversation)`
- 按钮图标、颜色、发送点击和 pending 态语义保持不变
- focused test 新增对象级 `busy` helper 对齐校验，
  确认对象级入口与按 id 入口继续保持同一判定语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `busy helper stays aligned with conversation busy mapping`
  focused test，确认 `isConversationBusyForConversation(conversation)` 与
  `isConversationBusy(conversation.id)` 继续保持一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 busy 判定语义和发送按钮展示行为
- `agent_dashboard_page.dart` 与 `agent_dashboard_model_test.dart` 相关静态分析继续通过，
  确认展示层读取收口未引入静态问题

### 风险备注

- 本轮只收掉 `_SendButton` build 入口里的一层 `busy` 包装判定，
  不等于输入区相关其他状态判定或 runtime 链路已经全部收口
- 如果后续继续优化输入区，应继续按“单个按钮 / 单个判定块”拆轮推进，
  避免把发送态、输入提示文案和 runtime 恢复逻辑混进同一轮

## 第一百一十四轮优化记录

### 目标

第一百一十四轮只收敛 `_ChatWorkspace` 输入提示当前 build 入口里的一次 `needsConfirmation` 包装判定，不改输入提示文案本身、优先级和输入区交互配置。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `tools/agent_dashboard_harness/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `_ChatWorkspace.build()` 当前已经拿到了 `conversation`
- 且 model 已经提供了对象级 `busy` helper，
  但“是否处于需要审批”这条判定仍保留在输入提示 build 作用域里直接基于 `status`
  做一次手动比较
- 这意味着同一个输入提示文案块在已经持有 `conversation` 的前提下，
  仍保留了一层对象状态到 `needsConfirmation` 布尔值的包装判定

### 优化后行为

- model 侧补齐并复用对象级
  `conversationNeedsConfirmationForConversation(conversation)` helper
- `_ChatWorkspace` 输入提示优先复用该 helper，再继续按原有优先级输出：
  - `Waiting for approval before continuing.`
  - `Agent is thinking. You can queue the next instruction.`
  - `Message your desktop agent`
- focused test 新增 needs-confirmation helper 对齐校验，
  确认对象级入口与按 id 入口继续保持同一判定语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `needs-confirmation helper stays aligned with conversation status mapping`
  focused test，确认
  `conversationNeedsConfirmationForConversation(conversation)` 与
  `conversationNeedsConfirmation(conversation.id)` 继续保持一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动输入提示文案语义和输入区交互行为
- `agent_dashboard_model.dart`、`agent_dashboard_page.dart`
  与新增 test 的静态分析继续通过，
  确认局部状态判定收口未引入静态问题

### 风险备注

- 本轮只收掉 `_ChatWorkspace` 输入提示里的一层 `needsConfirmation` 包装判定，
  不等于输入区相关其他状态判定或 runtime 链路已经全部收口
- 如果后续继续优化输入区，应继续按“单个提示块 / 单个状态判定”拆轮推进，
  避免把发送态、输入提示文案和 runtime 恢复逻辑混进同一轮

## 第一百一十五轮优化记录

### 目标

第一百一十五轮只收敛 runtime 轮询停止条件里的一次状态终止判定包装，不改轮询频率、bridge `status` 请求方式和停止条件本身。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/lib/models/agent_dashboard_runtime_web.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_runtime_web.dart`
- `flutter/lib/models/agent_dashboard_runtime_io.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- runtime web/io 轮询闭包当前已经拿到了 `conversation`
- 但“是否停止 status tracking”这条条件仍保留为
  `completed / failed / needsConfirmation` 的手动三段判定
- 这意味着同一个 runtime 停止判定块在已经持有 `conversation` 的前提下，
  仍保留了一层对象状态到终止布尔值的包装判定

### 优化后行为

- model 侧补齐并复用对象级
  `shouldStopStatusTrackingForConversation(conversation)` helper
- runtime web/io 轮询停止条件优先复用该 helper
- 轮询频率、`requestTaskStatus()` / `sessionSendAgentCommand(... mode: 'status')`
  调用、以及 `completed / failed / needsConfirmation` 终止语义保持不变
- focused test 新增 stop-tracking helper 对齐校验，
  确认对象级入口与按 id 入口继续保持同一判定语义

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 新增
  `status-tracking stop helper stays aligned with conversation status mapping`
  focused test，确认
  `shouldStopStatusTrackingForConversation(conversation)` 与
  `shouldStopStatusTracking(conversation.id)` 继续保持一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 runtime 停止条件语义
- `agent_dashboard_model.dart`、`agent_dashboard_runtime_web.dart`、
  `agent_dashboard_runtime_io.dart` 与新增 test 的静态分析继续通过，
  确认局部 runtime 判定收口未引入静态问题

### 风险备注

- 本轮只收掉 runtime 轮询停止条件里的一层终止判定包装，
  不等于 push / poll / snapshot 整体状态链路已经全部收口
- 如果后续继续优化 runtime 层，应继续按“单个轮询点 / 单个终止判定块”拆轮推进，
  避免把 bridge 通信、状态恢复和 UI 展示读路径混进同一轮

## 第一百一十六轮优化记录

### 目标

第一百一十六轮只收敛 desktop `runtime_io` 当前轮询停止条件调用点的一次终止判定包装，不改轮询频率、bridge `status` 请求方式和终止条件本身。
主要代码：
- `flutter/lib/models/agent_dashboard_runtime_io.dart`

### 优化前行为

- `AgentDashboardRuntimeIo._startStatusPolling()` 当前已经持有 `conversation`
- 且 model 已经提供了对象级
  `shouldStopStatusTrackingForConversation(conversation)` helper
- 但 desktop `runtime_io` 停止轮询调用点仍保留了
  `completed / failed / needsConfirmation` 的手动三段终止判定
- 这意味着同一个 runtime_io 轮询闭包在已经持有 `conversation` 的前提下，
  仍保留了一层对象状态到终止布尔值的包装判定

### 优化后行为

- desktop `runtime_io` 停止轮询调用点直接复用
  `shouldStopStatusTrackingForConversation(conversation)`
- 轮询频率、`sessionSendAgentCommand(... mode: 'status')` 调用、
  以及 `completed / failed / needsConfirmation` 终止语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`
3. `dart analyze lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_web.dart`

覆盖确认：

- 第 115 轮新增的
  `status-tracking stop helper stays aligned with conversation status mapping`
  focused test 继续通过，确认 runtime_io 调用点切到对象级 stop helper 后仍与原有按 id 入口判定一致
- 现有 `AgentDashboardModel` focused tests 继续通过，
  证明本轮没有改动 runtime_io 停止条件语义
- `agent_dashboard_runtime_io.dart` 与相关分析继续通过，
  确认局部 runtime 判定收口未引入静态问题

### 风险备注

- 本轮只收掉 desktop `runtime_io` 调用点里的一层终止判定包装，
  不等于 push / poll / snapshot 整体状态链路已经全部收口
- 如果后续继续优化 runtime 层，应继续按“单个轮询点 / 单个终止判定块”拆轮推进，
  避免把 bridge 通信、状态恢复和 UI 展示读路径混进同一轮

## 第一百一十七轮优化记录

### 目标

第一百一十七轮只收敛 `AgentDashboardModel` 里的 `rawEvents` 会话读取入口，不改
`rawEvents` 写入来源、session restore 语义和 UI 展示文案。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `AgentDashboardModel` 已经为 `statusDetail`、`timeline`、`busy`、
  `needsConfirmation`、`canLoadMoreSessionHistory` 等读取提供了对象级 helper
- 但 `rawEvents` 仍只保留按 `conversationId` 的读取入口
- 同时 `restoreSessionIntoConversation(sessionId: '')` 的“已是空白会话”短路判定，
  仍直接访问 `_timelineByConversation` / `_rawEventsByConversation` 内部 map
- 这意味着 `rawEvents` 这条会话附加数据读取路径还没有和其他会话对象读取入口对齐，
  空 session reset 判定里也仍保留一层直接容器访问

### 优化后行为

- 为 `rawEvents` 补齐对象级
  `rawEventsForConversationObject(conversation)` helper
- `rawEventsForConversation(conversationId)` 改为复用对象级 helper，
  保持缺失会话时返回空列表的现有语义不变
- `restoreSessionIntoConversation(sessionId: '')` 的空白会话短路判定
  改为复用 `timelineForConversationObject(conversation)` 与
  `rawEventsForConversationObject(conversation)`
- `rawEvents` 写入路径、session reset 行为、storage write 次数和 UI 文案保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `raw-events helper stays aligned with conversation raw-events mapping`
  focused test，确认
  `rawEventsForConversationObject(conversation)` 与
  `rawEventsForConversation(conversation.id)` 继续保持同一读取语义
- 现有
  `task snapshot without session binding still stores timeline and raw events`
  focused test 继续通过，证明本轮没有改动 `rawEvents` 写入结果
- 现有
  `clearing an already blank conversation skips storage write`
  与
  `clearing session restore still preserves blank timeline state with one write`
  focused tests 继续通过，证明空 session reset 的短路与写入语义保持不变
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部读取入口收口未引入静态问题

### 风险备注

- 本轮只收掉 `rawEvents` 读取入口的一层对象级缺口与空 session reset 判定里的直接容器访问，
  不等于 timeline / rawEvents 写入链路或 restore/hydration 路径已经整体收口
- 如果后续继续优化会话附加数据路径，应继续按“单个 helper / 单个读路径判定”拆轮推进，
  避免把事件写入、恢复流程和展示层混进同一轮

## 第一百一十八轮优化记录

### 目标

第一百一十八轮只收敛 `restoreSessionIntoConversation(sessionId: '')`
空白会话短路判定里最后一处 paging 读取包装，不改 session reset 语义、
历史分页语义和 storage write 行为。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 117 轮后，空白会话短路判定已经改为复用对象级
  `timelineForConversationObject(conversation)` 与
  `rawEventsForConversationObject(conversation)`
- 但这条判定里对“是否还有更多历史页”的检查，
  仍直接访问 `_sessionNextCursorByConversation[conversationId] == null`
- 这意味着同一个“已拿到 conversation 对象”的短路判定块里，
  会话附加数据读取已经走 helper，但 paging 状态仍保留一层直接容器访问

### 优化后行为

- 空白会话短路判定改为复用
  `canLoadMoreSessionHistoryForConversation(conversation)`
- `restoreSessionIntoConversation(sessionId: '')`
  的短路条件、空白会话 reset 语义、storage write 次数和历史分页行为保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `load-more helper stays aligned after blank-session short-circuit cleanup`
  focused test，确认
  `canLoadMoreSessionHistoryForConversation(conversation)` 与
  `canLoadMoreSessionHistory(conversation.id)` 继续保持同一判定语义
- 现有
  `clearing an already blank conversation skips storage write`
  与
  `clearing session restore still preserves blank timeline state with one write`
  focused tests 继续通过，证明空 session reset 的短路与写入语义保持不变
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 paging 判定收口未引入静态问题

### 风险备注

- 本轮只收掉空 session reset 短路判定里的最后一处 paging 读取包装，
  不等于 restore/hydration 主流程、session 分页加载链或会话状态容器访问已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个短路判定”拆轮推进，
  避免把会话恢复、历史分页加载和展示层行为混进同一轮

## 第一百一十九轮优化记录

### 目标

第一百一十九轮只收敛 `loadMoreSessionHistory()` 调用点里的 session paging cursor
读取包装，不改分页加载语义、错误处理和 listener / storage 行为。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `loadMoreSessionHistory()` 当前已经拿到了 `conversation`
- 同时 model 已经提供了对象级
  `canLoadMoreSessionHistoryForConversation(conversation)` helper
- 但分页加载调用点本身仍直接读取
  `_sessionNextCursorByConversation[conversationId]`
- 这意味着同一个“已拿到 conversation 对象”的历史分页入口里，
  是否可加载更多已经有对象级判定，但真正的 cursor 读取仍保留一层直接容器访问

### 优化后行为

- 为分页 cursor 补齐对象级
  `sessionNextCursorForConversationObject(conversation)` helper
- `loadMoreSessionHistory()` 改为复用该 helper 读取 cursor
- 分页加载顺序、空 cursor 直接返回语义、错误时 `failed` 状态写入和
  `notifyListeners()` 行为保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `session-next-cursor helper stays aligned with conversation paging state`
  focused test，确认对象级 cursor helper 与现有分页状态判定保持一致
- 现有
  `paged session restore persists once after full hydration`
  focused test 继续通过，证明分页 restore / merge 行为未被改动
- 现有
  `loading more history for missing conversation still skips write`
  focused test 继续通过，证明分页入口 guard 行为保持不变
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 cursor 读取收口未引入静态问题

### 风险备注

- 本轮只收掉分页入口里的 cursor 读取包装，
  不等于 session page 加载链、cursor 生命周期或 hydration 时序已经整体收口
- 如果后续继续优化分页路径，应继续按“单个 helper / 单个分页入口”拆轮推进，
  避免把 session detail 合并、历史分页加载和恢复调度混进同一轮

## 第一百二十轮优化记录

### 目标

第一百二十轮只收敛 `_hydrateRemainingSessionHistory()` paging loop 里的
session cursor 读取包装，不改 hydration 分页顺序、结束条件和持久化语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 119 轮后，`loadMoreSessionHistory()` 已经改为复用对象级
  `sessionNextCursorForConversationObject(conversation)` helper
- 但 `_hydrateRemainingSessionHistory()` 这条 restore 后续分页 loop
  仍直接读取 `_sessionNextCursorByConversation[conversationId]`
- 这意味着同一条 session paging 路径里，手动“加载更多”入口和自动 hydration loop
  对 cursor 的读取方式仍不一致

### 优化后行为

- `_hydrateRemainingSessionHistory()` 改为先稳定解析当前 `conversation`，
  再复用 `sessionNextCursorForConversationObject(_conversations[index])`
  读取 cursor
- hydration 分页顺序、cursor 为空时退出语义、消息 merge 和 persist 时序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `session-next-cursor helper stays aligned during hydration paging loop`
  focused test，确认 restore 触发的 hydration paging loop 结束后，
  对象级 cursor helper 仍与会话最终分页状态对齐
- 现有
  `paged session restore persists once after full hydration`
  focused test 继续通过，证明 hydration 分页与消息合并语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 hydration cursor 读取收口未引入静态问题

### 风险备注

- 本轮只收掉 hydration paging loop 里的 cursor 读取包装，
  不等于 session restore 全链路、分页状态容器生命周期或 hydration 调度已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个 paging loop”拆轮推进，
  避免把 restore 首屏 detail、历史分页合并和持久化时序混进同一轮

## 第一百二十一轮优化记录

### 目标

第一百二十一轮只收敛 `_applySessionDetail()` 里的 session paging cursor
字段解析包装，不改 `next_cursor / nextCursor` 兼容语义、分页恢复顺序和消息合并行为。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 119、120 轮后，session paging 的 cursor 读取已经在“手动加载更多”入口和
  hydration loop 两处收口到对象级 helper
- 但 `_applySessionDetail()` 在写回 `_sessionNextCursorByConversation` 时，
  仍直接内联解析
  `typed['next_cursor'] as int? ?? typed['nextCursor'] as int?`
- 这意味着同一条分页状态链路里，cursor 的读取已经有 helper，
  但 detail 到 cursor 的字段兼容解析仍保留为内联实现

### 优化后行为

- 为 session detail 补齐字段解析 helper：
  `sessionNextCursorFromDetail(detail)`
- `_applySessionDetail()` 改为复用该 helper 写回 `_sessionNextCursorByConversation`
- `next_cursor / nextCursor` 双字段兼容、分页恢复顺序、cursor 生命周期、
  消息 merge 和 persist 时序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `session-next-cursor helper still parses snake_case paging detail`
  focused test，确认 `next_cursor` 形式的分页 detail 仍可驱动完整的两页 restore
- 现有
  `paged session restore persists once after full hydration`
  focused test 继续通过，证明 camelCase `nextCursor` 路径未被改动
- 现有
  `session-next-cursor helper stays aligned during hydration paging loop`
  focused test 继续通过，证明 helper 收口后分页 loop 最终状态保持不变
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部字段解析收口未引入静态问题

### 风险备注

- 本轮只收掉 `_applySessionDetail()` 里的 cursor 字段解析包装，
  不等于 session detail 合并、分页状态写回或 restore 调度已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个字段解析点”拆轮推进，
  避免把 detail 合并、分页 cursor 生命周期和 hydration 时序混进同一轮

## 第一百二十二轮优化记录

### 目标

第一百二十二轮只收敛 `codexResult` 分支里的 `timeline/rawEvents` 容器读写包装，
不改 `codexResult` 事件语义、done/failed 阶段判断和后续 session refresh 行为。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `task_snapshot` 与 `session_detail/page` 路径已经共用
  `_storeTimelineAndRawEvents(...)`
- 但 `codexResult` 分支仍单独内联做：
  - 从 `_timelineByConversation[conversationId]` 读出列表并 clone
  - 追加一条 done/failed timeline
  - 再从 `_rawEventsByConversation[conversationId]` 读出列表并 clone
  - 追加 detail 后分别写回两个 map
- 这意味着同一类“timeline/rawEvents 写回”逻辑里，
  `codexResult` 仍保留一套局部重复容器读写实现

### 优化后行为

- `codexResult` 分支改为复用：
  - `timelineForConversation(conversationId)`
  - `rawEventsForConversation(conversationId)`
  - `_storeTimelineAndRawEvents(...)`
- `codexResult` 的 done/failed 阶段判断、
  `Codex result received` 文案、raw event 追加内容以及后续 session refresh 行为保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `codex result without session binding still appends timeline and raw events through shared store`
  focused test，确认不触发后续 session refresh 的 `codexResult` 事件仍会通过共享 store
  路径正常追加 timeline/rawEvents，且最终对外行为不变
- 现有
  `codex result done refreshes session detail once`
  与
  `codex result done still notifies listeners twice`
  focused tests 继续通过，证明 `codexResult` 的 refresh 和通知语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 shared-store 收口未引入静态问题

### 风险备注

- 本轮只收掉 `codexResult` 分支里的 timeline/rawEvents 容器读写包装，
  不等于 structured result 全链路、task snapshot 分支或 timeline/rawEvents 生命周期已经整体收口
- 如果后续继续优化结果事件路径，应继续按“单个事件分支 / 单个共享写回点”拆轮推进，
  避免把 structured result refresh、session 绑定和 UI 展示混进同一轮

## 第一百二十三轮优化记录

### 目标

第一百二十三轮只收敛 `task_snapshot` 分支里的 `sessionId / session_id`
字段解析包装，不改 snapshot session 绑定、done refresh、通知和持久化语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `task_snapshot` 链里目前有两处同义的 session id 解析：
  - `handleAgentResultEvent()` 的 `task_snapshot` 分支在决定是否进入 done refresh 前，
    内联解析 `detail.detail.sessionId / session_id`
  - `_applyTaskSnapshot()` 在决定是否绑定 `sessionRef` 时，
    也再次内联解析 `detail.sessionId / session_id`
- 这意味着同一条 `task_snapshot` session 绑定语义里，
  snake_case / camelCase 兼容解析已经存在，但仍保留为两处局部重复实现

### 优化后行为

- 为 `task_snapshot` 补齐统一字段解析 helper：
  `taskSnapshotSessionIdFromDetail(detail)`
- `handleAgentResultEvent()` 的 `task_snapshot` done refresh 入口，
  和 `_applyTaskSnapshot()` 的 session 绑定入口都改为复用该 helper
- `sessionId / session_id` 双字段兼容、
  snapshot 的 session 绑定、done refresh、通知次数和持久化时序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `task snapshot done still refreshes session detail with snake_case session id`
  focused test，确认 `session_id` 形式的 `task_snapshot` done 事件
  仍会只触发一次 session detail refresh，并保持最终会话恢复语义不变
- 现有
  `task snapshot still binds conversation session once`
  与
  `task snapshot done refreshes session detail once`
  focused tests 继续通过，证明 camelCase `sessionId` 路径未被改动
- 现有
  `task snapshot done still notifies listeners twice`
  focused test 继续通过，证明 done 通知语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部字段解析收口未引入静态问题

### 风险备注

- 本轮只收掉 `task_snapshot` 链里的 session id 字段解析包装，
  不等于 snapshot 全链路、structured result refresh 或 session 生命周期已经整体收口
- 如果后续继续优化 snapshot 事件路径，应继续按“单个 helper / 单个字段解析点”拆轮推进，
  避免把 snapshot 写回、done refresh 和 UI 展示混进同一轮

## 第一百二十四轮优化记录

### 目标

第一百二十四轮只收敛 `codexResult` 分支里的 error 字段解析包装，
不改 failed/done 阶段判断、timeline 文案、raw event 写回和后续 refresh 语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `codexResult` 分支当前已经在 122 轮收口了 `timeline/rawEvents` 容器读写
- 但生成 timeline 条目时仍有两次同义的 error 解析：
  - 一次用来判断 stage 是 `failed` 还是 `done`
  - 一次用来决定 summary 是错误文案还是 `Codex result received`
- 这意味着同一条 `codexResult` failed 语义里，
  error 字段虽然只来自一个来源，但仍保留为两处局部重复解析

### 优化后行为

- 为 `codexResult` 补齐统一错误读取 helper：
  `codexResultErrorText(detail)`
- `codexResult` timeline 的 stage / summary 生成都改为复用该 helper
- failed/done 阶段判断、错误文案、raw event 追加内容和后续 refresh 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `codex result error without session binding still records failed timeline`
  focused test，确认带 `error` 的 `codexResult` 事件
  仍会把 timeline 记录为 `failed`，并保留原有错误摘要与 raw event 内容
- 现有
  `codex result without session binding still appends timeline and raw events through shared store`
  focused test 继续通过，证明无 error 的 done 路径未被改动
- 现有
  `codex result done refreshes session detail once`
  与
  `codex result done still notifies listeners twice`
  focused tests 继续通过，证明 refresh 和通知语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部错误字段解析收口未引入静态问题

### 风险备注

- 本轮只收掉 `codexResult` 分支里的 error 字段解析包装，
  不等于 structured result 全链路、failed 状态处理或 refresh 生命周期已经整体收口
- 如果后续继续优化 `codexResult` 路径，应继续按“单个 helper / 单个字段解析点”拆轮推进，
  避免把 session 绑定、refresh 调度和 UI 展示混进同一轮

## 第一百二十五轮优化记录

### 目标

第一百二十五轮只收敛 `codexResult` 分支里的 `sessionId` 字段解析包装，
不改 session 绑定、done refresh、空 sessionId 跳过语义和通知行为。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `codexResult` 路径目前已经有统一的 error 字段 helper
- 但在 `handleAgentResultEvent()` 的 `codexResult` 分支里，
  是否继续做 session 绑定和 done refresh 仍直接内联解析
  `detail['sessionId']?.toString().trim() ?? ''`
- 这意味着同一条 `codexResult` session 恢复语义里，
  `sessionId` 读取仍保留为局部内联实现

### 优化后行为

- 为 `codexResult` 补齐统一 session id 读取 helper：
  `codexResultSessionIdFromDetail(detail)`
- `handleAgentResultEvent()` 的 `codexResult` 分支改为复用该 helper
- `sessionId` 为空时跳过 session 绑定、
  非空时继续原有 done refresh、通知和 request cleanup 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `codex result without session id still skips session refresh`
  focused test，确认空白 `sessionId` 的 `codexResult` done 事件
  仍不会触发 session detail refresh，也不会错误写入 `sessionRef`
- 现有
  `codex result done refreshes session detail once`
  与
  `codex result done still notifies listeners twice`
  focused tests 继续通过，证明非空 `sessionId` 的 refresh 和通知语义未被改动
- 现有
  `codex result without session binding still appends timeline and raw events through shared store`
  与
  `codex result error without session binding still records failed timeline`
  focused tests 继续通过，证明本轮没有影响 `codexResult` 的 timeline/raw event 写回
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 session id 字段解析收口未引入静态问题

### 风险备注

- 本轮只收掉 `codexResult` 分支里的 `sessionId` 字段解析包装，
  不等于 structured result 全链路、session 生命周期或 refresh 调度已经整体收口
- 如果后续继续优化 `codexResult` 路径，应继续按“单个 helper / 单个字段解析点”拆轮推进，
  避免把 request cleanup、session 恢复和 UI 展示混进同一轮

## 第一百二十六轮优化记录

### 目标

第一百二十六轮只收敛 `task_snapshot` 事件包里 `detail.detail` map 的解析包装，
不改 snapshot session 绑定、done refresh、通知和持久化语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `task_snapshot` 相关路径当前已经分别收口了：
  - `detail` 里的 `sessionId / session_id` 字段解析
  - item 里的 `timeline/raw_events` 写回
- 但 `detail.detail` 这层 nested map 的取值仍有两处同义实现：
  - `handleAgentResultEvent()` 的 `task_snapshot` 分支在进入 done refresh 前，
    内联判断 `detail['detail'] is Map`
  - `_applyDetailJson()` 的 `task_snapshot` 分支在进入 `_applyTaskSnapshot()` 前，
    也再次内联判断并转换同一个 `detail['detail']`
- 这意味着同一条 snapshot envelope 解析链里，
  nested detail map 的读取仍保留为两处局部重复实现

### 优化后行为

- 为 `task_snapshot` envelope 补齐统一 nested detail 读取 helper：
  `taskSnapshotDetailFromEnvelope(detail)`
- `handleAgentResultEvent()` 与 `_applyDetailJson()` 的 `task_snapshot` 分支
  都改为复用该 helper
- nested detail map 的存在性判定、
  snapshot session 绑定、done refresh、通知和持久化时序保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `task snapshot running still binds session with snake_case id in detail`
  focused test，确认带 `detail.session_id` 的 running `task_snapshot` 事件
  仍会按原语义绑定 `sessionRef` 并保持 running 状态
- 现有
  `task snapshot still binds conversation session once`
  与
  `task snapshot done still refreshes session detail with snake_case session id`
  focused tests 继续通过，证明 camelCase/snake_case 路径和 done refresh 语义未被改动
- 现有
  `task snapshot done still notifies listeners twice`
  focused test 继续通过，证明通知语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 nested detail 解析收口未引入静态问题

### 风险备注

- 本轮只收掉 `task_snapshot` envelope 里的 nested detail map 解析包装，
  不等于 snapshot 全链路、session 生命周期或 refresh 调度已经整体收口
- 如果后续继续优化 `task_snapshot` 路径，应继续按“单个 helper / 单个 envelope 字段解析点”拆轮推进，
  避免把 timeline 写回、session 绑定和 UI 展示混进同一轮

## 第一百二十七轮优化记录

### 目标

第一百二十七轮只收敛结构化事件 envelope 里的 `conversationId` 字段解析包装，
不改 request mapping、active request fallback、selected fallback 和事件路由优先级语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- `handleAgentResultEvent()` 在解析结构化事件路由目标时，
  当前优先级仍是：
  `request map -> detail.conversationId -> active request -> selected`
- 但 `detail.conversationId` 这一步仍直接内联解析
  `detail?['conversationId']?.toString().trim()`
  并再通过三元表达式把空字符串折回 `null`
- 这意味着结构化事件 envelope 的 `conversationId` 读取，
  仍保留为一处局部内联实现

### 优化后行为

- 为结构化事件 envelope 补齐统一 `conversationId` 读取 helper：
  `detailConversationIdFromEnvelope(detail)`
- `handleAgentResultEvent()` 的会话路由优先级链改为复用该 helper
- `request map -> detail.conversationId -> active request -> selected`
  的原有优先级和空字符串跳过语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `detail conversation id still routes event to the referenced conversation`
  focused test，确认当 detail 自带 `conversationId` 时，
  事件仍会路由到被引用的会话，而不是当前选中会话
- 现有
  `detail event without request id still updates session detail path`
  focused test 继续通过，证明没有 requestId 的结构化 detail 事件仍按原语义处理
- 现有
  `codex result without session binding still appends timeline and raw events through shared store`
  focused test 继续通过，证明 `codexResult` 路由后的 timeline/raw event 写回语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 envelope `conversationId` 解析收口未引入静态问题

### 风险备注

- 本轮只收掉结构化事件 envelope 里的 `conversationId` 字段解析包装，
  不等于 request 路由、active request 生命周期或 selection fallback 已经整体收口
- 如果后续继续优化结构化事件路由路径，应继续按“单个 helper / 单个 envelope 字段解析点”拆轮推进，
  避免把 request cleanup、状态恢复和 UI 展示混进同一轮

## 第一百二十八轮优化记录

### 目标

第一百二十八轮只收敛结构化 detail envelope 里的 `kind` 字段解析包装，
不改 `handleAgentResultEvent()` 与 `_applyDetailJson()` 的分支分发、状态恢复、
session 明细写回和 task snapshot 处理语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 结构化 detail 事件当前已经分别收口了：
  - `conversationId` 字段解析包装
  - `task_snapshot` 的 nested `detail` map 解析包装
  - `task_snapshot / codexResult` 的若干 session/error 字段解析包装
- 但 `kind` 这一步仍保留两处同义内联实现：
  - `handleAgentResultEvent()` 在决定
    `task_snapshot` 抑制 hydration/persist 与后续 done refresh 前，
    直接读取 `detail['kind']?.toString() ?? ''`
  - `_applyDetailJson()` 在决定 `sessions / skills / session_detail / session_page / task_snapshot`
    分发时，也再次直接读取同一段 `detail['kind']?.toString() ?? ''`
- 这意味着结构化 detail envelope 的 `kind` 读取，
  仍保留为两处局部重复实现

### 优化后行为

- 为结构化 detail envelope 补齐统一 `kind` 读取 helper：
  `detailKindFromEnvelope(detail)`
- `handleAgentResultEvent()` 与 `_applyDetailJson()` 都改为复用该 helper
- `kind` 分支分发结果、
  `task_snapshot` 的 done 抑制逻辑、
  `session_detail / session_page / skills / sessions` 的既有处理语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `detail session page kind still appends older messages`
  focused test，确认 detail `kind == session_page` 时，
  事件仍会进入 append-older 路径，而不是丢失到其它 detail 分支
- 现有
  `detail event without request id still updates session detail path`
  focused test 继续通过，证明没有 requestId 的结构化 detail 事件仍按原语义处理
- 现有
  `detail conversation id still routes event to the referenced conversation`
  focused test 继续通过，证明 helper 化 `kind` 后，
  结构化事件的 conversation 路由优先级未被改动
- 现有
  `task snapshot done still refreshes session detail with snake_case session id`
  与
  `codex result without session binding still appends timeline and raw events through shared store`
  focused tests 继续通过，证明 `task_snapshot` 与 `codexResult` 分支语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 `kind` 解析收口未引入静态问题

### 风险备注

- 本轮只收掉结构化 detail envelope 里的 `kind` 字段解析包装，
  不等于 detail 分发树、session 明细恢复链路或 task snapshot 生命周期已经整体收口
- 如果后续继续优化结构化 detail 分发路径，应继续按“单个 helper / 单个 envelope 字段解析点”拆轮推进，
  避免把 `item` 解析、session 写回和 UI 展示混进同一轮

## 第一百二十九轮优化记录

### 目标

第一百二十九轮只收敛结构化 detail envelope 里的 `item` map 解析包装，
不改 `_applyDetailJson()` 的分支分发、session 明细写回和 task snapshot 写回语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 128 轮后，结构化 detail envelope 的 `kind` 读取已经统一收口到
  `detailKindFromEnvelope(detail)`
- 但 `_applyDetailJson()` 里 `item` map 的读取仍保留两处同义内联实现：
  - `session_detail / session_page` 分支先读取 `detail['item']`，
    再做 `item is Map` 判定并 `Map<String, dynamic>.from(item)`
  - `task_snapshot` 分支也再次读取同一段 `detail['item']`，
    再做 `item is Map` 判定并 `Map<String, dynamic>.from(item)`
- 这意味着结构化 detail envelope 的 `item` map 解析，
  仍保留为两处局部重复实现

### 优化后行为

- 为结构化 detail envelope 补齐统一 `item` map 读取 helper：
  `detailItemFromEnvelope(detail)`
- `_applyDetailJson()` 的 `session_detail / session_page` 与 `task_snapshot`
  分支都改为复用该 helper
- `session_detail / session_page` 的 session 明细写回、
  `task_snapshot` 的 timeline/raw_events 与后续 session 绑定语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `detail task snapshot item still stores timeline and raw events`
  focused test，确认 detail `item` 继续进入 `task_snapshot` 写回路径，
  timeline/raw_events 语义未被改动
- 现有
  `detail session page kind still appends older messages`
  focused test 继续通过，证明 `session_detail / session_page` 的 `item` 路径未被改动
- 现有
  `task snapshot still binds conversation session once`
  与
  `task snapshot done still refreshes session detail with snake_case session id`
  focused tests 继续通过，证明 helper 化 `item` 后，
  `task_snapshot` 的 session 绑定与 done refresh 语义未被改动
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 `item` 解析收口未引入静态问题

### 风险备注

- 本轮只收掉结构化 detail envelope 里的 `item` map 解析包装，
  不等于 detail 分发树、task snapshot 生命周期或 session 明细恢复链路已经整体收口
- 如果后续继续优化结构化 detail 路径，应继续按“单个 helper / 单个 envelope 字段解析点”拆轮推进，
  避免把 nested `detail`、状态恢复和 UI 展示混进同一轮

## 第一百三十轮优化记录

### 目标

第一百三十轮只收敛结构化 detail envelope 里的 `items` 列表解析包装，
不改 `_applyDetailJson()` 里 `sessions / skills` 分支的数据装载与 loaded 标记语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 129 轮后，结构化 detail envelope 的单个 `item` map 读取已经统一收口到
  `detailItemFromEnvelope(detail)`
- 但 `_applyDetailJson()` 里 `items` 列表的读取仍保留两处同义内联实现：
  - `sessions` 分支直接读取 `detail['items'] as List<dynamic>? ?? const []`，
    再做 `whereType<Map>()` 与 `Map<String, dynamic>.from(...)`
  - `skills` 分支也再次读取同一段 `detail['items'] as List<dynamic>? ?? const []`，
    再做同样的 map 过滤与转换
- 这意味着结构化 detail envelope 的 `items` 列表解析，
  仍保留为两处局部重复实现

### 优化后行为

- 为结构化 detail envelope 补齐统一 `items` 列表读取 helper：
  `detailItemsFromEnvelope(detail)`
- `_applyDetailJson()` 的 `sessions` 与 `skills` 分支都改为复用该 helper
- `sessionSummaries / skillCatalog` 的装载结果与
  `sessionsLoaded / skillsLoaded` 的既有语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `detail sessions items still refreshes session summaries`
  focused test，确认 detail `items` 继续进入 `sessions` 装载路径，
  `sessionSummaries` 与 `sessionsLoaded` 语义未被改动
- 现有
  `detail event without request id still updates session detail path`
  focused test 继续通过，证明 `skills` 分支的 `items` 路径仍按原语义处理
- 现有
  `detail task snapshot item still stores timeline and raw events`
  与
  `detail session page kind still appends older messages`
  focused tests 继续通过，证明本轮没有把其它 detail 分支带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 `items` 解析收口未引入静态问题

### 风险备注

- 本轮只收掉结构化 detail envelope 里的 `items` 列表解析包装，
  不等于 detail 分发树、catalog 生命周期或 session 列表来源已经整体收口
- 如果后续继续优化结构化 detail 路径，应继续按“单个 helper / 单个 envelope 字段解析点”拆轮推进，
  避免把初始化加载、fallback 分发和 UI 展示混进同一轮

## 第一百三十一轮优化记录

### 目标

第一百三十一轮只收敛 `handleAgentResultEvent()` 里
`sessions / session_detail / session_page / skills`
这组结构化 detail 分类判定，不改 request cleanup、通知时机和后续 fallback 语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 130 轮后，结构化 detail envelope 的 `items / item / kind`
  等字段读取已经逐步收口
- 但 `handleAgentResultEvent()` 里对
  `sessions / session_detail / session_page / skills`
  这组结构化 detail 的分类判定仍保留一处内联多分支条件：
  `kind == 'sessions' || kind == 'session_detail' || kind == 'session_page' || kind == 'skills'`
- 这组条件决定的仍是同一件事：
  当前 detail 是否应该走“request cleanup + notify + return”路径
- 这意味着结构化 detail 的一组同类 kind 分类，
  仍保留为一处局部内联实现

### 优化后行为

- 为这组结构化 detail 分类补齐统一 helper：
  `isStructuredDetailCatalogOrSessionKind(kind)`
- `handleAgentResultEvent()` 改为复用该 helper 决定
  `request cleanup + notify + return` 路径
- `sessions / session_detail / session_page / skills`
  的既有分类结果、通知时机和后续 fallback 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `structured detail catalog or session kind still clears mapped request and notifies once`
  focused test，确认 `session_detail` 仍走同一条
  `request cleanup + notify + return` 路径，后续同 request id 的普通结果会重新落回当前选中会话
- 现有
  `detail event without request id still updates session detail path`
  focused test 继续通过，证明 `skills` 仍按原语义走结构化 detail 路径
- 现有
  `detail sessions items still refreshes session summaries`
  与
  `detail session page kind still appends older messages`
  focused tests 继续通过，证明 `sessions / session_page` 仍保持原分支行为
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部分类判定收口未引入静态问题

### 风险备注

- 本轮只收掉一组结构化 detail kind 分类判定，
  不等于 `handleAgentResultEvent()` 的整体分发树、request 生命周期或 fallback 恢复链路已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个分类判定块”拆轮推进，
  避免把 `task_snapshot` / `codexResult` 分支、状态恢复和 UI 展示混进同一轮

## 第一百三十二轮优化记录

### 目标

第一百三十二轮只收敛 `handleAgentResultEvent()` 里
`kind == 'task_snapshot' && status == 'done'`
这组重复布尔判定，不改 `task_snapshot` 的 suppress hydration/persist 语义、
done refresh 路径和通知时机。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 131 轮后，结构化 detail 的分类判定已经继续按 helper 收口
- 但 `handleAgentResultEvent()` 里针对 `task_snapshot done` 的 suppress 条件
  仍保留两处同义内联实现：
  - `suppressTaskSnapshotHydration`
    直接判断 `kind == 'task_snapshot' && status == 'done'`
  - `suppressTaskSnapshotPersist`
    也再次直接判断同一段 `kind == 'task_snapshot' && status == 'done'`
- 这意味着同一条 `task_snapshot done` 布尔语义，
  仍保留为两处局部重复实现

### 优化后行为

- 为这组 `task_snapshot done` suppress 条件补齐统一 helper：
  `shouldSuppressTaskSnapshotHydrationOrPersist(kind: kind, status: status)`
- `suppressTaskSnapshotHydration` 与 `suppressTaskSnapshotPersist`
  都改为复用该 helper
- `task_snapshot done` 的 suppress hydration/persist、
  detail-only refresh、通知与持久化语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `task snapshot done suppress helper still keeps detail-only refresh path`
  focused test，确认 `task_snapshot + done` 仍只走一轮 session detail refresh，
  并保持当前单次持久化语义
- 现有
  `task snapshot done still refreshes session detail with snake_case session id`
  与
  `task snapshot done still notifies listeners twice`
  focused tests 继续通过，证明 done refresh 与通知语义未被改动
- 现有
  `task snapshot still binds conversation session once`
  focused test 继续通过，证明非 done 的 `task_snapshot` 路径未被带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 suppress 判定收口未引入静态问题

### 风险备注

- 本轮只收掉 `task_snapshot done` 的一组重复 suppress 布尔判定，
  不等于 `task_snapshot` 生命周期、refresh 调度或 request cleanup 链路已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个布尔判定块”拆轮推进，
  避免把 `task_snapshot` 的 session 绑定、timeline 写回和 UI 展示混进同一轮

## 第一百三十三轮优化记录

### 目标

第一百三十三轮只收敛 `handleAgentResultEvent()` 里 `codexResult`
分支的 `status != 'done'` 重复布尔判定，
不改运行中 session 绑定、done refresh 路径和通知语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 132 轮后，`task_snapshot done` 的 suppress 条件已经继续按 helper 收口
- 但 `codexResult` 分支里是否“先绑定 session，但不立即 hydrate/persist”的布尔语义，
  仍保留两处同义内联实现：
  - `_bindSessionRefAtConversation(... hydrateIfNeeded: status != 'done', ...)`
  - `_bindSessionRefAtConversation(... persist: status != 'done', ...)`
- 这两处判断表达的仍是同一件事：
  当前 `codexResult` 是否处于“非 done，先做 in-place binding”的状态
- 这意味着 `codexResult` 的一组局部状态判定，
  仍保留为两处重复内联实现

### 优化后行为

- 为这组 `codexResult` 状态判定补齐统一 helper：
  `shouldBindCodexResultSessionWithoutImmediateRefresh(status)`
- `hydrateIfNeeded` 与 `persist` 的值都改为复用该 helper
- `codexResult` 的运行中 session 绑定、
  done refresh、通知和 request cleanup 语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `codex result running bind helper still keeps in-place session binding path`
  focused test，确认 `codexResult + running` 仍会先绑定 `sessionRef`，
  保持 `continue` 模式且不额外落消息
- 现有
  `codex result done refreshes session detail once`
  与
  `codex result done still notifies listeners twice`
  focused tests 继续通过，证明 done refresh 与通知语义未被改动
- 现有
  `codex result without session id still skips session refresh`
  focused test 继续通过，证明空 sessionId guard 路径未被带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 `codexResult` 状态判定收口未引入静态问题

### 风险备注

- 本轮只收掉 `codexResult` 分支里一组 `status != 'done'` 重复布尔判定，
  不等于 `codexResult` 生命周期、session 绑定链路或 request cleanup 已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个布尔判定块”拆轮推进，
  避免把 `codexResult` 的 timeline 写回、done refresh 和 UI 展示混进同一轮

## 第一百三十四轮优化记录

### 目标

第一百三十四轮只收敛 `handleAgentResultEvent()` 里 `task_snapshot`
分支的“非 `running / started` 时清理 request 映射”布尔判定，
不改 request cleanup、done refresh、通知和 fallback 路由语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 133 轮后，`codexResult` 分支里的 `status != 'done'`
  判定已经按 helper 收口
- 但 `task_snapshot` 分支里“什么时候从 `_requestToConversation`
  移除当前 requestId”的状态分类仍保留为一处内联实现：
  `status != 'running' && status != 'started'`
- 这段判定表达的仍是同一件事：
  当前 `task_snapshot` 是否已经离开运行中阶段，可以进入 request cleanup
- 这意味着 `task_snapshot` 的一组局部状态分类，
  仍保留为内联布尔实现

### 优化后行为

- 为这组 `task_snapshot` cleanup 状态分类补齐统一 helper：
  `shouldCleanupTaskSnapshotRequestForStatus(status)`
- `handleAgentResultEvent()` 的 `task_snapshot` cleanup 判定改为复用该 helper
- `task_snapshot` 的 running / started 保留 request 映射语义、
  failed / done / cancelled cleanup 语义、done refresh、通知和后续 fallback
  路由语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `task snapshot failed cleanup helper still routes later updates to selection`
  focused test，确认 `task_snapshot + failed` 仍会清理 request 映射，
  后续同 requestId 的普通结果继续回落到当前选中会话
- 现有
  `task snapshot done request cleanup still routes later updates to selection`
  focused test 继续通过，证明 done cleanup 与 fallback 路由语义未被改动
- 现有
  `task snapshot still binds conversation session once`
  与
  `task snapshot running still binds session with snake_case id in detail`
  focused tests 继续通过，证明运行中 `task_snapshot` 仍不会提前清理 request 映射
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 cleanup 状态判定收口未引入静态问题

### 风险备注

- 本轮只收掉 `task_snapshot` 分支里一组“非 running / started 时 cleanup”
  的重复状态分类语义，不等于 request 生命周期、fallback 路由或 snapshot
  状态流已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个状态判定块”拆轮推进，
  避免把 session 绑定、done refresh、timeline 写回和 UI 展示混进同一轮

## 第一百三十五轮优化记录

### 目标

第一百三十五轮只收敛 `handleAgentResultEvent()` 里结构化 session refresh
入口的 `status == 'done'` 重复布尔判定，不改 `task_snapshot`、
`codexResult` 的 session 绑定、done refresh、cleanup 和通知语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 134 轮后，`task_snapshot` 的 request cleanup 状态分类已经按 helper 收口
- 但结构化结果链里“什么时候允许进入 session detail refresh”这组语义，
  仍保留两处同义内联实现：
  - `task_snapshot` 分支在 `sessionId.isNotEmpty` 后直接判断 `status == 'done'`
  - `codexResult` 分支在 `sessionId.isNotEmpty` 后也直接判断 `status == 'done'`
- 这两处判断表达的仍是同一件事：
  当前结构化结果是否处于允许进入 refresh 的完成态
- 这意味着结构化 session refresh 的入口状态分类，
  仍保留为两处重复内联布尔实现

### 优化后行为

- 为这组结构化 refresh 状态判定补齐统一 helper：
  `shouldRefreshStructuredSessionDetailForStatus(status)`
- `task_snapshot` 与 `codexResult` 的 refresh 入口都改为复用该 helper
- `task_snapshot` 的 done refresh、
  `codexResult` 的 done refresh、failed 不触发 finalize refresh、
  request cleanup、session 绑定和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `codex result failed refresh helper still keeps binding-only detail hydration path`
  focused test，确认 `codexResult + failed + sessionId`
  仍不会进入 `_finalizeStructuredSessionRefresh(...)`，
  但会保留当前 session 绑定带来的单次 detail hydration 语义
- 现有
  `task snapshot done refreshes session detail once`
  与
  `codex result done refreshes session detail once`
  focused tests 继续通过，证明 done refresh 语义未被改动
- 现有
  `codex result without session id still skips session refresh`
  focused test 继续通过，证明空 sessionId guard 路径未被带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 refresh 状态判定收口未引入静态问题

### 风险备注

- 本轮只收掉结构化 session refresh 入口的一组 `status == 'done'`
  重复布尔判定，不等于 `task_snapshot` / `codexResult`
  生命周期、session 绑定或 refresh 调度链已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个状态判定块”拆轮推进，
  避免把 request cleanup、timeline 写回、fallback 路由和 UI 展示混进同一轮

## 第一百三十六轮优化记录

### 目标

第一百三十六轮只收敛 `handleAgentResultEvent()` 里结构化结果链的
`requestId -> conversationId` cleanup 副作用包装，不改
`task_snapshot`、`codexResult`、`sessions / session_detail / session_page / skills`
分支的 cleanup 时机、fallback 路由、done refresh 和通知语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 135 轮后，结构化 session refresh 的完成态判定已经按 helper 收口
- 但结构化结果链里同一段 request cleanup 副作用仍保留三处同义内联实现：
  - `task_snapshot` 在允许 cleanup 时直接判断 `requestId.isNotEmpty` 后移除 map
  - `codexResult + done` 在 finalize refresh 后也直接判断 `requestId.isNotEmpty`
    后移除 map
  - `sessions / session_detail / session_page / skills` 分支在 notify 前
    也再次直接判断 `requestId.isNotEmpty` 后移除 map
- 这三处副作用表达的仍是同一件事：
  如果当前结构化结果需要 cleanup，就从 `_requestToConversation`
  移除当前 request 映射
- 这意味着结构化结果链的 request cleanup 包装，
  仍保留为多处分散的内联副作用

### 优化后行为

- 为这组 request cleanup 副作用补齐统一 helper：
  `clearRequestConversationMapping(requestId)`
- `task_snapshot`、`codexResult + done`、
  `sessions / session_detail / session_page / skills`
  分支现在都复用该 helper 做 cleanup
- cleanup 时机、done refresh、fallback 路由和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `codex result done request cleanup still routes later updates to selection`
  focused test，确认 `codexResult + done`
  仍会清理 request 映射，后续同 requestId 的普通结果继续回落到当前选中会话
- 现有
  `task snapshot done request cleanup still routes later updates to selection`
  与
  `task snapshot failed cleanup helper still routes later updates to selection`
  focused tests 继续通过，证明 `task_snapshot` cleanup 与 fallback 路由语义未被改动
- 现有
  `structured detail catalog or session kind still clears mapped request and notifies once`
  focused test 继续通过，证明 catalog/session 类结构化结果的 cleanup 与通知语义未被带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部 cleanup 副作用收口未引入静态问题

### 风险备注

- 本轮只收掉结构化结果链里一组 request cleanup 的重复副作用包装，
  不等于 request 生命周期、fallback 路由或 result dispatch 链已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个副作用块”拆轮推进，
  避免把 refresh 判定、timeline 写回和 UI 展示混进同一轮

## 第一百三十七轮优化记录

### 目标

第一百三十七轮只收敛 `handleAgentResultEvent()` 里
`_activeRequestConversationId` 清理时机的终态状态判定，不改
plain 结果路由、request cleanup、done refresh 和通知语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 136 轮后，结构化结果链的 request cleanup 副作用已经按 helper 收口
- 但 `handleAgentResultEvent()` 在更新 `_runtimeStatuses` 之后，
  对 `_activeRequestConversationId` 的清理时机仍保留一处内联终态判定：
  `status == 'done' || status == 'failed' || status == 'cancelled'`
- 这段判定表达的仍是同一件事：
  当前 runtime 事件是否已进入应当释放 active request 绑定的终态
- 这意味着 active request 清理的状态分类，
  仍保留为一处内联布尔实现

### 优化后行为

- 为这组 active request 清理状态判定补齐统一 helper：
  `shouldClearActiveRequestConversationForStatus(status)`
- `handleAgentResultEvent()` 改为复用该 helper 决定是否清理
  `_activeRequestConversationId`
- `done / failed / cancelled` 的 active request 清理时机、
  后续 plain 结果路由、request cleanup、done refresh 和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `cancelled status cleanup helper still clears active request before later plain update`
  focused test，确认 `cancelled` 事件仍会先清掉
  `_activeRequestConversationId`，后续无 request map 的普通结果继续回落到当前选中会话
- 现有
  `plain agent result appends a message with one listener notification`
  focused test 继续通过，证明普通结果的基础落消息语义未被改动
- 现有
  `codex result done request cleanup still routes later updates to selection`
  focused test 继续通过，证明 request cleanup 与 selection fallback 语义未被带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部终态状态判定收口未引入静态问题

### 风险备注

- 本轮只收掉 `_activeRequestConversationId` 清理时机的一组终态状态判定，
  不等于 active request 生命周期、plain 结果路由或 runtime 状态流已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个状态判定块”拆轮推进，
  避免把 request map、session refresh 和 UI 展示混进同一轮

## 第一百三十八轮优化记录

### 目标

第一百三十八轮只收敛 `_applyDetailJson()` 里
`session_detail / session_page` kind 分类判定，不改 session 明细写回、
older messages append、cursor 恢复和通知语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 137 轮后，`handleAgentResultEvent()` 里的 active request 终态清理已经按 helper 收口
- 但 `_applyDetailJson()` 在分发 session 详情结果时，
  仍保留一处内联 kind 分类实现：
  `kind == 'session_detail' || kind == 'session_page'`
- 这段判定表达的仍是同一件事：
  当前 detail envelope 是否属于 session 明细或 session 历史分页
- 这意味着 `_applyDetailJson()` 的 session 明细分发分类，
  仍保留为一处内联布尔实现

### 优化后行为

- 为这组 session 明细分发判定补齐统一 helper：
  `isStructuredSessionDetailOrPageKind(kind)`
- `_applyDetailJson()` 的 session 明细分支改为复用该 helper
- `session_detail` 的主明细写回、
  `session_page` 的 older messages append、`nextCursor` 恢复和通知语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `session detail/page kind helper still keeps page append path`
  focused test，确认 `session_detail` 后继续接 `session_page`
  仍会保留主明细消息在前、older messages 追加在后，且不额外污染 timeline/rawEvents
- 现有
  `detail session page kind still appends older messages`
  focused test 继续通过，证明 page append 语义未被改动
- 现有
  `detail event without request id still updates session detail path`
  focused test 继续通过，证明明细分发入口未被带偏
- `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认局部分发 kind 判定收口未引入静态问题

### 风险备注

- 本轮只收掉 `_applyDetailJson()` 里一组
  `session_detail / session_page` kind 分类判定，
  不等于 session 明细合并、分页恢复或消息排序链已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个分发判定块”拆轮推进，
  避免把 session merge、cursor 生命周期和 UI 展示混进同一轮

## 第一百三十九轮优化记录

### 目标

第一百三十九轮只收敛 status recovery 链里
`_statusRecoveryAttempts.remove(requestId)` 的 cleanup 副作用包装，
不改 bridge transport failure 判定、deferred recovery、fallback 回灌和
failed/done 状态展示语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 138 轮后，`_applyDetailJson()` 的 session detail/page kind 分类已经按 helper 收口
- 但 status recovery 链里对 `_statusRecoveryAttempts` 的 cleanup 仍分散在三处：
  - `handleAgentResultEvent()` 收到普通 runtime 结果后的一次清理
  - `_recoverTaskStatus()` fallback 回灌前的一次清理
  - `_recoverTaskStatus()` catch fallback 回灌前的一次清理
- 这三处副作用表达的仍是同一件事：
  当前 `requestId` 的 status recovery attempt 生命周期已经结束，应移除 attempt 记录
- 这意味着 status recovery cleanup 仍保留为一组分散副作用，
  当前轮需要继续把“清理入口统一、行为不变”的证据补齐

### 优化后行为

- status recovery cleanup 统一通过
  `clearStatusRecoveryAttempt(requestId)` 执行
- `handleAgentResultEvent()` 的普通结果路径与 `_recoverTaskStatus()` 的
  fallback / catch fallback 路径继续共用该 helper
- `requestId` 为空时直接跳过清理；非空 request 的 attempt 记录统一从
  `_statusRecoveryAttempts` 中移除
- bridge transport failure 判定、deferred recovery、fallback 路由、
  runtime status 写回和 failed/done 展示语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `status recovery cleanup helper still allows repeated recovery for same request`
  focused test，确认同一个 `requestId` 在第一次 bridge transport failure
  通过 status recovery 完成后，后续再次收到同类 failed event 时仍会再次进入
  `requestTaskStatus()` 恢复路径
- 现有
  `does not immediately request task status when runtime already tracks the request`
  focused test 继续通过，证明 deferred recovery 入口未被带偏
- 现有
  `running status also clears immediate recovery attempt state`
  focused test 继续通过，证明运行中状态到来的 immediate recovery cleanup 语义未变
- 现有
  `still updates to completed when recovered status arrives`
  focused test 继续通过，证明 recovered done 结果写回 completed 状态的语义未变
- shared `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认本轮只收 cleanup 副作用包装，未引入新的静态问题

### 风险备注

- 本轮只收 status recovery attempt 的 cleanup 副作用包装，
  不等于 status recovery 生命周期、fallback 回灌策略或 transport failure
  判定链已经整体收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个 recovery 副作用块”拆轮推进，
  避免把 recovery 调度、fallback 语义和 UI 状态展示混进同一轮

## 第一百四十轮优化记录

### 目标

第一百四十轮只收敛 `_recoverTaskStatus()` 里的 status recovery attempt
有效性判定，不改 attempt 计数、延迟查询顺序、fallback 回灌和错误处理语义。
主要代码：
- `flutter/lib/models/agent_dashboard_model.dart`
- `tools/agent_dashboard_harness/lib/models/agent_dashboard_model.dart`
- `flutter/test/agent_dashboard_model_test.dart`

### 优化前行为

- 第 139 轮后，status recovery cleanup 已统一通过
  `clearStatusRecoveryAttempt(requestId)` 执行
- 但 `_recoverTaskStatus()` 里对“当前 attempt 是否仍有效”的判断仍分散在三处：
  - 4 秒延迟结束后的一次判定
  - `deferImmediateQuery` 分支里 status 查询返回 `null` 后的一次判定
  - `catch` fallback 回灌前的一次判定
- 这三处判定表达的仍是同一件事：
  当前 `requestId` 对应的 recovery attempt 是否还是本轮 attempt，
  如果已被新的运行中结果或新的 recovery 覆盖，就应直接退出当前恢复链
- 这意味着 `_recoverTaskStatus()` 的 attempt 有效性守卫仍保留为一组重复内联布尔判定

### 优化后行为

- 为 status recovery attempt 有效性守卫补齐统一 helper：
  `isCurrentStatusRecoveryAttempt(requestId: ..., attempt: ...)`
- `_recoverTaskStatus()` 的延迟恢复、deferred query 和 catch fallback
  三处守卫改为复用该 helper
- attempt 计数递增时机、deferred query 先后顺序、
  `clearStatusRecoveryAttempt(requestId)` cleanup 时机和 fallback 路由语义保持不变

### 回归验证

已完成：

1. `flutter test test/agent_dashboard_model_test.dart`
2. `dart analyze lib/common/widgets/overlay.dart lib/common/widgets/agent_dashboard_dev_shell.dart lib/common/widgets/agent_dashboard_page.dart lib/models/agent_dashboard_model.dart lib/models/agent_dashboard_runtime_io.dart lib/models/agent_dashboard_runtime_web.dart test/agent_dashboard_model_test.dart`

覆盖确认：

- 新增
  `status recovery attempt helper still suppresses deferred fallback after running update`
  focused test，确认 deferred recovery 已建立后，如果同一 request 收到
  `running` 更新并清掉旧 attempt，4 秒后不会再触发延迟 status 查询或 fallback 回灌
- 现有
  `does not immediately request task status when runtime already tracks the request`
  focused test 继续通过，证明 deferred recovery 的“先不立即查 status”语义未变
- 现有
  `status recovery cleanup helper still allows repeated recovery for same request`
  focused test 继续通过，证明 recovery cleanup 之后的重复 recovery 入口语义未变
- 现有
  `still updates to completed when recovered status arrives`
  focused test 继续通过，证明正常 recovered done 结果写回 completed 状态的语义未变
- shared `agent_dashboard_model.dart` 与新增 test 的静态分析继续通过，
  确认本轮只收 attempt 守卫判定，未引入新的静态问题

### 风险备注

- 本轮只收掉 `_recoverTaskStatus()` 里的 attempt 有效性守卫判定，
  不等于 status recovery 生命周期、fallback 回灌策略或 transport failure
  的整体恢复模型已经收口
- 如果后续继续优化这条路径，应继续按“单个 helper / 单个 recovery 守卫块”拆轮推进，
  避免把 recovery 调度、status 查询失败语义和 UI 状态展示混进同一轮

## 暂缓风险项

以下问题已经识别，但本轮基线阶段只记录，不处理：

1. session 详情读取存在重复扫描和整文件读取成本
2. dashboard hydration 路径偏重，长会话恢复成本高
3. push / poll / snapshot 状态链路存在重复
4. bridge 仍是 thread-per-request 模型
5. `TASKS` 仍使用全局 `Mutex<HashMap<...>>`，高频更新下的容器模型仍有后续优化空间
6. `AgentDashboardModel` 职责过重
7. voice 临时文件只做了保守清理，阈值和更细粒度回收策略仍有后续优化空间

对应风险分析见：

- `docs/agent-dashboard-optimization-audit-zh.md`

## 下一轮优化准入条件

进入真正优化实现前，需要满足：

1. 先以本基线文档作为回归契约
2. 每轮只收口一个主问题，不并发做大范围结构改动
3. 优化后逐项跑完“优化前验证清单”
4. 新发现的风险先记入文档，再决定是否进入当前轮次
