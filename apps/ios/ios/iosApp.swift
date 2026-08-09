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
    case map, paint, stats
}

struct RootView: View {
    @State private var tab: AppTab = .map
    @State private var showTutorial = false
    @AppStorage("got.sawTutorial") private var sawTutorial = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Around You", systemImage: "map.fill", value: .map) {
                MapTabView(tab: $tab) { showTutorial = true }
            }
            Tab("Paint", systemImage: "paintbrush.pointed.fill", value: .paint) {
                ContentView(isActive: tab == .paint) { showTutorial = true }
            }
            Tab("Stats", systemImage: "chart.bar.xaxis", value: .stats) {
                SiteView(path: "/data")
            }
        }
        .tint(Color(red: 1.00, green: 0.84, blue: 0.00))
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView {
                sawTutorial = true
                showTutorial = false
            }
        }
        .onAppear {
            LocationService.shared.start()
            if !sawTutorial { showTutorial = true }
        }
    }
}
