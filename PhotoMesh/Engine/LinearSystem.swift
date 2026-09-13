import Foundation

enum LinearSystemError: LocalizedError {
    case singular

    var errorDescription: String? {
        "The equations have no unique solution. This usually means two sources conflict (for example two voltage sources in parallel) or a component value is missing."
    }
}

/// Dense Gaussian elimination with partial pivoting. Circuits here have at most a few dozen unknowns.
struct LinearSystem {
    var a: [[Double]]
    var b: [Double]

    init(size: Int) {
        a = Array(repeating: Array(repeating: 0, count: size), count: size)
        b = Array(repeating: 0, count: size)
    }

    var size: Int { b.count }

    func solve() throws -> [Double] {
        var m = a
        var rhs = b
        let n = size
        guard n > 0 else { return [] }

        for column in 0..<n {
            var pivot = column
            var best = abs(m[column][column])
            for row in (column + 1)..<n where abs(m[row][column]) > best {
                best = abs(m[row][column])
                pivot = row
            }
            guard best > 1e-12 else { throw LinearSystemError.singular }
            if pivot != column {
                m.swapAt(pivot, column)
                rhs.swapAt(pivot, column)
            }
            for row in (column + 1)..<n {
                let factor = m[row][column] / m[column][column]
                guard factor != 0 else { continue }
                for k in column..<n { m[row][k] -= factor * m[column][k] }
                rhs[row] -= factor * rhs[column]
            }
        }

        var x = Array(repeating: 0.0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[row]
            for k in (row + 1)..<n { sum -= m[row][k] * x[k] }
            x[row] = sum / m[row][row]
        }
        return x.map { abs($0) < 1e-12 ? 0 : $0 }
    }
}
