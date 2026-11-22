import SwiftUI
import WebKit

/// Renders sanitized HTML from the Mac in a sandboxed WKWebView: JavaScript off, external network
/// requests blocked, and tapped http(s) links handed to the system browser.
struct HTMLMessageView: View {
    private static let minHeight: CGFloat = 40
    private static let maxHeight: CGFloat = 560

    var html: String
    @Environment(\.openURL) private var openURL
    @State private var contentHeight: CGFloat = 40

    var body: some View {
        HTMLWebView(html: html,
                    contentHeight: $contentHeight,
                    scrollable: contentHeight > Self.maxHeight) { url in
            openURL(url)
        }
        .frame(height: min(max(contentHeight, Self.minHeight), Self.maxHeight))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HTMLWebView: UIViewRepresentable {
    var html: String
    @Binding var contentHeight: CGFloat
    var scrollable: Bool
    var openURL: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, openURL: openURL)
    }

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = scrollable
        webView.scrollView.bounces = false
        context.coordinator.load(html, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.openURL = openURL
        if webView.scrollView.isScrollEnabled != scrollable {
            webView.scrollView.isScrollEnabled = scrollable
        }
        if context.coordinator.loadedHTML != html {
            context.coordinator.load(html, in: webView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static var cachedRuleList: WKContentRuleList?
        private static let ruleListJSON = """
        [
          {
            "trigger": { "url-filter": "^https?://" },
            "action": { "type": "block" }
          }
        ]
        """

        @Binding var contentHeight: CGFloat
        var openURL: (URL) -> Void
        var loadedHTML: String?

        init(contentHeight: Binding<CGFloat>, openURL: @escaping (URL) -> Void) {
            _contentHeight = contentHeight
            self.openURL = openURL
        }

        func load(_ html: String, in webView: WKWebView) {
            loadedHTML = html
            let wrapped = Self.wrap(html)
            if let ruleList = Self.cachedRuleList {
                install(ruleList, in: webView)
                webView.loadHTMLString(wrapped, baseURL: nil)
                return
            }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "FUMailBlockExternalNetwork",
                encodedContentRuleList: Self.ruleListJSON
            ) { [weak self, weak webView] ruleList, _ in
                Task { @MainActor in
                    if let ruleList {
                        Self.cachedRuleList = ruleList
                        if let webView {
                            self?.install(ruleList, in: webView)
                        }
                    }
                    guard let webView, self?.loadedHTML == html else { return }
                    webView.loadHTMLString(wrapped, baseURL: nil)
                }
            }
        }

        private func install(_ ruleList: WKContentRuleList, in webView: WKWebView) {
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            controller.add(ruleList)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)") { [weak self] result, _ in
                guard let height = (result as? NSNumber).map({ CGFloat($0.doubleValue) }), height > 0 else { return }
                Task { @MainActor [weak self] in
                    self?.contentHeight = height
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if navigationAction.navigationType == .linkActivated {
                if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    openURL(url)
                }
                decisionHandler(.cancel)
                return
            }
            if url == nil || url?.absoluteString == "about:blank" || url?.scheme?.lowercased() == "data" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private static func wrap(_ body: String) -> String {
            """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
            <meta name="color-scheme" content="light">
            <style>
            html, body {
                margin: 0;
                padding: 0;
                height: auto;
                background: #ffffff;
                color: #111111;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 15px;
                line-height: 1.45;
                overflow-wrap: break-word;
                word-wrap: break-word;
            }
            body { padding: 10px; display: flow-root; }
            img { max-width: 100%; height: auto; }
            pre, code { white-space: pre-wrap; }
            table { max-width: 100%; }
            </style>
            </head>
            <body>\(body)</body>
            </html>
            """
        }
    }
}
