import Foundation
import CoreLocation

struct Climb3DRoutePoint {
    let latitude: Double
    let longitude: Double
    let elevationM: Double
    let distanceM: Double
}

struct Climb3DRoute {

    let points: [Climb3DRoutePoint]
    let totalDistanceM: Double

    func point(at progress: Double) -> Climb3DRoutePoint? {

        guard !points.isEmpty else {
            return nil
        }

        return point(
            atDistanceM:
                min(1, max(0, progress)) *
                totalDistanceM
        )
    }

    func point(
        atDistanceM distanceM: Double
    ) -> Climb3DRoutePoint? {

        guard !points.isEmpty else {
            return nil
        }

        if points.count == 1 {
            return points[0]
        }

        let target =
            min(
                totalDistanceM,
                max(0, distanceM)
            )

        if target <= 0 {
            return points[0]
        }

        if target >= totalDistanceM {
            return points[points.count - 1]
        }

        var low = 0
        var high = points.count - 1

        while low + 1 < high {

            let mid =
                (low + high) / 2

            if points[mid].distanceM < target {
                low = mid
            } else {
                high = mid
            }
        }

        let a = points[low]
        let b = points[high]

        let span =
            max(
                0.001,
                b.distanceM -
                a.distanceM
            )

        let t =
            (target - a.distanceM) /
            span

        return Climb3DRoutePoint(
            latitude:
                a.latitude +
                (b.latitude - a.latitude) * t,

            longitude:
                a.longitude +
                (b.longitude - a.longitude) * t,

            elevationM:
                a.elevationM +
                (b.elevationM - a.elevationM) * t,

            distanceM:
                target
        )
    }

    func distance(
        at progress: Double
    ) -> Double {

        min(1, max(0, progress)) *
        totalDistanceM
    }

    func remainingDistance(
        at progress: Double
    ) -> Double {

        max(
            0,
            totalDistanceM -
            distance(at: progress)
        )
    }

    func elevation(
        at progress: Double
    ) -> Double {

        point(
            at: progress
        )?.elevationM ?? 0
    }

    // Prototype only.
    // RideClimb physical model remains authoritative.
    func gradePercent(
        at progress: Double,
        windowM: Double = 100
    ) -> Double {

        guard totalDistanceM > 1 else {
            return 0
        }

        let center =
            distance(at: progress)

        let half =
            max(
                30,
                windowM / 2
            )

        let beforeDistance =
            max(
                0,
                center - half
            )

        let afterDistance =
            min(
                totalDistanceM,
                center + half
            )

        guard
            let before =
                point(
                    atDistanceM:
                        beforeDistance
                ),

            let after =
                point(
                    atDistanceM:
                        afterDistance
                )
        else {
            return 0
        }

        let run =
            after.distanceM -
            before.distanceM

        guard run > 5 else {
            return 0
        }

        return
            (
                after.elevationM -
                before.elevationM
            ) /
            run *
            100
    }
}


// MARK: - GPX parser

/// PASS-THROUGH GPX parser for validation builds.
///
/// The imported GPX is the source of truth. This parser does NOT resample,
/// smooth, crop, simplify, regularize or alter latitude/longitude/elevation.
/// It only calculates cumulative horizontal distance between the original
/// GPX points so the existing progress/camera logic can operate.
final class Climb3DGPXParser: NSObject, XMLParserDelegate {

    private var raw: [(lat: Double, lon: Double, ele: Double)] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentText = ""

    func parse(url: URL) throws -> Climb3DRoute {
        let data = try Data(contentsOf: url)

        raw.removeAll(keepingCapacity: true)

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? NSError(
                domain: "Climb3D.GPX",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid GPX"]
            )
        }

        guard raw.count >= 2 else {
            throw NSError(
                domain: "Climb3D.GPX",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "GPX contains too few points"]
            )
        }

        var routePoints: [Climb3DRoutePoint] = []
        routePoints.reserveCapacity(raw.count)

        var cumulativeDistanceM = 0.0
        var previousLocation: CLLocation?

        for point in raw {
            let location = CLLocation(
                latitude: point.lat,
                longitude: point.lon
            )

            if let previousLocation {
                cumulativeDistanceM += location.distance(from: previousLocation)
            }

            routePoints.append(
                Climb3DRoutePoint(
                    latitude: point.lat,
                    longitude: point.lon,
                    elevationM: point.ele,
                    distanceM: cumulativeDistanceM
                )
            )

            previousLocation = location
        }

        return Climb3DRoute(
            points: routePoints,
            totalDistanceM: cumulativeDistanceM
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""

        if elementName == "trkpt" || elementName == "rtept" {
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentEle = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "ele" {
            currentEle = Double(
                currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if elementName == "trkpt" || elementName == "rtept" {
            if let lat = currentLat, let lon = currentLon {
                raw.append((lat: lat, lon: lon, ele: currentEle ?? 0))
            }

            currentLat = nil
            currentLon = nil
            currentEle = nil
        }
    }
}
