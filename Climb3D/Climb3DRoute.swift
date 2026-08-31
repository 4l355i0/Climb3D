import Foundation
import CoreLocation

struct Climb3DRoutePoint {
    let latitude: Double
    let longitude: Double
    let elevationM: Double
    let distanceM: Double
}

struct Climb3DRoute {

    let points: [Climb3DRoutePoint]
    let totalDistanceM: Double

    func point(at progress: Double) -> Climb3DRoutePoint? {

        guard !points.isEmpty else {
            return nil
        }

        return point(
            atDistanceM:
                min(1, max(0, progress)) *
                totalDistanceM
        )
    }

    func point(
        atDistanceM distanceM: Double
    ) -> Climb3DRoutePoint? {

        guard !points.isEmpty else {
            return nil
        }

        if points.count == 1 {
            return points[0]
        }

        let target =
            min(
                totalDistanceM,
                max(0, distanceM)
            )

        if target <= 0 {
            return points[0]
        }

        if target >= totalDistanceM {
            return points[points.count - 1]
        }

        var low = 0
        var high = points.count - 1

        while low + 1 < high {

            let mid =
                (low + high) / 2

            if points[mid].distanceM < target {
                low = mid
            } else {
                high = mid
            }
        }

        let a = points[low]
        let b = points[high]

        let span =
            max(
                0.001,
                b.distanceM -
                a.distanceM
            )

        let t =
            (target - a.distanceM) /
            span

        return Climb3DRoutePoint(
            latitude:
                a.latitude +
                (b.latitude - a.latitude) * t,

            longitude:
                a.longitude +
                (b.longitude - a.longitude) * t,

            elevationM:
                a.elevationM +
                (b.elevationM - a.elevationM) * t,

            distanceM:
                target
        )
    }

    func distance(
        at progress: Double
    ) -> Double {

        min(1, max(0, progress)) *
        totalDistanceM
    }

    func remainingDistance(
        at progress: Double
    ) -> Double {

        max(
            0,
            totalDistanceM -
            distance(at: progress)
        )
    }

    func elevation(
        at progress: Double
    ) -> Double {

        point(
            at: progress
        )?.elevationM ?? 0
    }

    // Prototype only.
    // RideClimb physical model remains authoritative.
    func gradePercent(
        at progress: Double,
        windowM: Double = 100
    ) -> Double {

        guard totalDistanceM > 1 else {
            return 0
        }

        let center =
            distance(at: progress)

        let half =
            max(
                30,
                windowM / 2
            )

        let beforeDistance =
            max(
                0,
                center - half
            )

        let afterDistance =
            min(
                totalDistanceM,
                center + half
            )

        guard
            let before =
                point(
                    atDistanceM:
                        beforeDistance
                ),

            let after =
                point(
                    atDistanceM:
                        afterDistance
                )
        else {
            return 0
        }

        let run =
            after.distanceM -
            before.distanceM

        guard run > 5 else {
            return 0
        }

        return
            (
                after.elevationM -
                before.elevationM
            ) /
            run *
            100
    }
}


// MARK: - GPX parser

