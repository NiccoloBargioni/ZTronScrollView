import SwiftUI
import Testing
@testable import ZTronScrollView

/// Design M8b-header-behaviors §5 test 2 (D70): the split fade's blend, no view. `u` runs over the band (0 the header's
/// top, 1 the band's end); the drawn opacity is what a `LinearGradient` with the layers' stops draws there.
@MainActor @Suite struct HeaderFadeMathTests {
    static let bg = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let samples = (0...32).map { CGFloat($0) / 32 }
    static let weights: [CGFloat] = [0, 0.25, 0.5, 1]

    /// The exact blend, written out independently of `HeaderFadeMath.target`.
    static func expected(_ rest: ZTronHeaderFade.Gradient?, _ partner: ZTronHeaderFade.Gradient?, t: CGFloat,
                         u: CGFloat) -> CGFloat {
        func a(_ g: ZTronHeaderFade.Gradient?) -> CGFloat {
            guard let g, g.start < 1 else { return 0 }
            return max(0, (u - g.start) / (1 - g.start))
        }
        return (1 - t) * a(rest) + t * a(partner)
    }

    static func weight(_ p: CGFloat, _ g: CGFloat, _ R: CGFloat) -> String {
        let w = HeaderFadeMath.weight(progress: p, pull: g, resting: R)
        return "\(w.partner) \(w.t)"
    }

    @Test func theWeights() {
        // Collapse: t = p; pull: t = min(1, g / (R / 2)); rest: 0.
        #expect(Self.weight(0, 0, 240) == "collapse 0.0")
        #expect(Self.weight(0.3, 0, 240) == "collapse 0.3")
        #expect(Self.weight(1, 0, 240) == "collapse 1.0")
        #expect(Self.weight(0, 60, 240) == "pull 0.5")
        #expect(Self.weight(0, 120, 240) == "pull 1.0", "full at half the resting height")
        #expect(Self.weight(0, 400, 240) == "pull 1.0")
        #expect(Self.weight(0, 10, 0) == "pull 1.0", "R = 0: any pull is full")
        #expect(Self.weight(.nan, .nan, 240) == "collapse 0.0")
        #expect(Self.weight(3, -5, 240) == "collapse 1.0")
        // Continuous through rest: both sides tend to 0.
        #expect(HeaderFadeMath.weight(progress: 0, pull: 0.001, resting: 240).t < 0.0001)
    }

    @Test(arguments: [(CGFloat(0.5), CGFloat(0)), (0.5, 0.5), (0.2, 0.8), (0, 0), (0.9, 0.1), (1, 0.4)])
    func aSingleColorIsOneGradientExactAtEverySample(restStart: CGFloat, partnerStart: CGFloat) throws {
        let fade = ZTronHeaderFade(rest: .linear(to: Self.bg, from: restStart),
                                   collapse: .linear(to: Self.bg, from: partnerStart),
                                   pull: .linear(to: Self.bg, from: partnerStart))
        #expect(!HeaderFadeMath.twoLayers(fade))
        for t in Self.weights {
            for (p, g) in [(t, CGFloat(0)), (0, t * 120)] {      // collapse at p = t, pull at g = t · R / 2
                let layers = try #require(HeaderFadeMath.layers(fade: fade, progress: p, pull: g, resting: 240))
                #expect(layers.top == nil && layers.bottom.color == Self.bg)
                #expect(layers.bottom.stops.count <= 4, "stops only at the breakpoints {0, s_A, s_B, 1}")
                #expect(layers.bottom.stops.first?.location == 0 && layers.bottom.stops.last?.location == 1)
                for u in Self.samples {
                    let want = Self.expected(fade.rest, fade.collapse, t: t, u: u)
                    #expect(abs(layers.coverage(at: u) - want) < 1e-9, "t \(t) u \(u): \(layers.coverage(at: u)) vs \(want)")
                }
            }
        }
    }

