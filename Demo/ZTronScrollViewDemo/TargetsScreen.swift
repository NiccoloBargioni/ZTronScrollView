import SwiftUI
import ZTronScrollView

/// M6 session 3: scroll targets, `scrollPosition`, `defaultScrollAnchor`, the reader (docs/design/M6-targets.md §7). The
/// section comes from `-ZTronTargetsSection reader|position|carousel|aligned|twin|velocity` (default `reader`); every
/// section has an `Info` button that writes its readout to `stateInfo` and the counters to `counter.<key>`.
struct TargetsScreen: View {
    static var section: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronTargetsSection"), i + 1 < a.count { return a[i + 1] }
        return "reader"
    }

    var body: some View {
        switch Self.section {
        case "position": TargetsPositionSection()
        case "carousel": TargetsCarouselSection()
        case "aligned": TargetsAlignedSection()
        case "twin": TargetsTwinSection()
        case "velocity": TargetsVelocitySection()
        default: TargetsReaderSection()
        }
    }
}

/// Counters read from the render counters; the display never perturbs the motion (it is filled by `Info`).
struct TargetsReadout: View {
    static let keys = ["content.body", "position.writes", "position.applied", "proxy.native"]
    let info: String
    let snapshot: [String: Int]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.keys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
            Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
        }
    }

    static func counters() -> [String: Int] {
        #if DEBUG
        return ZTronRenderCounters.snapshot
        #else
        return [:]
        #endif
    }

    static func resetCountersSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
        }
    }
}

/// A row that counts its own body (nothing in a scroll may run it) and carries its scroll target.
struct TargetsRow: View {
    static let height: CGFloat = 44
    let index: Int
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Text("Row \(index)")
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
            .background(index % 2 == 0 ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
            .ztronScrollID(index)
    }
}

// MARK: reader jump menu (ids 0 / 50 / 99 x anchors) and the proxy's animated jump

struct TargetsReaderSection: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]
    private let anchors: [(String, UnitPoint?)] = [("top", .top), ("center", .center), ("bottom", .bottom), ("nil", nil)]

    var body: some View {
        VStack(spacing: 4) {
            ZTronScrollViewReader { proxy in
                VStack(spacing: 4) {
                    ForEach([0, 50, 99], id: \.self) { id in
                        HStack(spacing: 4) {
                            ForEach(anchors, id: \.0) { name, anchor in
                                Button("\(id) \(name)") { proxy.scrollTo(id, anchor: anchor) }
                                    .accessibilityIdentifier("jump.\(id).\(name)")
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Animated 70") { withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(70, anchor: .center) } }
                            .accessibilityIdentifier("jump.animated")
                        Button("70 c") { proxy.scrollTo(70, anchor: .center) }.accessibilityIdentifier("jump.70.center")
                        Button("Unknown") { proxy.scrollTo(1234, anchor: .top) }.accessibilityIdentifier("jump.unknown")
                        Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                        Button("Info") { readout() }.accessibilityIdentifier("Info")
                    }
                    ZTronScrollView(.vertical, state: state) {
                        VStack(spacing: 0) { ForEach(0..<100, id: \.self) { TargetsRow(index: $0) } }
                    }
                    .frame(height: 260)
                    .border(Color.gray)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("targets.list")
                }
            }
            TargetsReadout(info: info, snapshot: snapshot)
        }
        .font(.caption)
        .padding(6)
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        TargetsReadout.resetCountersSoon()
    }

    private func readout() {
        snapshot = TargetsReadout.counters()
        let y = state.contentOffset.y
        info = String(format: "y=%.1f top=%d phase=%d", y, Int((y / TargetsRow.height).rounded()), state.phase.rawValue)
    }
}

// MARK: scrollPosition(_:) with edge / id jumps and user write-back

struct TargetsPositionSection: View {
    @State private var state = ZTronScrollState()
    @State private var position = ZTronScrollPosition()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button("Top") { position.scrollTo(edge: .top) }.accessibilityIdentifier("pos.top")
                Button("Bottom") { position.scrollTo(edge: .bottom) }.accessibilityIdentifier("pos.bottom")
                Button("Row 30") { position.scrollTo(id: 30, anchor: .top) }.accessibilityIdentifier("pos.row30")
                Button("Row 60 c") { position.scrollTo(id: 60, anchor: .center) }.accessibilityIdentifier("pos.row60")
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
            }
            ZTronScrollView(.vertical, state: state) {
                VStack(spacing: 0) { ForEach(0..<100, id: \.self) { TargetsRow(index: $0) } }
            }
            .scrollPosition($position)
            .frame(height: 300)
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("targets.list")
            TargetsReadout(info: info, snapshot: snapshot)
        }
        .font(.caption)
        .padding(6)
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        position = ZTronScrollPosition()
        TargetsReadout.resetCountersSoon()
    }

    private func readout() {
        snapshot = TargetsReadout.counters()
        let y = state.contentOffset.y
        let id = (position.viewID as? Int).map(String.init) ?? "nil"
        info = String(format: "y=%.1f top=%d id=%@ user=%d edge=%@ phase=%d", y, Int((y / TargetsRow.height).rounded()), id,
                      position.isPositionedByUser ? 1 : 0, position.edge.map { "\($0)" } ?? "nil", state.phase.rawValue)
    }
}

