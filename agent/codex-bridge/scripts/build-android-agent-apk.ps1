param(
    [ValidateSet("arm64-v8a")]
    [string]$Abi = "arm64-v8a",
    [ValidateSet("debug", "release")]
    [string]$Mode = "debug",
    [ValidateSet("flutter", "gradle")]
    [string]$BuildBackend = "gradle",
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$AndroidSdkRoot = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }),
    [string]$AndroidNdkVersion = "28.2.13676358",
    [string]$FlutterBin = $env:FLUTTER_BIN,
    [string]$VsCMakeBin = $env:RUSTDESK_VS_CMAKE_BIN,
    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [string]$VcpkgInstalledRoot = "",
    [string]$RustToolchain = "1.75.0-x86_64-pc-windows-msvc",
    [string]$CargoRegistryProtocol = "git",
    [string]$MsysPerl = "",
    [string]$CargoHome = $env:CARGO_HOME,
    [string]$PubCache = $env:PUB_CACHE,
    [string]$GradleUserHome = $env:GRADLE_USER_HOME,
    [string]$PubHostedUrl = $env:PUB_HOSTED_URL,
    [string]$FlutterStorageBaseUrl = $env:FLUTTER_STORAGE_BASE_URL,
    [string]$HttpProxy = $env:HTTP_PROXY,
    [string]$HttpsProxy = $env:HTTPS_PROXY,
    [string]$AllProxy = $env:ALL_PROXY,
    [string]$ApkSigner = "",
    [switch]$SkipApkVerify
)

$ErrorActionPreference = "Stop"

function Require-Path {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path $Path)) {
        throw "$Message Missing: $Path"
    }
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Body
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

function Resolve-MsysPerl {
    param([string]$PreferredPath)

    if ($PreferredPath) {
        Require-Path $PreferredPath "Configured MSYS perl is not available."
        return (Resolve-Path $PreferredPath).Path
    }

    $msysToolsRoot = Join-Path $env:LOCALAPPDATA "vcpkg\downloads\tools\msys2"
    if (-not (Test-Path $msysToolsRoot)) {
        return $null
    }

    $perl = Get-ChildItem -Path $msysToolsRoot -Recurse -Filter perl.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*\usr\bin\perl.exe" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($null -eq $perl) {
        return $null
    }

    return $perl.FullName
}

function Set-OptionalEnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        Set-Item -Path "Env:$Name" -Value $Value
    }
}

$repo = (Resolve-Path ".").Path
if ([string]::IsNullOrWhiteSpace($VcpkgInstalledRoot)) {
    $VcpkgInstalledRoot = Join-Path $repo ".vcpkg-android-installed"
}
if ([string]::IsNullOrWhiteSpace($FlutterBin)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $FlutterBin = Split-Path -Parent $flutterCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    throw "JAVA_HOME is not configured. Set JAVA_HOME or pass -JavaHome."
}
if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    throw "Android SDK is not configured. Set ANDROID_SDK_ROOT/ANDROID_HOME or pass -AndroidSdkRoot."
}
if ([string]::IsNullOrWhiteSpace($FlutterBin)) {
    throw "Flutter is not configured. Set FLUTTER_BIN, add flutter to PATH, or pass -FlutterBin."
}
if ([string]::IsNullOrWhiteSpace($VsCMakeBin)) {
    throw "Visual Studio CMake is not configured. Set RUSTDESK_VS_CMAKE_BIN or pass -VsCMakeBin."
}
if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    throw "vcpkg is not configured. Set VCPKG_ROOT or pass -VcpkgRoot."
}
$androidNdkHome = Join-Path $AndroidSdkRoot "ndk\$AndroidNdkVersion"
$sdkManager = Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
$javaExe = Join-Path $JavaHome "bin\java.exe"
$flutterExe = Join-Path $FlutterBin "flutter.bat"
$cmakeExe = Join-Path $VsCMakeBin "cmake.exe"
$vcpkgExe = Join-Path $VcpkgRoot "vcpkg.exe"
$gradleWrapper = Join-Path $repo "flutter\android\gradlew.bat"
$msysPerlExe = Resolve-MsysPerl $MsysPerl
if ([string]::IsNullOrWhiteSpace($ApkSigner)) {
    $ApkSigner = Join-Path $AndroidSdkRoot "build-tools\34.0.0\apksigner.bat"
}

