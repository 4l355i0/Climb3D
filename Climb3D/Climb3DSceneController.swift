import Foundation
import SceneKit
import UIKit

@MainActor
final class Climb3DSceneController {

    let scene = SCNScene()

    private weak var view: SCNView?

    private let meshNode = SCNNode()
    private let routeNode = SCNNode()
    private let markerNode: SCNNode

    private let cameraNode = SCNNode()
    private let keyLightNode = SCNNode()
    private let ambientNode = SCNNode()

    private var mesh: Climb3DMesh?
    private var route: Climb3DRoute?

    // Camera state
    private var cameraTarget = SCNVector3Zero
    private var cameraDistance: Float = 500
    private var overviewDistance: Float = 500

    private var yaw: Float = 0
    private var pitch: Float = .pi / 4

    private var modelSpan: Float = 500
    private var routeVisualRadius: CGFloat = 2

    init() {

        // Unit sphere: its visual size will be scaled
        // according to camera distance.
        let markerGeometry = SCNSphere(radius: 1.0)

        markerGeometry.segmentCount = 24
        markerGeometry.firstMaterial?.diffuse.contents =
            UIColor.systemRed
        markerGeometry.firstMaterial?.emission.contents =
            UIColor.systemRed.withAlphaComponent(0.45)
        markerGeometry.firstMaterial?.lightingModel =
            .physicallyBased

        markerNode = SCNNode(geometry: markerGeometry)
        markerNode.isHidden = true

        scene.rootNode.addChildNode(meshNode)
        scene.rootNode.addChildNode(routeNode)
        scene.rootNode.addChildNode(markerNode)

        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.1
        camera.zFar = 1_000_000

        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1500
        scene.rootNode.addChildNode(keyLightNode)

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 600
        ambientNode.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientNode)

