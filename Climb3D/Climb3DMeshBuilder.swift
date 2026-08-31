import Foundation

struct Climb3DMeshBuilder {

    // STL solid dimensions are retained from Build 13 so STLWriter keeps
    // receiving a closed GPXtruder-style solid.
    let stlHalfWidthM: Double = 5.0
    let stlJoinLimitMultiplier: Double = 2.0

    // Build 14 visual road is intentionally much narrower than the solid.
    // It is rendered independently, so the STL walls never appear on screen.
    let visualHalfWidthM: Double = 3.0

    // Small overlap at the end of each independent road segment fills the
    // inside wedge of normal bends without creating a long miter at hairpins.
    let visualSegmentOverlapM: Double = 1.0

    // GPXtruder-style vertical exaggeration.
    let verticalExaggeration: Double = 5.0

    let baseHeightM: Double = 8.0

    // Keep centerline almost on the visual road. Build 13 lifted it by more
    // than a metre, making the white line and marker look detached.
    let centerlineLiftM: Double = 0.10

    private struct ProjectedPoint {
        let x: Double
        let y: Double
        let z: Double
    }

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

        // Full centerline remains 1:1 with route.points. Marker and camera
        // therefore continue to interpolate against route.distanceM exactly.
        let allPoints: [ProjectedPoint] =
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

