import Foundation

struct Climb3DMeshBuilder {

    // Strada visibile
    let roadHalfWidthM: Double = 4.0

    // Fascia di "terreno" attorno alla strada
    let terrainHalfWidthM: Double = 32.0

    // Spessore locale del terreno.
    // Importante: NON scende più a una quota fissa globale.
    let terrainThicknessM: Double = 12.0

    // Leggera enfasi verticale per rendere percepibile la salita
    let verticalExaggeration: Double = 1.5

    let roadLiftM: Double = 0.7
    let centerlineLiftM: Double = 1.4

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

        // TERRAIN:
        // 4 vertici per punto:
        // top-left, top-right, bottom-left, bottom-right
        var terrainVertices: [Climb3DVertex] = []

        // ROAD:
        // 2 vertici per punto:
        // left, right
        var roadVertices: [Climb3DVertex] = []

        var centerline: [Climb3DVertex] = []

        terrainVertices.reserveCapacity(points.count * 4)
        roadVertices.reserveCapacity(points.count * 2)
        centerline.reserveCapacity(points.count)

        for index in points.indices {

            let point = points[index]

            let previous =
                points[max(0, index - 1)]

            let next =
                points[min(points.count - 1, index + 1)]

            var dx =
                next.x - previous.x

            var dz =
                next.z - previous.z

            var length =
                sqrt(dx * dx + dz * dz)

            if length < 0.001 {

                if index > 0 {
                    dx =
                        point.x - previous.x

                    dz =
                        point.z - previous.z

                    length =
                        sqrt(dx * dx + dz * dz)
                }
            }

            if length < 0.001 {
                dx = 1
                dz = 0
                length = 1
            }

            let nx = -dz / length
            let nz = dx / length

            // MARK: Terrain

            let terrainLeftX =
                point.x +
                nx * terrainHalfWidthM

            let terrainLeftZ =
                point.z +
                nz * terrainHalfWidthM

            let terrainRightX =
                point.x -
                nx * terrainHalfWidthM

            let terrainRightZ =
                point.z -
                nz * terrainHalfWidthM

            let topY = point.y

            let bottomY =
                point.y -
                terrainThicknessM

            terrainVertices.append(
                Climb3DVertex(
                    x: Float(terrainLeftX),
                    y: Float(topY),
                    z: Float(terrainLeftZ)
                )
            )

            terrainVertices.append(
                Climb3DVertex(
                    x: Float(terrainRightX),
                    y: Float(topY),
                    z: Float(terrainRightZ)
                )
            )

            terrainVertices.append(
                Climb3DVertex(
                    x: Float(terrainLeftX),
                    y: Float(bottomY),
                    z: Float(terrainLeftZ)
                )
            )

            terrainVertices.append(
                Climb3DVertex(
                    x: Float(terrainRightX),
                    y: Float(bottomY),
                    z: Float(terrainRightZ)
                )
            )

            // MARK: Road

            let roadLeftX =
                point.x +
                nx * roadHalfWidthM

            let roadLeftZ =
                point.z +
                nz * roadHalfWidthM

            let roadRightX =
                point.x -
                nx * roadHalfWidthM

            let roadRightZ =
                point.z -
                nz * roadHalfWidthM

            roadVertices.append(
                Climb3DVertex(
                    x: Float(roadLeftX),
                    y: Float(point.y + roadLiftM),
                    z: Float(roadLeftZ)
                )
            )

            roadVertices.append(
                Climb3DVertex(
                    x: Float(roadRightX),
                    y: Float(point.y + roadLiftM),
                    z: Float(roadRightZ)
                )
            )

            centerline.append(
                Climb3DVertex(
                    x: Float(point.x),
                    y: Float(point.y + centerlineLiftM),
                    z: Float(point.z)
                )
            )
        }

        // MARK: Terrain triangles

        var terrainTriangles: [Climb3DTriangle] = []

        func terrainIndex(
            _ point: Int,
            _ offset: Int
        ) -> Int32 {
            Int32(point * 4 + offset)
        }

        for i in 0..<(points.count - 1) {

            // top
            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 0),
                    b: terrainIndex(i, 1),
                    c: terrainIndex(i + 1, 0)
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 1),
                    b: terrainIndex(i + 1, 1),
                    c: terrainIndex(i + 1, 0)
                )
            )

            // left wall
            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 2),
                    b: terrainIndex(i, 0),
                    c: terrainIndex(i + 1, 2)
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 0),
                    b: terrainIndex(i + 1, 0),
                    c: terrainIndex(i + 1, 2)
                )
            )

            // right wall
            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 1),
                    b: terrainIndex(i, 3),
                    c: terrainIndex(i + 1, 1)
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 3),
                    b: terrainIndex(i + 1, 3),
                    c: terrainIndex(i + 1, 1)
                )
            )

            // bottom
            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 2),
                    b: terrainIndex(i + 1, 2),
                    c: terrainIndex(i, 3)
                )
            )

            terrainTriangles.append(
                Climb3DTriangle(
                    a: terrainIndex(i, 3),
                    b: terrainIndex(i + 1, 2),
                    c: terrainIndex(i + 1, 3)
                )
            )
        }

        // Caps
        terrainTriangles.append(
            Climb3DTriangle(
                a: terrainIndex(0, 2),
                b: terrainIndex(0, 1),
                c: terrainIndex(0, 0)
            )
        )

        terrainTriangles.append(
            Climb3DTriangle(
                a: terrainIndex(0, 2),
                b: terrainIndex(0, 3),
                c: terrainIndex(0, 1)
            )
        )

        let last =
            points.count - 1

        terrainTriangles.append(
            Climb3DTriangle(
                a: terrainIndex(last, 0),
                b: terrainIndex(last, 1),
                c: terrainIndex(last, 2)
            )
        )

        terrainTriangles.append(
            Climb3DTriangle(
                a: terrainIndex(last, 1),
                b: terrainIndex(last, 3),
                c: terrainIndex(last, 2)
            )
        )

        // MARK: Road triangles

        var roadTriangles: [Climb3DTriangle] = []

        func roadLeft(_ point: Int) -> Int32 {
            Int32(point * 2)
        }

        func roadRight(_ point: Int) -> Int32 {
            Int32(point * 2 + 1)
        }

        for i in 0..<(points.count - 1) {

            roadTriangles.append(
                Climb3DTriangle(
                    a: roadLeft(i),
                    b: roadRight(i),
                    c: roadLeft(i + 1)
                )
            )

            roadTriangles.append(
                Climb3DTriangle(
                    a: roadRight(i),
                    b: roadRight(i + 1),
                    c: roadLeft(i + 1)
                )
            )
        }

        return Climb3DMesh(
            vertices: terrainVertices,
            triangles: terrainTriangles,
            centerline: centerline,
            roadVertices: roadVertices,
            roadTriangles: roadTriangles
        )
    }
}
