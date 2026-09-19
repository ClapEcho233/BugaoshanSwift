import Foundation
import Combine
import SwiftUI

/// 应用配置（对应 lib/providers/app_config_provider.dart 的核心子集）。
/// 全部自动持久化到 UserDefaults；后续阶段补齐 ~40 项设置的其余部分。
@MainActor
final class AppConfig: ObservableObject {

    static let currentEulaVersion = 1
    static let defaultVisibleDockIds = ["course", "campus", "profile"]

    private let defaults: UserDefaults

    // MARK: 启动门

    @Published var acceptedEulaVersion: Int {
        didSet { defaults.set(acceptedEulaVersion, forKey: "accepted_eula_version") }
    }

    @Published var firstLaunchWizardCompleted: Bool {
        didSet { defaults.set(firstLaunchWizardCompleted, forKey: "first_launch_wizard_completed") }
    }

    // MARK: Dock

    /// 可见 dock 项（顺序即渲染顺序）
    @Published var visibleDockIds: [String] {
        didSet { defaults.set(visibleDockIds, forKey: "visible_dock_ids") }
    }

    // MARK: 课表展示

    @Published var showWeekend: Bool {
        didSet { defaults.set(showWeekend, forKey: "course_show_weekend") }
    }

    /// 行高 48–120，默认 72
    @Published var courseRowHeight: Double {
        didSet { defaults.set(courseRowHeight, forKey: "course_row_height") }
    }

    @Published var enablePageTransitionAnimation: Bool {
        didSet { defaults.set(enablePageTransitionAnimation, forKey: "enable_page_transition_animation") }
    }

    // MARK: 外观

    /// 主题强调色（ARGB；0 = 跟随系统默认）
    @Published var themeColorARGB: Int {
        didSet { defaults.set(themeColorARGB, forKey: "theme_color_argb") }
    }

    /// 字体大小偏好："" = 跟随系统 / "small" / "large"
    @Published var fontScale: String {
        didSet { defaults.set(fontScale, forKey: "font_scale") }
    }

    // MARK: 更新

    /// 检查更新时包含预发布版
    @Published var includePrerelease: Bool {
        didSet { defaults.set(includePrerelease, forKey: "include_prerelease") }
    }

    /// 开发者模式（关于页版本号连点 5 次开启）
    @Published var developerModeEnabled: Bool {
        didSet { defaults.set(developerModeEnabled, forKey: "developer_mode_enabled") }
    }

    var themeColor: Color? {
        guard themeColorARGB != 0 else { return nil }
        return themeColorARGB.argbColor
    }

    var dynamicTypeSize: DynamicTypeSize? {
        switch fontScale {
        case "small": return .small
        case "large": return .xLarge
        default: return nil
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        acceptedEulaVersion = defaults.object(forKey: "accepted_eula_version") as? Int ?? 0
        firstLaunchWizardCompleted = defaults.bool(forKey: "first_launch_wizard_completed")
        visibleDockIds = defaults.stringArray(forKey: "visible_dock_ids") ?? Self.defaultVisibleDockIds
        showWeekend = defaults.object(forKey: "course_show_weekend") as? Bool ?? false
        courseRowHeight = defaults.object(forKey: "course_row_height") as? Double ?? 72
        enablePageTransitionAnimation = defaults.object(forKey: "enable_page_transition_animation") as? Bool ?? true
        themeColorARGB = defaults.object(forKey: "theme_color_argb") as? Int ?? 0
        fontScale = defaults.string(forKey: "font_scale") ?? ""
        includePrerelease = defaults.bool(forKey: "include_prerelease")
        developerModeEnabled = defaults.bool(forKey: "developer_mode_enabled")
    }

    func resetDockToDefault() {
        visibleDockIds = Self.defaultVisibleDockIds
    }
}

// MARK: - Dock 项注册表（对应 campus_item_config.dart）

struct DockItem {
    let id: String
    let label: String
    let icon: String   // SF Symbol
    let accent: Int    // ARGB
}

enum DockRegistry {

    static let all: [DockItem] = [
        DockItem(id: "course", label: "课表", icon: "book", accent: 0xFF5B8DEF),
        DockItem(id: "campus", label: "校园", icon: "graduationcap", accent: 0xFF5B8DEF),
        DockItem(id: "profile", label: "我的", icon: "person.crop.circle", accent: 0xFF5B8DEF),
        DockItem(id: "grades", label: "成绩", icon: "chart.bar", accent: 0xFF5B8DEF),
        DockItem(id: "ccyl", label: "第二课堂", icon: "calendar.badge.plus", accent: 0xFF8B7CF6),
        DockItem(id: "plan_completion", label: "计划完成度", icon: "checkmark.circle", accent: 0xFF3FA796),
        DockItem(id: "fitness_test", label: "体测", icon: "figure.run", accent: 0xFFF27059),
        DockItem(id: "exam_plan", label: "考表", icon: "doc.text", accent: 0xFFE86A92),
        DockItem(id: "network_device", label: "校园网设备", icon: "wifi.router", accent: 0xFF5AB8A8),
        DockItem(id: "passpoint", label: "无感认证", icon: "wifi.router.fill", accent: 0xFF5AB8A8),
        DockItem(id: "balance_query", label: "电费查询", icon: "yensign.circle", accent: 0xFFE8A33D),
        DockItem(id: "repair", label: "宿舍报修", icon: "wrench.and.screwdriver", accent: 0xFF6C8CD5),
        DockItem(id: "academic_calendar", label: "校历", icon: "calendar.circle", accent: 0xFFD97757),
        DockItem(id: "zysc", label: "志愿四川", icon: "heart.circle", accent: 0xFF9A7FD1),
        DockItem(id: "leave", label: "办事大厅", icon: "checklist", accent: 0xFF6488C4),
        DockItem(id: "notice", label: "通知", icon: "megaphone", accent: 0xFFE05D5D),
        DockItem(id: "downloaded_attachments", label: "下载中心", icon: "folder", accent: 0xFF8F9BA8),
    ]

    /// 校园页三节分组（顺序即展示顺序）
    static let campusSections: [(title: String, ids: [String])] = [
        ("学业", ["grades", "ccyl", "plan_completion", "fitness_test", "exam_plan"]),
        ("实用工具", ["network_device", "passpoint", "balance_query", "repair",
                      "academic_calendar", "zysc", "leave"]),
        ("通知", ["notice", "downloaded_attachments"]),
    ]

    static func item(id: String) -> DockItem? {
        all.first { $0.id == id }
    }
}
