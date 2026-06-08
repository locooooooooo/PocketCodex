# RustDesk Agent Dashboard 开发调试流

更新时间：2026-06-04

## 目标

把当前 Dashboard 的调试链路收口成一套快速、可热重载、可完整预览的开发方案，减少“连真远控 + 重装 APK + 手敲长命令”的成本。

这套方案现在支持 3 种模式：

- `normal`：正常 RustDesk 启动
- `full`：独立全页 Dashboard mock 预览
- `floating`：模拟远控画面上的悬浮 Dashboard 完整预览

## 本次已完成

- 已把 Flutter 启动开关从单一布尔值升级成模式化开关：
  - `RUSTDESK_DEV_DASHBOARD_MODE=full`
  - `RUSTDESK_DEV_DASHBOARD_MODE=floating`
- 已增强 `AgentDashboardDevShell`：
  - `full` 模式：直接预览整页 Dashboard
  - `floating` 模式：预览“远控背景 + 悬浮 Dashboard + 最小化气泡”
  - 两种模式都保留 mock 数据和模拟 agent 动作
- 已新增统一启动脚本：
  - `agent/codex-bridge/scripts/run-dashboard-dev.ps1`

## 最快调试路径

### 1. 本机桌面直接调悬浮窗口态

这是当前最快、最完整、最适合 UI 迭代的路径。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform windows -Mode floating
```

特点：

- 直接进入“远控背景 + 浮动 Dashboard”完整预览
- 支持 Flutter hot reload
- 不需要 APK
- 不需要连真远控
- 最适合调窗口大小、层级、标题栏、最小化气泡、会话 sheet

### 2. 本机桌面调全页 Dashboard

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform windows -Mode full
```

特点：

- 适合调 Dashboard 内部信息架构
- 适合调长内容、会话列表、Context 面板
- 也支持 Flutter hot reload

### 3. Android 真机调悬浮窗口态

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform android -Mode floating -AndroidDeviceId <ANDROID_DEVICE_ID>
```

特点：

- 适合最终确认手机手感
- 支持 Flutter hot reload
- 不需要先连真远控

### 4. 正常模式启动

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/run-dashboard-dev.ps1 -Platform windows -Mode normal
```

不加 Dashboard dev 模式时，仍按正常 RustDesk 逻辑启动。

## 这套调试流能看到什么

### `full` 模式

- 完整 Dashboard 页面
- 会话列表
- Chat
- Context
- mock 数据
- `Simulate read-only / confirm / failure`

### `floating` 模式

- 模拟远控画布背景
- 悬浮 Dashboard 窗口
- 窗口最小化气泡
- Chat / Timeline / Sessions / Context / Skills 五个 tab
- 会话选择 sheet
- mock 数据
- `Simulate read-only / confirm / failure`

## 热重载边界

下面这些改动支持 `flutter run` 期间直接 hot reload：

- Dart UI 布局
- 样式
- 文案
- 悬浮窗口结构
- mock 交互
- 会话切换 sheet

下面这些改动通常不属于纯热重载范围：

- Rust 层改动
- FRB 绑定变化
- 原生 Android / Windows runner 改动
- protobuf / bridge 协议变化

这类改动仍需要重新编译或重新启动。

## 推荐工作方式

建议固定成这个顺序：

1. 先用 `windows + floating` 做大部分 UI 迭代
2. 再用 `windows + full` 检查 Dashboard 内容密度
3. 最后用 `android + floating` 看真机手感
4. UI 稳定后，再切回真远控链路验证实际行为

## 延期需求记录

- 任务结束状态气泡：用户希望后续参考 Codex pet 的体验，当 agent 任务完成、失败或等待确认时，用悬浮气泡展示当前对话状态，并支持点击回到对应会话。
- 本轮只记录需求，不接入功能；等当前 Dashboard UI/UX 收尾完成后，先输出技术方案，再决定实现边界。

## 后续建议

下一步如果继续收尾，我建议做这两件事：

1. 给 `floating` 开发模式补“预设窗口尺寸 / 预设横竖屏 / 预设 agent 状态”切换
2. 把真实 `/agent` confirm/cancel 接进现在这套窗口 UI
