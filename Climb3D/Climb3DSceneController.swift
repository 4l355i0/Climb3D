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

    init() {

        // Larger position marker
        let markerGeometry = SCNSphere(radius: 6.0)

        markerGeometry.firstMaterial?.diffuse.contents =
            UIColor.systemRed

        markerGeometry.firstMaterial?.emission.contents =
            UIColor.systemRed.withAlphaComponent(0.35)

        markerGeometry.firstMaterial?.lightingModel = .physicallyBased

        markerNode = SCNNode(geometry: markerGeometry)
        markerNode.isHidden = true

        scene.rootNode.addChildNode(meshNode)
        scene.rootNode.addChildNode(routeNode)
        scene.rootNode.addChildNode(markerNode)

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.1
        camera.zFar = 1_000_000

        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // Main light
        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1400
        scene.rootNode.addChildNode(keyLightNode)

        // Ambient light
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 550
        ambientNode.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientNode)

        scene.background.contents = UIColor.systemBackground
    }

    func attach(to view: SCNView) {
        self.view = view

        view.pointOfView = cameraNode

        resetCamera()
    }

    func setMesh(
        _ mesh: Climb3DMesh,
        route: Climb3DRoute
    ) {
        self.mesh = mesh

        meshNode.geometry = mesh.sceneGeometry()

        rebuildRoute(mesh.centerline)

        markerNode.isHidden = false

        updateProgress(0)

        resetCamera()
    }

    func updateProgress(_ progress: Double) {
        guard let mesh,
              !mesh.centerline.isEmpty
        else {
            markerNode.isHidden = true
            return
        }

        let p = min(1, max(0, progress))

        let scaled =
            p * Double(mesh.centerline.count - 1)

        let low = Int(floor(scaled))

        let high =
            min(
                mesh.centerline.count - 1,
                low + 1
            )

        let t =
            Float(
                scaled - Double(low)
            )

        let a = mesh.centerline[low]
        let b = mesh.centerline[high]

        markerNode.position = SCNVector3(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t + 4.0,
            a.z + (b.z - a.z) * t
        )

        markerNode.isHidden = false
    }

    // MARK: - Automatic camera

    func resetCamera() {
        guard let mesh,
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

        let center = SCNVector3(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            (minZ + maxZ) / 2
        )

        let widthX = maxX - minX
        let heightY = maxY - minY
        let depthZ = maxZ - minZ

        let horizontalSize =
            max(
                widthX,
                depthZ
            )

        let modelSize =
            max(
                horizontalSize,
                heightY * 1.5
            )

        let radius =
            max(
                50,
                modelSize
            )

        /*
         Automatic isometric-style view.

         Higher Y = more top-down.
         X/Z offset gives depth perception.

         This is intentionally less steep than
         the previous camera.
        */

        let cameraDistance =
            radius * 1.45

        let cameraHeight =
            radius * 1.10

        cameraNode.position =
            SCNVector3(
                center.x + cameraDistance * 0.72,
                center.y + cameraHeight,
                center.z + cameraDistance
            )

        cameraNode.look(
            at: center
        )

        keyLightNode.position =
            SCNVector3(
                center.x + radius * 0.8,
                center.y + radius * 1.8,
                center.z + radius
            )

        view?.pointOfView = cameraNode
    }

    // MARK: - Route rendering

    private func rebuildRoute(
        _ points: [Climb3DVertex]
    ) {
        routeNode.childNodes.forEach {
            $0.removeFromParentNode()
        }

        guard points.count >= 2 else {
            return
        }

        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]

            let start =
                SCNVector3(
                    a.x,
                    a.y + 1.0,
                    a.z
                )

            let end =
                SCNVector3(
                    b.x,
                    b.y + 1.0,
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
                radius: 1.15,
                height: CGFloat(length)
            )

        cylinder.firstMaterial?.diffuse.contents =
            UIColor.systemBlue

        cylinder.firstMaterial?.emission.contents =
            UIColor.systemBlue.withAlphaComponent(0.18)

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
