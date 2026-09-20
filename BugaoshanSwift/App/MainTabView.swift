import SwiftUI

/// 主界面：dock 驱动的 TabView（iOS 26+ 自动液态玻璃 tab bar）。
/// 层级：NavigationStack 为父、TabView 为子——二级页 push 到外层栈，
/// 与 TabView 平级，转场时从 tab bar 上方整体盖过去（无需隐藏修饰）；
/// 若栈在 tab 内则页面永远处于 tab bar 之下。
/// tab 根页面的导航栏要素（标题/显示模式/搜索栏）由外层按选中 tab 驱动，
/// 因为 TabView 子视图的导航偏好不会传到外层共享导航栏。
/// visibleDockIds 决定 tab 内容与顺序；少于 2 项时不显示 tab bar。
struct MainTabView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authBus: AuthBus

    @State private var selection: String = "course"

    var body: some View {
        let visibleIds = visibleTabIds
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(visibleIds, id: \.self) { id in
                    tabContent(for: id)
                        .tabItem {
                            let item = DockRegistry.item(id: id)
                            Label(item?.label ?? id, systemImage: item?.icon ?? "circle")
                        }
                        .tag(id)
                }
            }
            .navigationTitle(DockRegistry.item(id: selection)?.label ?? selection)
            .navigationBarTitleDisplayMode(.large)
            // 恒定修饰符结构 + 值切换：分支切换会导致 TabView 子树整体重建，
            // 引发 tab 荶丸滑动动画截断与课表页重载闪烁
            .toolbar(selection == "course" ? .hidden : .visible, for: .navigationBar)
        }
    }

    private var visibleTabIds: [String] {
        let ids = config.visibleDockIds
        return ids.count >= 2 ? ids : (ids.first.map { [$0] } ?? ["course"])
    }

    @ViewBuilder
    private func tabContent(for id: String) -> some View {
        switch id {
        case "course":
            CoursePage()
        case "campus":
            CampusPage()
        case "profile":
            ProfilePage()
        default:
            PlaceholderFeaturePage(dockId: id)
        }
    }
}

/// 未实现功能的占位页（后续阶段逐个替换为真实现）
struct PlaceholderFeaturePage: View {
    let dockId: String

    var body: some View {
        ContentUnavailableView {
            Label(DockRegistry.item(id: dockId)?.label ?? dockId, systemImage: DockRegistry.item(id: dockId)?.icon ?? "circle")
        } description: {
            Text("该功能将在后续版本中提供")
        }
        .navigationTitle(DockRegistry.item(id: dockId)?.label ?? dockId)
        .navigationBarTitleDisplayMode(.inline)
    }
}
