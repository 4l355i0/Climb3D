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

    let sceneController = Climb3DSceneController()

    private(set) var route: Climb3DRoute?
    private var mesh: Climb3DMesh?

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

        let parsed = try Climb3DGPXParser().parse(url: url)
        let generated = try Climb3DMeshBuilder().build(from: parsed)

        route = parsed
        mesh = generated

        sceneController.setMesh(
            generated,
            route: parsed
        )

        hasGPX = true
        hasMesh = true

        progress = 0

        status = String(
            format: "3D climb created • %.1f km",
            parsed.totalDistanceM / 1000
        )
    }

    func exportSTL() throws -> URL {
        guard let mesh else {
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

    func resetCamera() {
        sceneController.resetCamera()
    }
}