Require-Path $javaExe "JDK is not available."
Require-Path $sdkManager "Android command-line tools are not available."
Require-Path (Join-Path $AndroidSdkRoot "platforms\android-34") "Android platform android-34 is not installed."
Require-Path (Join-Path $AndroidSdkRoot "build-tools\34.0.0") "Android build-tools 34.0.0 is not installed."
Require-Path $androidNdkHome "Android NDK is not installed."
Require-Path $flutterExe "Flutter is not available."
Require-Path $cmakeExe "CMake is not available."
Require-Path $vcpkgExe "vcpkg is not available."
Require-Path $gradleWrapper "Gradle wrapper is not available."
Require-Path $msysPerlExe "MSYS perl is not available."

switch ($Abi) {
    "arm64-v8a" {
        $rustTarget = "aarch64-linux-android"
        $vcpkgTarget = "arm64-android"
        $flutterTarget = "android-arm64"
        $ndkLibTarget = "aarch64-linux-android"
        $ndkApi = 21
    }
}

$rustTargetUnderscored = $rustTarget.Replace("-", "_")
$ndkBinDir = Join-Path $androidNdkHome "toolchains\llvm\prebuilt\windows-x86_64\bin"
$ndkSysroot = Join-Path $androidNdkHome "toolchains\llvm\prebuilt\windows-x86_64\sysroot"
$clangExe = Join-Path $ndkBinDir "$rustTarget$ndkApi-clang.cmd"
$clangxxExe = Join-Path $ndkBinDir "$rustTarget$ndkApi-clang++.cmd"
$llvmArExe = Join-Path $ndkBinDir "llvm-ar.exe"
$llvmRanlibExe = Join-Path $ndkBinDir "llvm-ranlib.exe"
$androidTargetDir = Join-Path $repo "target\android-arm64"
$sodiumLibDir = Join-Path $VcpkgInstalledRoot "$vcpkgTarget\lib"
$sodiumIncludeDir = Join-Path $VcpkgInstalledRoot "$vcpkgTarget\include"
$opensslLibDir = $sodiumLibDir
$opensslIncludeDir = $sodiumIncludeDir

