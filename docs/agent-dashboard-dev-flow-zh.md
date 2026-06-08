# RustDesk Agent Dashboard 开发调试流

更新时间：2026-06-08

## 目标

Dashboard 开发优先走 Web 和桌面本机快速预览，减少“真远控 + 重装 APK + 手敲长命令”的迭代成本。

当前调试流支持：

- `normal`：正常 RustDesk 启动
- `full`：独立全页 Dashboard 预览
- `floating`：模拟远控画面上的悬浮 Dashboard 预览
- mock data：纯 UI 和状态模拟
- live debug bridge：读取本机配置的 Codex data directory，并转发到本机 bridge

## 推荐入口

### 1. 主工程 Flutter 预览

本机桌面悬浮窗口态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform windows -Mode floating
```

本机桌面全页：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform windows -Mode full
```

Android 真机悬浮窗口态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform android -Mode floating -AndroidDeviceId <ANDROID_DEVICE_ID>
```

正常 RustDesk 启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform windows -Mode normal
```

脚本会从 `FLUTTER_BIN` 或 PATH 找 Flutter；Android 设备 ID 可通过 `-AndroidDeviceId` 或 `RUSTDESK_ANDROID_DEVICE_ID` 传入。

### 2. Harness mock 模式

用于快速调 UI，不依赖本机 Codex session：

```powershell
cd tools/agent_dashboard_harness
.\run-web.ps1 -Mode floating
.\run-web.ps1 -Mode full
```

### 3. Harness live 模式

用于验证 Dashboard 与本机 debug bridge 的真实数据边界：

```powershell
cd tools/agent_dashboard_harness
.\run-web-live.ps1 -Mode floating
.\run-web-live.ps1 -Mode full
```

live 模式会启动：

- `tools/agent_dashboard_harness/debug-bridge/server.mjs`
- 本地 Web build server

debug bridge 只绑定本机地址，日志目录和 `.log` 文件不进入 Git。`/health` 不返回完整 `CODEX_HOME` 路径。

## 能看到什么

### `full` 模式

- 完整 Dashboard 页面
- conversation 列表
- Chat
- Timeline
- Sessions
- Context
- Skills
- 状态卡片
- mock agent 动作

### `floating` 模式

- 模拟远控画布背景
- 悬浮 Dashboard 窗口
- 最小化入口
- 会话选择 sheet
- task status bubble overlay
- `done` / `failed` / `needs_confirmation` 状态提醒

## 任务状态气泡调试

任务状态气泡已经接入，不再是延期需求。

当前可通过以下路径验证：

- mock 模式里的 agent 状态模拟
- live 模式里 bridge 返回的 structured `AgentResult`
- Flutter test 中的 task bubble 用例

期望行为：

- 完成任务显示 `Done`
- 失败任务显示 `Failed`
- 等待确认显示 `Needs approval`
- 同一 request/status 不重复弹
- 点击气泡选中对应 conversation
- 选中 conversation 后清理该 conversation 的气泡

## 热重载边界

通常支持 hot reload：

- Dart UI 布局
- 样式和文案
- Dashboard 页面结构
- floating window 结构
- mock 交互
- task bubble 展示

通常需要重新编译或重新启动：

- Rust 层改动
- Flutter Rust Bridge 绑定变化
- protobuf / message 协议变化
- Android / Windows runner 改动
- native 权限和服务改动

## 推荐工作方式

1. 用 `tools/agent_dashboard_harness/run-web.ps1` 快速调 UI。
2. 用 `tools/agent_dashboard_harness/run-web-live.ps1` 验证 live 数据边界。
3. 用 `run-dashboard-dev.ps1 -Platform windows -Mode floating` 验证主工程桌面预览。
4. 用 `run-dashboard-dev.ps1 -Platform android -Mode floating` 做真机手感验证。
5. UI 稳定后，再回到真实 RustDesk 远控链路验证 `AgentCommand` / `AgentResult`。

## 后续建议

- 给 floating 模式补预设窗口尺寸、横竖屏和远控工具栏位置。
- 增加 task bubble 在输入法、安全区、远控工具栏附近的避让检查。
- 将真机验证结果补回 `docs/voice-codex-agent-dashboard-status-zh.md`。
