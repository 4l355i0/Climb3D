import Foundation

@MainActor
final class Climb3DModel: ObservableObject {
    @Published var progress: Double = 0 {
        didSet {
            sceneController.updateProgress(progress)
        }
    }

    @Published var status = "Load a GPX to create the 3D climb"
    @Published private(set) var hasGPX = false
    @Published private(set) var hasMesh = false
    @Published private(set) var geometryChecks = ""

    let sceneController = Climb3DSceneController()

    private(set) var route: Climb3DRoute?
    private var mesh: Climb3DMesh?
    private var stlMesh: Climb3DMesh?

    var currentDistanceM: Double {
        guard let route else { return 0 }
        return route.distance(at: progress)
    }

    var remainingDistanceM: Double {
        guard let route else { return 0 }
        return route.remainingDistance(at: progress)
    }

    var currentElevationM: Double {
        guard let route else { return 0 }
        return route.elevation(at: progress)
    }

    var currentGradePercent: Double {
        guard let route else { return 0 }
        return route.gradePercent(at: progress)
    }

    func loadGPXAndBuild3D(url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()

        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let result = try GPXtruderEngine().build(url: url)
        let parsed = result.route
        let generated = result.sceneMesh

        route = parsed
        mesh = generated
        stlMesh = result.stlMesh
        geometryChecks = String(
            format: "Auto %dm • %d stations • %.1f×%.1f×%.1f mm • %@",
            result.diagnostics.smoothingDistanceM,
            result.diagnostics.centerlineStations,
            result.diagnostics.modelWidthMM,
            result.diagnostics.modelDepthMM,
            result.diagnostics.modelHeightMM,
            result.diagnostics.checksPassed ? "CHECKS OK" : "CHECK FAILED"
        )

        sceneController.setMesh(
            generated,
            route: parsed
        )

        hasGPX = true
        hasMesh = true

        progress = 0

        status = String(
            format: "GPXtruder exact JS • %.1f km",
            parsed.totalDistanceM / 1000
        )
    }

    func exportSTL() throws -> URL {
        guard let mesh = stlMesh else {
            throw NSError(
                domain: "Climb3D",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No 3D mesh available"
                ]
            )
        }

        return try STLWriter().write(
            mesh: mesh,
            filename: "Climb3D"
        )
    }

    func showOverview() {
        sceneController.showOverview()
    }

    func resetCamera() {
        sceneController.resetCamera()
    }
}
