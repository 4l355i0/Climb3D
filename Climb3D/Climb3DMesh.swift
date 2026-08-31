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

    // Solid mesh used only by STLWriter.
    let vertices: [Climb3DVertex]
    let triangles: [Climb3DTriangle]

    // Full GPX centerline used by progress marker and follow camera.
    let centerline: [Climb3DVertex]

    // Separate visual road. It intentionally contains only the top road
    // surface: no vertical walls, no base and no STL extrusion in SceneKit.
    // Four vertices are stored for each visual segment:
    // start-left, start-right, end-left, end-right.
    let visualVertices: [Climb3DVertex]
    let visualSegmentGrades: [Double]

    func sceneGeometry() -> SCNGeometry {

        guard !visualVertices.isEmpty,
              visualVertices.count >= 4,
              visualVertices.count / 4 == visualSegmentGrades.count else {

            return SCNGeometry()
        }

        let positions =
            visualVertices.map {
                SCNVector3($0.x, $0.y, $0.z)
            }

        // Visual segment vertices are intentionally not shared. This is
        // important on hairpins: each road leg stays a bounded rectangle
        // and cannot generate an enormous miter/cusp across the inside turn.
        var normals =
            Array(
                repeating: SCNVector3(0, 1, 0),
                count: positions.count
            )

        for segment in visualSegmentGrades.indices {

            let base = segment * 4

            let a = positions[base]
            let b = positions[base + 1]
            let c = positions[base + 2]

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

            var n = normalize(cross(ac, ab))

            // Keep the top surface normal facing upward for stable lighting.
            if n.y < 0 {
                n = SCNVector3(-n.x, -n.y, -n.z)
            }

            normals[base] = n
            normals[base + 1] = n
            normals[base + 2] = n
            normals[base + 3] = n
        }

        let vertexSource =
            SCNGeometrySource(vertices: positions)

        let normalSource =
            SCNGeometrySource(normals: normals)

        // Group all road segments into a small number of grade buckets.
        // This gives per-grade coloring without creating thousands of
        // SceneKit materials/elements on a long GPX.
        var bucketIndices: [Int: [Int32]] = [:]

        for segment in visualSegmentGrades.indices {

            let bucket = gradeBucket(visualSegmentGrades[segment])
            let base = Int32(segment * 4)

            // Upward-facing two-triangle quad.
            let indices: [Int32] = [
                base, base + 2, base + 1,
                base + 1, base + 2, base + 3
            ]

            bucketIndices[bucket, default: []]
                .append(contentsOf: indices)
        }

        let sortedBuckets = bucketIndices.keys.sorted()

        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []

        elements.reserveCapacity(sortedBuckets.count)
        materials.reserveCapacity(sortedBuckets.count)

        for (materialIndex, bucket) in sortedBuckets.enumerated() {

            guard let indices = bucketIndices[bucket],
                  !indices.isEmpty else {
                continue
            }

            let indexData =
                indices.withUnsafeBytes {
                    Data($0)
                }

            let element =
                SCNGeometryElement(
                    data: indexData,
                    primitiveType: .triangles,
                    primitiveCount: indices.count / 3,
                    bytesPerIndex: MemoryLayout<Int32>.size
                )

            element.materialIndex = materialIndex
            elements.append(element)
            materials.append(material(forBucket: bucket))
        }

        let geometry =
            SCNGeometry(
                sources: [vertexSource, normalSource],
                elements: elements
            )

        geometry.materials = materials
        return geometry
    }

    // MARK: - Climb Portal-style grade palette

    private func gradeBucket(_ grade: Double) -> Int {

        switch grade {
        case ..<0:
            return 0
        case 0..<3:
            return 1
        case 3..<5:
            return 2
        case 5..<7:
            return 3
        case 7..<9:
            return 4
        case 9..<12:
            return 5
        case 12..<15:
            return 6
        default:
            return 7
        }
    }

    private func material(forBucket bucket: Int) -> SCNMaterial {

        let color: UIColor

        switch bucket {
        case 0:
            // Descent / negative grade.
            color = UIColor(
                red: 0.16,
                green: 0.58,
                blue: 0.92,
                alpha: 1.0
            )

        case 1:
            // 0-3 %.
            color = UIColor(
                red: 0.24,
                green: 0.76,
                blue: 0.48,
                alpha: 1.0
            )

        case 2:
            // 3-5 %.
            color = UIColor(
                red: 0.93,
                green: 0.78,
                blue: 0.20,
                alpha: 1.0
            )

        case 3:
            // 5-7 %.
            color = UIColor(
                red: 0.98,
                green: 0.53,
                blue: 0.12,
                alpha: 1.0
            )

        case 4:
            // 7-9 %.
            color = UIColor(
                red: 0.95,
                green: 0.32,
                blue: 0.10,
                alpha: 1.0
            )

        case 5:
            // 9-12 %.
            color = UIColor(
                red: 0.88,
                green: 0.12,
                blue: 0.12,
                alpha: 1.0
            )

        case 6:
            // 12-15 %.
            color = UIColor(
                red: 0.72,
                green: 0.08,
                blue: 0.22,
                alpha: 1.0
            )

        default:
            // 15 %+.
            color = UIColor(
                red: 0.50,
                green: 0.07,
                blue: 0.32,
                alpha: 1.0
            )
        }

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.035)
        material.roughness.contents = 0.90
        material.metalness.contents = 0.0
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true

        return material
    }

    // MARK: - Vector helpers

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

    private func normalize(
        _ v: SCNVector3
    ) -> SCNVector3 {

        let length =
            sqrt(
                v.x * v.x +
                v.y * v.y +
                v.z * v.z
            )

        guard length > 0.000001 else {
            return SCNVector3(0, 1, 0)
        }

        return SCNVector3(
            v.x / length,
            v.y / length,
            v.z / length
        )
    }
}
