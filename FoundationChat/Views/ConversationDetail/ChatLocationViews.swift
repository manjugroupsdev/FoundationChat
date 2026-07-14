import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct ChatLocationPayload: Equatable {
  let latitude: Double
  let longitude: Double
  let label: String
  let battery: Int?
  let speed: String?
  let status: String?

  init(latitude: Double, longitude: Double, label: String = "Current Location", battery: Int? = nil, speed: String? = nil, status: String? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.label = label
    self.battery = battery
    self.speed = speed
    self.status = status
  }

  init?(messageBody: String) {
    let trimmed = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let startRange = trimmed.range(of: "[LOCATION:"),
      let endIndex = trimmed[startRange.upperBound...].firstIndex(of: "]")
    else { return nil }

    let body = trimmed[startRange.upperBound..<endIndex]
    var values: [String: String] = [:]

    for part in body.split(whereSeparator: { $0 == ";" || $0 == "," }) {
      let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard pair.count == 2 else { continue }
      values[String(pair[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
        String(pair[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard
      let lat = Double(values["lat"] ?? values["latitude"] ?? ""),
      let lon = Double(values["lon"] ?? values["lng"] ?? values["longitude"] ?? "")
    else {
      return nil
    }

    latitude = lat
    longitude = lon
    label = values["label"]?.isEmpty == false ? values["label"]! : "Current Location"
    battery = values["battery"].flatMap(Int.init)
    speed = values["speed"]
    status = values["status"] ?? values["motion"]
  }

  var encodedBody: String {
    var parts = [
      "lat=\(latitude)",
      "lon=\(longitude)",
      "label=\(label)"
    ]
    if let battery { parts.append("battery=\(battery)") }
    if let speed, !speed.isEmpty { parts.append("speed=\(speed)") }
    if let status, !status.isEmpty { parts.append("status=\(status)") }
    return "[LOCATION:\(parts.joined(separator: ";"))]"
  }

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  var mapsURL: URL? {
    var components = URLComponents(string: "http://maps.apple.com/")
    components?.queryItems = [
      URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
      URLQueryItem(name: "q", value: label)
    ]
    return components?.url
  }
}

@MainActor
final class ChatLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var payload: ChatLocationPayload?
  @Published var errorMessage: String?
  @Published var isLocating = false

  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
  }

  func requestLocation() {
    errorMessage = nil
    isLocating = true

    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      isLocating = false
      errorMessage = "Location permission is required to share your current location."
    @unknown default:
      isLocating = false
      errorMessage = "Unable to access location right now."
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
      manager.requestLocation()
    } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      isLocating = false
      errorMessage = "Location permission is required to share your current location."
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in
      let speedKmh = max(0, Int(location.speed * 3.6))
      let normalizedSpeed = speedKmh >= 3 ? speedKmh : 0
      payload = ChatLocationPayload(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        battery: Int(UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel * 100 : 100),
        speed: "\(normalizedSpeed)",
        status: normalizedSpeed >= 3 ? "Moving" : "Stationary"
      )
      isLocating = false
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    Task { @MainActor in
      isLocating = false
      errorMessage = "Could not get location. Please try again."
    }
  }
}

struct ShareLocationSheet: View {
  @StateObject private var provider = ChatLocationProvider()
  let onCancel: () -> Void
  let onShare: (ChatLocationPayload) -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        ZStack {
          Circle()
            .fill(Color(red: 0.05, green: 0.38, blue: 0.79).opacity(0.12))
            .frame(width: 118, height: 118)
          Image(systemName: "location.fill")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(Color(red: 0.05, green: 0.38, blue: 0.79))
        }
        .padding(.top, 8)

        if let payload = provider.payload {
          VStack(spacing: 8) {
            Text(payload.label)
              .font(.system(size: 20, weight: .semibold))
            Text("\(payload.latitude, specifier: "%.6f"), \(payload.longitude, specifier: "%.6f")")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(.secondary)
          }

          Button {
            onShare(payload)
          } label: {
            Text("Share Location")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .background(Color(red: 0.05, green: 0.38, blue: 0.79), in: Capsule())
          }
          .buttonStyle(.plain)
        } else {
          VStack(spacing: 10) {
            if provider.isLocating {
              ProgressView()
            }
            Text(provider.errorMessage ?? "Share your live GPS point in this chat.")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(provider.errorMessage == nil ? Color.secondary : Color.red)
              .multilineTextAlignment(.center)
          }

          Button {
            provider.requestLocation()
          } label: {
            Text(provider.isLocating ? "Locating..." : "Use Current Location")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .background(Color(red: 0.05, green: 0.38, blue: 0.79), in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(provider.isLocating)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 22)
      .navigationTitle("Location")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
      .onAppear {
        UIDevice.current.isBatteryMonitoringEnabled = true
        provider.requestLocation()
      }
    }
  }
}

struct ChatLocationCard: View {
  let payload: ChatLocationPayload
  let isOutgoing: Bool
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      if let url = payload.mapsURL {
        openURL(url)
      }
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        Map(position: .constant(.region(MKCoordinateRegion(
          center: payload.coordinate,
          span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))) {
          Marker(payload.label, coordinate: payload.coordinate)
        }
        .allowsHitTesting(false)
        .frame(width: 250, height: 138)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        HStack(spacing: 10) {
          Image(systemName: "location.north.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isOutgoing ? .white : Color(red: 0.05, green: 0.38, blue: 0.79))
            .frame(width: 24)
          VStack(alignment: .leading, spacing: 2) {
            Text(payload.label)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(isOutgoing ? .white : Color.black.opacity(0.9))
            Text(metaText)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(isOutgoing ? .white.opacity(0.72) : .secondary)
          }
          Spacer(minLength: 0)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private var metaText: String {
    var parts = [String(format: "%.5f, %.5f", payload.latitude, payload.longitude)]
    if let status = payload.status, !status.isEmpty {
      parts.append(status)
    }
    return parts.joined(separator: " · ")
  }
}

private struct ChatLocationMapSheet: View {
  let payload: ChatLocationPayload
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Map(position: .constant(.region(MKCoordinateRegion(
        center: payload.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
      )))) {
        Marker(payload.label, coordinate: payload.coordinate)
      }
      .ignoresSafeArea(edges: .bottom)
      .navigationTitle(payload.label)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if let url = payload.mapsURL {
              UIApplication.shared.open(url)
            }
          } label: {
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
          }
        }
      }
    }
  }
}
