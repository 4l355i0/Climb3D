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
        let markerGeometry = SCNSphere(radius: 2.4)
        markerGeometry.firstMaterial?.diffuse.contents = UIColor.systemRed
        markerGeometry.firstMaterial?.emission.contents =
            UIColor.systemRed.withAlphaComponent(0.2)

        markerNode = SCNNode(geometry: markerGeometry)
        markerNode.isHidden = true

        scene.rootNode.addChildNode(meshNode)
        scene.rootNode.addChildNode(routeNode)
        scene.rootNode.addChildNode(markerNode)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 48
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 1_000_000
        scene.rootNode.addChildNode(cameraNode)

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1200
        scene.rootNode.addChildNode(keyLightNode)

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 500
        scene.rootNode.addChildNode(ambientNode)

        scene.background.contents = UIColor.systemBackground
    }

    func attach(to view: SCNView) {
        self.view = view
        view.pointOfView = cameraNode
        resetCamera()
    }

    func setMesh(_ mesh: Climb3DMesh, route: Climb3DRoute) {
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
        let scaled = p * Double(mesh.centerline.count - 1)

        let low = Int(floor(scaled))
        let high = min(mesh.centerline.count - 1, low + 1)
        let t = Float(scaled - Double(low))

        let a = mesh.centerline[low]
        let b = mesh.centerline[high]

        markerNode.position = SCNVector3(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t
        )

        markerNode.isHidden = false
    }

    func resetCamera() {
        guard let mesh else {
            cameraNode.position = SCNVector3(0, 100, 250)
            cameraNode.look(at: SCNVector3Zero)
            return
        }

        let xs = mesh.vertices.map(\.x)
        let ys = mesh.vertices.map(\.y)
        let zs = mesh.vertices.map(\.z)

        guard let minX = xs.min(),
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

        let sx = maxX - minX
        let sy = maxY - minY
        let sz = maxZ - minZ
        let radius = max(50, max(sx, max(sy, sz)))

        cameraNode.position = SCNVector3(
            center.x + radius * 0.9,
            center.y + radius * 0.75,
            center.z + radius * 1.2
        )
        cameraNode.look(at: center)

        keyLightNode.position = SCNVector3(
            center.x + radius,
            center.y + radius * 1.5,
            center.z + radius
        )

        view?.pointOfView = cameraNode
    }

    private func rebuildRoute(_ points: [Climb3DVertex]) {
        routeNode.childNodes.forEach {
            $0.removeFromParentNode()
        }

        guard points.count >= 2 else { return }

        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]

            let start = SCNVector3(a.x, a.y, a.z)
            let end = SCNVector3(b.x, b.y, b.z)

            routeNode.addChildNode(
                lineNode(from: start, to: end)
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
        let length = sqrt(dx * dx + dy * dy + dz * dz)

        let cylinder = SCNCylinder(
            radius: 0.9,
            height: CGFloat(length)
        )

        cylinder.firstMaterial?.diffuse.contents = UIColor.systemBlue
        cylinder.firstMaterial?.emission.contents =
            UIColor.systemBlue.withAlphaComponent(0.12)

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3(
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
