import Foundation
import SceneKit

struct Climb3DVertex {
    let x: Float
    let y: Float
    let z: Float
}

struct Climb3DTriangle {
    let a: Int32
    let b: Int32
    let c: Int32
}

struct Climb3DMesh {
    let vertices: [Climb3DVertex]
    let triangles: [Climb3DTriangle]
    let centerline: [Climb3DVertex]

    func sceneGeometry() -> SCNGeometry {
        var positions: [SCNVector3] = vertices.map {
            SCNVector3($0.x, $0.y, $0.z)
        }

        var indices: [Int32] = []
        indices.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            indices.append(triangle.a)
            indices.append(triangle.b)
            indices.append(triangle.c)
        }

        let vertexData = Data(
            bytes: &positions,
            count: MemoryLayout<SCNVector3>.stride * positions.count
        )

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )

        let indexData = indices.withUnsafeBytes { Data($0) }

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: triangles.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(
            sources: [vertexSource],
            elements: [element]
        )

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemGray3
        material.roughness.contents = 0.85
        material.metalness.contents = 0.02
        material.isDoubleSided = true

        geometry.materials = [material]

        return geometry
    }
}
