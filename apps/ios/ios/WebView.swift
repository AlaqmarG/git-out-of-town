import SwiftUI
import WebKit

/// A page of the live site, rendered in-app. The web map and /data dashboard
/// are the canonical views — embedding them keeps all three surfaces in sync.
struct SiteView: View {
    let path: String
    @State private var model: WebViewModel

    init(path: String) {
        self.path = path
        _model = State(initialValue: WebViewModel(url: APIClient.baseURL.appendingPathComponent(path == "/" ? "" : path)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            WebViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)
                .opacity(model.isLoading || model.failed ? 0 : 1)
                .animation(.easeOut(duration: 0.35), value: model.isLoading)

            if model.failed {
                ContentUnavailableView {
                    Label("Can't reach the wall", systemImage: "wifi.slash")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Retry") { model.load() }
                        .buttonStyle(.borderedProminent)
                }
            } else if model.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let model: WebViewModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

@Observable
final class WebViewModel: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var isLoading = true
    var failed = false
    private let url: URL

    init(url: URL) {
        self.url = url
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        load()
    }

    func load() {
        failed = false
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        failed = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        failed = true
    }
}
