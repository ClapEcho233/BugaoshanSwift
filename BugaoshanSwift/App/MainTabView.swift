import SwiftUI

/// 主界面：dock 驱动的 TabView（iOS 26+ 自动液态玻璃 tab bar）。
/// 层级：NavigationStack 为父、TabView 为子——二级页 push 到外层栈，
/// 与 TabView 平级，转场时从 tab bar 上方整体盖过去（无需隐藏修饰）；
/// 若栈在 tab 内则页面永远处于 tab bar 之下。
/// tab 根页面统一隐藏导航栏，标题由页面内容承担（见 body 内注释）；
/// TabView 子视图的导航偏好不会传到外层共享导航栏。
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
            // 根级所有 tab 统一隐藏导航栏：tab 根页面标题由页面内容承担
            //（课表自绘头部，校园/我的内容内大标题），与课表页模式一致。
            // 规避 NavigationStack>TabView 单栈架构下共享导航栏大标题的
            // 滚动跟踪在非课表 tab 间切换不重绑的系统缺陷（第二个访问的
            // tab 大标题钉死不收起；唯一能触发重扫的导航栏隐藏→重现转换
            // 又必产生中间帧闪烁，无法两全）。push 二级页自带标题+返回键，
            // 不受根级隐藏影响。
            .toolbar(.hidden, for: .navigationBar)
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
