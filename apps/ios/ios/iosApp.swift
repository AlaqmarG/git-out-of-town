import AVFoundation
import CoreLocation
import SwiftUI

@main
struct iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The capture pose, the paint canvas and the projection back onto the wall are
/// all computed in portrait (`projectionMatrix(for: .portrait…)`), and the paint
/// canvas is frozen at the viewport size it was shot in. A rotation mid-flow
/// would silently misplace the art, so the app never leaves portrait.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

enum AppTab: Hashable {
    case map, paint, stats
}

/// What the AR tab is for right now. Looking at other people's work and making
/// your own want opposite chrome, so they are separate modes rather than one
/// screen carrying both.
enum ARMode {
    case view, paint
}

extension Color {
    /// The one brand colour. Every accent in the app is this.
    static let spray = Color(red: 1.00, green: 0.84, blue: 0.00)
    /// The web map's `palette.ink` and `palette.raised` — the backdrop a piece
    /// is presented against, so the two clients read as one product.
    static let ink = Color(red: 0.039, green: 0.043, blue: 0.059)
    static let raised = Color(red: 0.110, green: 0.122, blue: 0.157)
}

/// Camera and location authorisation, observable so a denial produces an
/// explanation and a way back instead of a dead black screen.
@MainActor
@Observable
final class Permissions: NSObject, CLLocationManagerDelegate {
    static let shared = Permissions()

    private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var location: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        location = manager.authorizationStatus
        // Toggling a switch in Settings is the only way these change without us
        // asking, and it always sends us through the background first.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.camera = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    var locationDenied: Bool { location == .denied || location == .restricted }

    func requestCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        camera = AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.location = status }
    }
}

/// Replaces a screen that cannot do its job, and says how to fix it.
struct BlockerView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.spray)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: 260)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.spray)
                .foregroundStyle(.black)
            }
        }
        .padding(28)
        .frame(maxWidth: 360)
    }
}

struct RootView: View {
    @State private var tab: AppTab = .map
    @State private var arMode: ARMode = .paint
    @State private var showTutorial = false
    @AppStorage("got.sawTutorial") private var sawTutorial = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Around You", systemImage: "map.fill", value: .map) {
                MapTabView(tab: $tab, arMode: $arMode) { showTutorial = true }
            }
            Tab("Paint", systemImage: "paintbrush.pointed.fill", value: .paint) {
                ContentView(isActive: tab == .paint, tab: $tab, mode: $arMode) { showTutorial = true }
            }
            Tab("Stats", systemImage: "chart.bar.xaxis", value: .stats) {
                SiteView(path: "/data")
            }
        }
        .tint(Color.spray)
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView {
                sawTutorial = true
                showTutorial = false
                // Only ask once the tutorial has said why: a location prompt
                // thrown at a stranger on page one just gets denied.
                LocationService.shared.start()
            }
        }
        .onAppear {
            if sawTutorial { LocationService.shared.start() } else { showTutorial = true }
        }
    }
}
