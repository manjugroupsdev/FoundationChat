import SwiftUI
import UIKit

/// Telecaller dialer: 4×3 keypad, editable Station number persisted to defaults.
/// Tapping Call routes through the Doocti PBX bridge so the agent's deskphone
/// rings first; falls back to the device dialer (`tel:`) if the bridge is
/// unreachable.
///
/// Mirrors the Android `DialerFragment` behaviour. Station defaults key matches
/// Android: `dialer.station`. Default station mirrors Android: `6369487527`.
struct DialerView: View {
    private static let defaultStation = "6369487527"

    @AppStorage("dialer.station") private var station: String = DialerView.defaultStation
    @State private var dialed: String = ""
    @State private var isEditingStation: Bool = false
    @State private var callError: String?
    @State private var statusMessage: String?
    @State private var isCalling: Bool = false

    private let keys: [[DialerKey]] = [
        [.digit("1"), .digit("2", subtitle: "ABC"), .digit("3", subtitle: "DEF")],
        [.digit("4", subtitle: "GHI"), .digit("5", subtitle: "JKL"), .digit("6", subtitle: "MNO")],
        [.digit("7", subtitle: "PQRS"), .digit("8", subtitle: "TUV"), .digit("9", subtitle: "WXYZ")],
        [.symbol("*"), .digit("0", subtitle: "+"), .symbol("#")],
    ]

    var body: some View {
        VStack(spacing: 0) {
            stationField
            displaySection
            keypad
            callRow
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .navigationTitle("Dialer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cannot Call", isPresented: Binding(
            get: { callError != nil },
            set: { if !$0 { callError = nil } }
        )) {
            Button("OK", role: .cancel) { callError = nil }
        } message: {
            Text(callError ?? "")
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Sections

    private var stationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATION")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                TextField("Station number", text: $station)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .autocorrectionDisabled()
                    .onSubmit { isEditingStation = false }
                if !station.isEmpty {
                    Button {
                        station = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.top, 8)
    }

    private var displaySection: some View {
        VStack(spacing: 4) {
            Text(dialed.isEmpty ? " " : dialed)
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            if !dialed.isEmpty {
                Text(formattedPreview(dialed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach(0..<keys.count, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(keys[row]) { key in
                        DialerKeyButton(key: key) {
                            handleKey(key)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var callRow: some View {
        HStack(spacing: 24) {
            Spacer()
            Button {
                placeCall()
            } label: {
                Group {
                    if isCalling {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "phone.fill")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Circle().fill((callEnabled && !isCalling) ? Color.green : Color.green.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!callEnabled || isCalling)
            .accessibilityLabel("Call")

            Button {
                if !dialed.isEmpty { dialed.removeLast() }
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .disabled(dialed.isEmpty)
            .accessibilityLabel("Backspace")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Actions

    private var callEnabled: Bool {
        !sanitizedNumberForCall.isEmpty
    }

    private var sanitizedNumberForCall: String {
        let allowed = Set("0123456789+*#")
        return dialed.filter { allowed.contains($0) }
    }

    private func handleKey(_ key: DialerKey) {
        switch key {
        case .digit(let value, _):
            dialed.append(value)
        case .symbol(let value):
            dialed.append(value)
        }
    }

    private func placeCall() {
        let number = sanitizedNumberForCall
        let digits = number.filter(\.isNumber)
        guard digits.count >= 10 else {
            callError = "Enter a valid phone number (min 10 digits)"
            return
        }
        guard !isCalling else { return }
        isCalling = true
        statusMessage = "Placing call…"
        let stationNumber = station.filter(\.isNumber).isEmpty
            ? Self.defaultStation
            : station.filter(\.isNumber)
        Task {
            defer { isCalling = false }
            do {
                _ = try await TelecallerConvexAPIService.dialDoocti(
                    phoneNumber: digits,
                    station: stationNumber
                )
                await MainActor.run {
                    statusMessage = "Call placed — your phone will ring shortly"
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { statusMessage = nil }
            } catch {
                await MainActor.run {
                    statusMessage = nil
                    callError = "Call failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formattedPreview(_ value: String) -> String {
        // Light-touch formatting hint — does not mutate the dialed value.
        let digits = value.filter(\.isNumber)
        switch digits.count {
        case 10:
            let a = digits.prefix(5)
            let b = digits.suffix(5)
            return "\(a) \(b)"
        case 11:
            let a = digits.prefix(1)
            let mid = digits.dropFirst(1).prefix(5)
            let last = digits.suffix(5)
            return "\(a) \(mid) \(last)"
        default:
            return value
        }
    }
}

// MARK: - Key

private enum DialerKey: Identifiable, Hashable {
    case digit(String, subtitle: String? = nil)
    case symbol(String)

    var id: String { primary }

    var primary: String {
        switch self {
        case .digit(let v, _): return v
        case .symbol(let v): return v
        }
    }

    var subtitle: String? {
        if case .digit(_, let s) = self { return s }
        return nil
    }
}

private struct DialerKeyButton: View {
    let key: DialerKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(key.primary)
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                if let subtitle = key.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                } else {
                    Text(" ")
                        .font(.caption2)
                }
            }
            .frame(width: 78, height: 78)
            .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(key.primary))
    }
}

#Preview {
    NavigationStack { DialerView() }
}
