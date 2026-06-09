# Windows Release 构建说明

本文记录在 Windows 环境为 Pocket-Codex 构建 Windows x64 桌面端 Release 版本时，仓库内已经收口的脚本入口、产物结构和已知坑位。

## 目标

- 编译 Windows x64 桌面端 Release 版本。
- 输出可直接运行的 Flutter Windows 程序目录。
- 尽量不改业务代码，只处理工具链、缓存和构建脚本兼容问题。

默认最终产物：

- `flutter/build/windows/x64/runner/Release/rustdesk.exe`

运行目录中还需要保留：

- `data/`
- `librustdesk.dll`
- `flutter_windows.dll`
- `dylib_virtual_display.dll`
- Flutter 插件 DLL

## 当前仓库内入口

先检查环境：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/check-windows-env.ps1
```

安装最小 Windows vcpkg 依赖：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/install-windows-deps.ps1
```

执行 Windows Release 构建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent/codex-bridge/scripts/build-windows-agent.ps1 `
  -Mode flutter-release
```

脚本默认会：

- 初始化 `vcvars64.bat`。
- 透传 Rust / Flutter / Python / LLVM / vcpkg / Cargo / Pub 相关环境变量。
- 调用 `python build.py --flutter --skip-portable-pack`。
- 构建完成后检查 `rustdesk.exe` 是否存在，并执行 `rustdesk.exe --version` 验证。

## 推荐环境变量

建议把实际路径抽象为以下变量：

```powershell
$env:RUSTDESK_VS_DEV_CMD = "<VS_VCVARS64_PATH>"
$env:RUSTDESK_VS_CMAKE_BIN = "<CMAKE_BIN>"
$env:LLVM_BIN = "<LLVM_BIN>"
$env:VCPKG_ROOT = "<VCPKG_ROOT>"
$env:VCPKG_INSTALLED_ROOT = "<VCPKG_INSTALLED_ROOT>"
$env:FLUTTER_BIN = "<FLUTTER_BIN>"
$env:PYTHON_HOME = "<PYTHON_HOME>"

$env:RUSTUP_TOOLCHAIN = "1.75.0-x86_64-pc-windows-msvc"
$env:CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse"
$env:CARGO_HOME = "<CARGO_HOME>"
$env:PUB_CACHE = "<PUB_CACHE>"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

$env:CC = "cl"
$env:CXX = "cl"
```

说明：

- `VCPKG_ROOT` 指向 `vcpkg.exe` 所在根目录。
- `VCPKG_INSTALLED_ROOT` 指向本地缓存的安装输出目录，默认可落在仓库 `.vcpkg-installed`。
- `CC` / `CXX` 显式设置为 `cl`，可避免 Ninja/CMake 误选普通 `clang++`。
- 当前这台机器上，`1.75.0-x86_64-pc-windows-msvc` 比 `stable 1.94.x` 更接近已知可用组合；后者在本次验证中会卡在 `windows-sys 0.60.2` 编译阶段。

## 已收口到仓库的 Windows 构建改进

### 1. `agent/codex-bridge/scripts/build-windows-agent.ps1`

已支持：

- 从环境变量读取 `vcvars64.bat`、LLVM、CMake、Flutter、Python、vcpkg、Cargo、Pub 配置。
- 默认 `RUSTUP_TOOLCHAIN=1.75.0-x86_64-pc-windows-msvc`。
- 默认 `CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse`。
- `flutter-release` 模式会检查 symlink 支持，并在构建后调用 `rustdesk.exe --version` 做最小验证。

### 2. `agent/codex-bridge/scripts/check-windows-env.ps1`

已支持：

- 缺少显式路径时仍可回退到 PATH 中的工具。
- 对 `RUSTDESK_VS_DEV_CMD`、`RUSTDESK_VS_CMAKE_BIN`、`LLVM_BIN` 给出明确提示。

### 3. `agent/codex-bridge/scripts/install-windows-deps.ps1`

已支持：

- 从环境变量读取 `VCPKG_ROOT`、`VCPKG_INSTALLED_ROOT`、CMake 目录。
- 不再依赖仓库作者机器上的硬编码路径。

### 4. `build.py`

已补两类 Windows 兼容收口：

- 在 Flutter Windows 构建前，尝试把 Flutter SDK `windows-x64-release` engine 文件同步到 `flutter/windows/flutter/ephemeral`，缓解 `flutter_windows.dll.lib` 缺失问题。
- 构建后如果实际输出落在 `flutter/build/windows/x64/runner/` 而不是 `runner/Release/`，自动整理出兼容的 `Release/` 目录，保证后续脚本和文档路径稳定。

## 常见坑

### 1. Flutter Windows 插件要求符号链接权限

现象：

```text
Building with plugins requires symlink support.
```

处理：

- 开启 Windows Developer Mode。
- 或在管理员终端中运行构建。

快速入口：

```powershell
start ms-settings:developers
```

### 2. Flutter 3.24 与 VS2026 检测兼容问题

现象可能类似：

```text
Unable to find suitable Visual Studio toolchain.
```

说明：

- 这是 Flutter SDK 自身工具链识别边界，不是项目源码问题。
- 当前仓库不会提交对本机 Flutter SDK 的私有补丁。

建议：

- 优先使用一套本机已验证可用的 Flutter 3.24.5 + VS/MSVC 组合。
- 如果必须在 VS2026 上继续沿用 Flutter 3.24.5，可能仍需要在本机 Flutter SDK 上保留兼容补丁。

### 3. Ninja / 单配置输出目录与原脚本预期不一致

现象：

- 实际输出在 `flutter/build/windows/x64/runner/`
- 但旧脚本或文档假设路径是 `flutter/build/windows/x64/runner/Release/`

处理：

- 当前仓库内 `build.py` 已自动整理兼容的 `Release/` 目录。

### 4. Flutter engine 文件没有同步到 ephemeral

现象：

```text
missing flutter_windows.dll.lib
```

处理：

- 当前仓库内 `build.py` 会在 Windows 构建前尝试从 Flutter SDK cache 的 `windows-x64-release` 同步关键 engine 文件到 `flutter/windows/flutter/ephemeral`。

### 5. Ninja 误选 clang++

现象：

```text
clang++: error: no such file or directory: '/W4'
```

处理：

- 显式设置：

```powershell
$env:CC = "cl"
$env:CXX = "cl"
```

- 并确保 `vcvars64.bat` 已被调用。

## 验证

构建成功后，至少检查：

```powershell
Get-ChildItem ".\\flutter\\build\\windows\\x64\\runner\\Release"
```

以及：

```powershell
& ".\\flutter\\build\\windows\\x64\\runner\\Release\\rustdesk.exe" --version
```

预期：

- 命令能正常执行。
- 退出码为 `0`。

## 边界说明

以下内容仍属于“本机工具链兼容问题”，不是仓库源码默认承诺：

- Flutter SDK 对 VS2026 的私有兼容补丁。
- `flutter_tools.snapshot` 的手工重建。
- Flutter 对 Ninja target、CMake generator、`CMAKE_BUILD_TYPE` 的上游兼容策略。

如果本机 Flutter 3.24.5 无法识别当前 Visual Studio 版本，需要在你的本机 Flutter SDK 上单独处理，不应把私有 SDK 补丁提交进本仓库。
