import SwiftUI
import WebKit
import WidgetKit

/// Command Center: your server's Command Center as a full-screen iPhone app.
/// The server address is not built into the app: it is set once from the server's /iphone page (commandcenter://set?url=...)
/// or typed on first launch, so the code and the app file contain nothing private.
@main
struct CommandCenterApp: App {
    @AppStorage("serverURL") private var serverURL: String = ""

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    // commandcenter://office (from the home-screen widget): show the Bot Office
                    if url.host == "office" {
                        NotificationCenter.default.post(name: .openServerPath, object: "/office")
                        return
                    }
                    // commandcenter://set?url=https://your-server/
                    guard url.host == "set",
                          let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
                          let server = URL(string: value), server.scheme == "https" else { return }
                    if server.absoluteString != serverURL { WidgetShared.forget() }
                    serverURL = server.absoluteString
                }
        }
    }
}

extension Notification.Name {
    static let openServerPath = Notification.Name("openServerPath")
}

struct RootView: View {
    @AppStorage("serverURL") private var serverURL: String = ""
    @State private var draft = "https://"

    var body: some View {
        if let url = URL(string: serverURL), !serverURL.isEmpty {
            WebView(url: url, onChangeServer: { serverURL = ""; WidgetShared.forget() })
                .ignoresSafeArea(.container, edges: .bottom)
                .background(Color(red: 0.043, green: 0.063, blue: 0.125))
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Command Center").font(.largeTitle.bold())
                Text("Open the /iphone page on your server and tap \"Connect this app\", or type your server's address. Tailscale must be on.")
                    .foregroundStyle(.secondary)
                TextField("https://", text: $draft)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Connect") {
                    let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let u = URL(string: v), u.scheme == "https" { WidgetShared.forget(); serverURL = u.absoluteString }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(24)
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let onChangeServer: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                 // keeps you signed in between launches
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "app")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.043, green: 0.063, blue: 0.125, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        context.coordinator.web = web
        context.coordinator.observePaths()
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: WebView
        weak var web: WKWebView?

        init(_ parent: WebView) { self.parent = parent }

        func observePaths() {
            NotificationCenter.default.addObserver(forName: .openServerPath, object: nil, queue: .main) { [weak self] note in
                guard let self, let path = note.object as? String,
                      let target = URL(string: path, relativeTo: self.parent.url) else { return }
                self.web?.load(URLRequest(url: target))
            }
        }

        // After a page loads while signed in, hand the widget the server address and its read-only key.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host == parent.url.host else { return }
            let server = parent.url
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let host = server.host?.lowercased() ?? ""
                let mine = cookies.filter { c in
                    let domain = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return host == domain || host.hasSuffix("." + domain)
                }
                guard !mine.isEmpty else { return }
                var req = URLRequest(url: server.appendingPathComponent("api/widget/key"))
                req.setValue(mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
                URLSession.shared.dataTask(with: req) { data, resp, _ in
                    guard (resp as? HTTPURLResponse)?.statusCode == 200, let data,
                          let key = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["key"] as? String else { return }
                    if WidgetShared.widgetKey != key || WidgetShared.serverURL != server {
                        WidgetShared.widgetKey = key
                        WidgetShared.serverURL = server
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }.resume()
            }
        }

        @objc func reload(_ sender: UIRefreshControl) {
            if web?.url == nil || web?.url?.scheme == "about" { web?.load(URLRequest(url: parent.url)) } else { web?.reload() }
            sender.endRefreshing()
        }

        // Links to other websites open in Safari; your server stays in the app.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let target = action.request.url, let host = target.host, host != parent.url.host, action.navigationType == .linkActivated {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // target=_blank links: open in the same view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil { webView.load(action.request) }
            return nil
        }

        // Camera and microphone (Ellie's voice) only for your own server.
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == parent.url.host ? .grant : .deny)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            present(UIAlertController(title: nil, message: message, preferredStyle: .alert), actions: [UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }])
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            present(UIAlertController(title: nil, message: message, preferredStyle: .alert),
                    actions: [UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) },
                              UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) }])
        }

        private func present(_ alert: UIAlertController, actions: [UIAlertAction]) {
            actions.forEach { alert.addAction($0) }
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            scene?.windows.first?.rootViewController?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showOffline(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showOffline(error) }

        private func showOffline(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            let html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{background:#0b1020;color:#e8ecff;font:17px -apple-system;padding:32px 24px}button{font:600 16px -apple-system;padding:12px 18px;border-radius:12px;border:0;margin:8px 8px 0 0}
            .a{background:#d6f36a;color:#0b1020}.b{background:#26305f;color:#e8ecff}p{color:#9aa3c7}</style></head><body>
            <h2>Can't reach your server</h2><p>Check that Tailscale is on, then try again.</p><p style="font-size:13px">\(error.localizedDescription)</p>
            <button class="a" onclick="location.href='\(parent.url.absoluteString)'">Try again</button>
            <button class="b" onclick="webkit.messageHandlers.app.postMessage('change-server')">Change server</button></body></html>
            """
            web?.loadHTMLString(html, baseURL: nil)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.body as? String == "change-server" { DispatchQueue.main.async { self.parent.onChangeServer() } }
        }
    }
}
