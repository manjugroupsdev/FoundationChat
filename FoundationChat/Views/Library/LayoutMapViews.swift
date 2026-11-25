import SwiftUI
import WebKit

/// 3D Layout Maps picker: only the projects that have a layout map configured
/// (and that this staff member can open). Tapping one opens its map.
struct LayoutMapProjectsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var projects: [LayoutMapProject] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var search = ""

    private var shown: [LayoutMapProject] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(query)
                || ($0.location ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if isLoading && projects.isEmpty {
                ProgressView("Loading projects…")
            } else if let errorMessage, projects.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load projects", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if projects.isEmpty {
                ContentUnavailableView(
                    "No 3D layout maps yet",
                    systemImage: "map",
                    description: Text("Maps are uploaded from the web, in the project's Details tab.")
                )
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ForEach(shown) { project in
                    NavigationLink {
                        LayoutMapView(project: project)
                    } label: {
                        LayoutMapProjectRow(project: project)
                    }
                }
            }
        }
        .navigationTitle("3D Layout Maps")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search project or location")
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            projects = try await MarketingConvexAPIService.listLayoutMaps(token: token)
                .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LayoutMapProjectRow: View {
    let project: LayoutMapProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 46, height: 46)
                .background(Color.adaptiveTint(0xEAF4FF), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name ?? "Unnamed project")
                    .font(AppModuleFont.rowTitle)
                    .lineLimit(2)
                if let location = project.location, !location.isEmpty {
                    Text(location)
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(project.plotCount ?? 0) plots · 3D map")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.adaptiveInk(0x067647))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.adaptiveTint(0xECFDF3), in: Capsule())
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

/// One project's 3D layout map. The map itself is the web app's page
/// (/m/layout-map/<projectId>, no web shell) in a web view, so plot status,
/// Hold and the look always match the web. Two things are native:
///  - sign-in: the app's session token is given to the page before it loads;
///  - "Book plot": the page posts it here and the app's booking form opens.
struct LayoutMapView: View {
    @Environment(AuthStore.self) private var authStore
    let project: LayoutMapProject

    fileprivate enum Phase { case loading, ready, failed }

    private struct BookingTarget: Identifiable {
        let project: MarketingProject
        let unit: InventoryUnit
        var id: String { unit.id }
    }

    @State private var phase: Phase = .loading
    @State private var reloadCount = 0
    @State private var bookingTarget: BookingTarget?
    @State private var message: String?

    private var mapURL: URL? {
        // storageBaseURL is the web app's host (mg / dev-mg), which serves this page.
        var components = URLComponents(string: AppConfig.storageBaseURL)
        components?.path = "/m/layout-map/\(project.projectId)"
        components?.queryItems = [URLQueryItem(name: "name", value: project.name ?? "")]
        return components?.url
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if let token = authStore.currentSession?.token, let mapURL {
                LayoutMapWebView(
                    url: mapURL,
                    sessionToken: token,
                    reloadCount: reloadCount,
                    onPhase: { phase = $0 },
                    onBook: { plotNo in Task { await book(plotNo: plotNo) } }
                )
                .ignoresSafeArea(edges: .bottom)
                .opacity(phase == .ready ? 1 : 0)
            }

            switch phase {
            case .ready:
                EmptyView()
            case .loading:
                ProgressView("Loading 3D map…")
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't load the map", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") {
                        phase = .loading
                        reloadCount += 1
                    }
                }
            }
        }
        .navigationTitle(project.name ?? "3D Layout Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $bookingTarget) { target in
            BookingCreateView(initialProject: target.project, initialUnit: target.unit)
                .appLibraryNativeSheet([.height(720), .large])
                .presentationBackground(Color.appElevatedSurface)
        }
        .floaterAlert($message)
    }

    /// The map knows a plot by its number; the booking form needs the project and that plot's unit row.
    @MainActor
    private func book(plotNo: String) async {
        guard let token = authStore.currentSession?.token else { return }
        // Same normalisation the map uses, so "A-12" and "a 12" are one plot.
        func key(_ value: String?) -> String {
            (value ?? "").uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        }
        do {
            async let projects = MarketingConvexAPIService.getMarketingProjects(token: token)
            async let units = MarketingConvexAPIService.listInventoryUnits(token: token, projectId: project.projectId)
            guard let marketingProject = try await projects.first(where: { $0.id == project.projectId }) else {
                message = "This project is not open for booking."
                return
            }
            guard let unit = try await units.first(where: { key($0.unitNumber) == key(plotNo) }) else {
                message = "Plot \(plotNo) is not set up for booking yet."
                return
            }
            bookingTarget = BookingTarget(project: marketingProject, unit: unit)
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct LayoutMapWebView: UIViewRepresentable {
    let url: URL
    let sessionToken: String
    let reloadCount: Int
    let onPhase: (LayoutMapView.Phase) -> Void
    let onBook: (String) -> Void

    private static let bridgeName = "mconnectLayout"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The web app keeps its session in localStorage. Writing it before any
        // page script runs signs the page in without putting the token in a URL.
        let tokenLiteral = (try? JSONEncoder().encode(sessionToken)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "try{localStorage.setItem('manju_session_token',\(tokenLiteral))}catch(e){}",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: Self.bridgeName)

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.bounces = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.reloadCount != reloadCount {
            context.coordinator.reloadCount = reloadCount
            view.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: bridgeName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: LayoutMapWebView
        var reloadCount = 0

        init(_ parent: LayoutMapWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onPhase(.ready)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onPhase(.failed)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onPhase(.failed)
        }

        /// Only the map page stays in here; directions, WhatsApp, calls and other links leave the app.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let target = navigationAction.request.url else { return .cancel }
            if navigationAction.targetFrame?.isMainFrame == false { return .allow }
            if target.host == parent.url.host, target.path.hasPrefix("/m/layout-map/") { return .allow }
            await UIApplication.shared.open(target)
            return .cancel
        }

        /// Links that ask for a new window (target="_blank") open outside the app too.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let target = navigationAction.request.url { UIApplication.shared.open(target) }
            return nil
        }

        /// Messages from the map page (see staff-layout-map.tsx in the web repo).
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "book",
                  let plotNo = body["plotNo"] as? String, !plotNo.isEmpty
            else { return }
            parent.onBook(plotNo)
        }
    }
}
