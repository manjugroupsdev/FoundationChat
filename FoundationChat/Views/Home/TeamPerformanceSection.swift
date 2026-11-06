import SwiftUI

/// Team Performance on the mobile dashboard: the web Insights "Executive
/// cockpit" cards (Calls, CP completed, SV completed, Bookings, Collections,
/// Registrations) for the viewer's permitted team over a chosen range.
/// Scoping happens in Telecaller Core from the viewer's identity, as on the
/// web. The last answer per range is cached so the card paints instantly.
struct TeamPerformanceSection: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Bump to force a fresh load (pull to refresh on the dashboard).
    var refreshID: Int = 0

    enum Range: String, CaseIterable, Identifiable {
        case today = "Today", week = "Last 7 days", month = "This month", days30 = "Last 30 days"
        var id: String { rawValue }
    }

    private struct Metric: Identifiable {
        let key: String
        let label: String
        var money = false
        var id: String { key }
    }

    private let metrics: [Metric] = [
        Metric(key: "calls", label: "Calls"),
        Metric(key: "cp", label: "CP completed"),
        Metric(key: "sv", label: "SV completed"),
        Metric(key: "booking", label: "Bookings"),
        Metric(key: "collection", label: "Collections", money: true),
        Metric(key: "registration", label: "Registrations"),
    ]

    @State private var range: Range = .week
    @State private var performance: CockpitPerformance?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var handledRefresh = 0

    private static let violet = Color(hex: 0x7C3AED)
    private static let violetSoft = Color(hex: 0xEDE9FE)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.violet)
                Text("Team Performance")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh team performance")
                .disabled(isLoading)
            }

            Text("Targets and achievements · \(rangeLabel) · Your permitted team")
                .font(.system(size: 12))
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Range.allCases) { item in
                        Button {
                            guard range != item else { return }
                            range = item
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(range == item ? Color.white : Color(hex: 0x5B21B6))
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(range == item ? Self.violet : Color.appSurface, in: Capsule())
                                .overlay(Capsule().stroke(range == item ? Color.clear : Color(hex: 0xDDD6FE), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(metrics) { metric in
                    metricCard(metric)
                }
            }

            if let errorText {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(hex: 0x7C3AED).opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: 0xDDD6FE), lineWidth: 1)
        )
        .task(id: "\(range.rawValue)-\(refreshID)") {
            // Only a pull to refresh forces a fresh server computation.
            let force = refreshID != handledRefresh
            handledRefresh = refreshID
            await load(force: force)
        }
    }

    // Two columns on phones, three on iPad / wide layouts.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: sizeClass == .regular ? 3 : 2)
    }

    private func metricCard(_ metric: Metric) -> some View {
        let m = performance?.metrics[metric.key] ?? CockpitMetric()
        let noData = isNoData
        let showValue = performance != nil && !noData
        return VStack(alignment: .leading, spacing: 8) {
            Text(metric.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
            Group {
                if showValue {
                    (Text(format(m.actual, money: metric.money))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                     + Text(" / \(m.target > 0 ? format(m.target, money: metric.money) : "No target")")
                        .font(.system(size: 13))
                        .foregroundColor(Color.appSecondaryText))
                } else {
                    Text("—").font(.system(size: 18, weight: .semibold))
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Self.violetSoft)
                    Capsule().fill(Self.violet)
                        .frame(width: proxy.size.width * CGFloat(showValue ? min(max(m.percentage, 0), 100) / 100 : 0))
                }
            }
            .frame(height: 6)

            Text(caption(m, metric: metric, noData: noData))
                .font(.system(size: 11))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.appSeparator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var isNoData: Bool {
        guard let from = performance?.availableFrom, let to = performance?.dateTo else { return false }
        return to < from
    }

    private func caption(_ m: CockpitMetric, metric: Metric, noData: Bool) -> String {
        if performance == nil { return isLoading ? "Loading…" : (errorText == nil ? " " : "Unavailable") }
        if noData { return "No recorded performance" }
        var text = m.target > 0 ? "\(trimmed(m.percentage))% achieved" : "No count target set"
        if let sqft = performance?.metrics["\(metric.key)Sqft"], sqft.target > 0 {
            text += "\nArea: \(format(sqft.actual, money: false)) / \(format(sqft.target, money: false)) sq.ft"
        }
        return text
    }

    // MARK: - Loading

    private var cacheKey: String {
        let staff = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "team.performance.\(staff).\(range)"
    }

    @MainActor
    private func load(force: Bool) async {
        guard let token = authStore.currentSession?.token else { return }
        let key = cacheKey
        if !force, performance == nil || performance?.dateTo != dates(range).to {
            performance = await Task.detached { LocalCache.get(key, as: CockpitPerformance.self) }.value
        }
        isLoading = true
        defer { isLoading = false }
        let span = dates(range)
        do {
            let data = try await TelecallerCoreService.shared.call(
                session: token,
                namespace: "reports",
                apiName: "cockpitPerformance",
                data: ["dateFrom": span.from, "dateTo": span.to, "refresh": force]
            )
            let decoded = try JSONDecoder().decode(CockpitPerformance.self, from: data)
            guard !Task.isCancelled else { return }
            performance = decoded
            errorText = nil
            Task.detached(priority: .utility) { LocalCache.put(key, decoded) }
        } catch {
            guard !Task.isCancelled else { return }
            errorText = "Couldn't load team performance. Tap to retry."
        }
    }

    // MARK: - Formatting

    private func dates(_ range: Range) -> (from: String, to: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let today = Date()
        let start: Date
        switch range {
        case .today: start = today
        case .week: start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .days30: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .month: start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: today))
    }

    private var rangeLabel: String {
        let span = performance.flatMap { p in p.dateFrom.map { ($0, p.dateTo ?? $0) } } ?? dates(range)
        return span.0 == span.1 ? pretty(span.0) : "\(pretty(span.0)) – \(pretty(span.1))"
    }

    private func pretty(_ iso: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_GB")
        output.dateFormat = "d MMM"
        return output.string(from: date)
    }

    private func trimmed(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value, let whole = Int(exactly: value) { return String(whole) }
        return String(format: "%.1f", value)
    }

    /// en-IN grouping; money compact like the web (₹71L, ₹2.4Cr, ₹85K).
    private func format(_ value: Double, money: Bool) -> String {
        if money {
            if value >= 1_00_00_000 {
                return "₹" + String(format: "%.1f", value / 1_00_00_000).replacingOccurrences(of: ".0", with: "") + "Cr"
            }
            if value >= 1_00_000 { return "₹\(Int((value / 1_00_000).rounded()))L" }
            if value >= 1_000 { return "₹\(Int((value / 1_000).rounded()))K" }
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return money ? "₹" + text : text
    }
}
