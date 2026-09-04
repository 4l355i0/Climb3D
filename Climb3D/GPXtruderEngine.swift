import Foundation
import JavaScriptCore

// Executes the GPXtruder Map/GOOGLE/Automatic geometry algorithm in JavaScript.
// The geometry-producing logic is kept in gpxtruder_core.js so it is not
// reinterpreted in Swift. Swift only parses GPX, invokes JS and maps the
// returned mesh into Climb3D types.
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
            return "GPXtruder JS • \(inputPoints)→\(filteredPoints)→\(centerlineStations) • \(check)"
        }
    }

    struct Result {
        let route: Climb3DRoute
        let sceneMesh: Climb3DMesh
        let stlMesh: Climb3DMesh
        let diagnostics: Diagnostics
    }

    private struct RawPoint {
        let lat: Double
        let lon: Double
        let ele: Double
    }

    private struct JSInput: Encodable {
        let points: [[Double]]
        let options: JSOptions
    }

    private struct JSOptions: Encodable {
        let buffer = 1.0
        let vertical = 5.0
        let bedx = 90.0
        let bedy = 90.0
        let base = 1.0
        let zcut = true
        let smoothtype = 0
        let smoothspan = 0.0
    }

    private struct JSStation: Decodable {
        let left: [Double]
        let right: [Double]
        let z: Double
        let raw: [Double]
    }

    private struct JSOutput: Decodable {
        let inputPoints: Int
        let smoothingDistanceM: Int
        let filteredPoints: Int
        let stations: [JSStation]
        let centerline: [[Double]]
        let vertices: [[Double]]
        let faces: [[Int]]
        let scale: Double
        let offset: [Double]
        let distance: Double
        let smoothTotal: Double
    }

    private let verticalExaggeration = 5.0
    private let baseHeightMM = 1.0

    func build(url: URL) throws -> Result {
        let raw = try parseFirstTrack(url: url)
        guard raw.count >= 2 else { throw error("GPX route too short") }

        let js = try runExactJavaScript(raw)
        guard js.stations.count >= 2 else { throw error("GPXtruder produced no usable geometry") }
        guard js.scale.isFinite, js.scale > 0 else { throw error("GPXtruder returned invalid scale") }
        guard js.offset.count >= 3 else { throw error("GPXtruder returned invalid offset") }

        let stlMesh = try makeSTLMesh(js)
        let built = try makeSceneMeshAndRoute(js)

        let bounds = meshBounds(stlMesh.vertices)
        let finite = stlMesh.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        let topologyOK = js.faces.count == js.stations.count * 8 - 4
        let countOK = js.vertices.count == js.stations.count * 4
        let routeOK = built.route.points.count == js.stations.count && built.route.totalDistanceM > 0
        let centerlineOK = js.centerline.count == js.stations.count
        let checksPassed = finite && topologyOK && countOK && routeOK && centerlineOK
        let checkMessage = [
            finite ? "finite" : "non-finite",
            topologyOK ? "topology" : "face count",
            countOK ? "4 vertices/station" : "vertex count",
            centerlineOK ? "centerline" : "centerline mismatch",
            routeOK ? "metric mapping" : "metric mapping failed"
        ].joined(separator: ", ")

        guard checksPassed else {
            throw error("GPXtruder JS geometry check failed: \(checkMessage)")
        }

        let diagnostics = Diagnostics(
            inputPoints: js.inputPoints,
            smoothingDistanceM: js.smoothingDistanceM,
            filteredPoints: js.filteredPoints,
            centerlineStations: js.stations.count,
            triangleCount: js.faces.count,
            modelWidthMM: bounds.maxX - bounds.minX,
            modelDepthMM: bounds.maxZ - bounds.minZ,
            modelHeightMM: bounds.maxY - bounds.minY,
            checksPassed: checksPassed,
            checkMessage: checkMessage
        )

        return Result(
            route: built.route,
            sceneMesh: built.mesh,
            stlMesh: stlMesh,
            diagnostics: diagnostics
        )
    }

    // MARK: - JavaScriptCore

    private func runExactJavaScript(_ raw: [RawPoint]) throws -> JSOutput {
        guard let scriptURL = Bundle.main.url(forResource: "gpxtruder_core", withExtension: "js") else {
            throw error("Missing embedded gpxtruder_core.js")
        }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        guard let context = JSContext() else {
            throw error("Unable to create JavaScriptCore context")
        }

        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString() ?? "Unknown JavaScript error"
        }

        context.evaluateScript(script)
        if let jsError { throw error("GPXtruder JS load error: \(jsError)") }

        guard let function = context.objectForKeyedSubscript("gpxtruderBuildJSON"), !function.isUndefined else {
            throw error("gpxtruderBuildJSON not found in embedded script")
        }

        let input = JSInput(
            points: raw.map { [$0.lon, $0.lat, $0.ele] },
            options: JSOptions()
        )
        let inputData = try JSONEncoder().encode(input)
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw error("Unable to encode GPXtruder input")
        }

        let value = function.call(withArguments: [inputJSON])
        if let jsError { throw error("GPXtruder JS execution error: \(jsError)") }
        guard let outputJSON = value?.toString(), let outputData = outputJSON.data(using: .utf8) else {
            throw error("GPXtruder JS returned no result")
        }

        return try JSONDecoder().decode(JSOutput.self, from: outputData)
    }

    // MARK: - GPX parser (only transport into GPXtruder JS)

    private func parseFirstTrack(url: URL) throws -> [RawPoint] {
        let data = try Data(contentsOf: url)
        let delegate = GPXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? error("Invalid GPX") }
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
            if elementName == "trk" { inFirstTrack = false; completedFirstTrack = true }
            text = ""
        }
    }

    // MARK: - Exact STL mesh from JavaScript output (millimetres)

    private func makeSTLMesh(_ js: JSOutput) throws -> Climb3DMesh {
        let vertices = try js.vertices.map { v -> Climb3DVertex in
            guard v.count >= 3 else { throw error("Invalid GPXtruder vertex") }
            // SceneKit axis convention while preserving numerical GPXtruder mm.
            return Climb3DVertex(x: Float(v[0]), y: Float(v[2]), z: Float(-v[1]))
        }
        let triangles = try js.faces.map { f -> Climb3DTriangle in
            guard f.count >= 3 else { throw error("Invalid GPXtruder face") }
            return Climb3DTriangle(a: Int32(f[0]), b: Int32(f[1]), c: Int32(f[2]))
        }
        let center = try js.centerline.map { p -> Climb3DVertex in
            guard p.count >= 3 else { throw error("Invalid GPXtruder centerline") }
            return Climb3DVertex(x: Float(p[0]), y: Float(p[2]), z: Float(-p[1]))
        }
        var visual: [Climb3DVertex] = []
        for s in js.stations {
            guard s.left.count >= 2, s.right.count >= 2 else { throw error("Invalid GPXtruder station") }
            visual.append(Climb3DVertex(x: Float(s.left[0]), y: Float(s.z), z: Float(-s.left[1])))
            visual.append(Climb3DVertex(x: Float(s.right[0]), y: Float(s.z), z: Float(-s.right[1])))
        }
        return Climb3DMesh(vertices: vertices, triangles: triangles, centerline: center, visualVertices: visual, visualSegmentGrades: [])
    }

    // MARK: - Same GPXtruder geometry mapped back to real metres for Climb3D camera

    private func makeSceneMeshAndRoute(_ js: JSOutput) throws -> (mesh: Climb3DMesh, route: Climb3DRoute) {
        let scale = js.scale
        let elevationOffset = js.offset[2]

        // IMPORTANT: GPXtruder itself remains untouched. From here on we only
        // derive a rideable/renderable centreline from its exact output.
        struct Sample {
            var x: Double
            var y: Double
            var z: Double
            var lat: Double
            var lon: Double
        }

        guard js.centerline.count == js.stations.count else {
            throw error("GPXtruder centerline/station mismatch")
        }

        // 1) Exact GPXtruder medial line, mapped back to real metres.
        var source: [Sample] = []
        source.reserveCapacity(js.stations.count)
        for i in js.stations.indices {
            let c = js.centerline[i]
            let st = js.stations[i]
            guard c.count >= 3, st.raw.count >= 3 else { throw error("Invalid GPXtruder centreline") }
            source.append(Sample(
                x: c[0] / scale,
                y: (c[2] - baseHeightMM) / (scale * verticalExaggeration),
                z: -c[1] / scale,
                lat: st.raw[1],
                lon: st.raw[0]
            ))
        }

        // 2) Densify the GPXtruder centreline every 5 m. This is linear along
        // the exact centreline: it adds resolution but does not invent XY bends.
        let spacingM = 5.0
        var sourceD = Array(repeating: 0.0, count: source.count)
        for i in 1..<source.count {
            sourceD[i] = sourceD[i - 1] + hypot(source[i].x - source[i - 1].x, source[i].z - source[i - 1].z)
        }
        let total = sourceD.last ?? 0
        guard total > 0 else { throw error("Zero-length GPXtruder centreline") }

        var dense: [Sample] = []
        var target = 0.0
        var seg = 1
        while target < total {
            while seg < sourceD.count - 1 && sourceD[seg] < target { seg += 1 }
            let d0 = sourceD[seg - 1], d1 = sourceD[seg]
            let t = d1 > d0 ? (target - d0) / (d1 - d0) : 0
            let a = source[seg - 1], b = source[seg]
            dense.append(Sample(
                x: a.x + (b.x - a.x) * t,
                y: a.y + (b.y - a.y) * t,
                z: a.z + (b.z - a.z) * t,
                lat: a.lat + (b.lat - a.lat) * t,
                lon: a.lon + (b.lon - a.lon) * t
            ))
            target += spacingM
        }
        if let last = source.last { dense.append(last) }

        // 3) Smooth ONLY elevation versus travelled distance. A symmetric
        // 50 m triangular window removes station-to-station grade steps while
        // leaving the plan-view geometry and hairpins exactly where GPXtruder put them.
        let rawY = dense.map(\.y)
        let radius = 5 // 5 samples each side = 25 m; full window ~50 m.
        var smoothY = rawY
        if dense.count > 2 {
            for i in dense.indices {
                var weighted = 0.0, weights = 0.0
                let lo = max(0, i - radius), hi = min(dense.count - 1, i + radius)
                for j in lo...hi {
                    let w = Double(radius + 1 - abs(j - i))
                    weighted += rawY[j] * w
                    weights += w
                }
                smoothY[i] = weighted / weights
            }
            // Preserve exact start/end elevation and distribute the tiny endpoint
            // correction continuously so total climbing height is unchanged.
            let startDelta = rawY[0] - smoothY[0]
            let endDelta = rawY[rawY.count - 1] - smoothY[smoothY.count - 1]
            let denom = Double(max(1, smoothY.count - 1))
            for i in smoothY.indices {
                let t = Double(i) / denom
                smoothY[i] += startDelta * (1 - t) + endDelta * t
                dense[i].y = smoothY[i]
            }
        }

        // 4) Build a narrow app road around the cleaned centreline. We do NOT
        // render GPXtruder's 2 mm STL miter ribbon because, when scaled back to
        // metres, its corner miters become the triangular spikes seen in B20.
        let roadHalfWidthM = 3.0
        var visual: [Climb3DVertex] = []
        var center: [Climb3DVertex] = []
        var grades: [Double] = []
        var routePoints: [Climb3DRoutePoint] = []
        visual.reserveCapacity(dense.count * 2)
        center.reserveCapacity(dense.count)

        var cumulative = 0.0
        for i in dense.indices {
            let p = dense[i]
            center.append(Climb3DVertex(x: Float(p.x), y: Float(p.y), z: Float(p.z)))

            let prev = dense[max(0, i - 1)]
            let next = dense[min(dense.count - 1, i + 1)]
            var tx = next.x - prev.x, tz = next.z - prev.z
            let tl = hypot(tx, tz)
            if tl > 0.0001 { tx /= tl; tz /= tl } else { tx = 1; tz = 0 }
            let nx = -tz, nz = tx
            visual.append(Climb3DVertex(x: Float(p.x + nx * roadHalfWidthM), y: Float(p.y), z: Float(p.z + nz * roadHalfWidthM)))
            visual.append(Climb3DVertex(x: Float(p.x - nx * roadHalfWidthM), y: Float(p.y), z: Float(p.z - nz * roadHalfWidthM)))

            if i > 0 {
                let a = dense[i - 1]
                let run = hypot(p.x - a.x, p.z - a.z)
                cumulative += run
                grades.append(run > 0.001 ? (p.y - a.y) / run * 100.0 : 0)
            }

            routePoints.append(Climb3DRoutePoint(
                latitude: p.lat,
                longitude: p.lon,
                elevationM: p.y + elevationOffset,
                distanceM: cumulative
            ))
        }

        // STL/export remains the exact GPXtruder mesh. Scene rendering uses the
        // cleaned ride centreline and app road only.
        let exactVertices = try js.vertices.map { v -> Climb3DVertex in
            guard v.count >= 3 else { throw error("Invalid GPXtruder vertex") }
            return Climb3DVertex(
                x: Float(v[0] / scale),
                y: Float((v[2] - baseHeightMM) / (scale * verticalExaggeration)),
                z: Float(-v[1] / scale)
            )
        }
        let exactTriangles = try js.faces.map { f -> Climb3DTriangle in
            guard f.count >= 3 else { throw error("Invalid GPXtruder face") }
            return Climb3DTriangle(a: Int32(f[0]), b: Int32(f[1]), c: Int32(f[2]))
        }

        let mesh = Climb3DMesh(
            vertices: exactVertices,
            triangles: exactTriangles,
            centerline: center,
            visualVertices: visual,
            visualSegmentGrades: grades
        )
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

