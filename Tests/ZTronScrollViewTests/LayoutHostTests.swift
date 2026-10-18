import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class BodyCount { var bodies = 0; var appears = 0; var ids = Set<UUID>() }

struct StatefulContent: View {
    let counts: BodyCount
    @State private var id = UUID()
    var body: some View {
        counts.bodies += 1
        counts.ids.insert(id)
        return Color.red.frame(height: 1000).onAppear { counts.appears += 1 }
    }
}

@MainActor
@Suite(.serialized)
struct LayoutHostTests {
    @Test(arguments: OSPath.allCases) func proposesNilOnScrollableAxes(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { Color.red })
        }
        // vertical: height from nil proposal (ideal, not the 200pt viewport); width = viewport (cross axis)
        #expect(s.peek.metrics.contentSize.width == 200)
        #expect(s.peek.metrics.contentSize.height != s.peek.metrics.viewportSize.height)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func proposesViewportOnCrossAxis(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.horizontal, state: s) { Color.red })
        }
        #expect(s.peek.metrics.viewportSize.height > 0)
        #expect(s.peek.metrics.contentSize.height == s.peek.metrics.viewportSize.height)
        #expect(s.peek.metrics.contentSize.width != 200)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func viewportMetricsObserved(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }) }
        #expect(s.peek.metrics.viewportSize.width == 200 && s.peek.metrics.viewportSize.height > 0)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        _ = w
    }

    @Test(arguments: OSPath.allCases) func contentSizeMeasuredUnscaled(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }) }
        s.track(offset: .zero, zoom: 2); pump(0.15)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        _ = w
    }

    @Test(arguments: OSPath.allCases) func contentBodyNeverRunsDuringMotionAndStateSurvives(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }) }
        let base = counts.bodies
        ZTronRenderCounters.reset()
        for y in stride(from: 10.0, through: 200.0, by: 20) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1 + y / 400); pump(0.03) }
        pump(0.1)
        #expect(counts.bodies == base)
        #expect(counts.appears == 1)
        #expect(counts.ids.count == 1)
        #expect(ZTronRenderCounters.value("transformHost.body") > 0)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func presentationWritesDoNotWakeTransformHost(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }) }
        pump(0.1)
        ZTronRenderCounters.reset()
        for y in stride(from: 10.0, through: 100.0, by: 10) {
            s.batch {
                s.storage.presentationOffset = CGPoint(x: 0, y: y)
                s.storage.presentationZoom = 1 + y / 1000
            }
            pump(0.03)
        }
        #expect(ZTronRenderCounters.value("transformHost.body") == 0)
        s.track(offset: CGPoint(x: 0, y: 50), zoom: 1); pump(0.1)
        #expect(ZTronRenderCounters.value("transformHost.body") > 0)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func contentSpaceFramesStableWhileScrolling(path: OSPath) {
        let s = makeState(path)
        final class Box { var frames: [CGRect] = [] }
        let box = Box()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) {
                Color.red.frame(height: 1000).background(GeometryReader { p -> Color in
                    box.frames.append(p.frame(in: ZTronCoordinateSpaces.content)); return .clear
                })
            })
        }
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1); pump(0.15)
        #expect(Set(box.frames.map { $0.origin.y }) == [0])
        _ = w
    }

    @Test(arguments: OSPath.allCases) func clockDrivesAnimatedOffsetThenPauses(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 2000) }) }
        ZTronRenderCounters.reset()
        s.setContentOffset(CGPoint(x: 0, y: 400), animated: true)
        pump(2.0)
        #expect(s.contentOffset.y == 400 || abs(s.contentOffset.y - 400) < 0.5)
        #expect(s.phase == .idle)
        #expect(!s.isClockRunning)
        let ticks = ZTronRenderCounters.value("clock.tick")
        #expect(ticks > 10)
        pump(0.5)
        #expect(ZTronRenderCounters.value("clock.tick") == ticks)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func withAnimationScrollSettlesAndEffectRunsPerFrame(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }) }
        let base = counts.bodies
        ZTronRenderCounters.reset()
        withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: 300)) }
        pump(1.5)
        #expect(s.phase == .idle)
        #expect(s.contentOffset.y == 300)
        #expect(counts.bodies == base)
        #expect(ZTronRenderCounters.value("transform.effect") >= 10)
        _ = w
    }
}
