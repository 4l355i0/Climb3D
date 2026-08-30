import Foundation

struct Climb3DMeshBuilder {
    // Prototype parameters. Intentionally isolated from RideClimb.
    let roadHalfWidthM: Double = 10.0
    let verticalExaggeration: Double = 2.2
    let baseDepthM: Double = 10.0

    func build(from route: Climb3DRoute) throws -> Climb3DMesh {
        guard route.points.count >= 2 else {
            throw NSError(
                domain: "Climb3D.Mesh",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Route too short"
                ]
            )
        }

        let first = route.points[0]
        let latScale = 111_320.0
        let lonScale =
            111_320.0 *
            cos(first.latitude * .pi / 180)

        let minElevation =
            route.points.map(\.elevationM).min() ?? 0

        let planar: [(x: Double, z: Double, y: Double)] =
            route.points.map { p in
                (
                    x: (p.longitude - first.longitude) * lonScale,
                    z: -(p.latitude - first.latitude) * latScale,
                    y: (p.elevationM - minElevation) * verticalExaggeration
                )
            }

        var vertices: [Climb3DVertex] = []
        var centerline: [Climb3DVertex] = []
        vertices.reserveCapacity(planar.count * 4)
        centerline.reserveCapacity(planar.count)

        for i in planar.indices {
            let p = planar[i]

            let previous = planar[max(0, i - 1)]
            let next = planar[min(planar.count - 1, i + 1)]

            let dx = next.x - previous.x
            let dz = next.z - previous.z
            let length = max(0.001, sqrt(dx * dx + dz * dz))

            let nx = -dz / length
            let nz = dx / length

            let leftX = p.x + nx * roadHalfWidthM
            let leftZ = p.z + nz * roadHalfWidthM
            let rightX = p.x - nx * roadHalfWidthM
            let rightZ = p.z - nz * roadHalfWidthM

            let topY = p.y
            let bottomY = -baseDepthM

            vertices.append(
                Climb3DVertex(
                    x: Float(leftX),
                    y: Float(topY),
                    z: Float(leftZ)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(rightX),
                    y: Float(topY),
                    z: Float(rightZ)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(leftX),
                    y: Float(bottomY),
                    z: Float(leftZ)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(rightX),
                    y: Float(bottomY),
                    z: Float(rightZ)
                )
            )

            centerline.append(
                Climb3DVertex(
                    x: Float(p.x),
                    y: Float(topY + 1.5),
                    z: Float(p.z)
                )
            )
        }

        var triangles: [Climb3DTriangle] = []

        func idx(_ pointIndex: Int, _ offset: Int) -> Int32 {
            Int32(pointIndex * 4 + offset)
        }

        for i in 0..<(planar.count - 1) {
            // top
            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 0),
                    b: idx(i, 1),
                    c: idx(i + 1, 0)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 1),
                    b: idx(i + 1, 1),
                    c: idx(i + 1, 0)
                )
            )

            // left side
            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 2),
                    b: idx(i, 0),
                    c: idx(i + 1, 2)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 0),
                    b: idx(i + 1, 0),
                    c: idx(i + 1, 2)
                )
            )

            // right side
            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 1),
                    b: idx(i, 3),
                    c: idx(i + 1, 1)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 3),
                    b: idx(i + 1, 3),
                    c: idx(i + 1, 1)
                )
            )

            // bottom
            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 2),
                    b: idx(i + 1, 2),
                    c: idx(i, 3)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(i, 3),
                    b: idx(i + 1, 2),
                    c: idx(i + 1, 3)
                )
            )
        }

        // front cap
        triangles.append(
            Climb3DTriangle(
                a: idx(0, 2),
                b: idx(0, 1),
                c: idx(0, 0)
            )
        )
        triangles.append(
            Climb3DTriangle(
                a: idx(0, 2),
                b: idx(0, 3),
                c: idx(0, 1)
            )
        )

        let last = planar.count - 1

        // rear cap
        triangles.append(
            Climb3DTriangle(
                a: idx(last, 0),
                b: idx(last, 1),
                c: idx(last, 2)
            )
        )
        triangles.append(
            Climb3DTriangle(
                a: idx(last, 1),
                b: idx(last, 3),
                c: idx(last, 2)
            )
        )

        return Climb3DMesh(
            vertices: vertices,
            triangles: triangles,
            centerline: centerline
        )
    }
}
