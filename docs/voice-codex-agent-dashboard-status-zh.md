# RustDesk Agent Dashboard 状态

更新时间：2026-06-03

## 本轮目标

把当前 RustDesk 移动端的简陋聊天面板，升级成一套更接近 `hermes-wingman` 工作台组织方式的 Agent Dashboard，并继续复用当前已打通的 `/agent -> 本机 Codex bridge` 链路。

## 本轮已完成

### 1. Hermes 风格工作台界面已落地

- 已重做 `flutter/lib/common/widgets/agent_dashboard_page.dart`
- 当前页面结构改为三栏工作台：
  - 左栏：会话列表、搜索、项目筛选
  - 中栏：消息主区、发送区、当前任务状态
  - 右栏：项目 / session / profile / 上下文配置 / 预览
- 视觉风格参考了 `hermes-wingman` 的组织方式：
  - 工作台顶栏
  - 玻璃面板感布局
  - 会话列表卡片
  - 状态 badge
  - 更明确的上下文与任务区域

### 2. 会话模型能力补齐

- 已增强 `flutter/lib/models/agent_dashboard_model.dart`
- 新增能力：
  - 会话搜索
  - 项目筛选
  - 会话 pin / unpin
  - 会话重命名
  - 会话删除
  - 历史上下文开关
  - 终端 transcript 上下文开关
  - 会话运行状态跟踪：
    - `idle`
    - `running`
    - `needsConfirmation`
    - `completed`
    - `failed`

### 3. Agent 结果分流更稳

- 当前 `[Agent:...]` 回包不再只依赖“当前选中会话”
- 已增加“最近一次发起请求的会话”优先归属
- 这样用户切换会话后，Agent 回包串到别的会话的概率会明显下降

### 4. 现有移动端入口继续生效

- `flutter/lib/mobile/pages/remote_page.dart`
- `flutter/lib/mobile/pages/view_camera_page.dart`
- 点击 `Text chat` 仍直接进入新的 Agent Dashboard

### 5. 终端上下文能力保留

- `flutter/lib/models/terminal_model.dart`
- 仍支持把当前受控机最近终端 transcript 作为 prompt context 注入

## 当前行为说明

- 当前发送仍复用兼容命令：

```text
/agent <project> [profile=...] [session=...] <prompt>
```

- Dashboard 里配置的：
  - project
  - session
  - profile
  - conversation history
  - terminal transcript

都会先被拼成兼容 `/agent` 命令再发到被控端。

## 已验证

- `flutter analyze` 已针对本轮相关文件跑过
- 当前无新的编译错误
- 剩余只有仓库里原有的 deprecated API 提示：
  - `chat_page.dart`
  - `remote_page.dart`
  - `view_camera_page.dart`
  - `chat_model.dart`

## 当前存在问题

### 1. 结果归属仍是启发式，不是正式任务绑定

- 目前还是按“最近一次发起请求的会话”归属 Agent 回包
- 这比“当前选中会话”稳，但还不是严格的 request_id 绑定
- 真正彻底的方案仍然是：
  - Flutter 侧接正式 `AgentResult`
  - 会话里保存 request_id
  - bridge / Rust / Flutter 做结构化关联

### 2. 仍主要依赖聊天文本兼容路由

- 现在 Dashboard 体验已经升级
- 但底层发送仍主要依赖 `/agent ...` 文本兼容链路
- 还没有把 `project / session / profile / executor` 全面切到正式 `AgentCommand`

### 3. 终端上下文仍然偏粗粒度

- 当前只支持拿最近 transcript
- 还没有做：
  - 指定某个终端会话
  - 指定截取范围
  - transcript 搜索
  - 多终端上下文编排

### 4. 还不是完整的 Hermes 功能面

- 当前是“参考 Hermes 的工作台组织方式”，不是一比一移植
- 还没做：
  - 会话历史跨来源编排
  - 会话标签体系
  - 任务卡片流
  - 结构化任务进度视图
  - 任务恢复 / resume 选择器 UI

## 下一步建议

1. 先在手机真机上看新版 Dashboard 实际手感，确认布局、入口、会话切换是否顺手。
2. 然后继续做正式协议收口：
   - Flutter 直接发 `sessionSendAgentCommand`
   - Flutter 直接收结构化 `AgentResult`
   - 用 `request_id` 把任务和会话严格绑定
3. 再补强工作台能力：
   - 会话历史搜索
   - terminal transcript 选择器
   - 会话 resume 选择器
   - 任务卡片 / 任务列表

## 需要你手动处理的事项

- 手机端需要安装并打开最新 APK，实际看新版 Dashboard
- 如果你要我继续做真机验证，需要你在手机上实际进入远控后的 `Text chat`
- 如果界面布局、层级、按钮位置有具体偏好，你需要直接指出：
  - 哪个区域太重
  - 哪个区域太弱
  - 更像 Hermes 的哪一块