        scene.background.contents = UIColor.systemBackground
    }

    // MARK: - Attach

    func attach(to view: SCNView) {
        self.view = view
        view.pointOfView = cameraNode

        if mesh != nil {
            resetCamera()
        }
    }

    // MARK: - Mesh

    func setMesh(
        _ mesh: Climb3DMesh,
        route: Climb3DRoute
    ) {
        self.mesh = mesh
        self.route = route

        meshNode.geometry = mesh.sceneGeometry()

        calculateModelMetrics(mesh)
        rebuildRoute(mesh.centerline)

        markerNode.isHidden = false

        updateProgress(0)
        resetCamera()
    }

    private func calculateModelMetrics(
        _ mesh: Climb3DMesh
    ) {
        guard !mesh.vertices.isEmpty else {
            return
        }

        let xs = mesh.vertices.map(\.x)
        let ys = mesh.vertices.map(\.y)
        let zs = mesh.vertices.map(\.z)

        guard
            let minX = xs.min(),
            let maxX = xs.max(),
            let minY = ys.min(),
            let maxY = ys.max(),
            let minZ = zs.min(),
            let maxZ = zs.max()
        else {
            return
        }

        let sx = maxX - minX
        let sy = maxY - minY
        let sz = maxZ - minZ

        modelSpan = max(
            50,
            max(
                sx,
                max(sz, sy * 1.3)
            )
        )

        cameraTarget = SCNVector3(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            (minZ + maxZ) / 2
        )

        /*
         Visual route line scales with route size.
         This keeps it visible on long GPX tracks.
        */
        routeVisualRadius = CGFloat(
            max(
                1.5,
                min(
                    8.0,
                    modelSpan * 0.0015
                )
            )
        )

        /*
         Estimate dominant horizontal direction
         of the route using 2D covariance / PCA.
        */
        if mesh.centerline.count >= 2 {

            let count =
                Float(mesh.centerline.count)

            let meanX =
                mesh.centerline.reduce(Float(0)) {
                    $0 + $1.x
                } / count

            let meanZ =
                mesh.centerline.reduce(Float(0)) {
                    $0 + $1.z
                } / count

            var xx: Float = 0
            var zz: Float = 0
            var xz: Float = 0

            for point in mesh.centerline {
                let dx = point.x - meanX
                let dz = point.z - meanZ

                xx += dx * dx
                zz += dz * dz
                xz += dx * dz
            }

            let majorAxis =
                0.5 *
                atan2(
                    2 * xz,
                    xx - zz
                )

            /*
             Look diagonally across the dominant
             route axis rather than straight along it.
            */
            yaw =
                majorAxis +
                .pi / 4
        }
    }

    // MARK: - Progress

    func updateProgress(
        _ progress: Double
    ) {
        guard
            let mesh,
            let route,
            !mesh.centerline.isEmpty,
            !route.points.isEmpty
        else {
            markerNode.isHidden = true
            return
        }

        let p =
            min(
                1,
                max(
                    0,
                    progress
                )
            )

        let targetDistance =
            p *
            route.totalDistanceM

        if targetDistance <= 0 {
            setMarker(
                at: mesh.centerline[0]
            )
            return
        }

        if targetDistance >= route.totalDistanceM {
            setMarker(
                at: mesh.centerline[
                    mesh.centerline.count - 1
                ]
            )
            return
        }

        var low = 0

        var high =
            min(
                route.points.count,
                mesh.centerline.count
            ) - 1

        while low + 1 < high {

            let middle =
                (low + high) / 2

            if route.points[middle].distanceM <
                targetDistance {

                low = middle

            } else {

                high = middle
            }
        }

        let routeA =
            route.points[low]

        let routeB =
            route.points[high]

        let pointA =
            mesh.centerline[low]

        let pointB =
            mesh.centerline[high]

        let segmentDistance =
            max(
                0.001,
                routeB.distanceM -
                routeA.distanceM
            )

        let t =
            Float(
                (
                    targetDistance -
                    routeA.distanceM
                ) /
                segmentDistance
            )

        let position =
            Climb3DVertex(
                x:
                    pointA.x +
                    (pointB.x - pointA.x) * t,

                y:
                    pointA.y +
                    (pointB.y - pointA.y) * t,

                z:
                    pointA.z +
                    (pointB.z - pointA.z) * t
            )

        setMarker(at: position)
    }

    private func setMarker(
        at point: Climb3DVertex
    ) {
        markerNode.position =
            SCNVector3(
                point.x,
                point.y + 4,
                point.z
            )

        markerNode.isHidden = false

        updateMarkerScale()
    }

    // MARK: - Camera

    func resetCamera() {
        guard let mesh,
              !mesh.vertices.isEmpty
        else {
            return
        }

        calculateModelMetrics(mesh)

        /*
         Start closer than the old implementation.
         Then refine using the actual projected size.
        */
        pitch = 52 * .pi / 180

        cameraDistance =
            modelSpan * 0.90

        overviewDistance =
            cameraDistance

        applyCamera()

        /*
         Once the view has dimensions, refine the
         distance so the route occupies ~78% of it.
        */
        fitCameraToModel()

        overviewDistance =
            cameraDistance
    }

    private func fitCameraToModel() {
        guard
            let view,
            let mesh,
            view.bounds.width > 10,
            view.bounds.height > 10
        else {
            updateMarkerScale()
            return
        }

        for _ in 0..<4 {

            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude

            for vertex in mesh.vertices {

                let projected =
                    view.projectPoint(
                        SCNVector3(
                            vertex.x,
                            vertex.y,
                            vertex.z
                        )
                    )

                guard
                    projected.x.isFinite,
                    projected.y.isFinite
                else {
                    continue
                }

                minX = min(
                    minX,
                    CGFloat(projected.x)
                )

                maxX = max(
                    maxX,
                    CGFloat(projected.x)
                )

                minY = min(
                    minY,
                    CGFloat(projected.y)
                )

                maxY = max(
                    maxY,
                    CGFloat(projected.y)
                )
            }

            let projectedWidth =
                maxX - minX

            let projectedHeight =
                maxY - minY

            guard
                projectedWidth > 1,
                projectedHeight > 1
            else {
                break
            }

            let targetWidth =
                view.bounds.width * 0.78

            let targetHeight =
                view.bounds.height * 0.76

            let scale =
                max(
                    projectedWidth /
                    targetWidth,

                    projectedHeight /
                    targetHeight
                )

            if abs(scale - 1) < 0.03 {
                break
            }

            cameraDistance *=
                Float(scale)

            cameraDistance =
                clamp(
                    cameraDistance,
                    min: modelSpan * 0.18,
                    max: modelSpan * 4.0
                )

            applyCamera()
        }

        updateMarkerScale()
    }

    func orbit(
        deltaX: CGFloat,
        deltaY: CGFloat
    ) {
        yaw -=
            Float(deltaX) * 0.006

        pitch +=
            Float(deltaY) * 0.006

        pitch =
            clamp(
                pitch,
                min: 15 * .pi / 180,
                max: 82 * .pi / 180
            )

        applyCamera()
    }

    func zoom(
        scale: CGFloat
    ) {
        guard scale > 0 else {
            return
        }

        cameraDistance /=
            Float(scale)

        cameraDistance =
            clamp(
                cameraDistance,
                min: max(25, modelSpan * 0.035),
                max: modelSpan * 5
            )

        applyCamera()
    }

    func focusOnMarker() {
        guard !markerNode.isHidden else {
            return
        }

        cameraTarget =
            markerNode.position

        cameraDistance =
            max(
                70,
                modelSpan * 0.16
            )

        pitch =
            46 * .pi / 180

        applyCamera()
    }

    private func applyCamera() {

        let horizontalDistance =
            cameraDistance *
            cos(pitch)

        let verticalDistance =
            cameraDistance *
            sin(pitch)

        let x =
            cameraTarget.x +
            horizontalDistance *
            sin(yaw)

        let z =
            cameraTarget.z +
            horizontalDistance *
            cos(yaw)

        let y =
            cameraTarget.y +
            verticalDistance

        cameraNode.position =
            SCNVector3(
                x,
                y,
                z
            )

        cameraNode.look(
            at: cameraTarget
        )

        keyLightNode.position =
            SCNVector3(
                cameraTarget.x +
                    modelSpan * 0.4,

                cameraTarget.y +
                    modelSpan * 0.7,

                cameraTarget.z +
                    modelSpan * 0.4
            )

        view?.pointOfView =
            cameraNode

        updateMarkerScale()
    }

    private func updateMarkerScale() {

        /*
         Marker size follows camera distance,
         giving approximately constant apparent
         size on screen.
        */
        let visualRadius =
            clamp(
                cameraDistance * 0.006,
                min: 4,
                max: 40
            )

        markerNode.scale =
            SCNVector3(
                visualRadius,
                visualRadius,
                visualRadius
            )
    }

    // MARK: - Route

    private func rebuildRoute(
        _ points: [Climb3DVertex]
    ) {
        routeNode.childNodes.forEach {
            $0.removeFromParentNode()
        }

        guard points.count >= 2 else {
            return
        }

        for index in 1..<points.count {

            let a =
                points[index - 1]

            let b =
                points[index]

            let start =
                SCNVector3(
                    a.x,
                    a.y + 1,
                    a.z
                )

            let end =
                SCNVector3(
                    b.x,
                    b.y + 1,
                    b.z
                )

            routeNode.addChildNode(
                lineNode(
                    from: start,
                    to: end
                )
            )
        }
    }

    private func lineNode(
        from a: SCNVector3,
        to b: SCNVector3
    ) -> SCNNode {

        let dx = b.x - a.x
        let dy = b.y - a.y
        let dz = b.z - a.z

        let length =
            sqrt(
                dx * dx +
                dy * dy +
                dz * dz
            )

        let cylinder =
            SCNCylinder(
                radius: routeVisualRadius,
                height: CGFloat(length)
            )

        cylinder.radialSegmentCount = 8

        cylinder.firstMaterial?.diffuse.contents =
            UIColor.systemBlue

        cylinder.firstMaterial?.emission.contents =
            UIColor.systemBlue
                .withAlphaComponent(0.16)

        let node =
            SCNNode(
                geometry: cylinder
            )

        node.position =
            SCNVector3(
                (a.x + b.x) / 2,
                (a.y + b.y) / 2,
                (a.z + b.z) / 2
            )

        node.look(
            at: b,
            up: SCNVector3(
                0,
                1,
                0
            ),
            localFront: SCNVector3(
                0,
                1,
                0
            )
        )

        return node
    }

    // MARK: - Helpers

    private func clamp(
        _ value: Float,
        min minValue: Float,
        max maxValue: Float
    ) -> Float {

        Swift.max(
            minValue,
            Swift.min(
                maxValue,
                value
            )
        )
    }
}
