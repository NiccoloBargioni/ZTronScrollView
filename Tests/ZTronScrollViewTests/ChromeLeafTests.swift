import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

extension Counter {
    /// A leaf body that only counts (a ViewBuilder closure cannot hold an assignment statement).
    func note(_ sample: ChromeSample) -> Color {
        runs += 1
        values.append("\(sample.offset.y)")
        return Color.clear
    }
}

/// M8-1 (design M8 §1, §10): `ChromeLeaf` wakes on the channels it declares and on nothing else, on both storage paths,
/// and nothing a leaf does re-evaluates the content (SPEC S4 tier 0).
@MainActor
@Suite(.serialized)
struct ChromeLeafTests {
    func ready(_ s: ZTronScrollState) {
        s.setContentSize(CGSize(width: 390, height: 3000))
        s.setViewport(ViewportMetrics(size: CGSize(width: 390, height: 800), safeArea: EdgeInsets()))
    }

    // MARK: the sample

    @Test(arguments: OSPath.allCases) func theSampleCarriesTheBoundsOvershootOfTheState(path: OSPath) {
        let s = makeState(path)
        ready(s)
        s.track(offset: CGPoint(x: 0, y: -40), zoom: 1)
        #expect(s.chromeSample(.all).overshoot == CGPoint(x: 0, y: -40))
        s.track(offset: CGPoint(x: 0, y: 2260), zoom: 1)                  // bounds 0 … 2200
        #expect(s.chromeSample(.all).overshoot == CGPoint(x: 0, y: 60))
        s.track(offset: CGPoint(x: 0, y: 1000), zoom: 1)
        #expect(s.chromeSample(.all).overshoot == .zero)
        s.contentInset = EdgeInsets(top: 100, leading: 0, bottom: 0, trailing: 0)   // bounds −100 … 2200
        s.track(offset: CGPoint(x: 0, y: -130), zoom: 1)
        #expect(s.chromeSample(.all).overshoot == CGPoint(x: 0, y: -30))
    }

    @Test(arguments: OSPath.allCases) func theSampleReadsEveryFieldOfTheState(path: OSPath) {
        let s = makeState(path)
        ready(s)
        s.track(offset: CGPoint(x: 3, y: 150), zoom: 1)
        s.setPhase(.decelerating)
        let sample = s.chromeSample(.all)
        #expect(sample.offset == CGPoint(x: 3, y: 150) && sample.zoom == 1 && sample.phase == .decelerating)
        #expect(sample.metrics.viewportSize == CGSize(width: 390, height: 800) && sample.metrics.contentSize.height == 3000)
        // Undeclared channels still hold the current values (a snapshot), they just do not wake a leaf.
        let partial = s.chromeSample([.phase])
        #expect(partial.offset == sample.offset && partial.metrics == sample.metrics && partial.phase == .decelerating)
    }

    @Test func channelSetsMapToTheStateChannels() {
        #expect(ChannelSet.all.stateChannels == [.offset, .zoom, .phase, .metrics])
        #expect(ChannelSet([.offset]).stateChannels == [.offset])
        #expect(ChannelSet([]).stateChannels.isEmpty)
        #expect(!ChannelSet.all.stateChannels.contains(.target), "presentation, not the transform host's target channel")
    }

    // MARK: waking (direct leaf, both paths)

