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

    private let cameraBehindM: Double = 62
    private let baseCameraHeightM: Double = 34
    private let lookAheadM: Double = 105

    init() {

        let markerGeometry =
            SCNSphere(radius: 4.0)

        markerGeometry.segmentCount = 28

        markerGeometry
            .firstMaterial?
            .diffuse.contents =
            UIColor.systemRed

        markerGeometry
            .firstMaterial?
            .emission.contents =
            UIColor.systemRed
                .withAlphaComponent(0.40)

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

        camera.fieldOfView = 48
        camera.zNear = 0.25
        camera.zFar = 50_000
        camera.automaticallyAdjustsZRange = true

        cameraNode.camera = camera

        scene.rootNode
            .addChildNode(cameraNode)

        keyLightNode.light =
            SCNLight()

        keyLightNode.light?.type =
            .directional

        keyLightNode.light?.intensity =
            1700

        keyLightNode.light?.castsShadow =
            true

        keyLightNode.light?.shadowRadius =
            4

        keyLightNode.light?.shadowSampleCount =
            12

        keyLightNode.eulerAngles =
            SCNVector3(
                -Float.pi / 3,
                Float.pi / 4,
                0
            )

        scene.rootNode
            .addChildNode(keyLightNode)

        fillLightNode.light =
            SCNLight()

        fillLightNode.light?.type =
            .directional

        fillLightNode.light?.intensity =
            500

        fillLightNode.eulerAngles =
            SCNVector3(
                -Float.pi / 4,
                -Float.pi / 2,
                0
            )

        scene.rootNode
            .addChildNode(fillLightNode)

        ambientNode.light =
            SCNLight()

        ambientNode.light?.type =
            .ambient

        ambientNode.light?.intensity =
            350

        ambientNode.light?.color =
            UIColor.white

        scene.rootNode
            .addChildNode(ambientNode)

        scene.background.contents =
            UIColor.systemBackground
    }

    func attach(to view: SCNView) {

        self.view = view
        view.pointOfView = cameraNode

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

        meshNode.geometry =
            mesh.sceneGeometry()

        meshNode.castsShadow = true

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
                    p *
                    route.totalDistanceM
            )

        markerNode.position =
            SCNVector3(
                position.x,
                position.y + 5,
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

    private func updateFollowCamera(
        progress: Double,
        animated: Bool
    ) {

        guard let route,
              route.totalDistanceM > 0 else {
            return
        }

        let currentDistance =
            progress *
            route.totalDistanceM

        let behindDistance =
            max(
                0,
                currentDistance - 25
            )

        let futureDistance =
            min(
                route.totalDistanceM,
                currentDistance +
                lookAheadM
            )

        let behind =
            meshPosition(
                atDistanceM:
                    behindDistance
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

            dx =
                Double(
                    current.x -
                    behind.x
                )

            dz =
                Double(
                    current.z -
                    behind.z
                )

            horizontalLength =
                sqrt(
                    dx * dx +
                    dz * dz
                )
        }

        guard horizontalLength > 0.001 else {
            return
        }

        let dirX =
            dx /
            horizontalLength

        let dirZ =
            dz /
            horizontalLength

        let visualRise =
            Double(
                future.y -
                current.y
            )

        let visualSlope =
            visualRise /
            max(
                1,
                lookAheadM
            )

        let pitchAdjustment =
            min(
                18,
                max(
                    -8,
                    visualSlope * 18
                )
            )

        let cameraHeight =
            baseCameraHeightM +
            pitchAdjustment

        let cameraPosition =
            SCNVector3(
                current.x -
                Float(
                    dirX *
                    cameraBehindM
                ),

                current.y +
                Float(cameraHeight),

                current.z -
                Float(
                    dirZ *
                    cameraBehindM
                )
            )

        let target =
            SCNVector3(
                future.x,
                future.y + 4,
                future.z
            )

        let apply = {

            self.cameraNode.position =
                cameraPosition

            self.cameraNode.look(
                at: target,
                up:
                    SCNVector3(
                        0,
                        1,
                        0
                    ),
                localFront:
                    SCNVector3(
                        0,
                        0,
                        -1
                    )
            )

            self.view?.pointOfView =
                self.cameraNode
        }

        if animated {

            SCNTransaction.begin()

            SCNTransaction.animationDuration =
                0.20

            SCNTransaction.animationTimingFunction =
                CAMediaTimingFunction(
                    name:
                        .easeInEaseOut
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

        let a =
            mesh.centerline[low]

        let b =
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
                a.x +
                (b.x - a.x) *
                t,

            y:
                a.y +
                (b.y - a.y) *
                t,

            z:
                a.z +
                (b.z - a.z) *
                t
        )
    }

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
                            a.y + 0.8,
                            a.z
                        ),

                    to:
                        SCNVector3(
                            b.x,
                            b.y + 0.8,
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
                radius: 0.28,
                height: CGFloat(length)
            )

        cylinder.radialSegmentCount = 6

        cylinder
            .firstMaterial?
            .diffuse.contents =
            UIColor.systemBlue
                .withAlphaComponent(0.70)

        cylinder
            .firstMaterial?
            .emission.contents =
            UIColor.systemBlue
                .withAlphaComponent(0.05)

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
