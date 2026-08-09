import SwiftUI

@main
struct iosApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum AppTab: Hashable {
    case paint, map, stats
}

struct RootView: View {
    @State private var tab: AppTab = .paint

    var body: some View {
        TabView(selection: $tab) {
            Tab("Paint", systemImage: "paintbrush.pointed.fill", value: .paint) {
                ContentView(isActive: tab == .paint)
            }
            Tab("Map", systemImage: "map.fill", value: .map) {
                SiteView(path: "/")
            }
            Tab("Stats", systemImage: "chart.bar.xaxis", value: .stats) {
                SiteView(path: "/data")
            }
        }
        .tint(Color(red: 1.00, green: 0.84, blue: 0.00))
    }
}
