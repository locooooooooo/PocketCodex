# RustDesk 自建服务器配置指南

本文是面向公开仓库的配置指南，不记录任何个人部署状态。请把实际 IP、设备 ID、server key、安装路径和调试日志保存在本地私有笔记、环境变量或未提交的 `.env` 文件中。

## 适用场景

Pocket-Codex 可以通过自建 RustDesk server 连接桌面和手机端。自建服务适合这些情况：

- 你希望远控链路不依赖公共 RustDesk server。
- 你拥有或管理桌面端、移动端和部署服务器。
- 你可以配置局域网、防火墙、路由器或云服务器安全组。

## 需要准备

- Docker 和 Docker Compose。
- 一台可被客户端访问的主机。
- 客户端可访问的 Host IP 或域名。
- Windows 用户需要管理员权限来放行防火墙端口。

## 端口

默认 RustDesk server OSS 端口：

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| `21114` | TCP | API / web console 相关路径，按部署需要开放 |
| `21115` | TCP | hbbs TCP |
| `21116` | TCP/UDP | hbbs NAT traversal |
| `21117` | TCP | hbbr relay |
| `21118` | TCP | hbbs WebSocket |
| `21119` | TCP | hbbr WebSocket |

如果手机和桌面在同一局域网，Host IP 通常填写局域网地址。如果跨公网访问，Host IP 应填写公网 IP 或域名，并确保端口映射和防火墙已放行。

## 启动自建服务

不要把真实 Host IP 写进仓库。启动时用参数或环境变量传入：

```powershell
$env:RUSTDESK_HOST_IP = "<HOST_IP_OR_DOMAIN>"
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1
```

也可以直接传参：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1 `
  -HostIp "<HOST_IP_OR_DOMAIN>"
```

脚本会在 `infra/rustdesk-server-oss/.env` 写入运行时配置，并使用 `infra/rustdesk-server-oss/docker-compose.yml` 启动 `hbbs` 和 `hbbr`。该 `.env` 文件是本地运行产物，不应提交。

如果你想手动维护 compose 配置，也可以复制模板：

```powershell
Copy-Item infra/rustdesk-server-oss/.env.example infra/rustdesk-server-oss/.env
```

然后把 `.env` 里的 `<HOST_IP_OR_DOMAIN>` 替换为你自己的 IP 或域名。不要提交 `.env`。

服务启动后会输出客户端配置：

- ID Server: `<HOST_IP_OR_DOMAIN>`
- Relay Server: `<HOST_IP_OR_DOMAIN>:21117`
- Key: `<SERVER_PUBLIC_KEY>`

这些值应只配置到你的客户端或本地私有记录中，不要写回公开文档。

## Windows 防火墙

如手机无法连接桌面端或服务端口不可达，以管理员 PowerShell 放行端口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/open-rustdesk-selfhosted-firewall.ps1
```

如果你使用云服务器，还需要在云平台安全组中放行同样的端口。

## 客户端配置

在桌面端和移动端 RustDesk / Pocket-Codex 设置中填写：

- ID Server: `<HOST_IP_OR_DOMAIN>`
- Relay Server: `<HOST_IP_OR_DOMAIN>:21117`
- Key: `<SERVER_PUBLIC_KEY>`

如果使用 RustDesk server OSS 且未确认 WebSocket 链路，请先关闭客户端里的 `Use WebSocket`，确认普通远控连通后再单独验证 WebSocket 端口。

## 验证

本机或同网段机器可先检查端口：

```powershell
Test-NetConnection <HOST_IP_OR_DOMAIN> -Port 21115
Test-NetConnection <HOST_IP_OR_DOMAIN> -Port 21116
Test-NetConnection <HOST_IP_OR_DOMAIN> -Port 21117
```

如果启用了 WebSocket，再检查：

```powershell
Test-NetConnection <HOST_IP_OR_DOMAIN> -Port 21118
Test-NetConnection <HOST_IP_OR_DOMAIN> -Port 21119
```

Docker 侧可查看日志：

```powershell
docker logs rustdesk-hbbs --tail 100
docker logs rustdesk-hbbr --tail 100
```

日志可能包含设备 ID、网络地址或连接行为，只能用于本地排查，不要提交到仓库。

## 隐私和发布规则

- 不提交 `infra/rustdesk-server-oss/.env`。
- 不提交 `infra/rustdesk-server-oss/data/`。
- 不提交 Docker 日志、Android logcat、设备 ID、server key 或真实客户端配置截图。
- 文档中只能保留 `<HOST_IP_OR_DOMAIN>`、`<SERVER_PUBLIC_KEY>`、`<DEVICE_ID>` 这类占位符。
