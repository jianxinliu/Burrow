//
//  LocalizationTests.swift
//  BurrowTests
//

import XCTest
@testable import Burrow

final class LocalizationTests: XCTestCase {
    func testTaskReportTextLocalizesOptimizeOutput() throws {
        let bundle = try zhHansBundle()
        XCTAssertEqual(TaskReportText.title("Periodic Maintenance", bundle: bundle), "定期维护")
        XCTAssertEqual(TaskReportText.title("Disk Health", bundle: bundle), "磁盘健康")
        XCTAssertEqual(TaskReportText.item("User directory permissions already optimal", bundle: bundle), "用户目录权限已是最佳状态")
        XCTAssertEqual(TaskReportText.item("Periodic maintenance skipped (not available on this macOS version)", bundle: bundle), "已跳过定期维护（此 macOS 版本不可用）")
        XCTAssertEqual(TaskReportText.item("Disk verify skipped (set MOLE_ENABLE_DISK_VERIFY=1 to enable)", bundle: bundle), "已跳过磁盘验证（设置 MOLE_ENABLE_DISK_VERIFY=1 可启用）")
        XCTAssertEqual(TaskReportText.item("Login items all healthy (3 checked)", bundle: bundle), "登录项均正常（已检查 3 项）")
        XCTAssertEqual(TaskReportText.item("Wallpaper agent cache, 33.0MB dry", bundle: bundle), "壁纸代理缓存，33.0MB 可清理")
    }

    func testSimplifiedChineseStringsCoverCoreInterface() throws {
        let strings = try zhHansStrings()
        let requiredKeys = [
            "Clean",
            "Software",
            "Optimize",
            "Analyze",
            "Status",
            "Settings",
            "History",
            "Open Burrow",
            "Clean Now",
            "Preview",
            "Uninstall",
            "Updates",
            "Search apps",
            "Everything's up to date",
            "Update all",
            "Run maintenance now",
            "Maintenance complete.",
            "Periodic Maintenance",
            "User directory permissions already optimal",
        ]

        for key in requiredKeys {
            let value = try XCTUnwrap(strings[key], "missing zh-Hans translation for \(key)")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNotEqual(value, key)
        }
    }

    private func zhHansStrings() throws -> [String: String] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = sourceRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("zh-Hans.lproj")
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private func zhHansBundle() throws -> Bundle {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = sourceRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("zh-Hans.lproj")
        return try XCTUnwrap(Bundle(url: url))
    }
}
