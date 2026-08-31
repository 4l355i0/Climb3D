import Foundation

struct Climb3DMeshBuilder {

    /*
     VISUAL MODEL

     RideClimb physics are completely separate.
    */

    let roadHalfWidthM: Double = 4.0

    // Wider visual terrain corridor
    let terrainHalfWidthM: Double = 42.0

    // Makes the terrain mass clearly visible
    let terrainThicknessM: Double = 22.0

    // Deliberately exaggerated for visual perception
    let verticalExaggeration: Double = 2.2

    let roadLiftM: Double = 1.0
    let centerlineLiftM: Double = 1.8

    func build(
        from route: Climb3DRoute
    ) throws -> Climb3DMesh {

        guard route.points.count >= 2 else {

            throw NSError(
                domain:
                    "Climb3D.Mesh",
                code:
                    1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Route too short"
                ]
            )
        }

        let first =
            route.points[0]

        let latScale =
            111_320.0

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

        var terrainVertices:
            [Climb3DVertex] = []

        var roadVertices:
            [Climb3DVertex] = []

        var centerline:
            [Climb3DVertex] = []

        terrainVertices.reserveCapacity(
            points.count * 4
        )

        roadVertices.reserveCapacity(
            points.count * 2
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

            // MARK: Terrain

            let terrainLeftX =
                point.x +
                nx *
                terrainHalfWidthM

            let terrainLeftZ =
                point.z +
                nz *
                terrainHalfWidthM

            let terrainRightX =
                point.x -
                nx *
                terrainHalfWidthM

            let terrainRightZ =
                point.z -
                nz *
                terrainHalfWidthM

            let topY =
                point.y

            /*
             Local thickness follows the road.
             No global "wall to zero".
            */

            let bottomY =
                point.y -
                terrainThicknessM

            terrainVertices.append(
                Climb3DVertex(
                    x:
                        Float(
                            terrainLeftX
                        ),
                    y:
                        Float(topY),
                    z:
                        Float(
                            terrainLeftZ
                        )
                )
            )

            terrainVertices.append(
                Climb3DVertex(
                    x:
                        Float(
                            terrainRightX
                        ),
                    y:
                        Float(topY),
                    z:
                        Float(
                            terrainRightZ
                        )
                )
            )

            terrainVertices.append(
                Climb3DVertex(
                    x:
                        Float(
                            terrainLeftX
                        ),
                    y:
                        Float(bottomY),
                    z:
                        Float(
                            terrainLeftZ
                        )
                )
            )

            terrainVertices.append(
                Climb3DVertex(
                    x:
                        Float(
                            terrainRightX
                        ),
                    y:
                        Float(bottomY),
                    z:
                        Float(
                            terrainRightZ
                        )
                )
            )

            // MARK: Road

            let roadLeftX =
                point.x +
                nx *
                roadHalfWidthM

            let roadLeftZ =
                point.z +
                nz *
                roadHalfWidthM

            let roadRightX =
                point.x -
                nx *
                roadHalfWidthM

            let roadRightZ =
                point.z -
                nz *
                roadHalfWidthM

            roadVertices.append(
                Climb3DVertex(
                    x:
                        Float(
                            roadLeftX
                        ),
                    y:
                        Float(
                            point.y +
                            roadLiftM
                        ),
                    z:
                        Float(
                            roadLeftZ
                        )
                )
            )

            roadVertices.append(
                Climb3DVertex(
                    x:
                        Float(
                            roadRightX
                        ),
                    y:
                        Float(
                            point.y +
                            roadLiftM
                        ),
                    z:
                        Float(
                            roadRightZ
                        )
                )
            )

            centerline.append(
                Climb3DVertex(
                    x:
                        Float(
                            point.x
                        ),
                    y:
                        Float(
                            point.y +
                            centerlineLiftM
                        ),
                    z:
                        Float(
                            point.z
                        )
                )
            )
        }

        // MARK: Terrain triangles

        var terrainTriangles:
            [Climb3DTriangle] = []

        func terrainIndex(
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

            // Top
            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            0
                        ),
                    b:
                        terrainIndex(
                            index,
                            1
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            0
                        )
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            1
                        ),
                    b:
                        terrainIndex(
                            index + 1,
                            1
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            0
                        )
                )
            )

            // Left side
            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            2
                        ),
                    b:
                        terrainIndex(
                            index,
                            0
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            2
                        )
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            0
                        ),
                    b:
                        terrainIndex(
                            index + 1,
                            0
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            2
                        )
                )
            )

            // Right side
            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            1
                        ),
                    b:
                        terrainIndex(
                            index,
                            3
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            1
                        )
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            3
                        ),
                    b:
                        terrainIndex(
                            index + 1,
                            3
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            1
                        )
                )
            )

            // Bottom
            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            2
                        ),
                    b:
                        terrainIndex(
                            index + 1,
                            2
                        ),
                    c:
                        terrainIndex(
                            index,
                            3
                        )
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a:
                        terrainIndex(
                            index,
                            3
                        ),
                    b:
                        terrainIndex(
                            index + 1,
                            2
                        ),
                    c:
                        terrainIndex(
                            index + 1,
                            3
                        )
                )
            )
        }

        // Front cap

        terrainTriangles.append(
            Climb3DTriangle(
                a:
                    terrainIndex(
                        0,
                        2
                    ),
                b:
                    terrainIndex(
                        0,
                        1
                    ),
                c:
                    terrainIndex(
                        0,
                        0
                    )
            )
        )

        terrainTriangles.append(
            Climb3DTriangle(
                a:
                    terrainIndex(
                        0,
                        2
                    ),
                b:
                    terrainIndex(
                        0,
                        3
                    ),
                c:
                    terrainIndex(
                        0,
                        1
                    )
            )
        )

        let last =
            points.count - 1

        // Rear cap

        terrainTriangles.append(
            Climb3DTriangle(
                a:
                    terrainIndex(
                        last,
                        0
                    ),
                b:
                    terrainIndex(
                        last,
                        1
                    ),
                c:
                    terrainIndex(
                        last,
                        2
                    )
            )
        )

        terrainTriangles.append(
            Climb3DTriangle(
                a:
                    terrainIndex(
                        last,
                        1
                    ),
                b:
                    terrainIndex(
                        last,
                        3
                    ),
                c:
                    terrainIndex(
                        last,
                        2
                    )
            )
        )

        // MARK: Road triangles

        var roadTriangles:
            [Climb3DTriangle] = []

        func roadLeft(
            _ point: Int
        ) -> Int32 {

            Int32(
                point * 2
            )
        }

        func roadRight(
            _ point: Int
        ) -> Int32 {

            Int32(
                point * 2 + 1
            )
        }

        for index in
            0..<(points.count - 1) {

            roadTriangles.append(
                Climb3DTriangle(
                    a:
                        roadLeft(
                            index
                        ),
                    b:
                        roadRight(
                            index
                        ),
                    c:
                        roadLeft(
                            index + 1
                        )
                )
            )

            roadTriangles.append(
                Climb3DTriangle(
                    a:
                        roadRight(
                            index
                        ),
                    b:
                        roadRight(
                            index + 1
                        ),
                    c:
                        roadLeft(
                            index + 1
                        )
                )
            )
        }

        return Climb3DMesh(
            vertices:
                terrainVertices,

            triangles:
                terrainTriangles,

            centerline:
                centerline,

            roadVertices:
                roadVertices,

            roadTriangles:
                roadTriangles
        )
    }
}
