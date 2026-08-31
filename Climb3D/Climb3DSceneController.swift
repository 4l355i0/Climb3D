import Foundation
import SceneKit
import UIKit

@MainActor
final class Climb3DSceneController {

    let scene = SCNScene()

    private weak var view: SCNView?

    private let meshNode = SCNNode()
    private let roadNode = SCNNode()
    private let routeNode = SCNNode()
    private let markerNode: SCNNode

    private let cameraNode = SCNNode()
    private let keyLightNode = SCNNode()
    private let ambientNode = SCNNode()

    private var mesh: Climb3DMesh?
    private var route: Climb3DRoute?

    private var currentProgress: Double = 0
    private var followMode = true

    // Climb Portal style camera
    private let cameraBehindM: Double = 85
    private let baseCameraHeightM: Double = 38
    private let lookAheadM: Double = 125

    init() {

        let markerGeometry =
            SCNSphere(radius: 4.5)

        markerGeometry.segmentCount = 24

        markerGeometry.firstMaterial?.diffuse.contents =
            UIColor.systemRed

        markerGeometry.firstMaterial?.emission.contents =
            UIColor.systemRed.withAlphaComponent(0.35)

        markerNode =
            SCNNode(
                geometry: markerGeometry
            )

        markerNode.isHidden = true

        scene.rootNode.addChildNode(meshNode)
        scene.rootNode.addChildNode(roadNode)
        scene.rootNode.addChildNode(routeNode)
        scene.rootNode.addChildNode(markerNode)

        let camera = SCNCamera()

        camera.fieldOfView = 53
        camera.zNear = 0.5
        camera.zFar = 20_000
        camera.automaticallyAdjustsZRange = true

        cameraNode.camera = camera

        scene.rootNode.addChildNode(cameraNode)

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1700

        scene.rootNode.addChildNode(keyLightNode)

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 650
        ambientNode.light?.color = UIColor.white

        scene.rootNode.addChildNode(ambientNode)

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

        roadNode.geometry =
            mesh.roadGeometry()

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

        guard
            let route,
            route.totalDistanceM > 0
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

        let distance =
            p *
            route.totalDistanceM

        let position =
            meshPosition(
                atDistanceM: distance
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

    // MARK: - Climb Portal follow camera

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

        let behindDistance =
            max(
                0,
                currentDistance - 35
            )

        let futureDistance =
            min(
                route.totalDistanceM,
                currentDistance + lookAheadM
            )

        let behind =
            meshPosition(
                atDistanceM: behindDistance
            )

        let current =
            meshPosition(
                atDistanceM: currentDistance
            )

        let future =
            meshPosition(
                atDistanceM: futureDistance
            )

        // Horizontal direction
        var dx =
            Double(
                future.x - current.x
            )

        var dz =
            Double(
                future.z - current.z
            )

        var horizontalLength =
            sqrt(
                dx * dx +
                dz * dz
            )

        if horizontalLength < 0.001 {

            dx =
                Double(
                    current.x - behind.x
                )

            dz =
                Double(
                    current.z - behind.z
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

        /*
         Dynamic camera pitch.

         The height difference to the look-ahead point
         determines how much the camera has to tilt.

         Steep climb -> target higher.
         Descent -> target lower.
        */
        let rise =
            Double(
                future.y -
                current.y
            )

        let dynamicExtraHeight =
            min(
                18,
                max(
                    -6,
                    abs(rise) * 0.18
                )
            )

        let cameraHeight =
            baseCameraHeightM +
            dynamicExtraHeight

        let cameraPosition =
            SCNVector3(
                current.x -
                    Float(
                        dirX *
                        cameraBehindM
                    ),

                current.y +
                    Float(
                        cameraHeight
                    ),

                current.z -
                    Float(
                        dirZ *
                        cameraBehindM
                    )
            )

        /*
         Target follows REAL elevation.

         This is what makes the camera pitch change
         automatically as the road climbs or descends.
        */
        let target =
            SCNVector3(
                future.x,
                future.y + 5,
                future.z
            )

        let apply = {

            self.cameraNode.position =
                cameraPosition

            /*
             Explicit world-up prevents the road
             from appearing rolled sideways.
            */
            self.cameraNode.look(
                at: target,
                up: SCNVector3(
                    0,
                    1,
                    0
                ),
                localFront: SCNVector3(
                    0,
                    0,
                    -1
                )
            )

            self.keyLightNode.position =
                SCNVector3(
                    current.x + 80,
                    current.y + 160,
                    current.z + 80
                )

            self.view?.pointOfView =
                self.cameraNode
        }

        if animated {

            SCNTransaction.begin()

            SCNTransaction.animationDuration = 0.22

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
                (b.x - a.x) * t,

            y:
                a.y +
                (b.y - a.y) * t,

            z:
                a.z +
                (b.z - a.z) * t
        )
    }

    // MARK: - Center line

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
                points[index - 1]

            let b =
                points[index]

            let start =
                SCNVector3(
                    a.x,
                    a.y + 0.5,
                    a.z
                )

            let end =
                SCNVector3(
                    b.x,
                    b.y + 0.5,
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

        /*
         Much thinner now.
         The ROAD is the main visual element,
         not the blue line.
        */
        let cylinder =
            SCNCylinder(
                radius: 0.45,
                height: CGFloat(length)
            )

        cylinder.radialSegmentCount = 6

        cylinder.firstMaterial?.diffuse.contents =
            UIColor.systemBlue

        cylinder.firstMaterial?.emission.contents =
            UIColor.systemBlue
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
}
