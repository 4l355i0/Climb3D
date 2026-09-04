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

        func sceneVertex(_ v: [Double]) throws -> Climb3DVertex {
            guard v.count >= 3 else { throw error("Invalid GPXtruder vertex") }
            return Climb3DVertex(
                x: Float(v[0] / scale),
                y: Float((v[2] - baseHeightMM) / (scale * verticalExaggeration)),
                z: Float(-v[1] / scale)
            )
        }

        let vertices = try js.vertices.map(sceneVertex)
        let triangles = try js.faces.map { f -> Climb3DTriangle in
            guard f.count >= 3 else { throw error("Invalid GPXtruder face") }
            return Climb3DTriangle(a: Int32(f[0]), b: Int32(f[1]), c: Int32(f[2]))
        }
        let center = try js.centerline.map(sceneVertex)

        var visual: [Climb3DVertex] = []
        var routePoints: [Climb3DRoutePoint] = []
        var grades: [Double] = []
        var cumulative = 0.0

        for i in js.stations.indices {
            let s = js.stations[i]
            guard s.left.count >= 2, s.right.count >= 2, s.raw.count >= 3 else {
                throw error("Invalid GPXtruder station")
            }
            let left = try sceneVertex([s.left[0], s.left[1], s.z])
            let right = try sceneVertex([s.right[0], s.right[1], s.z])
            visual.append(left); visual.append(right)

            if i > 0 {
                let a = center[i - 1], b = center[i]
                cumulative += hypot(Double(b.x - a.x), Double(b.z - a.z))
                let run = hypot(Double(b.x - a.x), Double(b.z - a.z))
                let rise = Double(b.y - a.y)
                grades.append(run > 0.001 ? rise / run * 100.0 : 0)
            }

            let absoluteElevation = (s.z - baseHeightMM) / (scale * verticalExaggeration) + elevationOffset
            routePoints.append(
                Climb3DRoutePoint(
                    latitude: s.raw[1],
                    longitude: s.raw[0],
                    elevationM: absoluteElevation,
                    distanceM: cumulative
                )
            )
        }

        let mesh = Climb3DMesh(
            vertices: vertices,
            triangles: triangles,
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