final class Climb3DGPXParser:
    NSObject,
    XMLParserDelegate {

    private var raw:
        [
            (
                lat: Double,
                lon: Double,
                ele: Double
            )
        ] = []

    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentText = ""

    /*
     VISUALIZATION PARAMETERS

     These do NOT affect RideClimb physics.
    */

    private let resampleStepM:
        Double = 8.0

    // 5 samples each side ≈ 40 m
    private let horizontalSmoothRadius:
        Int = 5

    // 6 samples each side ≈ 48 m
    private let elevationSmoothRadius:
        Int = 6

    func parse(
        url: URL
    ) throws -> Climb3DRoute {

        let data =
            try Data(
                contentsOf: url
            )

        raw.removeAll(
            keepingCapacity: true
        )

        let parser =
            XMLParser(
                data: data
            )

        parser.delegate = self

        guard parser.parse() else {

            throw parser.parserError ??
                NSError(
                    domain:
                        "Climb3D.GPX",
                    code:
                        1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Invalid GPX"
                    ]
                )
        }

        guard raw.count >= 2 else {

            throw NSError(
                domain:
                    "Climb3D.GPX",
                code:
                    2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "GPX contains too few points"
                ]
            )
        }

        let original =
            buildOriginalRoute()

        let resampled =
            resample(original)

        let horizontalSmoothed =
            smoothHorizontal(
                resampled
            )

        let fullySmoothed =
            smoothElevation(
                horizontalSmoothed
            )

        guard fullySmoothed.count >= 2 else {

            throw NSError(
                domain:
                    "Climb3D.GPX",
                code:
                    3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to process GPX"
                ]
            )
        }

        /*
         Recalculate distance after smoothing X/Y.

         This makes Progress consistent with the
         visual route rather than the rider's GPS
         wobble.
        */

        let finalRoute =
            recalculateDistances(
                fullySmoothed
            )

        return Climb3DRoute(
            points:
                finalRoute,

            totalDistanceM:
                finalRoute.last?.distanceM ?? 0
        )
    }

    // MARK: Original route

    private func buildOriginalRoute()
        -> [Climb3DRoutePoint] {

        var result:
            [Climb3DRoutePoint] = []

        result.reserveCapacity(
            raw.count
        )

        var cumulative = 0.0
        var previous: CLLocation?

        for point in raw {

            let location =
                CLLocation(
                    latitude:
                        point.lat,

                    longitude:
                        point.lon
                )

            if let previous {

                cumulative +=
                    location.distance(
                        from:
                            previous
                    )
            }

            result.append(
                Climb3DRoutePoint(
                    latitude:
                        point.lat,

                    longitude:
                        point.lon,

                    elevationM:
                        point.ele,

                    distanceM:
                        cumulative
                )
            )

            previous =
                location
        }

        return result
    }

    // MARK: Resampling

    private func resample(
        _ source:
            [Climb3DRoutePoint]
    ) -> [Climb3DRoutePoint] {

        guard
            source.count >= 2,
            let last = source.last,
            last.distanceM > 0
        else {
            return source
        }

        let total =
            last.distanceM

        var result:
            [Climb3DRoutePoint] = []

        result.reserveCapacity(
            Int(
                total /
                resampleStepM
            ) + 2
        )

        var target = 0.0
        var segmentIndex = 0

        while target <= total {

            while
                segmentIndex + 1 <
                    source.count,
                source[
                    segmentIndex + 1
                ].distanceM < target {

                segmentIndex += 1
            }

            let nextIndex =
                min(
                    source.count - 1,
                    segmentIndex + 1
                )

            let a =
                source[
                    segmentIndex
                ]

            let b =
                source[
                    nextIndex
                ]

            let span =
                max(
                    0.001,
                    b.distanceM -
                    a.distanceM
                )

            let t =
                min(
                    1,
                    max(
                        0,
                        (
                            target -
                            a.distanceM
                        ) /
                        span
                    )
                )

            result.append(
                Climb3DRoutePoint(
                    latitude:
                        a.latitude +
                        (
                            b.latitude -
                            a.latitude
                        ) * t,

                    longitude:
                        a.longitude +
                        (
                            b.longitude -
                            a.longitude
                        ) * t,

                    elevationM:
                        a.elevationM +
                        (
                            b.elevationM -
                            a.elevationM
                        ) * t,

                    distanceM:
                        target
                )
            )

            target +=
                resampleStepM
        }

        if
            let lastResult =
                result.last,

            total -
                lastResult.distanceM >
                0.1 {

            result.append(
                source[
                    source.count - 1
                ]
            )
        }

        return result
    }

    // MARK: Horizontal smoothing

    private func smoothHorizontal(
        _ source:
            [Climb3DRoutePoint]
    ) -> [Climb3DRoutePoint] {

        guard source.count >= 5 else {
            return source
        }

        var result:
            [Climb3DRoutePoint] = []

        result.reserveCapacity(
            source.count
        )

        for index in source.indices {

            /*
             Preserve start/end more strongly.
            */

            if index == 0 ||
                index == source.count - 1 {

                result.append(
                    source[index]
                )

                continue
            }

            let start =
                max(
                    0,
                    index -
                    horizontalSmoothRadius
                )

            let end =
                min(
                    source.count - 1,
                    index +
                    horizontalSmoothRadius
                )

            var latitudeSum = 0.0
            var longitudeSum = 0.0
            var weightSum = 0.0

            for sampleIndex in start...end {

                let sampleDistance =
                    abs(
                        sampleIndex -
                        index
                    )

                /*
                 Triangular weighted smoothing.
                 Nearby samples matter more.
                */

                let weight =
                    Double(
                        horizontalSmoothRadius +
                        1 -
                        sampleDistance
                    )

                latitudeSum +=
                    source[
                        sampleIndex
                    ].latitude *
                    weight

                longitudeSum +=
                    source[
                        sampleIndex
                    ].longitude *
                    weight

                weightSum +=
                    weight
            }

            result.append(
                Climb3DRoutePoint(
                    latitude:
                        latitudeSum /
                        weightSum,

                    longitude:
                        longitudeSum /
                        weightSum,

                    elevationM:
                        source[
                            index
                        ].elevationM,

                    distanceM:
                        source[
                            index
                        ].distanceM
                )
            )
        }

        return result
    }

    // MARK: Elevation smoothing

    private func smoothElevation(
        _ source:
            [Climb3DRoutePoint]
    ) -> [Climb3DRoutePoint] {

        guard source.count >= 3 else {
            return source
        }

        var result:
            [Climb3DRoutePoint] = []

        result.reserveCapacity(
            source.count
        )

        for index in source.indices {

            let start =
                max(
                    0,
                    index -
                    elevationSmoothRadius
                )

            let end =
                min(
                    source.count - 1,
                    index +
                    elevationSmoothRadius
                )

            var elevationSum = 0.0
            var weightSum = 0.0

            for sampleIndex in start...end {

                let sampleDistance =
                    abs(
                        sampleIndex -
                        index
                    )

                let weight =
                    Double(
                        elevationSmoothRadius +
                        1 -
                        sampleDistance
                    )

                elevationSum +=
                    source[
                        sampleIndex
                    ].elevationM *
                    weight

                weightSum +=
                    weight
            }

            result.append(
                Climb3DRoutePoint(
                    latitude:
                        source[
                            index
                        ].latitude,

                    longitude:
                        source[
                            index
                        ].longitude,

                    elevationM:
                        elevationSum /
                        weightSum,

                    distanceM:
                        source[
                            index
                        ].distanceM
                )
            )
        }

        return result
    }

    // MARK: Recalculate visual distance

    private func recalculateDistances(
        _ source:
            [Climb3DRoutePoint]
    ) -> [Climb3DRoutePoint] {

        guard !source.isEmpty else {
            return []
        }

        var result:
            [Climb3DRoutePoint] = []

        result.reserveCapacity(
            source.count
        )

        var cumulative = 0.0
        var previous: CLLocation?

        for point in source {

            let location =
                CLLocation(
                    latitude:
                        point.latitude,

                    longitude:
                        point.longitude
                )

            if let previous {

                cumulative +=
                    location.distance(
                        from:
                            previous
                    )
            }

            result.append(
                Climb3DRoutePoint(
                    latitude:
                        point.latitude,

                    longitude:
                        point.longitude,

                    elevationM:
                        point.elevationM,

                    distanceM:
                        cumulative
                )
            )

            previous =
                location
        }

        return result
    }

    // MARK: XML

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {

        currentText = ""

        if elementName == "trkpt" ||
            elementName == "rtept" {

            currentLat =
                Double(
                    attributeDict[
                        "lat"
                    ] ?? ""
                )

            currentLon =
                Double(
                    attributeDict[
                        "lon"
                    ] ?? ""
                )

            currentEle = nil
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {

        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {

        if elementName == "ele" {

            currentEle =
                Double(
                    currentText
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                )
        }

        if elementName == "trkpt" ||
            elementName == "rtept" {

            if
                let lat = currentLat,
                let lon = currentLon {

                raw.append(
                    (
                        lat: lat,
                        lon: lon,
                        ele:
                            currentEle ?? 0
                    )
                )
            }

            currentLat = nil
            currentLon = nil
            currentEle = nil
        }
    }
}