    @Test(arguments: [(CGFloat(0.5), CGFloat(0)), (0.5, 0.5), (0.2, 0.8), (0, 0), (0.9, 0.1), (0.1, 0.95)])
    func twoColorsCoverWithinOnePercentAndThePartnersShareIsExact(restStart: CGFloat, partnerStart: CGFloat) throws {
        let fade = ZTronHeaderFade(rest: .linear(to: .black, from: restStart), collapse: .linear(to: .red, from: partnerStart),
                                   pull: .linear(to: .blue, from: partnerStart))
        #expect(HeaderFadeMath.twoLayers(fade))
        let fine = (0...200).map { CGFloat($0) / 200 }
        for t in Self.weights + [0.9, 0.97, 0.999] {
            for (p, g) in [(t, CGFloat(0)), (0, t * 120)] {
                let partner = g > 0 ? fade.pull : fade.collapse      // a zero pull is rest: the collapse side
                let layers = try #require(HeaderFadeMath.layers(fade: fade, progress: p, pull: g, resting: 240))
                let top = try #require(layers.top)
                #expect(layers.bottom.color == .black && top.color == partner?.color)
                for u in fine {
                    let want = Self.expected(fade.rest, partner, t: t, u: u)
                    #expect(abs(layers.coverage(at: u) - want) < 0.01, "t \(t) u \(u): \(layers.coverage(at: u)) vs \(want)")
                    #expect(abs(top.alpha(at: u) - t * HeaderFadeMath.alpha(partner, at: u)) < 1e-9, "B's share is exact")
                }
                for u in Self.samples {
                    // At the stops themselves the coverage is exact.
                    if layers.bottom.stops.contains(where: { $0.location == u }) {
                        #expect(abs(layers.coverage(at: u) - Self.expected(fade.rest, partner, t: t, u: u)) < 1e-9)
                    }
                }
            }
        }
    }

    @Test func nilStatesDrawNothing() throws {
        #expect(HeaderFadeMath.layers(fade: nil, progress: 0.5, pull: 0, resting: 240) == nil)
        #expect(HeaderFadeMath.layers(fade: .init(rest: nil), progress: 0.5, pull: 0, resting: 240) == nil)
        // The user's split: rest and collapse, no pull fade.
        let split = ZTronHeaderFade(rest: .linear(to: Self.bg), collapse: .linear(to: Self.bg, from: 0), pull: nil)
        let atRest = try #require(HeaderFadeMath.layers(fade: split, progress: 0, pull: 0, resting: 240))
        let pulled = try #require(HeaderFadeMath.layers(fade: split, progress: 0, pull: 120, resting: 240))
        let halfPulled = try #require(HeaderFadeMath.layers(fade: split, progress: 0, pull: 60, resting: 240))
        let collapsed = try #require(HeaderFadeMath.layers(fade: split, progress: 1, pull: 0, resting: 240))
        for u in Self.samples {
            #expect(atRest.coverage(at: u) == HeaderFadeMath.alpha(split.rest, at: u))
            #expect(pulled.coverage(at: u) == 0, "fully pulled: the nil pull state has no fade")
            #expect(abs(halfPulled.coverage(at: u) - 0.5 * HeaderFadeMath.alpha(split.rest, at: u)) < 1e-9)
            #expect(abs(collapsed.coverage(at: u) - u) < 1e-9, "fully collapsed: the collapse gradient from 0")
        }
        // A rest-less fade: nothing at rest, the partner's gradient by its weight; its color is the partner's.
        let collapseOnly = ZTronHeaderFade(rest: nil, collapse: .linear(to: .red, from: 0))
        let quarter = try #require(HeaderFadeMath.layers(fade: collapseOnly, progress: 0.25, pull: 0, resting: 240))
        #expect(quarter.bottom.color == .red && quarter.top == nil)
        let rest = try #require(HeaderFadeMath.layers(fade: collapseOnly, progress: 0, pull: 0, resting: 240))
        for u in Self.samples {
            #expect(abs(quarter.coverage(at: u) - 0.25 * u) < 1e-9)
            #expect(rest.coverage(at: u) == 0)
        }
        // A start of 1 draws nothing (no band to fade over).
        #expect(HeaderFadeMath.alpha(.linear(to: .red, from: 1), at: 1) == 0)
        // Two colors with a nil partner: the clear top keeps the structure.
        let mixed = ZTronHeaderFade(rest: .linear(to: .black), collapse: .linear(to: .red), pull: nil)
        let mixedPull = try #require(HeaderFadeMath.layers(fade: mixed, progress: 0, pull: 60, resting: 240))
        #expect(mixedPull.top != nil && mixedPull.top!.stops.allSatisfy { $0.alpha == 0 })
    }

