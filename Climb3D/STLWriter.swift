import Foundation
import simd

struct STLWriter {
    func write(mesh: Climb3DMesh, filename: String) throws -> URL {
        var data = Data(count: 80)

        var count = UInt32(mesh.triangles.count).littleEndian
        withUnsafeBytes(of: &count) {
            data.append(contentsOf: $0)
        }

        for triangle in mesh.triangles {
            let a = mesh.vertices[Int(triangle.a)]
            let b = mesh.vertices[Int(triangle.b)]
            let c = mesh.vertices[Int(triangle.c)]

            let va = SIMD3<Float>(a.x, a.y, a.z)
            let vb = SIMD3<Float>(b.x, b.y, b.z)
            let vc = SIMD3<Float>(c.x, c.y, c.z)

            let normal = simd_normalize(
                simd_cross(vb - va, vc - va)
            )

            appendFloat(normal.x, to: &data)
            appendFloat(normal.y, to: &data)
            appendFloat(normal.z, to: &data)

            appendVertex(a, to: &data)
            appendVertex(b, to: &data)
            appendVertex(c, to: &data)

            var attribute: UInt16 = 0
            withUnsafeBytes(of: &attribute) {
                data.append(contentsOf: $0)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let url =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "\(filename)_\(formatter.string(from: Date())).stl"
                )

        try data.write(to: url, options: .atomic)
        return url
    }

    private func appendVertex(
        _ v: Climb3DVertex,
        to data: inout Data
    ) {
        appendFloat(v.x, to: &data)
        appendFloat(v.y, to: &data)
        appendFloat(v.z, to: &data)
    }

    private func appendFloat(
        _ value: Float,
        to data: inout Data
    ) {
        var x = value.littleEndian
        withUnsafeBytes(of: &x) {
            data.append(contentsOf: $0)
        }
    }
}

private extension Float {
    var littleEndian: Float {
        var bits = bitPattern.littleEndian
        return Float(bitPattern: bits)
    }
}
