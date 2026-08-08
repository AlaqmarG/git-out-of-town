//  GeoCheck.swift
//  Issue #24 — does ARKit geo-tracking (ARGeoAnchor) work at the venue?
//
//  Drop this file into the Xcode project from #23 and show `GeoCheckView()` as the
//  root view. Run it AT THE VENUE — Apple's coverage is per-area, not per-city.
//
//  Info.plist needs:
//    NSLocationWhenInUseUsageDescription — "Checks whether precise AR anchoring works here."
//
//  Result decides the placement strategy:
//    AVAILABLE  -> use ARGeoAnchor, set used_geo_anchor = true
//    NOT        -> ARWorldTrackingConfiguration + GPS bearing fallback (build this first regardless)

import ARKit
import CoreLocation
import SwiftUI

final class GeoCheckModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var deviceSupported = ARGeoTrackingConfiguration.isSupported
    @Published var hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var accuracy: CLLocationAccuracy?
    @Published var available: Bool?
    @Published var status = "Tap Check to begin."

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        guard deviceSupported else {
            status = "This device can't do geo-tracking at all (needs A12+ and GPS). Use the GPS fallback."
            available = false
            return
        }
        status = "Getting a location fix…"
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        coordinate = loc.coordinate
        accuracy = loc.horizontalAccuracy
        status = "Asking Apple about coverage here…"

        ARGeoTrackingConfiguration.checkAvailability(at: loc.coordinate) { [weak self] isAvailable, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.available = isAvailable
                if let error {
                    self.status = "Error: \(error.localizedDescription)"
                } else {
                    self.status = isAvailable
                        ? "✅ AVAILABLE — use ARGeoAnchor here."
                        : "❌ NOT available here — ship the GPS-bearing fallback."
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Location failed: \(error.localizedDescription)"
    }
}

struct GeoCheckView: View {
    @StateObject private var model = GeoCheckModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Geo-tracking check").font(.largeTitle.bold())

            row("Device supports geo-tracking", model.deviceSupported)
            row("Device has LiDAR", model.hasLiDAR)

            if let c = model.coordinate {
                Text(String(format: "📍 %.6f, %.6f  ±%.0fm",
                            c.latitude, c.longitude, model.accuracy ?? -1))
                    .font(.system(.footnote, design: .monospaced))
            }

            Text(model.status).font(.headline)

            Button("Check") { model.start() }
                .buttonStyle(.borderedProminent)

            Spacer()

            Text("Run this AT THE VENUE. Apple's coverage is per-area, not per-city. "
                 + "Toronto/Vancouver/Montreal are supported regions, but the specific block matters.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func row(_ label: String, _ value: Bool) -> some View {
        HStack {
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(value ? .green : .red)
            Text(label)
        }
    }
}

#Preview { GeoCheckView() }
