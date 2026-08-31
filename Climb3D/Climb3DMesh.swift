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

    // Closed solid used only by STLWriter.
    let vertices: [Climb3DVertex]
    let triangles: [Climb3DTriangle]

    // Full GPX centerline used by marker and camera.
    let centerline: [Climb3DVertex]

    // Build 15 visual ribbon:
    // two shared vertices per path point: left, right.
    let visualVertices: [Climb3DVertex]

    // One grade value per segment between consecutive visual point pairs.
    let visualSegmentGrades: [Double]

    func sceneGeometry() -> SCNGeometry {

        guard visualVertices.count >= 4,
              visualVertices.count % 2 == 0 else {
            return SCNGeometry()
        }

        let pointCount =
            visualVertices.count / 2

        guard visualSegmentGrades.count ==
                pointCount - 1 else {
            return SCNGeometry()
        }

        let positions =
            visualVertices.map {
                SCNVector3($0.x, $0.y, $0.z)
            }

        // Shared vertices are what make the road visually continuous.
        // Accumulate adjacent face normals so lighting also flows smoothly
        // from one road segment into the next.
        var normals =
            Array(
                repeating: SCNVector3Zero,
                count: positions.count
            )

        for segment in visualSegmentGrades.indices {

            let left0 = segment * 2
            let right0 = left0 + 1
            let left1 = (segment + 1) * 2
            let right1 = left1 + 1

            let a = positions[left0]
            let b = positions[right0]
            let c = positions[left1]

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

            if n.y < 0 {
                n = SCNVector3(-n.x, -n.y, -n.z)
            }

            normals[left0] = add(normals[left0], n)
            normals[right0] = add(normals[right0], n)
            normals[left1] = add(normals[left1], n)
            normals[right1] = add(normals[right1], n)
        }

        normals =
            normals.map(normalize)

        let vertexSource =
            SCNGeometrySource(vertices: positions)

        let normalSource =
            SCNGeometrySource(normals: normals)

        // Grade colouring stays exactly a rendering concern.
        // Adjacent road segments may use different materials while still
        // sharing the same geometric vertices, so there are no physical gaps.
        var bucketIndices: [Int: [Int32]] = [:]

        for segment in visualSegmentGrades.indices {

            let bucket =
                gradeBucket(
                    visualSegmentGrades[segment]
                )

            let left0 = Int32(segment * 2)
            let right0 = left0 + 1
            let left1 = Int32((segment + 1) * 2)
            let right1 = left1 + 1

            let indices: [Int32] = [
                left0, left1, right0,
                right0, left1, right1
            ]

            bucketIndices[bucket, default: []]
                .append(contentsOf: indices)
        }

        let sortedBuckets =
            bucketIndices.keys.sorted()

        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []

        elements.reserveCapacity(sortedBuckets.count)
        materials.reserveCapacity(sortedBuckets.count)

        for bucket in sortedBuckets {

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

            elements.append(element)
            materials.append(
                material(forBucket: bucket)
            )
        }

        let geometry =
            SCNGeometry(
                sources: [
                    vertexSource,
                    normalSource
                ],
                elements: elements
            )

        geometry.materials = materials
        return geometry
    }

    // MARK: - Grade palette

    private func gradeBucket(
        _ grade: Double
    ) -> Int {

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

    private func material(
        forBucket bucket: Int
    ) -> SCNMaterial {

        let color: UIColor

        switch bucket {

        case 0:
            color = UIColor(
                red: 0.16,
                green: 0.58,
                blue: 0.92,
                alpha: 1.0
            )

        case 1:
            color = UIColor(
                red: 0.24,
                green: 0.76,
                blue: 0.48,
                alpha: 1.0
            )

        case 2:
            color = UIColor(
                red: 0.93,
                green: 0.78,
                blue: 0.20,
                alpha: 1.0
            )

        case 3:
            color = UIColor(
                red: 0.98,
                green: 0.53,
                blue: 0.12,
                alpha: 1.0
            )

        case 4:
            color = UIColor(
                red: 0.95,
                green: 0.32,
                blue: 0.10,
                alpha: 1.0
            )

        case 5:
            color = UIColor(
                red: 0.88,
                green: 0.12,
                blue: 0.12,
                alpha: 1.0
            )

        case 6:
            color = UIColor(
                red: 0.72,
                green: 0.08,
                blue: 0.22,
                alpha: 1.0
            )

        default:
            color = UIColor(
                red: 0.50,
                green: 0.07,
                blue: 0.32,
                alpha: 1.0
            )
        }

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents =
            color.withAlphaComponent(0.035)
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
