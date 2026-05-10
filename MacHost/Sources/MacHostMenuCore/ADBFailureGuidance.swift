import Foundation

public enum ADBFailureOperation {
    case installReceiver
    case configureReverse
    case launchReceiver
    case displayAudit
}

public enum ADBFailureGuidance {
    public static func message(exitCode: Int32, output: String, operation: ADBFailureOperation) -> String {
        let details = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "无命令输出。"
            : output.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.localizedCaseInsensitiveContains("timed out") {
            return """
            ADB 命令超时。

            请重新插拔 USB，解锁手机，确认 USB 调试授权弹窗已允许。必要时运行 adb kill-server 后重试。

            原始错误：
            \(details)
            """
        }

        switch operation {
        case .installReceiver:
            return installMessage(output: output, details: details)
        case .configureReverse:
            return reverseMessage(output: output, details: details)
        case .launchReceiver:
            return launchMessage(output: output, details: details)
        case .displayAudit:
            return displayAuditMessage(exitCode: exitCode, output: output, details: details)
        }
    }

    private static func installMessage(output: String, details: String) -> String {
        if output.contains("INSTALL_FAILED_USER_RESTRICTED") {
            return """
            手机阻止了 USB 安装。

            请在手机上打开开发者选项，并确认：
            1. USB 调试已开启。
            2. Install via USB / 通过 USB 安装 已开启。
            3. 如果是 MIUI，开启 USB debugging (Security settings) / USB 调试（安全设置）。

            也可以运行 scripts/stage-apk.sh，把 APK 推到手机 Downloads 后手动安装。

            原始错误：
            \(details)
            """
        }
        if output.contains("INSTALL_FAILED_VERSION_DOWNGRADE") {
            return """
            手机上已有更高版本的 Android Monitor。

            请先卸载手机上的 Android Monitor，或继续使用当前版本。

            原始错误：
            \(details)
            """
        }
        if output.contains("INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES") {
            return """
            手机上已安装的 Android Monitor 和当前 APK 签名不一致。

            如果只是想启动现有手机端，请使用 Android Studio 的 Launch Installed Android Receiver，或在 Mac 菜单中直接启动已安装客户端。
            如果要安装当前构建，请先运行 Android Studio 的 Uninstall Android Receiver，或在手机上卸载 Android Monitor，再重新安装。不要在 USB 安装仍被系统阻止时先卸载现有可用版本。

            原始错误：
            \(details)
            """
        }
        return "安装 Android 客户端失败。\n\n原始错误：\n\(details)"
    }

    private static func reverseMessage(output: String, details: String) -> String {
        if output.contains("more than one device") {
            return """
            ADB 检测到多台设备，但没有明确目标设备。

            请在 Android Monitor 设置窗口的“投屏设备”下拉框中选择目标手机，然后重试。

            原始错误：
            \(details)
            """
        }
        if output.localizedCaseInsensitiveContains("device offline") {
            return """
            手机处于 offline 状态。

            请解锁手机，重新插拔 USB，并在手机上允许 USB 调试。必要时运行 adb kill-server 后重试。

            原始错误：
            \(details)
            """
        }
        return """
        USB 通道配置失败。

        请确认手机仍通过 USB 连接且 ADB 状态是 device。旧 Android 5/MIUI 设备上不要依赖 adb reverse --list；本程序只做必要的 reverse 配置。

        原始错误：
        \(details)
        """
    }

    private static func launchMessage(output: String, details: String) -> String {
        if output.contains("Error type 3") || output.localizedCaseInsensitiveContains("does not exist") {
            return """
            手机端 Android Monitor 没有安装或包名不匹配。

            请先点击“安装/更新手机客户端”，或运行 scripts/install-android-receiver.sh。

            原始错误：
            \(details)
            """
        }
        return "启动 Android Monitor 手机端失败。\n\n原始错误：\n\(details)"
    }

    private static func displayAuditMessage(exitCode: Int32, output: String, details: String) -> String {
        if exitCode == 11 || output.contains("stale Android Monitor") {
            return """
            检测到上一次运行残留的虚拟显示器。

            请先注销或重启 macOS，再重新打开 Android Monitor Host。残留虚拟屏会导致开始扩展屏失败或捕获到旧画面。

            检查输出：
            \(details)
            """
        }
        return "扩展屏启动前检查失败。\n\n检查输出：\n\(details)"
    }
}