// MARK: horizontal paging carousel with page dots bound by scrollPosition(id:)

struct TargetsCarouselSection: View {
    static let page = CGSize(width: 300, height: 160)
    @State private var state = ZTronScrollState()
    @State private var page: Int? = 0
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
            }
            ZTronScrollView(.horizontal, state: state) {
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        TargetsPage(index: i).frame(width: Self.page.width, height: Self.page.height).ztronScrollID(i)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .frame(width: Self.page.width, height: Self.page.height)
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("targets.carousel")
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { i in
                    Button { withAnimation(.easeInOut(duration: 0.5)) { page = i } } label: {
                        Circle().fill(page == i ? Color.primary : Color.gray.opacity(0.4)).frame(width: 14, height: 14)
                    }
                    .accessibilityIdentifier("dot.\(i)")
                    .accessibilityValue(page == i ? "selected" : "")
                }
            }
            TargetsReadout(info: info, snapshot: snapshot)
        }
        .font(.caption)
        .padding(6)
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        page = 0
        TargetsReadout.resetCountersSoon()
    }

    private func readout() {
        snapshot = TargetsReadout.counters()
        let x = state.contentOffset.x
        info = String(format: "x=%.1f page=%d id=%@ phase=%d", x, Int((x / Self.page.width).rounded()), page.map(String.init) ?? "nil",
                      state.phase.rawValue)
    }
}

struct TargetsPage: View {
    let index: Int
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return ZStack {
            Color(hue: Double(index) / 5, saturation: 0.35, brightness: 0.95)
            Text("Page \(index)").font(.title)
        }
    }
}

// MARK: viewAligned list with a limit picker, next to SwiftUI's own (R5)

struct TargetsAlignedSection: View {
    static let cell = CGSize(width: 120, height: 90)
    @State private var state = ZTronScrollState()
    @State private var limit = "never"
    @State private var oursID: Int? = 0
    @State private var nativeID: Int? = 0
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]

    private var behavior: ZTronViewAlignedScrollTargetBehavior.LimitBehavior {
        switch limit {
        case "automatic": return .automatic
        case "byOne": return .alwaysByOne
        case "byFew": return .alwaysByFew
        default: return .never
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(["automatic", "never", "byOne", "byFew"], id: \.self) { name in
                    Button(name) { limit = name }.accessibilityIdentifier("limit.\(name)")
                }
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
            }
            Text("ZTron").font(.caption2)
            ZTronScrollView(.horizontal, state: state) { cells }
                .scrollTargetBehavior(.viewAligned(limitBehavior: behavior))
                .scrollPosition(id: $oursID)
                .frame(width: 300, height: Self.cell.height)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("aligned.ours")
            Text("SwiftUI").font(.caption2)
            native
            TargetsReadout(info: info, snapshot: snapshot)
        }
        .font(.caption)
        .padding(6)
    }

    private var cells: some View {
        HStack(spacing: 0) {
            ForEach(0..<16, id: \.self) { i in
                TargetsAlignedCell(index: i).frame(width: Self.cell.width, height: Self.cell.height).ztronScrollID(i).id(i)
            }
        }
        .ztronScrollTargetLayout()
    }

    @ViewBuilder
    private var native: some View {
        if #available(iOS 17, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { i in
                        TargetsAlignedCell(index: i).frame(width: Self.cell.width, height: Self.cell.height).id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: behavior).native)
            .scrollPosition(id: $nativeID)
            .frame(width: 300, height: Self.cell.height)
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("aligned.native")
        } else {
            Text("SwiftUI view-aligned needs iOS 17").font(.caption2)
        }
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        oursID = 0
        nativeID = 0
        TargetsReadout.resetCountersSoon()
    }

    private func readout() {
        snapshot = TargetsReadout.counters()
        info = String(format: "limit=%@ ox=%.1f ours=%@ native=%@", limit, state.contentOffset.x,
                      oursID.map(String.init) ?? "nil", nativeID.map(String.init) ?? "nil")
    }
}

struct TargetsAlignedCell: View {
    let index: Int
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return ZStack {
            Color(hue: Double(index) / 16, saturation: 0.3, brightness: 0.95).padding(2)
            Text("\(index)")
        }
    }
}

// MARK: proxy first match against a native ScrollViewReader over two scroll views (Open 4)

