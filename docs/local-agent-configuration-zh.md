# 本地 Agent 开发配置指南

本文说明如何在本机配置 Pocket-Codex / Codex Agent Bridge 的开发脚本。公开仓库不会保存你的真实工具链路径、设备序列号、安装路径、服务器地址或 Codex 会话目录；这些值应通过环境变量或命令行参数传入。

## 配置原则

- 不要把本机路径写进源码。
- 不要提交 `.env`、日志、设备 ID、server key、session 数据。
- 推荐在本机 PowerShell Profile、临时终端环境变量或私有脚本里设置路径。
- 所有脚本都支持命令行参数覆盖环境变量。

## 常用环境变量

| 环境变量 | 用途 |
| --- | --- |
| `RUSTDESK_VS_DEV_CMD` | Visual Studio `vcvars64.bat` 路径 |
| `RUSTDESK_VS_CMAKE_BIN` | Visual Studio CMake `bin` 目录 |
| `LLVM_BIN` | LLVM `bin` 目录 |
| `VCPKG_ROOT` | vcpkg 根目录 |
| `VCPKG_INSTALLED_ROOT` | Windows vcpkg 依赖安装目录 |
| `JAVA_HOME` | JDK 根目录 |
| `ANDROID_SDK_ROOT` / `ANDROID_HOME` | Android SDK 根目录 |
| `FLUTTER_BIN` | Flutter `bin` 目录 |
| `PYTHON_HOME` | Python 安装目录 |
| `RUSTDESK_ANDROID_DEVICE_ID` | Flutter Android 调试设备 ID |
| `RUSTDESK_HOST_IP` | 自建 RustDesk server 对客户端可见的 IP 或域名 |
| `RUSTDESK_INSTALL_EXE` | 本机已安装 RustDesk / Pocket-Codex exe 路径 |
| `RUSTLS_PLATFORM_VERIFIER_MAVEN_DIR` | Android 构建需要时的本地 Maven 目录 |

示例：

```powershell
$env:RUSTDESK_VS_DEV_CMD = "<VS_VCVARS64_PATH>"
$env:RUSTDESK_VS_CMAKE_BIN = "<VS_CMAKE_BIN>"
$env:LLVM_BIN = "<LLVM_BIN>"
$env:VCPKG_ROOT = "<VCPKG_ROOT>"
$env:FLUTTER_BIN = "<FLUTTER_BIN>"
$env:ANDROID_SDK_ROOT = "<ANDROID_SDK_ROOT>"
$env:RUSTDESK_HOST_IP = "<HOST_IP_OR_DOMAIN>"
```

## Windows 桌面构建

检查环境：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/check-windows-env.ps1
```

安装最小 vcpkg 依赖：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/install-windows-deps.ps1
```

运行 Rust 检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-windows-agent.ps1 -Mode check
```

如不想设置环境变量，也可以直接传参：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-windows-agent.ps1 `
  -VsDevCmd "<VS_VCVARS64_PATH>" `
  -VsCMakeBin "<VS_CMAKE_BIN>" `
  -VcpkgRoot "<VCPKG_ROOT>" `
  -FlutterBin "<FLUTTER_BIN>" `
  -Mode check
```

## Android 构建和安装

构建 Android APK：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-android-agent-apk.ps1 `
  -Mode debug
```

安装到已授权 USB 调试设备：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/install-android-agent-apk.ps1
```

多设备时指定序列号：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/install-android-agent-apk.ps1 `
  -Serial "<ANDROID_DEVICE_ID>"
```

## iOS Google / Firebase 配置

公开仓库只保留模板文件：

```powershell
Copy-Item flutter/ios/Runner/GoogleService-Info.plist.example `
  flutter/ios/Runner/GoogleService-Info.plist
```

将模板中的 `<GOOGLE_API_KEY>`、`<GOOGLE_APP_ID>`、`<FIREBASE_PROJECT_ID>` 等占位符替换为你自己的 Firebase / Google 项目配置。真实 `GoogleService-Info.plist` 是本地私有配置，已被 `.gitignore` 忽略，不要提交。

## Agent Bridge 本地项目配置

将当前仓库配置为允许 Codex Agent Bridge 访问的项目：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/configure-local-agent.ps1
```

配置其他项目：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/configure-local-agent.ps1 `
  -ProjectId "<PROJECT_ID>" `
  -ProjectPath "<PROJECT_PATH>"
```

`ProjectPath` 是本机私有路径。它会写入本机 RustDesk 配置，不应写进公开仓库文档。

## 自建 RustDesk Server

启动前设置客户端可访问的 Host IP 或域名：

```powershell
$env:RUSTDESK_HOST_IP = "<HOST_IP_OR_DOMAIN>"
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/start-rustdesk-selfhosted-server.ps1
```

更多说明见 [RustDesk 自建服务器配置指南](rustdesk-selfhosted-status-zh.md)。

## 刷新本机已安装运行时

如果你要把当前仓库的 debug exe 覆盖到本机安装位置：

```powershell
$env:RUSTDESK_INSTALL_EXE = "<INSTALLED_RUSTDESK_EXE>"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/restart-rustdesk-from-source.ps1
```

该脚本会停止服务、复制 exe 并重启服务。请只在你管理的本机开发环境中使用。

## 发布前注意

- 本文里的 `<...>` 都是占位符，不要替换后提交。
- 如果你创建了本地辅助脚本，请放在仓库外或确保被 `.gitignore` 覆盖。
- 提交前运行隐私整改清单里的门禁命令。
