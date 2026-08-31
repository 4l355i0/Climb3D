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
    private var followMode = true

    /*
     CLOSE FOLLOW CAMERA

     Deliberately much closer than previous build.
    */
    private let cameraBehindM: Double = 50
    private let baseCameraHeightM: Double = 27
    private let lookAheadM: Double = 85

    init() {

        let markerGeometry =
            SCNSphere(
                radius: 3.6
            )

        markerGeometry.segmentCount = 24

        markerGeometry
            .firstMaterial?
            .diffuse
            .contents =
            UIColor.systemRed

        markerGeometry
            .firstMaterial?
            .emission
            .contents =
            UIColor.systemRed
                .withAlphaComponent(0.35)

        markerGeometry
            .firstMaterial?
            .lightingModel =
            .physicallyBased

        markerNode =
            SCNNode(
                geometry:
                    markerGeometry
            )

        markerNode.isHidden =
            true

        scene.rootNode.addChildNode(
            meshNode
        )

        scene.rootNode.addChildNode(
            routeNode
        )

        scene.rootNode.addChildNode(
            markerNode
        )

        // MARK: Camera

        let camera =
            SCNCamera()

        camera.fieldOfView =
            45

        camera.zNear =
            0.25

        camera.zFar =
            20_000

        camera
            .automaticallyAdjustsZRange =
            true

        cameraNode.camera =
            camera

        scene.rootNode.addChildNode(
            cameraNode
        )

        // MARK: Key light

        keyLightNode.light =
            SCNLight()

        keyLightNode.light?.type =
            .directional

        keyLightNode.light?.intensity =
            1500

        keyLightNode.light?.castsShadow =
            true

        keyLightNode.light?.shadowRadius =
            3

        keyLightNode.light?.shadowSampleCount =
            8

        keyLightNode.eulerAngles =
    SCNVector3(
        -Float.pi / 3,
        Float.pi / 4,
        0
            )

        scene.rootNode.addChildNode(
            keyLightNode
        )

        // MARK: Ambient light

        ambientNode.light =
            SCNLight()

        ambientNode.light?.type =
            .ambient

        ambientNode.light?.intensity =
            500

        ambientNode.light?.color =
            UIColor.white

        scene.rootNode.addChildNode(
            ambientNode
        )

        scene.background.contents =
            UIColor.systemBackground
    }

    // MARK: - Attach

    func attach(
        to view: SCNView
    ) {

        self.view =
            view

        view.pointOfView =
            cameraNode

        if mesh != nil {

            updateFollowCamera(
                progress:
                    currentProgress,
                animated:
                    false
            )
        }
    }

    // MARK: - Mesh

    func setMesh(
        _ mesh: Climb3DMesh,
        route: Climb3DRoute
    ) {

        self.mesh =
            mesh

        self.route =
            route

        /*
         IMPORTANT:
         ONE geometry only.

         Previous build was drawing sceneGeometry()
         twice through meshNode and roadNode.
        */
        meshNode.geometry =
            mesh.sceneGeometry()

        meshNode.castsShadow =
            true

        rebuildRoute(
            mesh.centerline
        )

        markerNode.isHidden =
            false

        currentProgress =
            0

        followMode =
            true

        updateProgress(
            0
        )
    }

    // MARK: - Progress

    func updateProgress(
        _ progress: Double
    ) {

        guard
            let route,
            route.totalDistanceM > 0
        else {

            markerNode.isHidden =
                true

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

        currentProgress =
            p

        let distance =
            p *
            route.totalDistanceM

        let position =
            meshPosition(
                atDistanceM:
                    distance
            )

        markerNode.position =
            SCNVector3(
                position.x,
                position.y + 4,
                position.z
            )

        markerNode.isHidden =
            false

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

        /*
         Use a point slightly behind as fallback
         direction near very tight curves.
        */
        let behindDistance =
            max(
                0,
                currentDistance - 20
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

        guard
            horizontalLength >
                0.001
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
         REAL VISUAL PITCH

         Signed rise is important.

         Uphill:
         camera subtly adapts upward.

         Downhill:
         camera does not incorrectly
         behave as if it were climbing.
        */

        let rise =
            Double(
                future.y -
                current.y
            )

        let visualSlope =
            rise /
            max(
                1,
                lookAheadM
            )

        let pitchAdjustment =
            min(
                9,
                max(
                    -5,
                    visualSlope * 30
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
         Look toward the future section,
         including its real visual elevation.
        */

        let target =
            SCNVector3(
                future.x,
                future.y + 4,
                future.z
            )

        let apply = {

            self.cameraNode.position =
                cameraPosition

            /*
             Fixed world-up keeps horizon stable
             and prevents unwanted roll.
            */

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
                0.18

            SCNTransaction
                .animationTimingFunction =
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

    // MARK: - Follow mode

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

    // MARK: - Position interpolation

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

        if target >=
            route.totalDistanceM {

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
                (
                    b.x -
                    a.x
                ) * t,

            y:
                a.y +
                (
                    b.y -
                    a.y
                ) * t,

            z:
                a.z +
                (
                    b.z -
                    a.z
                ) * t
        )
    }

    // MARK: - Route reference

    private func rebuildRoute(
        _ points:
            [Climb3DVertex]
    ) {

        routeNode
            .childNodes
            .forEach {

                $0.removeFromParentNode()
            }

        guard
            points.count >= 2
        else {
            return
        }

        for index in
            1..<points.count {

            let a =
                points[
                    index - 1
                ]

            let b =
                points[index]

            let start =
                SCNVector3(
                    a.x,
                    a.y + 0.6,
                    a.z
                )

            let end =
                SCNVector3(
                    b.x,
                    b.y + 0.6,
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

        /*
         Very subtle reference line.
         The 3D base/road should dominate.
        */

        let cylinder =
            SCNCylinder(
                radius: 0.22,
                height:
                    CGFloat(length)
            )

        cylinder.radialSegmentCount =
            6

        cylinder
            .firstMaterial?
            .diffuse
            .contents =
            UIColor.systemBlue
                .withAlphaComponent(
                    0.65
                )

        cylinder
            .firstMaterial?
            .emission
            .contents =
            UIColor.systemBlue
                .withAlphaComponent(
                    0.04
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
