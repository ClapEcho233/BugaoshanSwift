import SwiftUI

/// 主界面：dock 驱动的 TabView（iOS 26+ 自动液态玻璃 tab bar）。
/// visibleDockIds 决定 tab 内容与顺序；少于 2 项时不显示 tab bar。
struct MainTabView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authBus: AuthBus

    @State private var selection: String = "course"

    var body: some View {
        let visibleIds = visibleTabIds
        TabView(selection: $selection) {
            ForEach(visibleIds, id: \.self) { id in
                NavigationStack {
                    tabContent(for: id)
                }
                .tabItem {
                    let item = DockRegistry.item(id: id)
                    Label(item?.label ?? id, systemImage: item?.icon ?? "circle")
                }
                .tag(id)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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
