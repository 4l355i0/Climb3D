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
        guard !points.isEmpty else { return nil }
        if points.count == 1 { return points[0] }

        let target =
            min(1, max(0, progress)) *
            totalDistanceM

        if target <= 0 { return points[0] }
        if target >= totalDistanceM { return points[points.count - 1] }

        var low = 0
        var high = points.count - 1

        while low + 1 < high {
            let mid = (low + high) / 2

            if points[mid].distanceM < target {
                low = mid
            } else {
                high = mid
            }
        }

        let a = points[low]
        let b = points[high]
        let span = max(0.001, b.distanceM - a.distanceM)
        let t = (target - a.distanceM) / span

        return Climb3DRoutePoint(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t,
            elevationM: a.elevationM + (b.elevationM - a.elevationM) * t,
            distanceM: target
        )
    }
}

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
            throw parser.parserError ??
                NSError(
                    domain: "Climb3D.GPX",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid GPX"
                    ]
                )
        }

        guard raw.count >= 2 else {
            throw NSError(
                domain: "Climb3D.GPX",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "GPX contains too few points"
                ]
            )
        }

        var result: [Climb3DRoutePoint] = []
        result.reserveCapacity(raw.count)

        var cumulative = 0.0
        var previous: CLLocation?

        for p in raw {
            let location = CLLocation(
                latitude: p.lat,
                longitude: p.lon
            )

            if let previous {
                cumulative += location.distance(from: previous)
            }

            result.append(
                Climb3DRoutePoint(
                    latitude: p.lat,
                    longitude: p.lon,
                    elevationM: p.ele,
                    distanceM: cumulative
                )
            )

            previous = location
        }

        return Climb3DRoute(
            points: result,
            totalDistanceM: cumulative
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

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
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
            if let lat = currentLat,
               let lon = currentLon {
                raw.append(
                    (
                        lat: lat,
                        lon: lon,
                        ele: currentEle ?? 0
                    )
                )
            }

            currentLat = nil
            currentLon = nil
            currentEle = nil
        }
    }
}
