import Foundation

struct Climb3DMeshBuilder {

    let pathHalfWidthM: Double = 6.0
    let verticalExaggeration: Double = 5.0
    let baseHeightM: Double = 8.0
    let centerlineLiftM: Double = 2.0
    let miterLimit: Double = 2.5

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

        let minimumElevation =
            route.points
                .map(\.elevationM)
                .min() ?? 0

        let points: [(x: Double, y: Double, z: Double)] =
            route.points.map { point in

                let x =
                    (point.longitude - first.longitude) *
                    lonScale

                let z =
                    -(point.latitude - first.latitude) *
                    latScale

                let y =
                    (point.elevationM - minimumElevation) *
                    verticalExaggeration

                return (
                    x: x,
                    y: y,
                    z: z
                )
            }

        var leftXZ: [(x: Double, z: Double)] = []
        var rightXZ: [(x: Double, z: Double)] = []

        leftXZ.reserveCapacity(points.count)
        rightXZ.reserveCapacity(points.count)

        for index in points.indices {

            let current = points[index]

            let previous =
                points[max(0, index - 1)]

            let next =
                points[min(points.count - 1, index + 1)]

            let incoming = normalized2D(
                x: current.x - previous.x,
                z: current.z - previous.z
            )

            let outgoing = normalized2D(
                x: next.x - current.x,
                z: next.z - current.z
            )

            let direction: (
                x: Double,
                z: Double
            )

            if index == 0 {

                direction = outgoing

            } else if index == points.count - 1 {

                direction = incoming

            } else {

                let sum = normalized2D(
                    x: incoming.x + outgoing.x,
                    z: incoming.z + outgoing.z
                )

                if abs(sum.x) < 0.000001 &&
                    abs(sum.z) < 0.000001 {

                    direction = outgoing

                } else {

                    direction = sum
                }
            }

            let baseNormal = normalized2D(
                x: -direction.z,
                z: direction.x
            )

            var offsetDistance =
                pathHalfWidthM

            if index > 0 &&
                index < points.count - 1 {

                let outgoingNormal =
                    normalized2D(
                        x: -outgoing.z,
                        z: outgoing.x
                    )

                let dot =
                    baseNormal.x *
                    outgoingNormal.x +
                    baseNormal.z *
                    outgoingNormal.z

                if abs(dot) > 0.15 {

                    offsetDistance =
                        pathHalfWidthM /
                        abs(dot)
                }

                offsetDistance = min(
                    offsetDistance,
                    pathHalfWidthM * miterLimit
                )
            }

            leftXZ.append(
                (
                    x:
                        current.x +
                        baseNormal.x *
                        offsetDistance,

                    z:
                        current.z +
                        baseNormal.z *
                        offsetDistance
                )
            )

            rightXZ.append(
                (
                    x:
                        current.x -
                        baseNormal.x *
                        offsetDistance,

                    z:
                        current.z -
                        baseNormal.z *
                        offsetDistance
                )
            )
        }

        let baseY = -baseHeightM

        var vertices: [Climb3DVertex] = []
        var centerline: [Climb3DVertex] = []

        vertices.reserveCapacity(
            points.count * 4
        )

        centerline.reserveCapacity(
            points.count
        )

        for index in points.indices {

            let point = points[index]
            let left = leftXZ[index]
            let right = rightXZ[index]

            vertices.append(
                Climb3DVertex(
                    x: Float(left.x),
                    y: Float(point.y),
                    z: Float(left.z)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(right.x),
                    y: Float(point.y),
                    z: Float(right.z)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(left.x),
                    y: Float(baseY),
                    z: Float(left.z)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(right.x),
                    y: Float(baseY),
                    z: Float(right.z)
                )
            )

            centerline.append(
                Climb3DVertex(
                    x: Float(point.x),
                    y: Float(
                        point.y +
                        centerlineLiftM
                    ),
                    z: Float(point.z)
                )
            )
        }

        var triangles: [Climb3DTriangle] = []

        func idx(
            _ pointIndex: Int,
            _ offset: Int
        ) -> Int32 {

            Int32(
                pointIndex * 4 +
                offset
            )
        }

        for index in 0..<(points.count - 1) {

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 0),
                    b: idx(index, 1),
                    c: idx(index + 1, 0)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 1),
                    b: idx(index + 1, 1),
                    c: idx(index + 1, 0)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 2),
                    b: idx(index, 0),
                    c: idx(index + 1, 2)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 0),
                    b: idx(index + 1, 0),
                    c: idx(index + 1, 2)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 1),
                    b: idx(index, 3),
                    c: idx(index + 1, 1)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 3),
                    b: idx(index + 1, 3),
                    c: idx(index + 1, 1)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 2),
                    b: idx(index + 1, 2),
                    c: idx(index, 3)
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: idx(index, 3),
                    b: idx(index + 1, 2),
                    c: idx(index + 1, 3)
                )
            )
        }

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

        let last =
            points.count - 1

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

    private func normalized2D(
        x: Double,
        z: Double
    ) -> (
        x: Double,
        z: Double
    ) {

        let length =
            sqrt(
                x * x +
                z * z
            )

        guard length > 0.000001 else {
            return (
                x: 0,
                z: 0
            )
        }

        return (
            x: x / length,
            z: z / length
        )
    }
}