Require-Path $clangExe "Android clang is not available."
Require-Path $clangxxExe "Android clang++ is not available."
Require-Path $llvmArExe "Android llvm-ar is not available."
Require-Path $llvmRanlibExe "Android llvm-ranlib is not available."

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdkRoot
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$env:ANDROID_NDK_HOME = $androidNdkHome
$env:ANDROID_NDK_ROOT = $androidNdkHome
$env:CARGO_HOME = $CargoHome
$env:PUB_CACHE = $PubCache
$env:GRADLE_USER_HOME = $GradleUserHome
$env:VCPKG_ROOT = $VcpkgRoot
$env:VCPKG_INSTALLED_ROOT = $VcpkgInstalledRoot
$env:CARGO_TARGET_DIR = $androidTargetDir
$env:RUSTUP_TOOLCHAIN = $RustToolchain
$env:CARGO_REGISTRIES_CRATES_IO_PROTOCOL = $CargoRegistryProtocol
$env:PERL = "perl"
$env:CARGO_NDK_ANDROID_PLATFORM = "$ndkApi"
$env:CARGO_NDK_ANDROID_TARGET = $Abi
$env:CARGO_NDK_CC = $clangExe
$env:CARGO_NDK_CXX = $clangxxExe
$env:CARGO_NDK_AR = $llvmArExe
$env:CARGO_NDK_RANLIB = $llvmRanlibExe
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $clangExe
$env:CC_aarch64_linux_android = $clangExe
$env:CXX_aarch64_linux_android = $clangxxExe
$env:AR_aarch64_linux_android = $llvmArExe
$env:RANLIB_aarch64_linux_android = $llvmRanlibExe
$env:TARGET_CC = $clangExe
$env:TARGET_CXX = $clangxxExe
$env:TARGET_AR = $llvmArExe
$env:TARGET_RANLIB = $llvmRanlibExe
$env:SODIUM_LIB_DIR = $sodiumLibDir
$env:SODIUM_INCLUDE_DIR = $sodiumIncludeDir
$env:OPENSSL_DIR = Join-Path $VcpkgInstalledRoot $vcpkgTarget
$env:OPENSSL_LIB_DIR = $opensslLibDir
$env:OPENSSL_INCLUDE_DIR = $opensslIncludeDir
$env:OPENSSL_STATIC = "1"
$env:OPENSSL_NO_VENDOR = "1"
if ($env:RUSTLS_PLATFORM_VERIFIER_MAVEN_DIR) {
    Require-Path $env:RUSTLS_PLATFORM_VERIFIER_MAVEN_DIR "Configured rustls-platform-verifier Maven directory is not available."
}
Set-OptionalEnvironmentVariable -Name "PUB_HOSTED_URL" -Value $PubHostedUrl
Set-OptionalEnvironmentVariable -Name "FLUTTER_STORAGE_BASE_URL" -Value $FlutterStorageBaseUrl
Set-OptionalEnvironmentVariable -Name "HTTP_PROXY" -Value $HttpProxy
Set-OptionalEnvironmentVariable -Name "HTTPS_PROXY" -Value $HttpsProxy
Set-OptionalEnvironmentVariable -Name "ALL_PROXY" -Value $AllProxy
Set-Item -Path Env:CC_aarch64-linux-android -Value $clangExe
Set-Item -Path Env:CXX_aarch64-linux-android -Value $clangxxExe
Set-Item -Path Env:AR_aarch64-linux-android -Value $llvmArExe
Set-Item -Path Env:RANLIB_aarch64-linux-android -Value $llvmRanlibExe
$bindgenClangArgs = "--target=$rustTarget$ndkApi --sysroot=$($ndkSysroot.Replace('\','/')) -I$($ndkSysroot.Replace('\','/'))/usr/include -I$($ndkSysroot.Replace('\','/'))/usr/include/$rustTarget"
$env:BINDGEN_EXTRA_CLANG_ARGS = $bindgenClangArgs
Set-Item -Path Env:BINDGEN_EXTRA_CLANG_ARGS_aarch64-linux-android -Value $bindgenClangArgs
$env:BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android = $bindgenClangArgs
$env:KCP_SYS_EXTRA_HEADER_PATH = "$($ndkSysroot.Replace('\','/'))/usr/include:$($ndkSysroot.Replace('\','/'))/usr/include/$rustTarget"
Remove-Item Env:SODIUM_SHARED -ErrorAction SilentlyContinue
$msysPerlDir = Split-Path -Parent $msysPerlExe
$env:PATH = "$msysPerlDir;$JavaHome\bin;$VsCMakeBin;$AndroidSdkRoot\cmdline-tools\latest\bin;$AndroidSdkRoot\platform-tools;$androidNdkHome\toolchains\llvm\prebuilt\windows-x86_64\bin;$FlutterBin;$env:USERPROFILE\.cargo\bin;$env:PATH"

Invoke-Step "Verify Android toolchain" {
    & $javaExe -version
    & $flutterExe doctor -v
}

Invoke-Step "Install Rust Android target" {
    rustup target add $rustTarget --toolchain $RustToolchain
}

