import Foundation

// GPXtruder Map/Automatic core port for Climb3D.
// Source algorithm: anoved/gpxtruder, gh-pages branch (MIT License).
// This port intentionally implements the route geometry path used by GPXtruder:
// WGS84/Vincenty distance filter -> Google Web Mercator -> fit/scale ->
// jointPoints() miter logic -> acute-series collapse -> closed route solid.
struct GPXtruderEngine {

    struct Diagnostics {
        let inputPoints: Int
        let smoothingDistanceM: Int
        let filteredPoints: Int
        let centerlineStations: Int
        let triangleCount: Int
        let modelWidthMM: Double
        let modelDepthMM: Double
        let modelHeightMM: Double
        let checksPassed: Bool
        let checkMessage: String

        var shortSummary: String {
            let check = checksPassed ? "CHECKS OK" : "CHECK FAILED"
            return "GPXtruder • \(inputPoints)→\(filteredPoints)→\(centerlineStations) • \(check)"
        }
    }

    struct Result {
        let route: Climb3DRoute
        let mesh: Climb3DMesh
        let diagnostics: Diagnostics
    }

    private struct RawPoint {
        let lat: Double
        let lon: Double
        let ele: Double
    }

    private struct XYZE {
        let x: Double
        let y: Double
        let z: Double
        let raw: RawPoint
    }

    private struct EdgeStation {
        let leftX: Double
        let leftY: Double
        let rightX: Double
        let rightY: Double
        let z: Double
        let raw: RawPoint
    }

    // These are GPXtruder's default UI values for the Map profile used in our
    // reference STL: 90x90 mm bed, 2 mm path, x5 vertical exaggeration,
    // 1 mm base, clip-to-minimum, automatic smoothing.
    private let bedWidthMM = 90.0
    private let bedDepthMM = 90.0
    private let pathWidthMM = 2.0
    private let verticalExaggeration = 5.0
    private let baseHeightMM = 1.0
    private let clipToMinimumElevation = true

    private var bufferMM: Double { pathWidthMM / 2.0 }

    func build(url: URL) throws -> Result {
        let raw = try parseFirstTrack(url: url)
        guard raw.count >= 2 else { throw error("GPX route too short") }

        let rawBounds = geographicBounds(raw)
        let minMerc = webMercator(lon: rawBounds.minLon, lat: rawBounds.minLat)
        let maxMerc = webMercator(lon: rawBounds.maxLon, lat: rawBounds.maxLat)
        let geoX = max(0.000001, maxMerc.x - minMerc.x)
        let geoY = max(0.000001, maxMerc.y - minMerc.y)
        let bedX = bedWidthMM - 2.0 * bufferMM
        let bedY = bedDepthMM - 2.0 * bufferMM
        let preliminaryScale = min(bedX / geoX, bedY / geoY)
        let smoothingDistanceM = Int(floor(bufferMM / preliminaryScale))

        let filtered = distanceFilter(raw, minimumDistanceM: Double(smoothingDistanceM))
        guard filtered.count >= 2 else { throw error("GPXtruder smoothing removed too many points") }

        let projectedRaw: [XYZE] = filtered.map { p in
            let m = webMercator(lon: p.lon, lat: p.lat)
            return XYZE(x: m.x, y: m.y, z: p.ele, raw: p)
        }

        let minX = projectedRaw.map(\.x).min() ?? 0
        let maxX = projectedRaw.map(\.x).max() ?? 0
        let minY = projectedRaw.map(\.y).min() ?? 0
        let maxY = projectedRaw.map(\.y).max() ?? 0
        let minZ = projectedRaw.map(\.z).min() ?? 0

        let xExtent = max(0.000001, maxX - minX)
        let yExtent = max(0.000001, maxY - minY)
        let scale = min(bedX / xExtent, bedY / yExtent)
        let offsetX = (minX + maxX) / 2.0
        let offsetY = (minY + maxY) / 2.0
        let offsetZ: Double
        if clipToMinimumElevation || minZ <= 0 {
            offsetZ = floor(minZ - 1.0)
        } else {
            offsetZ = 0
        }

        let output: [XYZE] = projectedRaw.map { p in
            XYZE(
                x: scale * (p.x - offsetX),
                y: scale * (p.y - offsetY),
                z: scale * (p.z - offsetZ) * verticalExaggeration + baseHeightMM,
                raw: p.raw
            )
        }

        let stations = processPath(output)
        guard stations.count >= 2 else { throw error("GPXtruder produced no usable route geometry") }

        let built = makeMeshAndRoute(
            stations: stations,
            scale: scale,
            elevationOffsetM: offsetZ
        )

        let bounds = meshBounds(built.mesh.vertices)
        let expectedTriangles = stations.count * 8 - 4
        let finite = built.mesh.vertices.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        }
        let countOK = built.mesh.triangles.count == expectedTriangles
        let routeOK = built.route.points.count == stations.count && built.route.totalDistanceM > 0
        let widthOK = stations.allSatisfy { s in
            hypot(s.leftX - s.rightX, s.leftY - s.rightY) <= pathWidthMM * 2.01
        }
        let checksPassed = finite && countOK && routeOK && widthOK
        let checkMessage = [
            finite ? "finite" : "non-finite vertices",
            countOK ? "topology" : "triangle count",
            routeOK ? "route mapping" : "route mapping failed",
            widthOK ? "joint width" : "joint width failed"
        ].joined(separator: ", ")

