# Pocket-Codex 项目介绍

> 让 AI 留在桌面继续工作，你把时间留给路上、餐桌和假期。

`Pocket-Codex` 不是在 RustDesk 里塞几个页面，也不是做一个“安卓版 Codex 聊天客户端”。

这个项目要解决的是另一件事：

当你人不在电脑前，甚至出差、在路上、在餐桌边、在假期里时，桌面上的 Codex 还能继续在真实工作区里做事，而你用手机负责发起、确认和查看结果。

## 这是什么

这是一个基于 `rustdesk/rustdesk` 的分支项目。

上游 RustDesk 解决的是远程桌面连接问题。这个分支在它的基础上继续往前做，目标是把“远控桌面”变成“远控桌面上的 agent 工作流”。

项目当前围绕两个核心功能展开：

- `Codex Agent Bridge`
- `Agent Dashboard`

这两个部分才是这个仓库区别于普通 RustDesk 分支、也区别于移动端原生 Codex 客户端的关键。

## 为什么要做这个

桌面端已经有真实仓库、真实终端、真实依赖、真实账号状态，也已经有能执行代码任务的 Codex CLI。

问题不在“能不能执行”，而在“人不在桌前时，怎么把这套执行能力接出来”。

普通远控只能解决“看到桌面、点到桌面”。

这个项目想解决的是：

- 手机连上桌面后，不只是远控
- 还可以直接调度桌面上的 Codex
- 让桌面机器在真实工作区里持续推进任务

换句话说，这个项目不是把手机变成开发机，而是把手机变成桌面 agent 的控制面板。

## 两个核心功能

### Codex Agent Bridge

`Codex Agent Bridge` 运行在被控桌面端。

它负责把来自移动端的 agent 请求，转换成桌面本机对 Codex CLI 的真实调用，并把状态和结果再送回 RustDesk 会话。

当前相关代码主要在：

- `src/agent_bridge.rs`
- `src/server/connection.rs`
- `libs/hbb_common/protos/message.proto`

它当前已经覆盖的职责包括：

- 启动本机 bridge 服务
- 接收 run / confirm / cancel / task status 请求
- 限制只允许在白名单项目内执行
- 支持 `read-only` 和 `workspace-write`
- 在需要时保留写入前确认
- 返回任务状态和执行结果

### Agent Dashboard

`Agent Dashboard` 是移动端任务面板，不再把 agent 入口停留在一个普通聊天框里。

当前相关代码主要在：

- `flutter/lib/models/agent_dashboard_model.dart`
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`

它当前已经具备的方向包括：

- 把对话组织成任务工作区
- 选择 project / profile / session
- 控制是否带会话历史和终端 transcript
- 展示 running / needs confirmation / completed / failed 等状态
- 支持 full page 和 floating dashboard 两种开发预览模式

## 这个项目和别的方案有什么区别

### 和上游 RustDesk 的区别

上游的重点是远程桌面本身。

这个项目的重点是：让远程桌面成为桌面 agent 的工作入口。

### 和移动端 Codex 客户端的区别

这里真正执行任务的不是手机，而是桌面端。

也就是说：

- 仓库在桌面上
- 终端在桌面上
- 依赖环境在桌面上
- Codex 执行也在桌面上

手机只是控制入口。

这就是整个项目最重要的产品定位。

## 当前进展

这个仓库现在已经不是纯概念阶段，但也还不是面向大众的一键可用版本。

已经有的部分：

- 本机 bridge 运行时
- bridge HTTP 接口和任务状态流
- RustDesk 链路里的 agent 请求转发
- Dashboard 的模型层和 UI 壳
- Dashboard 的 mock/dev shell
- `AgentCommand` / `AgentResult` / `AgentCancel` 正式协议结构

仍在收口中的部分：

- Dashboard 有些请求路径还复用兼容聊天命令
- 正式协议链路还不是唯一入口
- request id 级别的结果归属还在继续收紧
- 语音输入和 STT 还没完成
- 面向公开用户的安装和接入文档还不够完整

## 适合谁

这个项目更适合下面这类用户：

- 有长期在线的桌面机器
- 已经习惯在桌面环境里用 Codex CLI
- 不想在出门时浪费桌面端的工作能力
- 希望用手机做“调度”和“确认”，而不是在手机上假装完整开发

如果你的目标只是远程控制桌面，上游 RustDesk 就够了。

如果你的目标是“人不在桌前，但桌面上的 Codex 继续在真实项目里工作”，这个项目才有意义。

## 代码入口

如果想从代码层面快速理解这个仓库，建议先看这些位置：

- `src/agent_bridge.rs`
- `src/server/connection.rs`
- `flutter/lib/common/widgets/agent_dashboard_page.dart`
- `flutter/lib/common/widgets/agent_dashboard_dev_shell.dart`
- `flutter/lib/models/agent_dashboard_model.dart`
- `libs/hbb_common/protos/message.proto`
- `agent/codex-bridge/scripts/`

## 文档入口

当前补充文档主要是中文：

- `docs/voice-codex-agent-tech-status-zh.md`
- `docs/voice-codex-agent-dashboard-status-zh.md`
- `docs/agent-dashboard-dev-flow-zh.md`
- `docs/rustdesk-selfhosted-status-zh.md`

## 面向公开仓库的方向

这个仓库最终不是想停在“个人分支实验”。

目标是把它整理成一个别人也能看懂、能搭起来、能继续迭代的公开仓库。

接下来文档层最该补的是：

- 一条清晰的快速开始路径
- 一份简洁的架构说明
- 明确的安全边界和信任边界
- 本地模式 / 自建服务模式的接入方法
- 面向贡献者的约束和路线图

## 和上游的关系

这个仓库基于 [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk)。

RustDesk 仍然是远程桌面基础能力的来源。这个项目是在那个基础上做另一条产品方向。

如果你要找原始项目、官方发布或通用构建文档，请直接看：

- 上游仓库：<https://github.com/rustdesk/rustdesk>
- 官方构建文档：<https://rustdesk.com/docs/en/dev/build/>
- RustDesk Server：<https://rustdesk.com/server>
