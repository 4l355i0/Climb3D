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

    private var currentProgress: Double = 0

    // MARK: - Follow camera settings

    private let cameraBehindM: Double = 110
    private let cameraHeightM: Double = 50
    private let lookAheadM: Double = 160
    private let targetLiftM: Double = 8

    private var followMode = true

    init() {

        let markerGeometry = SCNSphere(radius: 5.0)
        markerGeometry.segmentCount = 24

        markerGeometry.firstMaterial?.diffuse.contents =
            UIColor.systemRed

        markerGeometry.firstMaterial?.emission.contents =
            UIColor.systemRed.withAlphaComponent(0.45)

        markerGeometry.firstMaterial?.lightingModel =
            .physicallyBased

        markerNode = SCNNode(
            geometry: markerGeometry
        )

        markerNode.isHidden = true

        scene.rootNode.addChildNode(meshNode)
        scene.rootNode.addChildNode(routeNode)
        scene.rootNode.addChildNode(markerNode)

        let camera = SCNCamera()

        camera.fieldOfView = 50
        camera.zNear = 1
        camera.zFar = 20_000
        camera.automaticallyAdjustsZRange = true

        cameraNode.camera = camera

        scene.rootNode.addChildNode(
            cameraNode
        )

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1500

        scene.rootNode.addChildNode(
            keyLightNode
        )

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 600
        ambientNode.light?.color = UIColor.white

        scene.rootNode.addChildNode(
            ambientNode
        )

        scene.background.contents =
            UIColor.systemBackground
    }

    // MARK: - View

    func attach(to view: SCNView) {
        self.view = view

        view.pointOfView =
            cameraNode

        if mesh != nil {
            updateFollowCamera(
                progress: currentProgress,
                animated: false
            )
        }
    }

    // MARK: - Mesh

    func setMesh(
        _ mesh: Climb3DMesh,
        route: Climb3DRoute
    ) {
        self.mesh = mesh
        self.route = route

        meshNode.geometry =
            mesh.sceneGeometry()

        rebuildRoute(
            mesh.centerline
        )

        markerNode.isHidden = false

        currentProgress = 0
        followMode = true

        updateProgress(0)
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

        currentProgress = p

        let targetDistance =
            p *
            route.totalDistanceM

        let position =
            meshPosition(
                atDistanceM:
                    targetDistance
            )

        markerNode.position =
            SCNVector3(
                position.x,
                position.y + 4,
                position.z
            )

        markerNode.isHidden = false

        if followMode {
            updateFollowCamera(
                progress: p,
                animated: true
            )
        }
    }

    // MARK: - Follow camera

    private func updateFollowCamera(
        progress: Double,
        animated: Bool
    ) {
        guard
            let route,
            route.totalDistanceM > 0
        else {
            return
        }

        let currentDistance =
            progress *
            route.totalDistanceM

        let futureDistance =
            min(
                route.totalDistanceM,
                currentDistance +
                lookAheadM
            )

        let current =
            meshPosition(
                atDistanceM:
                    currentDistance
            )

        let future =
            meshPosition(
                atDistanceM:
                    futureDistance
            )

        var dx =
            Double(
                future.x -
                current.x
            )

        var dz =
            Double(
                future.z -
                current.z
            )

        var horizontalLength =
            sqrt(
                dx * dx +
                dz * dz
            )

        if horizontalLength < 0.001 {

            let fallbackDistance =
                min(
                    route.totalDistanceM,
                    currentDistance + 20
                )

            let fallback =
                meshPosition(
                    atDistanceM:
                        fallbackDistance
                )

            dx =
                Double(
                    fallback.x -
                    current.x
                )

            dz =
                Double(
                    fallback.z -
                    current.z
                )

            horizontalLength =
                sqrt(
                    dx * dx +
                    dz * dz
                )
        }

        guard horizontalLength > 0.001
        else {
            return
        }

        let dirX =
            dx /
            horizontalLength

        let dirZ =
            dz /
            horizontalLength

        let cameraPosition =
            SCNVector3(
                current.x -
                    Float(
                        dirX *
                        cameraBehindM
                    ),

                current.y +
                    Float(
                        cameraHeightM
                    ),

                current.z -
                    Float(
                        dirZ *
                        cameraBehindM
                    )
            )

        let target =
            SCNVector3(
                future.x,
                future.y +
                    Float(
                        targetLiftM
                    ),
                future.z
            )

        if animated {

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            SCNTransaction.animationTimingFunction =
                CAMediaTimingFunction(
                    name: .easeInEaseOut
                )

            cameraNode.position =
                cameraPosition

            cameraNode.look(
                at: target
            )

            SCNTransaction.commit()

        } else {

            cameraNode.position =
                cameraPosition

            cameraNode.look(
                at: target
            )
        }

        keyLightNode.position =
            SCNVector3(
                current.x + 100,
                current.y + 180,
                current.z + 100
            )

        view?.pointOfView =
            cameraNode
    }

    // MARK: - Manual camera mode

    func disableFollowMode() {
        followMode = false
    }

    func enableFollowMode() {
        followMode = true

        updateFollowCamera(
            progress:
                currentProgress,
            animated:
                true
        )
    }

    func resetCamera() {
        enableFollowMode()
    }

    // MARK: - Mesh interpolation

    private func meshPosition(
        atDistanceM distanceM: Double
    ) -> Climb3DVertex {

        guard
            let mesh,
            let route,
            !mesh.centerline.isEmpty,
            !route.points.isEmpty
        else {
            return Climb3DVertex(
                x: 0,
                y: 0,
                z: 0
            )
        }

        let target =
            min(
                route.totalDistanceM,
                max(
                    0,
                    distanceM
                )
            )

        if target <= 0 {
            return mesh.centerline[0]
        }

        if target >= route.totalDistanceM {
            return mesh.centerline[
                mesh.centerline.count - 1
            ]
        }

        var low = 0

        var high =
            min(
                route.points.count,
                mesh.centerline.count
            ) - 1

        while low + 1 < high {

            let mid =
                (low + high) / 2

            if route.points[mid].distanceM <
                target {

                low = mid

            } else {

                high = mid
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

        let span =
            max(
                0.001,
                routeB.distanceM -
                routeA.distanceM
            )

        let t =
            Float(
                (
                    target -
                    routeA.distanceM
                ) /
                span
            )

        return Climb3DVertex(
            x:
                pointA.x +
                (
                    pointB.x -
                    pointA.x
                ) *
                t,

            y:
                pointA.y +
                (
                    pointB.y -
                    pointA.y
                ) *
                t,

            z:
                pointA.z +
                (
                    pointB.z -
                    pointA.z
                ) *
                t
        )
    }

    // MARK: - Route rendering

    private func rebuildRoute(
        _ points: [Climb3DVertex]
    ) {
        routeNode.childNodes.forEach {
            $0.removeFromParentNode()
        }

        guard points.count >= 2
        else {
            return
        }

        for index in 1..<points.count {

            let a =
                points[
                    index - 1
                ]

            let b =
                points[
                    index
                ]

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
                    from:
                        start,
                    to:
                        end
                )
            )
        }
    }

    private func lineNode(
        from a: SCNVector3,
        to b: SCNVector3
    ) -> SCNNode {

        let dx =
            b.x - a.x

        let dy =
            b.y - a.y

        let dz =
            b.z - a.z

        let length =
            sqrt(
                dx * dx +
                dy * dy +
                dz * dz
            )

        let cylinder =
            SCNCylinder(
                radius: 1.2,
                height: CGFloat(
                    length
                )
            )

        cylinder.radialSegmentCount = 8

        cylinder.firstMaterial?.diffuse.contents =
            UIColor.systemBlue

        cylinder.firstMaterial?.emission.contents =
            UIColor.systemBlue
                .withAlphaComponent(
                    0.12
                )

        let node =
            SCNNode(
                geometry:
                    cylinder
            )

        node.position =
            SCNVector3(
                (a.x + b.x) / 2,
                (a.y + b.y) / 2,
                (a.z + b.z) / 2
            )

        node.look(
            at:
                b,
            up:
                SCNVector3(
                    0,
                    1,
                    0
                ),
            localFront:
                SCNVector3(
                    0,
                    1,
                    0
                )
        )

        return node
    }
}