Invoke-Step "Install Android vcpkg dependencies for $Abi" {
    & $vcpkgExe install --triplet $vcpkgTarget --x-install-root="$VcpkgInstalledRoot"
    $libsodiumArchive = Join-Path $sodiumLibDir "libsodium.a"
    $libsodiumCompatArchive = Join-Path $sodiumLibDir "liblibsodium.a"
    if ((Test-Path $libsodiumArchive) -and -not (Test-Path $libsodiumCompatArchive)) {
        Copy-Item -Path $libsodiumArchive -Destination $libsodiumCompatArchive -Force
    }
    $installedDir = Join-Path $VcpkgInstalledRoot "installed"
    New-Item -ItemType Directory -Force -Path $installedDir | Out-Null
    $installedTargetDir = Join-Path $installedDir $vcpkgTarget
    if (-not (Test-Path $installedTargetDir)) {
        New-Item -ItemType Junction -Path $installedTargetDir -Target (Join-Path $VcpkgInstalledRoot $vcpkgTarget) | Out-Null
    }
}

Invoke-Step "Build librustdesk.so for $Abi" {
    $env:VCPKG_ROOT = $VcpkgInstalledRoot
    cargo build --lib --target $rustTarget --locked --release --features "flutter"
}

$jniLibDir = Join-Path $repo "flutter\android\app\src\main\jniLibs\$Abi"
New-Item -ItemType Directory -Force -Path $jniLibDir | Out-Null

$sourceSo = Join-Path $androidTargetDir "$rustTarget\release\liblibrustdesk.so"
$targetSo = Join-Path $jniLibDir "librustdesk.so"
$cppShared = Join-Path $androidNdkHome "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\$ndkLibTarget\libc++_shared.so"

Require-Path $sourceSo "Rust Android library was not produced."
Require-Path $cppShared "NDK libc++_shared.so is missing."

Copy-Item -Path $sourceSo -Destination $targetSo -Force
Copy-Item -Path $cppShared -Destination (Join-Path $jniLibDir "libc++_shared.so") -Force

$stripExe = Join-Path $androidNdkHome "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe"
if (Test-Path $stripExe) {
    & $stripExe (Join-Path $jniLibDir "librustdesk.so") (Join-Path $jniLibDir "libc++_shared.so")
}

Invoke-Step "Fetch Flutter packages" {
    Push-Location (Join-Path $repo "flutter")
    try {
        & $flutterExe pub get
    } finally {
        Pop-Location
    }
}

Invoke-Step "Build Android $Abi $Mode APK" {
    if ($BuildBackend -eq "gradle") {
        $gradleTask = if ($Mode -eq "release") { "assembleRelease" } else { "assembleDebug" }
        Push-Location (Join-Path $repo "flutter\android")
        try {
            & $gradleWrapper `
                "-Ptarget-platform=$flutterTarget" `
                "-Ptarget=lib/main.dart" `
                "-Pbase-application-name=android.app.Application" `
                "-Pdart-obfuscation=false" `
                "-Ptrack-widget-creation=true" `
                "-Ptree-shake-icons=false" `
                "-Psplit-per-abi=true" `
                $gradleTask
        } finally {
            Pop-Location
        }
    } else {
        Push-Location (Join-Path $repo "flutter")
        try {
            & $flutterExe --no-version-check build apk "--$Mode" --target-platform $flutterTarget --split-per-abi
        } finally {
            Pop-Location
        }
    }
}

$apk = Join-Path $repo "flutter\build\app\outputs\flutter-apk\app-$Abi-$Mode.apk"
if (-not (Test-Path $apk)) {
    $apk = Join-Path $repo "flutter\build\app\outputs\flutter-apk\app-$Mode.apk"
}
Require-Path $apk "APK was not produced."

if (-not $SkipApkVerify) {
    if (Test-Path $ApkSigner) {
        Invoke-Step "Verify APK signature" {
            & $ApkSigner verify --print-certs $apk
        }
    } else {
        Write-Warning "APK signer not found at $ApkSigner; skipping signature verification."
    }
}

Write-Host ""
Write-Host "Android APK ready:"
Write-Host $apk
