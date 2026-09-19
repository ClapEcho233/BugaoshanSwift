import Foundation
import WidgetKit

/// 小组件刷新联动（对应 lib/services/widget_update_service.dart）：
/// 课程/课表数据变化后刷新全部时间线。偏好键与 Flutter 版一致
/// （widget_show_tomorrow / widget_color_style / widget_density，枚举存序号 int）。
enum WidgetUpdateService {

    static let showTomorrowKey = "widget_show_tomorrow"
    static let colorStyleKey = "widget_color_style"
    static let densityKey = "widget_density"

    static func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 三项偏好写入 App Group（小组件侧读取）
    static func updatePreferences(showTomorrow: Bool? = nil, colorStyle: Int? = nil, density: Int? = nil) {
        guard let defaults = UserDefaults(suiteName: Constants.appGroupId) else { return }
        if let showTomorrow {
            defaults.set(showTomorrow, forKey: showTomorrowKey)
        }
        if let colorStyle {
            defaults.set(colorStyle, forKey: colorStyleKey)
        }
        if let density {
            defaults.set(density, forKey: densityKey)
        }
        reloadTimelines()
    }
}