struct TargetsTwinSection: View {
    @State private var upper = ZTronScrollState()
    @State private var lower = ZTronScrollState()
    @State private var nativeUpper: Int? = 0
    @State private var nativeLower: Int? = 0
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 4) {
            Text("ZTron: two scroll views, one reader").font(.caption2)
            ZTronScrollViewReader { proxy in
                VStack(spacing: 2) {
                    Button("ZTron scrollTo(15)") { proxy.scrollTo(15, anchor: .top) }.accessibilityIdentifier("twin.ztron")
                    ZTronScrollView(.vertical, state: upper) { column }
                        .frame(height: 90).border(Color.gray)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("twin.ztron.upper")
                    ZTronScrollView(.vertical, state: lower) { column }
                        .frame(height: 90).border(Color.gray)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("twin.ztron.lower")
                }
            }
            Text("SwiftUI: the same shape").font(.caption2)
            nativePair
            HStack(spacing: 8) {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
            }
            TargetsReadout(info: info, snapshot: snapshot)
        }
        .font(.caption)
        .padding(6)
    }

    private var column: some View {
        VStack(spacing: 0) { ForEach(0..<30, id: \.self) { TargetsRow(index: $0) } }
    }

    @ViewBuilder
    private var nativePair: some View {
        if #available(iOS 17, *) {
            ScrollViewReader { proxy in
                VStack(spacing: 2) {
                    Button("SwiftUI scrollTo(15)") { proxy.scrollTo(15, anchor: .top) }.accessibilityIdentifier("twin.native")
                    ScrollView { nativeColumn("NU").scrollTargetLayout() }
                        .scrollPosition(id: $nativeUpper)
                        .frame(height: 90).border(Color.gray)
                        .accessibilityIdentifier("twin.native.upper")
                    ScrollView { nativeColumn("NL").scrollTargetLayout() }
                        .scrollPosition(id: $nativeLower)
                        .frame(height: 90).border(Color.gray)
                        .accessibilityIdentifier("twin.native.lower")
                }
            }
        } else {
            Text("needs iOS 17").font(.caption2)
        }
    }

    private func nativeColumn(_ tag: String) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<30, id: \.self) { i in
                Text("\(tag) \(i)").frame(maxWidth: .infinity, minHeight: TargetsRow.height, maxHeight: TargetsRow.height).id(i)
            }
        }
    }

    private func reset() {
        for s in [upper, lower] { s.stopScrollingAndZooming(); s.setContentOffset(.zero, animated: false) }
        nativeUpper = 0
        nativeLower = 0
        TargetsReadout.resetCountersSoon()
    }

    private func readout() {
        snapshot = TargetsReadout.counters()
        info = String(format: "ztronUpper=%.1f ztronLower=%.1f nativeUpper=%@ nativeLower=%@", upper.contentOffset.y,
                      lower.contentOffset.y, nativeUpper.map(String.init) ?? "nil", nativeLower.map(String.init) ?? "nil")
    }
}

// MARK: R4 — SwiftUI's ScrollTargetBehaviorContext.velocity next to ours during a real pan

final class VelocityBox: @unchecked Sendable {
    var native = CGVector.zero
    var nativeCalls = 0
    var ours = CGVector.zero
    var oursCalls = 0
}

@available(iOS 17, *)
struct NativeVelocityBehavior: ScrollTargetBehavior {
    let box: VelocityBox
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        box.native = context.velocity
        box.nativeCalls += 1
    }
}

struct OursVelocityBehavior: ZTronScrollTargetBehavior {
    let box: VelocityBox
    @MainActor func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) {
        box.ours = context.velocity
        box.oursCalls += 1
    }
}

struct TargetsVelocitySection: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]
    private let box = VelocityBox()

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
            }
            Text("SwiftUI").font(.caption2)
            native
            Text("ZTron").font(.caption2)
            ZTronScrollView(.vertical, state: state) { column }
                .scrollTargetBehavior(OursVelocityBehavior(box: box))
                .frame(height: 200).border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("velocity.ours")
            TargetsReadout(info: info, snapshot: snapshot)
        }
        .font(.caption)
        .padding(6)
    }

    private var column: some View {
        VStack(spacing: 0) { ForEach(0..<200, id: \.self) { TargetsRow(index: $0) } }
    }

    @ViewBuilder
    private var native: some View {
        if #available(iOS 17, *) {
            ScrollView { VStack(spacing: 0) { ForEach(0..<200, id: \.self) { Text("Row \($0)").frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44) } } }
                .scrollTargetBehavior(NativeVelocityBehavior(box: box))
                .frame(height: 200).border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("velocity.native")
        } else {
            Text("needs iOS 17").font(.caption2)
        }
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        box.native = .zero; box.ours = .zero; box.nativeCalls = 0; box.oursCalls = 0
    }

    private func readout() {
        snapshot = TargetsReadout.counters()
        info = String(format: "native.vy=%.1f native.n=%d ours.vy=%.1f ours.n=%d", box.native.dy, box.nativeCalls, box.ours.dy, box.oursCalls)
    }
}