    @Test(arguments: OSPath.allCases) func aLeafOnOffsetRunsOncePerDistinctOffsetAndIgnoresTheRest(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = withOSPath(path) { host(ChromeLeaf(s, channels: [.offset]) { c.note($0) }) }
        let base = c.runs
        for y in stride(from: 10.0, through: 100.0, by: 10) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.03) }
        #expect(c.runs == base + 10, "one body per frame with a distinct sample")
        s.track(offset: CGPoint(x: 0, y: 100), zoom: 1); pump(0.05)
        #expect(c.runs == base + 10, "the same sample again wakes nothing")
        s.track(offset: CGPoint(x: 0, y: 100), zoom: 3); pump(0.05)
        #expect(c.runs == base + 10, "zoom is not on its channels")
        s.setPhase(.interacting); pump(0.05)
        #expect(c.runs == base + 10, "neither is the phase")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aLeafOnZoomIgnoresPanning(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = withOSPath(path) { host(ChromeLeaf(s, channels: [.zoom]) { c.note($0) }) }
        let base = c.runs
        for y in stride(from: 10.0, through: 100.0, by: 10) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.03) }
        #expect(c.runs == base)
        for z in [1.5, 2.0, 2.5] as [CGFloat] { s.track(offset: CGPoint(x: 0, y: 100), zoom: z); pump(0.03) }
        #expect(c.runs == base + 3)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aLeafOnPhaseDoesNotWakePerFrame(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = withOSPath(path) { host(ChromeLeaf(s, channels: [.phase]) { c.note($0) }) }
        let base = c.runs
        for y in stride(from: 5.0, through: 100.0, by: 5) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1 + y / 200); pump(0.02) }
        #expect(c.runs == base, "20 frames of offset and zoom, no wake")
        s.setPhase(.interacting); pump(0.05)
        #expect(c.runs == base + 1)
        s.setPhase(.interacting); pump(0.05)
        #expect(c.runs == base + 1, "the same phase again wakes nothing")
        s.setPhase(.idle); pump(0.05)
        #expect(c.runs == base + 2)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aLeafOnMetricsWakesOnLayoutNotMotion(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = withOSPath(path) { host(ChromeLeaf(s, channels: [.metrics]) { c.note($0) }) }
        let base = c.runs
        for y in stride(from: 10.0, through: 100.0, by: 10) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.02) }
        #expect(c.runs == base)
        s.setContentSize(CGSize(width: 390, height: 3000)); pump(0.05)
        #expect(c.runs == base + 1)
        s.scrollIndicatorInsets = EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0); pump(0.05)
        #expect(c.runs == base + 2, "an indicator inset is a metrics write")
        s.scrollIndicatorInsets = EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0); pump(0.05)
        #expect(c.runs == base + 2, "the same inset again publishes nothing")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aLeafWithNoChannelsNeverWakes(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = withOSPath(path) { host(ChromeLeaf(s, channels: []) { c.note($0) }) }
        let base = c.runs
        s.track(offset: CGPoint(x: 0, y: 50), zoom: 2); pump(0.05)
        s.setPhase(.interacting); pump(0.05)
        s.setContentSize(CGSize(width: 390, height: 3000)); pump(0.05)
        #expect(c.runs == base)
        unhost(w)
    }

    // MARK: tier 0 through the real container (both paths)

    @Test(arguments: OSPath.allCases) func aScriptedScrollAndZoomRunNoContentBodyAndOneLeafBodyPerFrame(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.2)
        let contentBodies = counts.bodies
        let hostBodies = ZTronRenderCounters.value("indicators.host.body")
        #expect(s.indicatorController?.lastRender?.layout.vertical != nil, "the thumb leaf is in the overlay")
        ZTronRenderCounters.reset()
        for y in stride(from: 10.0, through: 200.0, by: 10) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1 + y / 400); pump(0.03) }
        pump(0.1)
        #expect(counts.bodies == contentBodies, "content.body 0 during the scripted scroll + zoom")
        #expect(counts.appears == 1 && counts.ids.count == 1, "the content's identity survives")
        #expect(ZTronRenderCounters.value("indicators.host.body") == 0, "the cold host does not run per frame (was \(hostBodies) before)")
        #expect(ZTronRenderCounters.value("chromeLeaf.body") == 20, "the leaf runs once per frame with a distinct sample")
        #expect(ZTronRenderCounters.value("transformHost.body") > 0)
        unhost(w)
    }

    /// The thumb the math gives for the state's own metrics (the window has bars, so the viewport is whatever it is).
    func expectedThumb(_ s: ZTronScrollState) -> IndicatorThumb? {
        let p = s.peek
        return IndicatorMath.layout(offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics,
                                    trackInsets: IndicatorMath.trackInsets(p.metrics, extra: EdgeInsets()),
                                    resolved: ResolvedIndicators(), axes: .vertical, zoomEnabled: s.isZoomEnabled).vertical
    }

    @Test(arguments: OSPath.allCases) func theThumbFollowsZoomAndOffsetLiveWithoutTheContent(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.2)
        let rest = s.indicatorController?.lastRender?.layout.vertical
        #expect(rest != nil && rest == expectedThumb(s), "at rest: the math for the state's metrics")
        s.track(offset: CGPoint(x: 0, y: 0), zoom: 2); pump(0.1)
        let zoomed = s.indicatorController?.lastRender?.layout.vertical
        #expect(zoomed != nil && zoomed == expectedThumb(s), "zoom is on the leaf's channels: the thumb is recomputed live")
        #expect(zoomed!.length <= rest!.length, "zooming in never lengthens the thumb")
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 2); pump(0.1)
        let moved = s.indicatorController?.lastRender?.layout.vertical
        #expect(moved == expectedThumb(s) && moved!.origin > zoomed!.origin && moved!.length == zoomed!.length)
        s.track(offset: CGPoint(x: 0, y: -60), zoom: 2); pump(0.1)
        let pulled = s.indicatorController?.lastRender?.layout.vertical
        #expect(pulled == expectedThumb(s) && pulled!.length < zoomed!.length, "the rubber band shrinks it")
        #expect(counts.appears == 1)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func anIndicatorInsetMovesTheLiveThumb(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }) }
        pump(0.2)
        let before = s.indicatorController?.lastRender?.layout.vertical
        s.scrollIndicatorInsets = EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0); pump(0.1)
        let after = s.indicatorController?.lastRender?.layout.vertical
        #expect(before != nil && after != nil && after!.origin == before!.origin + 40)
        unhost(w)
    }

    /// The overlay is laid out at the viewport's own size even when the viewport reaches under the bars (the container
    /// ignores the safe area on the adjusted edges): chrome positions are viewport coordinates.
    @Test(arguments: OSPath.allCases) func theOverlayIsLaidOutAtTheViewportSize(path: OSPath) {
        for behavior in [ZTronContentInsetAdjustmentBehavior.never, .automatic, .always] {
            let s = makeState(path)
            s.contentInsetAdjustmentBehavior = behavior
            let w = withOSPath(path) { host(ZTronScrollView([.horizontal, .vertical], state: s) { Color.red.frame(width: 600, height: 1000) }) }
            pump(0.2)
            let viewport = s.peek.metrics.viewportSize
            guard let overlay = s.indicatorController?.lastOverlaySize else { Issue.record("no overlay size (\(behavior))"); unhost(w); continue }
            #expect(abs(overlay.width - viewport.width) <= 1 && abs(overlay.height - viewport.height) <= 1,
                    "overlay \(overlay) vs viewport \(viewport) (\(behavior))")
            unhost(w)
        }
    }

    @Test func activityIsMotionNotAFingerDownAndNotAResize() {
        func sample(_ phase: ZTronScrollPhase, resizing: Bool = false) -> ChromeSample {
            var m = ScrollMetrics()
            m.resize.isOpen = resizing
            return ChromeSample(offset: .zero, zoom: 1, phase: phase, metrics: m, overshoot: .zero)
        }
        #expect(!ScrollIndicatorsLeaf.isActive(sample(.idle)))
        #expect(!ScrollIndicatorsLeaf.isActive(sample(.tracking)), "a touch that has not moved the content shows nothing")
        #expect(ScrollIndicatorsLeaf.isActive(sample(.interacting)))
        #expect(ScrollIndicatorsLeaf.isActive(sample(.decelerating)))
        #expect(ScrollIndicatorsLeaf.isActive(sample(.animating)))
        #expect(!ScrollIndicatorsLeaf.isActive(sample(.animating, resizing: true)), "the resize watch reports .animating for itself")
    }
}
