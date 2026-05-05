# Android Monitor

把一台 Android 手机当作 macOS 的扩展显示器使用。Mac 端创建虚拟显示器，手机端通过 USB 接收 H.264 画面并显示。

这是本地自用工具，不面向 App Store 分发。

## 普通使用

目标流程是：双击 Mac app，选择手机，点击开始。Android 客户端会自动检测，没装就自动安装。

1. 先打包一次应用：

```sh
scripts/package-mac-host-app.sh
```

生成的应用在：

```text
MacHost/build/Android Monitor Host.app
```

2. 用 USB 连接 Android 手机，打开手机上的“开发者选项”和“USB 调试”。

3. 双击 `MacHost/build/Android Monitor Host.app`。

4. 如果手机弹出 USB 调试授权，点允许。建议勾选“一律允许使用这台电脑进行调试”。

5. 在 Android Monitor 窗口里选择投屏设备，然后点“开始扩展屏”。

6. 如果 macOS 提示屏幕录制权限，点“授权屏幕录制”，在系统设置里允许 `Android Monitor Host` 或 `phase0-spike`，然后回到 Android Monitor 窗口点击“重启应用”，重启后再点“开始扩展屏”。

正常情况下不需要手动安装 Android APK。点击“开始扩展屏”时，Mac app 会自动检查手机上是否安装 `com.androidmonitor.receiver`，没有就安装内置的 `android-receiver-debug.apk`，然后自动启动手机端。

## 使用条件

- macOS 14 或更新版本。
- Android Studio 或 Android SDK platform-tools。`adb` 需要可用；应用会自动查找常见路径，包括 `~/Library/Android/sdk/platform-tools/adb`。
- 一台开启 USB 调试的 Android 手机，当前目标设备是 Android 5 / API 21 及以上。
- 扩展屏需要 macOS 屏幕录制权限。
- 触摸输入需要 macOS 辅助功能权限。

## 窗口按钮

- “开始扩展屏”：创建 Mac 虚拟显示器，并把画面传到手机。
- “安装/更新手机客户端”：手动把内置 Android 客户端安装到当前手机。普通使用通常不用点。
- “打开状态面板”：不创建虚拟显示器，只在手机上显示 Mac 状态信息。
- “刷新设备”：重新检测 USB 手机。
- “画质/延迟设置”：调整分辨率、FPS、码率。旧手机建议从 `1024x600 @ 30 FPS Low Latency` 开始，不流畅再降到 `1024x600 @ 15 FPS`。
- “授权屏幕录制”：触发 macOS 屏幕录制授权。
- “重启应用”：授权屏幕录制后使用。应用不会出现在 Dock 里，所以不需要去 Dock 找它。
- “退出应用”：关闭菜单栏后台进程。

这个应用是菜单栏应用，不显示在 Dock。也可以从屏幕顶部菜单栏的 `AM` 菜单里退出。

## 为什么有时还会要求授权

macOS 的屏幕录制权限是按“实际采集屏幕的程序”记录的。本项目里真正采集屏幕的是 app 内部的 `phase0-spike` 后端，不只是外层菜单栏应用。

普通使用时，打包后固定使用同一个 `.app`，授权一次就应该持续有效。不要在每次使用前都重新运行打包脚本。

如果你开发时频繁运行 `scripts/package-mac-host-app.sh`，`phase0-spike` 二进制会被重新生成；在没有稳定代码签名的本地构建里，macOS 可能把它当成新的程序，所以会要求重新授权一次。

如果你经常重新打包，并且本机有固定的代码签名身份，可以这样打包，减少重复授权：

```sh
ANDROID_MONITOR_CODE_SIGN_IDENTITY="你的签名身份名称" scripts/package-mac-host-app.sh
```

可用签名身份可以用下面命令查看：

```sh
security find-identity -v -p codesigning
```

## 触摸输入

Android 端触摸默认关闭。长按手机上的 Extended Display 画面可以切换触摸输入。

- 单指点击：Mac 左键点击。
- 单指拖拽：Mac 左键拖拽。
- 两指滑动：Mac 滚轮滚动。

如果触摸不生效，在菜单栏里点击 `Request Accessibility Permission`，或到系统设置里给 Android Monitor Host 辅助功能权限。

## 日志和排障

串流日志：

```text
/tmp/android-monitor-menubar.log
```

状态面板日志：

```text
/tmp/android-monitor-status-panel.log
```

检查是否残留 Android Monitor 虚拟显示器：

```sh
scripts/display-audit.sh
scripts/display-audit.sh --count
```

检查手机、安装状态和解码能力：

```sh
scripts/device-audit.sh
```

如果需要手动安装 Android 客户端：

```sh
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :android-receiver:assembleDebug
adb install -r -d AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk
```

## 开发命令

Mac 端构建：

```sh
cd MacHost
swift build
```

Android 单元测试：

```sh
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :android-receiver:testDebugUnitTest
```

运行一个短的真实采集串流测试：

```sh
scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 30 --bitrate-mbps 3 --duration 20 --test-content-window --require-real-capture --min-decoded-frames 300 --min-input-fps 20
```

## 进一步文档

- 详细搭建和脚本说明：[docs/setup.md](docs/setup.md)
- 协议说明：[docs/protocol.md](docs/protocol.md)
- 完成度审计：[docs/completion-audit.md](docs/completion-audit.md)
