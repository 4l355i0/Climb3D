import Foundation

struct Climb3DMeshBuilder {

    // Closed solid retained for STL export.
    let stlHalfWidthM: Double = 5.0
    let stlJoinLimitMultiplier: Double = 2.0

    // Build 15 visual road: one continuous ribbon.
    let visualHalfWidthM: Double = 3.0

    // Tight clamp keeps the ribbon continuous without producing the
    // long spikes that appeared on hairpins in earlier builds.
    let visualJoinLimitMultiplier: Double = 1.30

    let verticalExaggeration: Double = 5.0
    let baseHeightM: Double = 8.0
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

        // Full centerline remains 1:1 with the GPX route.
        // Marker/camera therefore remain driven by route distance exactly.
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

        // PASS-THROUGH VALIDATION BUILD:
        // use every imported GPX point exactly as supplied.
        // No point removal, no reversal cleanup, no XY preprocessing.
        let meshPoints = allPoints

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
        // 2) CONTINUOUS VISUAL ROAD
        // -----------------------------------------------------------------
        // Build 14 used four unique vertices per segment, which solved the
        // giant hairpin spikes but made the road look tiled. Build 15 creates
        // one left/right pair per path point and shares those vertices between
        // adjacent segments. The result is a single continuous ribbon.
        //
        // Join length is deliberately clamped to 1.30 x half-width, so even
        // sharp bends cannot generate the huge miter triangles seen earlier.

        let visualEdges =
            buildBufferedEdges(
                meshPoints,
                halfWidth: visualHalfWidthM,
                joinLimitMultiplier: visualJoinLimitMultiplier
            )

        var visualVertices: [Climb3DVertex] = []
        visualVertices.reserveCapacity(meshPoints.count * 2)

        for index in meshPoints.indices {

            let point = meshPoints[index]
            let edge = visualEdges[index]

            // left, right -- shared by the previous and next segment.
            visualVertices.append(
                Climb3DVertex(
                    x: Float(edge.left.x),
                    y: Float(point.y),
                    z: Float(edge.left.z)
                )
            )

            visualVertices.append(
                Climb3DVertex(
                    x: Float(edge.right.x),
                    y: Float(point.y),
                    z: Float(edge.right.z)
                )
            )
        }

        var visualSegmentGrades: [Double] = []
        visualSegmentGrades.reserveCapacity(meshPoints.count - 1)

        for index in 0..<(meshPoints.count - 1) {

            let a = meshPoints[index]
            let b = meshPoints[index + 1]

            let horizontalLength =
                horizontalDistance(a, b)

            guard horizontalLength > 0.001 else {
                visualSegmentGrades.append(0)
                continue
            }

            // Real grade, never the 5x visual exaggeration.
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

        // Protection against consecutive pathological GPS reversals.
        // Genuine hairpins remain because they are composed of several
        // progressive direction changes.
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

    // MARK: - Buffered edges

    private func buildBufferedEdges(
        _ points: [ProjectedPoint],
        halfWidth: Double,
        joinLimitMultiplier: Double
    ) -> [(
        left: (x: Double, z: Double),
        right: (x: Double, z: Double)
    )] {

        guard points.count >= 2 else {
            return []
        }

        var edges: [(
            left: (x: Double, z: Double),
            right: (x: Double, z: Double)
        )] = []

        edges.reserveCapacity(points.count)

        for index in points.indices {

            let incomingAngle: Double
            let outgoingAngle: Double

            if index == 0 {
                incomingAngle = segmentAngle(points[0], points[1])
                outgoingAngle = incomingAngle
            } else if index == points.count - 1 {
                incomingAngle = segmentAngle(points[index - 1], points[index])
                outgoingAngle = incomingAngle
            } else {
                incomingAngle = segmentAngle(points[index - 1], points[index])
                outgoingAngle = segmentAngle(points[index], points[index + 1])
            }

            let relativeAngle =
                normalizedAngle(outgoingAngle - incomingAngle)

            let jointAngle =
                incomingAngle + relativeAngle / 2

            let cosHalf =
                cos(relativeAngle / 2)

            var joinRadius = halfWidth

            if abs(cosHalf) > 0.0001 {
                joinRadius = halfWidth / cosHalf
            }

            // Critical Build 15 protection: bounded miter.
            // A continuous join is preserved, but it can never extend far
            // enough to create the giant inside-hairpin spikes.
            let limit =
                halfWidth * joinLimitMultiplier

            joinRadius =
                min(limit, max(-limit, joinRadius))

            let point = points[index]

            let leftAngle =
                jointAngle + .pi / 2

            let rightAngle =
                jointAngle - .pi / 2

            edges.append(
                (
                    left: (
                        x: point.x + joinRadius * cos(leftAngle),
                        z: point.z + joinRadius * sin(leftAngle)
                    ),
                    right: (
                        x: point.x + joinRadius * cos(rightAngle),
                        z: point.z + joinRadius * sin(rightAngle)
                    )
                )
            )
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
