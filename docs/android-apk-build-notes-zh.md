# Android APK 打包说明

本文记录在 Windows 环境为 Pocket-Codex 构建 Android APK 的最小可复现流程，以及目前仓库内已经收口的构建入口。

## 目标

- 输出 `arm64-v8a` Android APK。
- 尽量不改业务逻辑，只补齐打包所需环境、脚本参数和最小 Android 配置。
- 默认输出路径：
  - `flutter/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`

## 当前仓库内入口

构建脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-android-agent-apk.ps1 `
  -Mode debug
```

安装到已授权 Android 设备：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/install-android-agent-apk.ps1
```

脚本默认会：

- 复用环境变量中的 JDK / Android SDK / Flutter / vcpkg 路径。
- 构建 Android Rust 动态库并复制到 `jniLibs/arm64-v8a/`。
- 默认直接走 `flutter/android/gradlew.bat assembleDebug`，便于保留更清晰的 Gradle 日志。
- 在构建完成后尝试用 `apksigner verify --print-certs` 校验 APK 签名。

## 推荐工具链

建议统一抽象成以下目录变量：

- `$PROJECT_ROOT`：仓库根目录。
- `$TOOL_ROOT`：Flutter、Android SDK、JDK 等工具目录。
- `$CACHE_ROOT`：Cargo、Pub、Gradle 等缓存目录。

建议版本：

| 工具 | 建议值 |
| --- | --- |
| Flutter | `3.24.5` |
| Dart | Flutter 自带 `3.5.4` |
| Android SDK | 包含 `platforms/android-34`、`build-tools/34.0.0` |
| Android NDK | `28.2.13676358` |
| JDK | `17` |

## 推荐环境变量

最小必需：

```powershell
$env:JAVA_HOME = "<JDK_ROOT>"
$env:ANDROID_SDK_ROOT = "<ANDROID_SDK_ROOT>"
$env:FLUTTER_BIN = "<FLUTTER_BIN>"
$env:RUSTDESK_VS_CMAKE_BIN = "<VS_CMAKE_BIN>"
$env:VCPKG_ROOT = "<VCPKG_ROOT>"
```

推荐同时设置缓存目录：

```powershell
$env:CARGO_HOME = "<CACHE_ROOT>\\cargo-home"
$env:PUB_CACHE = "<CACHE_ROOT>\\pub-cache"
$env:GRADLE_USER_HOME = "<CACHE_ROOT>\\gradle-home"
```

如果使用自定义 Cargo 缓存，或需要显式指定 rustls Android Maven 仓库：

```powershell
$env:RUSTLS_PLATFORM_VERIFIER_MAVEN_DIR = "<rustls-platform-verifier-android 的 maven 目录>"
```

网络不稳定时可选：

```powershell
$env:HTTP_PROXY = "http://127.0.0.1:7890"
$env:HTTPS_PROXY = "http://127.0.0.1:7890"
$env:ALL_PROXY = "http://127.0.0.1:7890"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "<本地或镜像 Flutter engine Maven URL>"
```

## 常用构建方式

默认推荐直接用仓库脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-android-agent-apk.ps1 `
  -Mode debug `
  -BuildBackend gradle
```

如果要强制走 Flutter 命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-android-agent-apk.ps1 `
  -Mode debug `
  -BuildBackend flutter
```

如果只想跳过签名校验：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-android-agent-apk.ps1 `
  -Mode debug `
  -SkipApkVerify
```

## 已沉淀到仓库的 Android 侧修复

- `flutter/android/app/build.gradle`
  - `minSdkVersion` 已提升到 `22`，满足 `rustls-platform-verifier-android 0.1.1` 的 Manifest 要求。
  - Gradle 配置会优先读取 `RUSTLS_PLATFORM_VERIFIER_MAVEN_DIR`，否则从 `CARGO_HOME` 或默认 Cargo registry 中查找本地 Maven 仓库。
- `flutter/android/app/src/main/res/`
  - 已补齐 `mipmap-*` 目录下的 launcher/foreground 资源，避免 `ic_launcher_foreground` 缺失。
- `flutter/android/app/src/main/res/values/colors.xml`
  - 仅保留业务需要的颜色定义，避免与 launcher 生成资源冲突。
- `flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt`
  - 前台通知改为使用存在的 `R.mipmap.ic_launcher`。
  - `NotificationCompat.Builder` 对应的默认常量改为 `NotificationCompat.DEFAULT_ALL`。

## 常见坑

### 1. Flutter 新版本与当前 Gradle/Kotlin 组合不匹配

现象：

```text
Language version 1.4 is no longer supported
```

处理：

- 优先使用 Flutter `3.24.5`。
- 不要在当前仓库上直接切到更高 Flutter 版本再假设 Android 构建仍然兼容。

### 2. Gradle wrapper 下载慢或超时

建议：

- 预热 `GRADLE_USER_HOME`。
- 必要时手工缓存 `gradle-7.6.4-all.zip`。

### 3. rustls Android Maven 仓库找不到

现象：

```text
rustls-platform-verifier-android maven directory was not found
```

处理：

- 设置 `CARGO_HOME` 到真实缓存目录。
- 或显式设置 `RUSTLS_PLATFORM_VERIFIER_MAVEN_DIR`。

### 4. Flutter engine jar 下载反复断流

处理：

- 使用代理、镜像，或本地 `FLUTTER_STORAGE_BASE_URL`。
- 构建脚本会透传这些环境变量，不需要改仓库源码。

### 5. Manifest minSdkVersion 冲突

现象：

```text
uses-sdk:minSdkVersion 21 cannot be smaller than version 22 declared in library
```

处理：

- 保持仓库里的 `minSdkVersion 22`。
- 不建议用 `tools:overrideLibrary` 硬覆盖依赖要求。

### 6. 通知栏图标或默认常量报错

现象：

```text
Unresolved reference 'ic_stat_logo'
```

或：

```text
Unresolved reference 'setDefaults'
```

处理：

- 使用已存在的 `R.mipmap.ic_launcher`。
- 对 `NotificationCompat.Builder` 使用 `NotificationCompat.DEFAULT_ALL`。

### 7. 华为 / HarmonyOS 安装检测拦截本地 APK

现象：

```text
华为安装器或安全检测拦截本地构建的 APK，联网状态下无法继续安装
```

处理：

- 先关闭手机 Wi-Fi 和移动数据，让手机处于断网状态。
- 断网后安装 APK，安装完成后再恢复联网。
- 如果是 `adb install` 报版本降级或签名冲突，按 Android 安装错误单独处理：提升 `versionCode`、卸载旧包，或确认签名来源，不要把这类错误误判成华为检测拦截。

## 验证

检查 APK：

```powershell
Get-ChildItem -Recurse -Path ".\\flutter\\build\\app\\outputs" -Include "*.apk"
```

手动校验签名：

```powershell
& "$env:ANDROID_SDK_ROOT\\build-tools\\34.0.0\\apksigner.bat" verify --print-certs `
  ".\\flutter\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-debug.apk"
```

预期至少能看到：

```text
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
```
