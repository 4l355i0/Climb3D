import Foundation

struct Climb3DMeshBuilder {

    /*
     VISUAL MODEL ONLY

     RideClimb physics remain authoritative.
    */

    let roadHalfWidthM: Double = 5.0

    // Local block thickness under the road.
    let roadThicknessM: Double = 10.0

    // Deliberately exaggerated for visual perception.
    let verticalExaggeration: Double = 2.2

    let roadLiftM: Double = 0.8
    let centerlineLiftM: Double = 1.5

    func build(
        from route: Climb3DRoute
    ) throws -> Climb3DMesh {

        guard route.points.count >= 2 else {
            throw NSError(
                domain: "Climb3D.Mesh",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Route too short"
                ]
            )
        }

        let first = route.points[0]

        let latScale = 111_320.0

        let lonScale =
            111_320.0 *
            cos(
                first.latitude *
                .pi /
                180
            )

        let minElevation =
            route.points
                .map(\.elevationM)
                .min() ?? 0

        let points:
            [
                (
                    x: Double,
                    y: Double,
                    z: Double
                )
            ] =
            route.points.map { point in

                let x =
                    (
                        point.longitude -
                        first.longitude
                    ) *
                    lonScale

                let z =
                    -(
                        point.latitude -
                        first.latitude
                    ) *
                    latScale

                let y =
                    (
                        point.elevationM -
                        minElevation
                    ) *
                    verticalExaggeration

                return (
                    x: x,
                    y: y,
                    z: z
                )
            }

        /*
         Four vertices per route point:

         top-left
         top-right
         bottom-left
         bottom-right

         The bottom follows the local elevation:
         topY - roadThicknessM.

         This gives volume without building huge
         terrain sheets around the route.
        */

        var vertices:
            [Climb3DVertex] = []

        var centerline:
            [Climb3DVertex] = []

        vertices.reserveCapacity(
            points.count * 4
        )

        centerline.reserveCapacity(
            points.count
        )

        for index in points.indices {

            let point =
                points[index]

            let previous =
                points[
                    max(
                        0,
                        index - 1
                    )
                ]

            let next =
                points[
                    min(
                        points.count - 1,
                        index + 1
                    )
                ]

            var dx =
                next.x -
                previous.x

            var dz =
                next.z -
                previous.z

            var length =
                sqrt(
                    dx * dx +
                    dz * dz
                )

            if length < 0.001 {

                if index > 0 {

                    dx =
                        point.x -
                        previous.x

                    dz =
                        point.z -
                        previous.z

                    length =
                        sqrt(
                            dx * dx +
                            dz * dz
                        )
                }
            }

            if length < 0.001 {
                dx = 1
                dz = 0
                length = 1
            }

            let nx =
                -dz /
                length

            let nz =
                dx /
                length

            let leftX =
                point.x +
                nx *
                roadHalfWidthM

            let leftZ =
                point.z +
                nz *
                roadHalfWidthM

            let rightX =
                point.x -
                nx *
                roadHalfWidthM

            let rightZ =
                point.z -
                nz *
                roadHalfWidthM

            let topY =
                point.y +
                roadLiftM

            let bottomY =
                topY -
                roadThicknessM

            // Top left
            vertices.append(
                Climb3DVertex(
                    x: Float(leftX),
                    y: Float(topY),
                    z: Float(leftZ)
                )
            )

            // Top right
            vertices.append(
                Climb3DVertex(
                    x: Float(rightX),
                    y: Float(topY),
                    z: Float(rightZ)
                )
            )

            // Bottom left
            vertices.append(
                Climb3DVertex(
                    x: Float(leftX),
                    y: Float(bottomY),
                    z: Float(leftZ)
                )
            )

            // Bottom right
            vertices.append(
                Climb3DVertex(
                    x: Float(rightX),
                    y: Float(bottomY),
                    z: Float(rightZ)
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

        var triangles:
            [Climb3DTriangle] = []

        func idx(
            _ point: Int,
            _ offset: Int
        ) -> Int32 {

            Int32(
                point * 4 +
                offset
            )
        }

        for index in
            0..<(points.count - 1) {

            // TOP
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

            // LEFT SIDE
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

            // RIGHT SIDE
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

            // BOTTOM
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

        // Front cap
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

        // Rear cap
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