    @Test func linearIsThePerStateFormWithEqualGradientsAndIgnoresTheWeight() throws {
        let linear = ZTronHeaderFade.linear(to: Self.bg, from: 0.4)
        let perState = ZTronHeaderFade(rest: .linear(to: Self.bg, from: 0.4), collapse: .linear(to: Self.bg, from: 0.4),
                                       pull: .linear(to: Self.bg, from: 0.4))
        #expect(linear == perState)
        let reference = try #require(HeaderFadeMath.layers(fade: linear, progress: 0, pull: 0, resting: 240))
        #expect(reference.bottom.stops.map(\.location) == [0, 0.4, 1] && reference.top == nil)
        #expect(reference.bottom.stops.map(\.alpha) == [0, 0, 1], "today's gradient: clear at 0.4, the color at the end")
        for (p, g) in [(CGFloat(0.3), CGFloat(0)), (1, 0), (0, 30), (0, 500)] {
            let l = try #require(HeaderFadeMath.layers(fade: linear, progress: p, pull: g, resting: 240))
            #expect(l == reference, "p \(p) g \(g): the same gradient in every state")
            #expect(l == HeaderFadeMath.layers(fade: perState, progress: p, pull: g, resting: 240))
        }
    }

    @Test func theBandEnd() {
        // `.compress`: the whole (unscaled) frame.
        #expect(HeaderFadeMath.bandEnd(collapse: .compress, progress: 0.5, layoutHeight: 152) == 152)
        // `.slideBehind(k)`: the content's top edge in the header's frame, R − (1 − k)·c.
        let R: CGFloat = 240
        for k in [0, 0.25, 0.5, 1] as [CGFloat] {
            for c in [0, 60, 120, 240] as [CGFloat] {
                let end = HeaderFadeMath.bandEnd(collapse: .slideBehind(parallax: k), progress: c / R, layoutHeight: R)
                #expect(abs(end - (R - (1 - k) * c)) < 1e-9, "k \(k) c \(c)")
                // The header's top moved up by k·c, the content's top is at R − c below top0: the same edge.
                #expect(abs((-k * c + end) - (R - c)) < 1e-9)
            }
        }
        #expect(HeaderFadeMath.bandEnd(collapse: .slideBehind(parallax: 1), progress: 1, layoutHeight: R) == R,
                "k = 1: the header moves with the content, the band is the whole frame")
        #expect(HeaderFadeMath.bandEnd(collapse: .slideBehind(parallax: 0.5), progress: .nan, layoutHeight: R) == R)
        #expect(HeaderFadeMath.endPoint(bandEnd: 120, frameHeight: 240) == UnitPoint(x: 0.5, y: 0.5))
        #expect(HeaderFadeMath.endPoint(bandEnd: 0, frameHeight: 240).y > 0, "never the start point")
        #expect(HeaderFadeMath.endPoint(bandEnd: 10, frameHeight: 0) == UnitPoint(x: 0.5, y: 1))
    }

    @Test func gradientStopsCarryTheOpacity() throws {
        let l = try #require(HeaderFadeMath.layers(fade: .linear(to: .red, from: 0.5), progress: 0, pull: 0, resting: 240))
        let stops = l.bottom.gradientStops
        #expect(stops.map(\.location) == [0, 0.5, 1])
        #expect(stops.map(\.color) == [Color.red.opacity(0), Color.red.opacity(0), Color.red.opacity(1)])
    }
}
