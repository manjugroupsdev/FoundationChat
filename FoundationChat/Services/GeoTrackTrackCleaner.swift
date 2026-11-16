import CoreLocation
import Foundation

/// Turns a staff member's raw GPS fixes into the track worth drawing, the way
/// Google Timeline does before it draws a day. Same rules as Mconnect
/// `TrackCleaner`, the web's lib/geotrack-clean-track.ts and the geo service's
/// road snapping:
///
///  1. Drops fixes that can't be trusted: mock, (0,0), accuracy worse than
///     100 m (kept when nothing better exists), or an impossible jump.
///  2. Drops single-fix spikes: one fix that jumps out and straight back.
///  3. Collapses every stay into ONE point. While a phone sits on a site its
///     fixes wander 20–100 m around the real spot, so joining them drew a star
///     of criss-crossing lines over every stop. A stay = fixes within ~60 m
///     (or their own accuracy, up to 100 m) of the running centre for 3+
///     minutes; a few strays that come straight back are part of it.
nonisolated enum GeoTrackTrackCleaner {

    struct Fix: Sendable {
        var lat: Double
        var lng: Double
        var accuracy: Double?
        /// Epoch milliseconds; nil = no time (only the validity filter applies).
        var atMs: Double?
        var isMock: Bool = false
    }

    struct Point: Sendable {
        var lat: Double
        var lng: Double
        /// A stay's point carries its arrival time.
        var atMs: Double?
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    static let maxAccuracyM = 100.0
    private static let maxPlausibleSpeedMps = 55.0
    private static let spikeMinM = 60.0
    private static let spikeMaxSpanMs = 10.0 * 60_000 // still phones report every ~5 min
    private static let stayRadiusM = 60.0
    private static let stayMaxRadiusM = 100.0
    private static let stayMinMs = 3.0 * 60_000
    private static let stayExcursionPoints = 3
    private static let stayExcursionMs = 10.0 * 60_000
    private static let stayExcursionMaxM = 250.0 // strays farther are a real trip

    private struct F {
        let lat: Double
        let lng: Double
        let acc: Double
        let at: Double?
    }

    /// The geo service timeline, cleaned and ready to draw.
    static func clean(timeline: [GeoTrackTimelinePoint]) -> [Point] {
        clean(timeline.map {
            Fix(lat: $0.lat, lng: $0.lng, accuracy: $0.accuracy,
                atMs: $0.recordedAt > 0 ? $0.recordedAt : nil, isMock: $0.isMock == true)
        })
    }

    static func clean(_ points: [Fix]) -> [Point] {
        guard !points.isEmpty else { return [] }
        return collapseStays(dropSpikes(dropImpossibleJumps(valid(points))))
    }

    static func distanceM(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6_371_000.0
        let rad = Double.pi / 180
        let dLat = (lat2 - lat1) * rad
        let dLng = (lng2 - lng1) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * rad) * cos(lat2 * rad) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * asin(min(1, h.squareRoot()))
    }

    private static func valid(_ points: [Fix]) -> [F] {
        let all: [F] = points.compactMap { p in
            guard p.lat.isFinite, p.lng.isFinite, !(p.lat == 0 && p.lng == 0),
                  (-90...90).contains(p.lat), (-180...180).contains(p.lng), !p.isMock else { return nil }
            let acc = p.accuracy.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
            return F(lat: p.lat, lng: p.lng, acc: acc, at: p.atMs)
        }
        let accurate = all.filter { $0.acc <= maxAccuracyM }
        return accurate.count >= 2 ? accurate : all
    }

    private static func dropImpossibleJumps(_ fixes: [F]) -> [F] {
        var out: [F] = []
        out.reserveCapacity(fixes.count)
        for f in fixes {
            if let last = out.last, let lastAt = last.at, let at = f.at {
                let dt = (at - lastAt) / 1000
                let d = distanceM(last.lat, last.lng, f.lat, f.lng)
                if dt < 0 { continue }
                if dt == 0 && d > spikeMinM { continue }
                if dt > 0 && d / dt > maxPlausibleSpeedMps { continue }
            }
            out.append(f)
        }
        return out
    }

    private static func dropSpikes(_ fixes: [F]) -> [F] {
        var current = fixes
        for _ in 0..<3 {
            var out: [F] = []
            out.reserveCapacity(current.count)
            var removed = false
            for i in current.indices {
                let b = current[i]
                if let a = out.last, i + 1 < current.count {
                    let c = current[i + 1]
                    let ab = distanceM(a.lat, a.lng, b.lat, b.lng)
                    let bc = distanceM(b.lat, b.lng, c.lat, c.lng)
                    let ac = distanceM(a.lat, a.lng, c.lat, c.lng)
                    let threshold = max(spikeMinM, b.acc)
                    var quick = true
                    if let aAt = a.at, let cAt = c.at { quick = cAt - aAt <= spikeMaxSpanMs }
                    if quick && ab > threshold && bc > threshold && ac < 0.35 * min(ab, bc) {
                        removed = true
                        continue
                    }
                }
                out.append(b)
            }
            current = out
            if !removed { break }
        }
        return current
    }

    private static func weight(_ f: F) -> Double {
        let a = max(5, f.acc > 0 ? f.acc : 25)
        return 1 / (a * a)
    }

    private static func radius(_ f: F) -> Double {
        min(stayMaxRadiusM, max(stayRadiusM, f.acc))
    }

    private static func collapseStays(_ fixes: [F]) -> [Point] {
        var out: [Point] = []
        var i = 0
        while i < fixes.count {
            let head = fixes[i]
            guard let headAt = head.at else {
                out.append(Point(lat: head.lat, lng: head.lng, atMs: nil))
                i += 1
                continue
            }
            var wSum = weight(head)
            var latSum = head.lat * wSum
            var lngSum = head.lng * wSum
            var cLat = head.lat
            var cLng = head.lng
            func add(_ f: F) {
                let w = weight(f)
                wSum += w; latSum += f.lat * w; lngSum += f.lng * w
                cLat = latSum / wSum; cLng = lngSum / wSum
            }
            func inside(_ f: F) -> Bool { distanceM(cLat, cLng, f.lat, f.lng) <= radius(f) }

            var lastIn = i
            var j = i + 1
            while j < fixes.count {
                let f = fixes[j]
                guard f.at != nil else { break }
                if inside(f) {
                    add(f); lastIn = j; j += 1
                    continue
                }
                // A few stray fixes that come straight back still belong to the stay.
                let lastAt = fixes[lastIn].at ?? headAt
                var back = -1
                var k = j
                while k < fixes.count && k <= j + stayExcursionPoints {
                    let g = fixes[k]
                    guard let gAt = g.at, gAt - lastAt <= stayExcursionMs else { break }
                    if k > j && inside(g) { back = k; break }
                    if distanceM(cLat, cLng, g.lat, g.lng) > stayExcursionMaxM { break }
                    k += 1
                }
                if back < 0 { break }
                add(fixes[back]); lastIn = back; j = back + 1
            }

            if lastIn > i, let lastAt = fixes[lastIn].at, lastAt - headAt >= stayMinMs {
                out.append(Point(lat: cLat, lng: cLng, atMs: headAt))
                i = lastIn + 1
            } else {
                out.append(Point(lat: head.lat, lng: head.lng, atMs: headAt))
                i += 1
            }
        }
        return out
    }
}