                return ProjectedPoint(
                    x: x,
                    y: y,
                    z: z
                )
            }

        // Same path preparation as Build 13: remove only pathological
        // near-duplicates. No XY moving average, so hairpins are not cut.
        let meshPoints =
            prepareMeshPath(allPoints)

        guard meshPoints.count >= 2 else {
            throw NSError(
                domain: "Climb3D.Mesh",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to create path geometry"
                ]
            )
        }

        // -----------------------------------------------------------------
        // 1) CLOSED STL SOLID
        // -----------------------------------------------------------------

        let stlEdges =
            buildBufferedEdges(
                meshPoints,
                halfWidth: stlHalfWidthM,
                joinLimitMultiplier: stlJoinLimitMultiplier
            )

        let baseY = -baseHeightM

        var vertices: [Climb3DVertex] = []
        vertices.reserveCapacity(meshPoints.count * 4)

        for index in meshPoints.indices {

            let point = meshPoints[index]
            let edges = stlEdges[index]

            // 0 top-left, 1 top-right, 2 base-left, 3 base-right.
            vertices.append(
                Climb3DVertex(
                    x: Float(edges.left.x),
                    y: Float(point.y),
                    z: Float(edges.left.z)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(edges.right.x),
                    y: Float(point.y),
                    z: Float(edges.right.z)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(edges.left.x),
                    y: Float(baseY),
                    z: Float(edges.left.z)
                )
            )

            vertices.append(
                Climb3DVertex(
                    x: Float(edges.right.x),
                    y: Float(baseY),
                    z: Float(edges.right.z)
                )
            )
        }

        var triangles: [Climb3DTriangle] = []
        triangles.reserveCapacity((meshPoints.count - 1) * 8 + 4)

        func idx(
            _ pointIndex: Int,
            _ offset: Int
        ) -> Int32 {

            Int32(pointIndex * 4 + offset)
        }

        for index in 0..<(meshPoints.count - 1) {

            // Top.
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

            // Left wall.
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

            // Right wall.
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

            // Bottom.
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

        // Start cap.
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

        // End cap.
        let last = meshPoints.count - 1

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

        // -----------------------------------------------------------------
        // 2) VISUAL ROAD ONLY
        // -----------------------------------------------------------------
        // Every road leg is an independent bounded quad. There is no miter
        // intersection at a hairpin, therefore no giant triangular spike or
        // wall can shoot across the inside of the turn.

        var visualVertices: [Climb3DVertex] = []
        var visualSegmentGrades: [Double] = []

        visualVertices.reserveCapacity((meshPoints.count - 1) * 4)
        visualSegmentGrades.reserveCapacity(meshPoints.count - 1)

        for index in 0..<(meshPoints.count - 1) {

            let a = meshPoints[index]
            let b = meshPoints[index + 1]

            let dx = b.x - a.x
            let dz = b.z - a.z

            let horizontalLength =
                sqrt(dx * dx + dz * dz)

            guard horizontalLength > 0.001 else {
                continue
            }

            let dirX = dx / horizontalLength
            let dirZ = dz / horizontalLength

            let normalX = -dirZ
            let normalZ = dirX

            // Keep overlap small and bounded. It closes normal corner wedges
            // but never scales with turn angle, unlike a miter join.
            let overlap =
                min(
                    visualSegmentOverlapM,
                    horizontalLength * 0.15
                )

            let startX = a.x - dirX * overlap
            let startZ = a.z - dirZ * overlap

            let endX = b.x + dirX * overlap
            let endZ = b.z + dirZ * overlap

            // Four unique vertices for this segment.
            visualVertices.append(
                Climb3DVertex(
                    x: Float(startX + normalX * visualHalfWidthM),
                    y: Float(a.y),
                    z: Float(startZ + normalZ * visualHalfWidthM)
                )
            )

            visualVertices.append(
                Climb3DVertex(
                    x: Float(startX - normalX * visualHalfWidthM),
                    y: Float(a.y),
                    z: Float(startZ - normalZ * visualHalfWidthM)
                )
            )

            visualVertices.append(
                Climb3DVertex(
                    x: Float(endX + normalX * visualHalfWidthM),
                    y: Float(b.y),
                    z: Float(endZ + normalZ * visualHalfWidthM)
                )
            )

            visualVertices.append(
                Climb3DVertex(
                    x: Float(endX - normalX * visualHalfWidthM),
                    y: Float(b.y),
                    z: Float(endZ - normalZ * visualHalfWidthM)
                )
            )

            // Grade is calculated from the real elevation, not the 5x visual
            // exaggeration. Elevation has already been smoothed by Route.
            let realRise =
                (b.y - a.y) /
                verticalExaggeration

            let grade =
                realRise /
                horizontalLength *
                100

            visualSegmentGrades.append(
                min(25, max(-15, grade))
            )
        }

        let centerline =
            allPoints.map { point in
                Climb3DVertex(
                    x: Float(point.x),
                    y: Float(point.y + centerlineLiftM),
                    z: Float(point.z)
                )
            }

        return Climb3DMesh(
            vertices: vertices,
            triangles: triangles,
            centerline: centerline,
            visualVertices: visualVertices,
            visualSegmentGrades: visualSegmentGrades
        )
    }

    // MARK: - Path preparation

    private func prepareMeshPath(
        _ source: [ProjectedPoint]
    ) -> [ProjectedPoint] {

        guard source.count >= 2 else {
            return source
        }

        let minimumDistanceM = 1.5

        var filtered: [ProjectedPoint] = []
        filtered.reserveCapacity(source.count)
        filtered.append(source[0])

        for point in source.dropFirst().dropLast() {

            guard let last = filtered.last else {
                filtered.append(point)
                continue
            }

            if horizontalDistance(last, point) >= minimumDistanceM {
                filtered.append(point)
            }
        }

        if let last = source.last {

            if filtered.count == 1 ||
                horizontalDistance(
                    filtered[filtered.count - 1],
                    last
                ) > 0.01 {

                filtered.append(last)
            }
        }

        guard filtered.count >= 4 else {
            return filtered
        }

        // Retain Build 13 protection against consecutive pathological GPS
        // reversals. Genuine rounded hairpins remain because they consist of
        // several moderate direction changes.
        var result: [ProjectedPoint] = []
        result.reserveCapacity(filtered.count)

        var i = 0

        while i < filtered.count {

            if i > 0 && i < filtered.count - 2 {

                let previousAngle =
                    segmentAngle(filtered[i - 1], filtered[i])

                let currentAngle =
                    segmentAngle(filtered[i], filtered[i + 1])

                let nextAngle =
                    segmentAngle(filtered[i + 1], filtered[i + 2])

                let currentTurn =
                    normalizedAngle(currentAngle - previousAngle)

                let nextTurn =
                    normalizedAngle(nextAngle - currentAngle)

                if isAcuteReversal(currentTurn) &&
                    isAcuteReversal(nextTurn) {

                    i += 1
                    continue
                }
            }

            result.append(filtered[i])
            i += 1
        }

        return result.count >= 2 ? result : filtered
    }

    // MARK: - STL buffered edges

    private func buildBufferedEdges(
        _ points: [ProjectedPoint],
        halfWidth: Double,
        joinLimitMultiplier: Double
    ) -> [(
        left: (x: Double, z: Double),
        right: (x: Double, z: Double)
    )] {

        var edges: [(
            left: (x: Double, z: Double),
            right: (x: Double, z: Double)
        )] = []

        edges.reserveCapacity(points.count)

        var lastAngle =
            segmentAngle(points[0], points[1])

        for index in points.indices {

            let angle: Double

            if index + 1 < points.count {
                angle =
                    segmentAngle(
                        points[index],
                        points[index + 1]
                    )
            } else {
                angle = lastAngle
            }

            let relativeAngle =
                normalizedAngle(angle - lastAngle)

            let jointAngle =
                lastAngle + relativeAngle / 2

            var joinRadius = halfWidth
            let cosHalf = cos(relativeAngle / 2)

            if abs(cosHalf) > 0.0001 {
                joinRadius = halfWidth / cosHalf
            } else {
                joinRadius = halfWidth * joinLimitMultiplier
            }

            let limit =
                halfWidth * joinLimitMultiplier

            joinRadius =
                min(limit, max(-limit, joinRadius))

            let point = points[index]

            let leftAngle = jointAngle + .pi / 2
            let rightAngle = jointAngle - .pi / 2

            let left = (
                x: point.x + joinRadius * cos(leftAngle),
                z: point.z + joinRadius * sin(leftAngle)
            )

            let right = (
                x: point.x + joinRadius * cos(rightAngle),
                z: point.z + joinRadius * sin(rightAngle)
            )

            edges.append(
                (left: left, right: right)
            )

            lastAngle = angle
        }

        return edges
    }

    private func segmentAngle(
        _ a: ProjectedPoint,
        _ b: ProjectedPoint
    ) -> Double {

        atan2(
            b.z - a.z,
            b.x - a.x
        )
    }

    private func normalizedAngle(
        _ angle: Double
    ) -> Double {

        var result = angle

        while result > .pi {
            result -= 2 * .pi
        }

        while result < -.pi {
            result += 2 * .pi
        }

        return result
    }

    private func isAcuteReversal(
        _ angle: Double
    ) -> Bool {

        abs(angle) > .pi / 2
    }

    private func horizontalDistance(
        _ a: ProjectedPoint,
        _ b: ProjectedPoint
    ) -> Double {

        let dx = b.x - a.x
        let dz = b.z - a.z

        return sqrt(dx * dx + dz * dz)
    }
}