        let diagnostics = Diagnostics(
            inputPoints: raw.count,
            smoothingDistanceM: smoothingDistanceM,
            filteredPoints: filtered.count,
            centerlineStations: stations.count,
            triangleCount: built.mesh.triangles.count,
            modelWidthMM: bounds.maxX - bounds.minX,
            modelDepthMM: bounds.maxZ - bounds.minZ,
            modelHeightMM: bounds.maxY - bounds.minY,
            checksPassed: checksPassed,
            checkMessage: checkMessage
        )

        guard checksPassed else {
            throw error("GPXtruder geometry check failed: \(checkMessage)")
        }

        return Result(route: built.route, mesh: built.mesh, diagnostics: diagnostics)
    }

    // MARK: - GPX parser

    private func parseFirstTrack(url: URL) throws -> [RawPoint] {
        let data = try Data(contentsOf: url)
        let delegate = GPXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? error("Invalid GPX")
        }
        return delegate.points
    }

    private final class GPXDelegate: NSObject, XMLParserDelegate {
        var points: [RawPoint] = []
        private var inFirstTrack = false
        private var completedFirstTrack = false
        private var lat: Double?
        private var lon: Double?
        private var ele: Double?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            if elementName == "trk" && !completedFirstTrack && !inFirstTrack { inFirstTrack = true }
            guard inFirstTrack else { return }
            if elementName == "trkpt" {
                lat = attributeDict["lat"].flatMap(Double.init)
                lon = attributeDict["lon"].flatMap(Double.init)
                ele = nil
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard inFirstTrack else { return }
            if elementName == "ele" { ele = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if elementName == "trkpt", let lat, let lon, let ele {
                points.append(RawPoint(lat: lat, lon: lon, ele: ele))
                self.lat = nil; self.lon = nil; self.ele = nil
            }
            if elementName == "trk" {
                inFirstTrack = false
                completedFirstTrack = true
            }
            text = ""
        }
    }

    // MARK: - GPXtruder ScanPoints equivalent

    private func distanceFilter(_ points: [RawPoint], minimumDistanceM: Double) -> [RawPoint] {
        guard let first = points.first else { return [] }
        var kept = [first]
        for p in points.dropFirst() {
            guard let previous = kept.last else { break }
            let d = vincentyDistance(previous, p)
            if minimumDistanceM == 0 || d >= minimumDistanceM { kept.append(p) }
        }
        return kept
    }

    // WGS84 Vincenty inverse, matching GPXtruder's distance method.
    private func vincentyDistance(_ a: RawPoint, _ b: RawPoint) -> Double {
        let major = 6_378_137.0
        let flattening = 1.0 / 298.257223563
        let minor = (1.0 - flattening) * major
        let phi1 = a.lat * .pi / 180
        let phi2 = b.lat * .pi / 180
        let L = (b.lon - a.lon) * .pi / 180
        let U1 = atan((1 - flattening) * tan(phi1))
        let U2 = atan((1 - flattening) * tan(phi2))
        let sinU1 = sin(U1), cosU1 = cos(U1), sinU2 = sin(U2), cosU2 = cos(U2)
        var lambda = L
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0, sinAlpha = 0.0, cosSqAlpha = 0.0, cos2SigmaM = 0.0
        for _ in 0..<100 {
            let sinLambda = sin(lambda), cosLambda = cos(lambda)
            sinSigma = sqrt(pow(cosU2 * sinLambda, 2) + pow(cosU1 * sinU2 - sinU1 * cosU2 * cosLambda, 2))
            if sinSigma == 0 { return 0 }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cosSqAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha
            let C = flattening / 16 * cosSqAlpha * (4 + flattening * (4 - 3 * cosSqAlpha))
            let old = lambda
            lambda = L + (1 - C) * flattening * sinAlpha * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            if abs(lambda - old) < 1e-12 { break }
        }
        let uSq = cosSqAlpha * (major * major - minor * minor) / (minor * minor)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        return minor * A * (sigma - deltaSigma)
    }

    // MARK: - Projection + path geometry

    private func webMercator(lon: Double, lat: Double) -> (x: Double, y: Double) {
        let radius = 6_378_137.0
        let safeLat = min(85.05112878, max(-85.05112878, lat))
        return (
            radius * lon * .pi / 180,
            radius * log(tan(.pi / 4 + safeLat * .pi / 360))
        )
    }

    private func geographicBounds(_ p: [RawPoint]) -> (minLon: Double, maxLon: Double, minLat: Double, maxLat: Double) {
        (p.map(\.lon).min() ?? 0, p.map(\.lon).max() ?? 0, p.map(\.lat).min() ?? 0, p.map(\.lat).max() ?? 0)
    }

    private func processPath(_ p: [XYZE]) -> [EdgeStation] {
        func angle(_ i: Int) -> Double {
            if i + 1 == p.count { return angle(i - 1) }
            return atan2(p[i + 1].y - p[i].y, p[i + 1].x - p[i].x)
        }
        func acute(_ a: Double) -> Bool {
            let v = abs(a)
            return v > .pi / 2 && v < 3 * .pi / 2
        }

        var stations: [EdgeStation] = []
        var lastAngle = angle(0)
        for i in p.indices {
            let a = angle(i)
            let rel = a - lastAngle
            let joint = rel / 2 + lastAngle
            if acute(rel) && i < p.count - 1 && acute(angle(i + 1) - a) { continue }

            var joinRadius = bufferMM / cos(rel / 2)
            if abs(joinRadius) > bufferMM * 2 {
                joinRadius = (joinRadius < 0 ? -1 : 1) * bufferMM * 2
            }
            let lx = p[i].x + joinRadius * cos(joint + .pi / 2)
            let ly = p[i].y + joinRadius * sin(joint + .pi / 2)
            let rx = p[i].x + joinRadius * cos(joint - .pi / 2)
            let ry = p[i].y + joinRadius * sin(joint - .pi / 2)
            stations.append(EdgeStation(leftX: lx, leftY: ly, rightX: rx, rightY: ry, z: p[i].z, raw: p[i].raw))
            lastAngle = a
        }
        return stations
    }

    private func makeMeshAndRoute(stations: [EdgeStation], scale: Double, elevationOffsetM: Double) -> (mesh: Climb3DMesh, route: Climb3DRoute) {
        var vertices: [Climb3DVertex] = []
        var visual: [Climb3DVertex] = []
        var center: [Climb3DVertex] = []
        var routePoints: [Climb3DRoutePoint] = []
        var grades: [Double] = []
        var cumulative = 0.0

        for i in stations.indices {
            let s = stations[i]
            // SceneKit axes: GPXtruder X -> X, GPXtruder Z -> Y(vertical), GPXtruder Y -> -Z.
            let tl = Climb3DVertex(x: Float(s.leftX), y: Float(s.z), z: Float(-s.leftY))
            let tr = Climb3DVertex(x: Float(s.rightX), y: Float(s.z), z: Float(-s.rightY))
            let bl = Climb3DVertex(x: Float(s.leftX), y: 0, z: Float(-s.leftY))
            let br = Climb3DVertex(x: Float(s.rightX), y: 0, z: Float(-s.rightY))
            vertices.append(contentsOf: [tl, tr, bl, br])
            visual.append(contentsOf: [tl, tr])

            let c = Climb3DVertex(
                x: Float((s.leftX + s.rightX) / 2),
                y: Float(s.z),
                z: Float(-(s.leftY + s.rightY) / 2)
            )
            center.append(c)

            if i > 0 { cumulative += vincentyDistance(stations[i - 1].raw, s.raw) }
            let realElevation = (s.z - baseHeightMM) / (scale * verticalExaggeration) + elevationOffsetM
            routePoints.append(Climb3DRoutePoint(latitude: s.raw.lat, longitude: s.raw.lon, elevationM: realElevation, distanceM: cumulative))
        }

        var triangles: [Climb3DTriangle] = []
        func idx(_ i: Int, _ o: Int) -> Int32 { Int32(i * 4 + o) }
        for i in 0..<(stations.count - 1) {
            triangles.append(contentsOf: [
                Climb3DTriangle(a: idx(i,0), b: idx(i,1), c: idx(i+1,0)),
                Climb3DTriangle(a: idx(i,1), b: idx(i+1,1), c: idx(i+1,0)),
                Climb3DTriangle(a: idx(i,2), b: idx(i,0), c: idx(i+1,2)),
                Climb3DTriangle(a: idx(i,0), b: idx(i+1,0), c: idx(i+1,2)),
                Climb3DTriangle(a: idx(i,1), b: idx(i,3), c: idx(i+1,1)),
                Climb3DTriangle(a: idx(i,3), b: idx(i+1,3), c: idx(i+1,1)),
                Climb3DTriangle(a: idx(i,2), b: idx(i+1,2), c: idx(i,3)),
                Climb3DTriangle(a: idx(i,3), b: idx(i+1,2), c: idx(i+1,3))
            ])

            let a = stations[i], b = stations[i+1]
            let horizontalMM = hypot(
                (b.leftX+b.rightX-a.leftX-a.rightX)/2,
                (b.leftY+b.rightY-a.leftY-a.rightY)/2
            )
            let realRiseM = (b.z - a.z) / (scale * verticalExaggeration)
            let realRunM = horizontalMM / scale
            grades.append(realRunM > 0.001 ? realRiseM / realRunM * 100 : 0)
        }
        triangles.append(contentsOf: [
            Climb3DTriangle(a: idx(0,2), b: idx(0,1), c: idx(0,0)),
            Climb3DTriangle(a: idx(0,2), b: idx(0,3), c: idx(0,1))
        ])
        let last = stations.count - 1
        triangles.append(contentsOf: [
            Climb3DTriangle(a: idx(last,0), b: idx(last,1), c: idx(last,2)),
            Climb3DTriangle(a: idx(last,1), b: idx(last,3), c: idx(last,2))
        ])

        let mesh = Climb3DMesh(vertices: vertices, triangles: triangles, centerline: center, visualVertices: visual, visualSegmentGrades: grades)
        let route = Climb3DRoute(points: routePoints, totalDistanceM: cumulative)
        return (mesh, route)
    }

    private func meshBounds(_ v: [Climb3DVertex]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double) {
        let xs = v.map { Double($0.x) }, ys = v.map { Double($0.y) }, zs = v.map { Double($0.z) }
        return (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0, zs.min() ?? 0, zs.max() ?? 0)
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "Climb3D.GPXtruder", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
