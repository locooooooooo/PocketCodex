# AgentDashboard 手机端 Sessions 排障与修复记录

本文记录一套可复用处理流程：手机端 AgentDashboard 已经可以和 Codex 对话，但 `Sessions` 页面没有内容，或手机远控下看板 UI 不明显、不好点、不好刷新。目标是帮助后来使用者更快判断是 bridge、会话目录、筛选状态还是手机端展示链路出了问题。

## 适用现象

- 手机端能发出 Codex 请求并收到结果，但 `Sessions` 页面空白。
- `Refresh` 入口不明显，用户不知道如何重新加载 session catalog。
- 看板浮窗还在，但因为手机端远控场景限制，用户误以为 `Sessions` 功能不可用。

## 优先判断顺序

1. 先确认 bridge 活着：`/health`
2. 再确认普通只读 run 能执行。
3. 再确认本机 `/agent/sessions` 是否有数据。
4. 最后确认远程 `list_sessions` envelope 是否能返回结构化 catalog。

公开仓库现在提供了对应自检脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/check-agent-dashboard-sessions.ps1 `
  -Project "<PROJECT_ID>"
```

## 当前仓库已收口的修复

### 1. 远程 `list_sessions` 只返回最近一批

手机端远程链路走的是 `AgentResult.detail_json`。如果一次返回完整 session index，payload 过大时更容易在远控路径上丢失或导致 UI 刷新失败。

当前仓库已把远程 `list_sessions` 收口为只返回最近一批 public summaries：

- Rust bridge 远程 catalog 默认只返回最近 `60` 条 sessions。
- 本机 HTTP `/agent/sessions` 仍保留完整能力，方便桌面侧排查和更完整的本地工具消费。

### 2. 远程刷新不再先把旧 Sessions 列表清空

旧做法会在远程刷新开始时先清空 `_sessionSummaries`。如果新事件没有及时到达，用户会直接看到空页。

当前仓库改为：

- 远程刷新开始时保留旧列表。
- 如果已有 sessions，则继续保持 loaded 状态。
- 新的 `kind=sessions` 结构化事件回来后再替换。

### 3. `Sessions` 页固定提供刷新入口

当前仓库在 `Sessions` 页 header 右上角固定提供：

- 刷新按钮
- 刷新中的 loading 状态
- 有项目筛选时的“清除筛选”按钮

这样即使当前是空页，也不需要先点击空状态卡片里的按钮才能刷新。

## 自检输出应该怎么看

`check-agent-dashboard-sessions.ps1` 现在会输出几类关键信息：

- `health`：bridge 是否正常监听。
- `config`：本地项目配置是否已经被 bridge 读取。
- `run status`：普通 read-only 请求是否正常执行。
- `direct sessions count`：桌面 bridge 本地 session index 条数。
- `remote sessions count`：远程 `list_sessions` envelope 返回的条数。
- `detail_json_bytes`：远程结构化目录的大致体积。

常见判断：

- 如果 `direct sessions count > 0` 且 `remote sessions count = 0`：
  - 桌面 bridge 有数据，但远程链路或手机端结构化事件应用仍有问题。
- 如果两边都是 `0`：
  - 更可能是桌面 `~/.codex` 没有有效 session，或当前项目并没有已有会话。
- 如果远程条数少于本机直读：
  - 这是当前仓库为了手机端稳定性做的有意限制，不是 bug。

## 对外安装部署建议

- 安装完桌面端并配置好本地项目后，先跑一次：
  - `agent/codex-bridge/scripts/smoke-test.ps1`
- 如果手机端 `Sessions` 仍异常，再跑：
  - `agent/codex-bridge/scripts/check-agent-dashboard-sessions.ps1`
- 再根据输出决定是修 bridge 配置、修项目 allowlist，还是继续看手机端 UI 交互。

这样比直接让用户手工拼 `Invoke-RestMethod` 更容易复用，也更适合对外公开文档。
