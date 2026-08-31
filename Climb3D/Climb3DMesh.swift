import Foundation
import SceneKit
import UIKit

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
        let positions = vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        var indices: [Int32] = []
        indices.reserveCapacity(triangles.count * 3)

        for t in triangles {
            indices += [t.a, t.b, t.c]
        }

        var normals = Array(repeating: SCNVector3Zero, count: positions.count)

        for triangle in triangles {
            let ia = Int(triangle.a)
            let ib = Int(triangle.b)
            let ic = Int(triangle.c)

            guard positions.indices.contains(ia),
                  positions.indices.contains(ib),
                  positions.indices.contains(ic) else {
                continue
            }

            let a = positions[ia]
            let b = positions[ib]
            let c = positions[ic]

            let ab = SCNVector3(
                b.x - a.x,
                b.y - a.y,
                b.z - a.z
            )

            let ac = SCNVector3(
                c.x - a.x,
                c.y - a.y,
                c.z - a.z
            )

            let n = normalize(cross(ab, ac))

            normals[ia] = add(normals[ia], n)
            normals[ib] = add(normals[ib], n)
            normals[ic] = add(normals[ic], n)
        }

        normals = normals.map(normalize)

        let vertexSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)

        let indexData = indices.withUnsafeBytes {
            Data($0)
        }

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: triangles.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(
            sources: [vertexSource, normalSource],
            elements: [element]
        )

        let material = SCNMaterial()
        // Warm road/terrain tone closer to the rider-view reference.
        material.diffuse.contents = UIColor.systemOrange
        material.roughness.contents = 0.90
        material.metalness.contents = 0.0
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true

        geometry.materials = [material]

        return geometry
    }

    private func cross(
        _ a: SCNVector3,
        _ b: SCNVector3
    ) -> SCNVector3 {
        SCNVector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    private func add(
        _ a: SCNVector3,
        _ b: SCNVector3
    ) -> SCNVector3 {
        SCNVector3(
            a.x + b.x,
            a.y + b.y,
            a.z + b.z
        )
    }

    private func normalize(
        _ v: SCNVector3
    ) -> SCNVector3 {
        let l = sqrt(
            v.x * v.x +
            v.y * v.y +
            v.z * v.z
        )

        guard l > 0.000001 else {
            return SCNVector3(0, 1, 0)
        }

        return SCNVector3(
            v.x / l,
            v.y / l,
            v.z / l
        )
    }
}
