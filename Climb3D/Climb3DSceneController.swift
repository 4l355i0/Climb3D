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
    private let fillLightNode = SCNNode()
    private let ambientNode = SCNNode()

    private var mesh: Climb3DMesh?
    private var route: Climb3DRoute?

    private var currentProgress: Double = 0
    private var followMode = true

    // Build 14 rider view. Position is taken from the actual route behind
    // the rider, so the camera follows a hairpin rather than cutting across it.
    private let cameraBehindM: Double = 12
    private let cameraHeightM: Float = 5.8
    private let lookAheadM: Double = 16
    private let startBackwardOffsetM: Double = 10

    init() {

        // Build 13 marker was 3.6 m in diameter and obscured the road.
        let markerGeometry =
            SCNSphere(radius: 0.78)

        markerGeometry.segmentCount = 24

        markerGeometry
            .firstMaterial?
            .diffuse.contents =
            UIColor.systemRed

        markerGeometry
            .firstMaterial?
            .emission.contents =
            UIColor.systemRed
                .withAlphaComponent(0.28)

        markerGeometry
            .firstMaterial?
            .lightingModel =
            .physicallyBased

        markerNode =
            SCNNode(
                geometry: markerGeometry
            )

        markerNode.isHidden = true

        scene.rootNode
            .addChildNode(meshNode)

        scene.rootNode
            .addChildNode(routeNode)

        scene.rootNode
            .addChildNode(markerNode)

        let camera = SCNCamera()

        camera.fieldOfView = 66
        camera.zNear = 0.12
        camera.zFar = 50_000
        camera.automaticallyAdjustsZRange = true
        camera.wantsHDR = true

        cameraNode.camera = camera

        scene.rootNode
            .addChildNode(cameraNode)

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .directional
        keyLightNode.light?.intensity = 1450
        keyLightNode.light?.castsShadow = true
        keyLightNode.light?.shadowRadius = 4
        keyLightNode.light?.shadowSampleCount = 12

        keyLightNode.eulerAngles =
            SCNVector3(
                -Float.pi / 3,
                Float.pi / 4,
                0
            )

        scene.rootNode
            .addChildNode(keyLightNode)

        fillLightNode.light = SCNLight()
        fillLightNode.light?.type = .directional
        fillLightNode.light?.intensity = 390

        fillLightNode.eulerAngles =
            SCNVector3(
                -Float.pi / 4,
                -Float.pi / 2,
                0
            )

        scene.rootNode
            .addChildNode(fillLightNode)

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 400
        ambientNode.light?.color = UIColor.white

        scene.rootNode
            .addChildNode(ambientNode)

        scene.background.contents =
            UIColor(
                red: 0.55,
                green: 0.69,
                blue: 0.80,
                alpha: 1.0
            )
    }

    func attach(to view: SCNView) {

        self.view = view
        view.pointOfView = cameraNode

        // No default SceneKit camera control while follow mode is active.
        // The existing SwiftUI/SceneKit wrapper can still disable follow mode
        // before user manipulation, as in Build 13.
        if mesh != nil {

            updateFollowCamera(
                progress: currentProgress,
                animated: false
            )
        }
    }

    func setMesh(
        _ mesh: Climb3DMesh,
        route: Climb3DRoute
    ) {

        self.mesh = mesh
        self.route = route

        // sceneGeometry() now returns only the visual road top. STL walls,
        // bottom and base remain in mesh.vertices/triangles for STLWriter.
        meshNode.geometry =
            mesh.sceneGeometry()

        meshNode.castsShadow = false

        rebuildRoute(
            mesh.centerline
        )

        markerNode.isHidden = false

        currentProgress = 0
        followMode = true

        updateProgress(0)
    }

    func updateProgress(
        _ progress: Double
    ) {

        guard let route,
              route.totalDistanceM > 0 else {

            markerNode.isHidden = true
            return
        }

        let p =
            min(
                1,
                max(0, progress)
            )

        currentProgress = p

        let position =
            meshPosition(
                atDistanceM:
                    p * route.totalDistanceM
            )

        markerNode.position =
            SCNVector3(
                position.x,
                position.y + 0.82,
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

    // MARK: - Rider follow camera

    private func updateFollowCamera(
        progress: Double,
        animated: Bool
    ) {

        guard let route,
              route.totalDistanceM > 0 else {
            return
        }

        let currentDistance =
            progress * route.totalDistanceM

        let current =
            meshPosition(
                atDistanceM:
                    currentDistance
            )

        let futureDistance =
            min(
                route.totalDistanceM,
                currentDistance + lookAheadM
            )

        let future =
            meshPosition(
                atDistanceM:
                    futureDistance
            )

        let cameraPosition: SCNVector3

        if currentDistance >= cameraBehindM {

            let behind =
                meshPosition(
                    atDistanceM:
                        currentDistance - cameraBehindM
                )

            cameraPosition =
                SCNVector3(
                    behind.x,
                    behind.y + cameraHeightM,
                    behind.z
                )

        } else {

            let dx =
                Double(future.x - current.x)

            let dz =
                Double(future.z - current.z)

            let length =
                max(
                    0.001,
                    sqrt(dx * dx + dz * dz)
                )

            cameraPosition =
                SCNVector3(
                    current.x -
                        Float(
                            dx / length *
                            startBackwardOffsetM
                        ),

                    current.y + cameraHeightM,

                    current.z -
                        Float(
                            dz / length *
                            startBackwardOffsetM
                        )
                )
        }

        // Keep target local. A long target can land on the next leg of a
        // hairpin and make the camera appear to look through the turn.
        let target =
            SCNVector3(
                future.x,
                future.y + 0.65,
                future.z
            )

        let apply = {

            self.cameraNode.position =
                cameraPosition

            self.cameraNode.look(
                at: target,
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )

            self.view?.pointOfView =
                self.cameraNode
        }

        if animated {

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.14

            SCNTransaction.animationTimingFunction =
                CAMediaTimingFunction(
                    name: .easeInEaseOut
                )

            apply()
            SCNTransaction.commit()

        } else {
            apply()
        }
    }

    func disableFollowMode() {
        followMode = false
    }

    func enableFollowMode() {

        followMode = true

        updateFollowCamera(
            progress: currentProgress,
            animated: true
        )
    }

    func resetCamera() {
        enableFollowMode()
    }

    // MARK: - Route interpolation

    private func meshPosition(
        atDistanceM distanceM: Double
    ) -> Climb3DVertex {

        guard let mesh,
              let route,
              !mesh.centerline.isEmpty,
              !route.points.isEmpty else {

            return Climb3DVertex(
                x: 0,
                y: 0,
                z: 0
            )
        }

        let target =
            min(
                route.totalDistanceM,
                max(0, distanceM)
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

            if route.points[mid].distanceM < target {
                low = mid
            } else {
                high = mid
            }
        }

        let routeA = route.points[low]
        let routeB = route.points[high]

        let a = mesh.centerline[low]
        let b = mesh.centerline[high]

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
                a.x +
                (b.x - a.x) * t,

            y:
                a.y +
                (b.y - a.y) * t,

            z:
                a.z +
                (b.z - a.z) * t
        )
    }

    // MARK: - Centerline rendering

    private func rebuildRoute(
        _ points: [Climb3DVertex]
    ) {

        routeNode.childNodes
            .forEach {
                $0.removeFromParentNode()
            }

        guard points.count >= 2 else {
            return
        }

        for i in 1..<points.count {

            let a = points[i - 1]
            let b = points[i]

            routeNode.addChildNode(
                lineNode(
                    from:
                        SCNVector3(
                            a.x,
                            a.y + 0.08,
                            a.z
                        ),

                    to:
                        SCNVector3(
                            b.x,
                            b.y + 0.08,
                            b.z
                        )
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
                radius: 0.075,
                height: CGFloat(length)
            )

        cylinder.radialSegmentCount = 5

        cylinder
            .firstMaterial?
            .diffuse.contents =
            UIColor.white
                .withAlphaComponent(0.78)

        cylinder
            .firstMaterial?
            .emission.contents =
            UIColor.white
                .withAlphaComponent(0.08)

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
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 1, 0)
        )

        return node
    }
}


