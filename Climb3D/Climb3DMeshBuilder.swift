import Foundation

struct Climb3DMeshBuilder {

    // Width of the rendered road in metres.
    // Kept deliberately wider than a real road so it stays visible on iPhone.
    let roadHalfWidthM: Double = 15.0

    // Much more conservative than the old 2.2.
    // 1.0 = geometrically correct elevation.
    let verticalExaggeration: Double = 1.25

    // Small visual offset for marker / centerline.
    let routeLiftM: Double = 1.0

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
            route.points
                .map(\.elevationM)
                .min() ?? 0

        /*
         Convert GPX coordinates into local metric coordinates.

         X = east/west
         Z = north/south
         Y = elevation

         This keeps the actual GPS geometry of the route.
        */
        let points: [(x: Double, y: Double, z: Double)] =
            route.points.map { point in

                let x =
                    (point.longitude - first.longitude) *
                    lonScale

                let z =
                    -(point.latitude - first.latitude) *
                    latScale

                let y =
                    (point.elevationM - minElevation) *
                    verticalExaggeration

                return (
                    x: x,
                    y: y,
                    z: z
                )
            }

        /*
         Two vertices for every GPX point:

             left -------- right

         No extrusion downward.
         No side walls.
         No bottom surface.

         This produces a true 3D road ribbon.
        */

        var vertices: [Climb3DVertex] = []
        var centerline: [Climb3DVertex] = []

        vertices.reserveCapacity(
            points.count * 2
        )

        centerline.reserveCapacity(
            points.count
        )

        for index in points.indices {

            let point = points[index]

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

            /*
             Direction of travel in the horizontal plane.
            */
            var dx =
                next.x -
                previous.x

            var dz =
                next.z -
                previous.z

            var horizontalLength =
                sqrt(
                    dx * dx +
                    dz * dz
                )

            /*
             Protect against duplicate GPX points.
            */
            if horizontalLength < 0.001 {

                if index > 0 {
                    dx =
                        point.x -
                        previous.x

                    dz =
                        point.z -
                        previous.z

                    horizontalLength =
                        sqrt(
                            dx * dx +
                            dz * dz
                        )
                }
            }

            if horizontalLength < 0.001 {
                dx = 1
                dz = 0
                horizontalLength = 1
            }

            /*
             Perpendicular horizontal vector.

             This creates the left/right road edges.
            */
            let normalX =
                -dz /
                horizontalLength

            let normalZ =
                dx /
                horizontalLength

            let left =
                Climb3DVertex(
                    x: Float(
                        point.x +
                        normalX *
                        roadHalfWidthM
                    ),
                    y: Float(
                        point.y
                    ),
                    z: Float(
                        point.z +
                        normalZ *
                        roadHalfWidthM
                    )
                )

            let right =
                Climb3DVertex(
                    x: Float(
                        point.x -
                        normalX *
                        roadHalfWidthM
                    ),
                    y: Float(
                        point.y
                    ),
                    z: Float(
                        point.z -
                        normalZ *
                        roadHalfWidthM
                    )
                )

            vertices.append(left)
            vertices.append(right)

            /*
             Centerline follows the real route.
             A small vertical lift avoids z-fighting
             with the road surface.
            */
            centerline.append(
                Climb3DVertex(
                    x: Float(point.x),
                    y: Float(
                        point.y +
                        routeLiftM
                    ),
                    z: Float(point.z)
                )
            )
        }

        /*
         Build the road surface.

         Each pair of consecutive GPX points
         becomes one quad made of two triangles.

             L0 -------- R0
              | \        |
              |   \      |
             L1 -------- R1
        */

        var triangles: [Climb3DTriangle] = []

        triangles.reserveCapacity(
            (points.count - 1) * 2
        )

        func leftIndex(
            _ pointIndex: Int
        ) -> Int32 {
            Int32(
                pointIndex * 2
            )
        }

        func rightIndex(
            _ pointIndex: Int
        ) -> Int32 {
            Int32(
                pointIndex * 2 + 1
            )
        }

        for index in 0..<(points.count - 1) {

            let left0 =
                leftIndex(index)

            let right0 =
                rightIndex(index)

            let left1 =
                leftIndex(index + 1)

            let right1 =
                rightIndex(index + 1)

            triangles.append(
                Climb3DTriangle(
                    a: left0,
                    b: right0,
                    c: left1
                )
            )

            triangles.append(
                Climb3DTriangle(
                    a: right0,
                    b: right1,
                    c: left1
                )
            )
        }

        return Climb3DMesh(
            vertices: vertices,
            triangles: triangles,
            centerline: centerline
        )
    }
}
