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

    init() {

        // Large, clearly visible rider/position marker
        let markerGeometry = SCNSphere(radius: 6.0)

        markerGeometry.firstMaterial?.diffuse.contents =
            UIColor.systemRed

        markerGeometry.firstMaterial?.emission.contents =
            UIColor.systemRed.withAlphaComponent(0.40)

        markerGeometry.firstMaterial?.lightingModel =
            .physicallyBased

        markerNode = SCNNode(
            geometry: markerGeometry
        )

        markerNode.isHidden = true

        scene.rootNode.addChildNode(meshNode)
        scene.rootNode.addChildNode(routeNode)
        scene.rootNode.addChildNode(markerNode)

        // MARK: Camera

        let camera = SCNCamera()

        camera.fieldOfView = 42
        camera.zNear = 0.1
        camera.zFar = 1_000_000

        cameraNode.camera = camera

        scene.rootNode.addChildNode(
            cameraNode
        )

        // MARK: Main light

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1400

        scene.rootNode.addChildNode(
            keyLightNode
        )

        // MARK: Ambient light

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 550
        ambientNode.light?.color = UIColor.white

        scene.rootNode.addChildNode(
            ambientNode
        )

        scene.background.contents =
            UIColor.systemBackground
    }

    // MARK: - Attach view

    func attach(
        to view: SCNView
    ) {

        self.view = view

        view.pointOfView =
            cameraNode

        resetCamera()
    }

    // MARK: - Load mesh

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

        updateProgress(0)

        resetCamera()
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

        /*
         Progress is now based on REAL GPX DISTANCE,
         not on the number of GPX samples.
        */

        let targetDistance =
            p *
            route.totalDistanceM

        // Start
        if targetDistance <= 0 {

            setMarker(
                at: mesh.centerline[0]
            )

            return
        }

        // End
        if targetDistance >= route.totalDistanceM {

            setMarker(
                at: mesh.centerline[
                    mesh.centerline.count - 1
                ]
            )

            return
        }

        /*
         Binary search for the two GPX points
         surrounding the requested distance.
        */

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

        setMarker(
            at: position
        )
    }

    private func setMarker(
        at point: Climb3DVertex
    ) {

        markerNode.position =
            SCNVector3(
                point.x,
                point.y + 5.0,
                point.z
            )

        markerNode.isHidden = false
    }

    // MARK: - Automatic camera

    func resetCamera() {

        guard
            let mesh,
            !mesh.vertices.isEmpty
        else {

            cameraNode.position =
                SCNVector3(
                    150,
                    180,
                    250
                )

            cameraNode.look(
                at: SCNVector3Zero
            )

            return
        }

        let xs =
            mesh.vertices.map(\.x)

        let ys =
            mesh.vertices.map(\.y)

        let zs =
            mesh.vertices.map(\.z)

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

        let center =
            SCNVector3(

                (minX + maxX) / 2,

                (minY + maxY) / 2,

                (minZ + maxZ) / 2
            )

        let widthX =
            maxX - minX

        let heightY =
            maxY - minY

        let depthZ =
            maxZ - minZ

        let horizontalSize =
            max(
                widthX,
                depthZ
            )

        /*
         Elevation should influence framing,
         but should not dominate it.
        */

        let modelSize =
            max(
                horizontalSize,
                heightY * 1.3
            )

        let radius =
            max(
                50,
                modelSize
            )

        /*
         Perspective overview:
         high enough to understand route shape,
         low enough to perceive climbing.
        */

        let cameraDistance =
            radius * 1.30

        let cameraHeight =
            radius * 0.85

        cameraNode.position =
            SCNVector3(

                center.x +
                cameraDistance * 0.70,

                center.y +
                cameraHeight,

                center.z +
                cameraDistance
            )

        cameraNode.look(
            at: center
        )

        keyLightNode.position =
            SCNVector3(

                center.x +
                radius * 0.8,

                center.y +
                radius * 1.8,

                center.z +
                radius
            )

        view?.pointOfView =
            cameraNode
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
                points[index - 1]

            let b =
                points[index]

            let start =
                SCNVector3(
                    a.x,
                    a.y + 0.8,
                    a.z
                )

            let end =
                SCNVector3(
                    b.x,
                    b.y + 0.8,
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
                radius: 1.15,
                height: CGFloat(length)
            )

        cylinder.firstMaterial?.diffuse.contents =
            UIColor.systemBlue

        cylinder.firstMaterial?.emission.contents =
            UIColor.systemBlue
                .withAlphaComponent(0.18)

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
