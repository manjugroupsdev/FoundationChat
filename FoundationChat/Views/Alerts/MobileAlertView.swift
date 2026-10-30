import SwiftUI
import UIKit
import WebKit

/// Full-screen mandatory alert. It can't be swiped away, and Close stays
/// disabled until the alert has been on screen for `minViewSeconds`.
struct MobileAlertView: View {
    let alert: MobileAlert
    /// Bearer token for the `/api/storage/files/...` image.
    let token: String?
    let onClose: () -> Void

    @State private var secondsLeft: Int
    @State private var bodyHeight: CGFloat = 1
    @State private var didClose = false

    init(alert: MobileAlert, token: String?, onClose: @escaping () -> Void) {
        self.alert = alert
        self.token = token
        self.onClose = onClose
        _secondsLeft = State(initialValue: alert.minViewSeconds)
    }

    private var canClose: Bool { secondsLeft <= 0 && !didClose }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    alertPill

                    Text(alert.title)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    if let sentAt = alert.sentAt {
                        Text(sentAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.appSecondaryText)
                            .padding(.top, 6)
                    }

                    if let imageURL {
                        MobileAlertImage(url: imageURL, token: token)
                    }

                    if alert.bodyHtml.nonBlank != nil {
                        MobileAlertHTMLView(html: alert.bodyHtml, contentHeight: $bodyHeight)
                            .frame(height: max(bodyHeight, 1))
                            .padding(.top, 18)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            Divider()

            Button {
                guard canClose else { return }
                didClose = true
                onClose()
            } label: {
                Text(secondsLeft > 0 ? "You can close in \(secondsLeft)s" : "Close")
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(canClose ? Color.white : Color.appSecondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if canClose {
                            Capsule().fill(closeGradient)
                        } else {
                            Capsule().fill(Color.appFieldBackground)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canClose)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color.appElevatedSurface.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .accessibilityAddTraits(.isModal)
        .task(id: alert.id) {
            secondsLeft = alert.minViewSeconds
            while secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                secondsLeft -= 1
            }
        }
    }

    private var alertPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Alert")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(hex: 0x0B61CA))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(hex: 0x0B61CA).opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(hex: 0x0B61CA), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// `imageUrl` is usually the relative `/api/storage/files/<id>` route.
    private var imageURL: URL? {
        guard let raw = alert.imageUrl?.nonBlank else { return nil }
        if raw.hasPrefix("/") {
            return URL(string: "\(AppConfig.baseURL)\(raw)")
        }
        return URL(string: raw)
    }

    private var closeGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x1BCA0B), Color(hex: 0x3D9D02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Image

/// The storage route needs the bearer token, so a plain AsyncImage gets a
/// 401. Placeholder while loading; nothing at all (no broken icon) on failure.
private struct MobileAlertImage: View {
    let url: URL
    let token: String?

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 18)
                    .accessibilityHidden(true)
            } else if !didFail {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.appSurface)
                    .frame(height: 200)
                    .overlay { ProgressView() }
                    .padding(.top, 18)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Only our own hosts get the token, never a third-party image URL.
        if let token, Self.isAppHost(url) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                didFail = true
                return
            }
            guard let loaded = UIImage(data: data) else {
                didFail = true
                return
            }
            image = loaded
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            didFail = true
        }
    }

    private static func isAppHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let appHosts = [AppConfig.baseURL, AppConfig.chatBaseURL, AppConfig.storageBaseURL]
            .compactMap { URL(string: $0)?.host?.lowercased() }
        return appHosts.contains(host)
    }
}

// MARK: - Rich body

/// Renders the alert's HTML (headings, bold/italic/underline/strike, lists,
/// blockquotes, links) in a non-scrolling WKWebView sized to its content, so
/// it scrolls with the rest of the alert. Page JavaScript is off; links open
/// in Safari instead of navigating inside the alert.
private struct MobileAlertHTMLView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 1), configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.document(for: html), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var contentHeight: Binding<CGFloat>
        var loadedHTML: String?

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        /// didFinish fires after the load event (inline images included), so
        /// the measured height is final. The measuring script runs in the app's
        /// own content world, which page-JavaScript-off doesn't block.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = "Math.ceil(document.getElementById('alert-body').getBoundingClientRect().bottom)"
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self, weak webView] result in
                guard let self else { return }
                var height: CGFloat = 0
                if case .success(let value) = result, let number = value as? NSNumber {
                    height = CGFloat(number.doubleValue)
                }
                // Fallback: the content size of the (still 1pt tall) web view.
                if height <= 0, let webView {
                    height = webView.scrollView.contentSize.height
                }
                guard height > 0, abs(height - self.contentHeight.wrappedValue) > 0.5 else { return }
                self.contentHeight.wrappedValue = height
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            // The loadHTMLString document itself.
            if url.scheme?.lowercased() == "about" { return .allow }
            if navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto", "tel"].contains(scheme) {
                Task { _ = await UIApplication.shared.open(url) }
            }
            return .cancel
        }
    }

    private static func document(for body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>\(css)</style>
        </head>
        <body><div id="alert-body">\(body)</div></body>
        </html>
        """
    }

    /// App typography (system font, 16pt body) with light and dark palettes.
    /// The `ql-*` / `data-list` rules cover Quill-style editor output.
    private static let css = """
    :root { color-scheme: light dark; }
    html, body { margin: 0; padding: 0; background: transparent; }
    body {
      font-family: -apple-system, system-ui, sans-serif;
      font-size: 16px;
      line-height: 1.55;
      color: #161B23;
      -webkit-text-size-adjust: 100%;
    }
    #alert-body { display: flow-root; overflow-wrap: break-word; word-break: break-word; }
    #alert-body > :first-child { margin-top: 0; }
    #alert-body > :last-child { margin-bottom: 0; }
    h1 { font-size: 24px; line-height: 1.25; font-weight: 700; margin: 18px 0 8px; }
    h2 { font-size: 20px; line-height: 1.3; font-weight: 700; margin: 16px 0 6px; }
    h3 { font-size: 17px; line-height: 1.35; font-weight: 600; margin: 14px 0 6px; }
    p { margin: 0 0 12px; }
    strong, b { font-weight: 700; }
    em, i { font-style: italic; }
    u { text-decoration: underline; }
    s, strike, del { text-decoration: line-through; }
    ul, ol { margin: 0 0 12px; padding-left: 24px; }
    li { margin: 4px 0; }
    li > p { margin: 0; }
    li[data-list="bullet"] { list-style-type: disc; }
    li[data-list="ordered"] { list-style-type: decimal; }
    .ql-ui { display: none; }
    .ql-align-center { text-align: center; }
    .ql-align-right { text-align: right; }
    .ql-align-justify { text-align: justify; }
    blockquote {
      margin: 0 0 12px;
      padding: 8px 14px;
      border-left: 3px solid #0B61CA;
      border-radius: 0 8px 8px 0;
      background: rgba(11, 97, 202, 0.08);
      color: #475467;
    }
    a { color: #0B61CA; text-decoration: underline; }
    img { max-width: 100%; height: auto; border-radius: 10px; }
    hr { border: 0; border-top: 1px solid rgba(60, 60, 67, 0.29); margin: 16px 0; }
    code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 14px; }
    pre { white-space: pre-wrap; margin: 0 0 12px; }
    @media (prefers-color-scheme: dark) {
      body { color: #F2F4F7; }
      blockquote { color: #D0D5DD; border-left-color: #5AA2F5; background: rgba(90, 162, 245, 0.14); }
      a { color: #5AA2F5; }
      hr { border-top-color: rgba(84, 84, 88, 0.65); }
    }
    """
}
