# Pocket-Codex TODO

更新时间：2026-06-04

## 总目标

把当前 fork 收敛成一套可长期使用的个人工作流：

- 手机连接自己的 RustDesk server
- 在远控画面上打开窗口式 Agent Dashboard
- 指定项目和线程
- 文字或语音把任务交给被控端桌面 Codex
- 手机端看到与桌面 Codex 连续一致的会话过程

## 第一性原理优先级

先按“系统要成立必须先满足什么”排序，而不是按界面表象排序。

### 必须先成立的 4 件事

1. `Transport`
   Agent 请求必须稳定走 RustDesk 远控链路。
2. `Execution`
   被控端桌面必须稳定调起 Codex / whisper。
3. `Authority`
   会话历史必须有单一权威源。
4. `Observability`
   手机端必须能看到 started / running / confirm / failed / done。

这 4 件事不稳，后面的 UI 润色、skills 页面丰富、语音按钮动画都没有意义。

## 已完成

### 结构化主链路

- [x] `AgentCommand / AgentResult / AgentCancel` 已接入 RustDesk 主链路
- [x] Flutter 已通过 `sessionSendAgentCommand` 发送结构化 agent 请求
- [x] 被控端已通过 `handle_agent_command / spawn_agent_run` 调本机 bridge
- [x] bridge 已支持 `run / confirm / cancel / task status`
- [x] Flutter 已消费 `agent_result` 结构化事件

### Dashboard 基础工作台

- [x] 移动端 `Text chat` 已切到新的 Agent Dashboard
- [x] Dashboard 已有 `Chat / Timeline / Sessions / Context / Skills`
- [x] 已有会话列表、project、threadMode、sessionRef、profile、skills
- [x] 已支持恢复本机 Codex session
- [x] 已支持 `request_id -> conversation` 结果归属
- [x] 已有 dev shell / mock route / hot reload 调试流

### 桌面端 bridge 扩展能力

- [x] bridge 已支持 sessions 索引与详情读取
- [x] bridge 已支持 skills catalog 与镜像
- [x] bridge 已支持 `voice/transcribe` 和 `voice/run` 骨架
- [x] bridge 已支持本地审计日志和任务 timeline

### 自建服务方向

- [x] 自建 RustDesk server 脚本和文档已落仓库
- [x] 当前方向已经明确：后续正式链路不再依赖公共服务器

## 现在最应该执行的事

### P0：把“真能工作”的闭环补齐

#### P0.1 移动端语音 MVP

- [ ] Android Dashboard 增加语音入口
- [ ] 录音权限走现有 `kRecordAudio`
- [ ] Android 原生录音采集短语音片段
- [ ] 录音结束后封装为 `voice_run` envelope
- [ ] 通过现有 `sessionSendAgentCommand` 发到被控端
- [ ] 被控端 bridge 执行 `voice_run`
- [ ] transcript / error / done 回写到当前会话

验收标准：

- 手机上的语音请求不再走本地 `127.0.0.1`
- 能在当前对话里看到 transcript 或明确错误
- 结果进入现有 `Timeline` 和 `Chat`

#### P0.2 桌面端 STT 配置真正可用

- [ ] 配置 `codex-bridge-whisper-command`
- [ ] 配置 `codex-bridge-whisper-model`
- [ ] 明确默认 `voice_language`
- [ ] 跑一次桌面 bridge 本地转写 smoke test

验收标准：

- 被控端桌面本机执行 `voice/transcribe` 返回有效 transcript
- 配置缺失时 UI 有明确错误，不是静默失败

#### P0.3 会话权威源收口

- [ ] 定义“手机端历史和桌面 Codex 历史谁是权威”
- [ ] 默认让 Codex session 成为历史权威
- [ ] Flutter 本地会话只保留：
  - title
  - pinned
  - archived
  - draft
  - lastReadAt
  - windowState
- [ ] 打开会话时优先从 bridge 拉 Codex transcript

验收标准：

- 手机端看到的会话内容和桌面 Codex 线程一致
- Flutter 本地不再保存一份会漂移的完整 transcript 副本

### P1：把兼容层收口成正式产品链路

- [ ] 把 confirm/cancel 从聊天命令切到正式结构化流
- [ ] Dashboard 增加确认弹窗和任务恢复入口
- [ ] 普通聊天与 agent 结果显示彻底解耦
- [ ] 减少 `/agent` 文本命令在正式用户流中的存在感

### P2：把 Dashboard 做成长期工作台

- [ ] sessions 分页与更早历史加载
- [ ] pinned / archived / unread 完整行为收口
- [ ] skills 新建 / 编辑 / 删除完整 UI
- [ ] project registry 可视化管理
- [ ] raw event 展开视图
- [ ] terminal transcript 选择器

### P3：发布与维护

- [ ] 清理中文文档编码污染
- [ ] 补开发者指南
- [ ] 补架构图和故障排查
- [ ] 明确 Android release 签名与版本策略
- [ ] 明确 Windows runner / 安装版的替换与测试路径

## 需要你手动处理的事项

### 1. 桌面端 STT 运行时

- [ ] 安装或提供 `whisper.cpp` 可执行文件
- [ ] 提供模型文件路径
- [ ] 决定默认语言

### 2. 自建 RustDesk server 验收

- [ ] 管理员 PowerShell 放行防火墙端口
- [ ] 重启自建服务
- [ ] 确认手机和电脑都连到自建 server

### 3. 如果要联调安装版 Windows RustDesk

- [ ] 停掉 `RustDesk Service`
- [ ] 再替换安装目录 DLL

## 建议执行顺序

### 下一轮直接执行

1. 先做 `P0.1`：移动端语音 MVP
2. 再做 `P0.2`：桌面 STT 配置与错误回显
3. 再做 `P0.3`：会话权威源收口

### 之后继续

4. 收口 confirm/cancel
5. 完善 Dashboard 工作台
6. 最后做发布与长期维护文档
