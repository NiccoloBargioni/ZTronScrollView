import CoreGraphics
import Foundation
import Testing

/// `|a − b| ≤ tolerance`, reported at the caller's location.
func expectClose(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat, _ comment: Comment? = nil,
                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(a - b) <= tolerance, "\(a) vs \(b) (tolerance \(tolerance)) \(comment.map { "\($0)" } ?? "")",
            sourceLocation: sourceLocation)
}

/// Component-wise `expectClose` for points.
func expectClose(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat, _ comment: Comment? = nil,
                 sourceLocation: SourceLocation = #_sourceLocation) {
    expectClose(a.x, b.x, tolerance, comment, sourceLocation: sourceLocation)
    expectClose(a.y, b.y, tolerance, comment, sourceLocation: sourceLocation)
}

/// Deterministic generator so randomized property tests are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `count` evenly spaced values from `from` to `to` (inclusive).
func grid(_ from: CGFloat, _ to: CGFloat, count: Int) -> [CGFloat] {
    (0..<count).map { from + (to - from) * CGFloat($0) / CGFloat(count - 1) }
}
