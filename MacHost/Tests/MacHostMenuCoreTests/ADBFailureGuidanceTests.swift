import XCTest
@testable import MacHostMenuCore

final class ADBFailureGuidanceTests: XCTestCase {
    func testAdbTimeoutExplainsUsbRecovery() {
        let message = ADBFailureGuidance.message(
            exitCode: -2,
            output: "Command timed out after 8s: adb devices -l",
            operation: .configureReverse
        )

        XCTAssertTrue(message.contains("ADB 命令超时"))
        XCTAssertTrue(message.contains("重新插拔 USB"))
        XCTAssertTrue(message.contains("adb kill-server"))
    }

    func testInstallUserRestrictedExplainsMIUISettings() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "Failure [INSTALL_FAILED_USER_RESTRICTED]",
            operation: .installReceiver
        )

        XCTAssertTrue(message.contains("手机阻止了 USB 安装"))
        XCTAssertTrue(message.contains("Install via USB"))
        XCTAssertTrue(message.contains("scripts/stage-apk.sh"))
    }

    func testInstallVersionDowngradeSuggestsUninstall() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]",
            operation: .installReceiver
        )

        XCTAssertTrue(message.contains("更高版本"))
        XCTAssertTrue(message.contains("卸载"))
    }

    func testInstallInconsistentCertificatesSuggestsLaunchOrUninstall() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "Failure [INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES]",
            operation: .installReceiver
        )

        XCTAssertTrue(message.contains("签名不一致"))
        XCTAssertTrue(message.contains("Launch Installed Android Receiver"))
        XCTAssertTrue(message.contains("Uninstall Android Receiver"))
        XCTAssertTrue(message.contains("卸载 Android Monitor"))
    }

    func testGenericInstallFailureIncludesOriginalOutput() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "broken pipe",
            operation: .installReceiver
        )

        XCTAssertTrue(message.contains("安装 Android 客户端失败"))
        XCTAssertTrue(message.contains("broken pipe"))
    }

    func testReverseMultipleDevicesTellsUserToChooseDevice() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "error: more than one device/emulator",
            operation: .configureReverse
        )

        XCTAssertTrue(message.contains("多台设备"))
        XCTAssertTrue(message.contains("选择目标手机"))
    }

    func testReverseOfflineExplainsAuthorizationRecovery() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "device offline",
            operation: .configureReverse
        )

        XCTAssertTrue(message.contains("offline"))
        XCTAssertTrue(message.contains("重新插拔 USB"))
    }

    func testGenericReverseFailureWarnsAboutAndroid5ReverseList() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "protocol fault",
            operation: .configureReverse
        )

        XCTAssertTrue(message.contains("USB 通道配置失败"))
        XCTAssertTrue(message.contains("Android 5"))
        XCTAssertTrue(message.contains("protocol fault"))
    }

    func testLaunchMissingActivitySuggestsInstall() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "Error type 3\nActivity class does not exist.",
            operation: .launchReceiver
        )

        XCTAssertTrue(message.contains("没有安装"))
        XCTAssertTrue(message.contains("安装/更新手机客户端"))
    }

    func testGenericLaunchFailureIncludesOutput() {
        let message = ADBFailureGuidance.message(
            exitCode: 1,
            output: "permission denied",
            operation: .launchReceiver
        )

        XCTAssertTrue(message.contains("启动 Android Monitor 手机端失败"))
        XCTAssertTrue(message.contains("permission denied"))
    }

    func testDisplayAuditStaleDisplayExplainsLogoutOrRestart() {
        let message = ADBFailureGuidance.message(
            exitCode: 11,
            output: "[WARN] Found 1 stale Android Monitor virtual display(s).",
            operation: .displayAudit
        )

        XCTAssertTrue(message.contains("残留的虚拟显示器"))
        XCTAssertTrue(message.contains("注销或重启 macOS"))
    }

    func testGenericDisplayAuditFailureIncludesOutput() {
        let message = ADBFailureGuidance.message(
            exitCode: 2,
            output: "",
            operation: .displayAudit
        )

        XCTAssertTrue(message.contains("扩展屏启动前检查失败"))
        XCTAssertTrue(message.contains("无命令输出"))
    }
}
