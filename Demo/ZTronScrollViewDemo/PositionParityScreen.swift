import SwiftUI
import ZTronScrollView

/// PARITY-s1 (Orchestration item 9): SwiftUI's position APIs measured next to ours, in one screen, on one OS.
/// `-ZTronScreen positionParity -ZTronParity position|id|anchor`; options: `-ZTronParityInset <pt>` (a `safeAreaInset` on top of
/// every pane), `-ZTronParityAnchor top|center|bottom|leading|nil` (the modifier's anchor), `-ZTronParityRole
/// all|initialOffset|sizeChanges|alignment` (anchor section), `-ZTronParityRows <n>`, `-ZTronParityLazy 1` (native panes use a
/// `LazyVStack`). Panes: `n` = SwiftUI's `ScrollView` with SwiftUI's modifier, `b` = SwiftUI's `ScrollView` under our twin
/// (the native bridge), `z` = `ZTronScrollView` with the member. Every button applies to all panes at once; `Info` writes
/// `stateInfo` as `key=value` tokens per pane (`dy` = where the content is drawn in the pane, read by a probe in the content).
struct PositionParityScreen: View {
    static let config = ParityConfig()

    var body: some View {
        switch Self.config.section {
        case "id": ParityIDSection(config: Self.config)
        case "anchor": ParityAnchorSection(config: Self.config)
        default: ParityPositionSection(config: Self.config)
        }
    }
}

struct ParityConfig {
    var section = "position"
    var inset: CGFloat = 0
    var anchor: UnitPoint?
    var role = "all"
    var rows = 100
    var lazy = false
    static let paneHeight: CGFloat = 150

    init() {
        let a = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
            return a[i + 1]
        }
        section = value("-ZTronParity") ?? "position"
        inset = value("-ZTronParityInset").flatMap(Double.init).map { CGFloat($0) } ?? 0
        anchor = Self.unitPoint(value("-ZTronParityAnchor") ?? "nil")
        role = value("-ZTronParityRole") ?? "all"
        rows = value("-ZTronParityRows").flatMap(Int.init) ?? 100
        lazy = value("-ZTronParityLazy") == "1"
    }

    static func unitPoint(_ name: String) -> UnitPoint? {
        switch name {
        case "top": return .top
        case "center": return .center
        case "bottom": return .bottom
        case "leading": return .leading
        case "topLeading": return .topLeading
        default: return nil
        }
    }

    var ztronRole: ZTronScrollAnchorRole? {
        switch role {
        case "initialOffset": return .initialOffset
        case "sizeChanges": return .sizeChanges
        case "alignment": return .alignment
        default: return nil
        }
    }
}

/// What every pane records; written by probes and `onChange`, read by `Info` (never observed, so recording perturbs nothing).
final class ParityBox: @unchecked Sendable {
    var drawn: [String: CGRect] = [:]
    var geometry: [String: ParityGeometryValue] = [:]
    var position: [String: String] = [:]
    var sequence: [String: [String]] = [:]
    var changes: [String: Int] = [:]
    var ztron: [String: ZTronScrollState] = [:]
    /// `onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5)` per pane (SwiftUI's on 18+, ours everywhere).
    var visible: [String: [Int]] = [:]

    func note(_ tag: String, token: String, fields: String) {
        position[tag] = fields
        changes[tag, default: 0] += 1
        var s = sequence[tag, default: []]
        s.append(token)
        if s.count > 16 { s.removeFirst(s.count - 16) }
        sequence[tag] = s
    }

    func clear() {
        sequence = [:]
        changes = [:]
    }

    @MainActor func readout(_ tags: [String]) -> String {
        var parts: [String] = []
        for tag in tags {
            let d = drawn[tag] ?? .zero
            parts.append(String(format: "%@.dy=%.1f %@.dx=%.1f %@.h=%.1f", tag, d.minY, tag, d.minX, tag, d.height))
            if let s = ztron[tag] {
                parts.append(String(format: "%@.oy=%.1f %@.ox=%.1f %@.it=%.1f", tag, s.contentOffset.y, tag, s.contentOffset.x, tag,
                                    s.adjustedContentInset.top))
            } else if let g = geometry[tag] {
                parts.append(String(format: "%@.oy=%.1f %@.ox=%.1f %@.it=%.1f", tag, g.offset.y, tag, g.offset.x, tag, g.insetTop))
            }
            if let p = position[tag] { parts.append(p) }
            if let v = visible[tag] { parts.append("\(tag).vis=\(v.map(String.init).joined(separator: ","))") }
            parts.append("\(tag).w=\(changes[tag] ?? 0) \(tag).seq=\((sequence[tag] ?? []).joined(separator: ","))")
        }
        return parts.joined(separator: " ")
    }
}

struct ParityGeometryValue: Equatable {
    var offset: CGPoint
    var insetTop: CGFloat
}

/// The frame of the content in its pane, read from inside the content (SwiftUI's and ours alike). The reader writes the box
/// from its own body, which re-runs whenever that frame changes (a preference + `onPreferenceChange` never delivered here).
struct ParityProbe: ViewModifier {
    let tag: String
    let box: ParityBox
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in ParityProbeLeaf(frame: g.frame(in: .named(tag)), tag: tag, box: box) })
    }
}

struct ParityProbeLeaf: View {
    let frame: CGRect
    let tag: String
    let box: ParityBox
    var body: some View {
        box.drawn[tag] = frame
        return Color.clear
    }
}

/// SwiftUI's own offset and inset (iOS 18+).
@available(iOS 18, *)
struct ParityNativeGeometry: ViewModifier {
    let tag: String
    let box: ParityBox
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: ParityGeometryValue.self) { g in
            ParityGeometryValue(offset: g.contentOffset, insetTop: g.contentInsets.top)
        } action: { [box, tag] _, new in
            box.geometry[tag] = new
        }
    }
}

extension View {
    func parityPane(_ tag: String, _ config: ParityConfig) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { Color.orange.opacity(0.3).frame(height: config.inset) }
            .frame(height: ParityConfig.paneHeight)
            .coordinateSpace(name: tag)
            .clipped()
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pane.\(tag)")
    }
}

/// Row 0 carries the probe: a reader around the whole scroll target layout made SwiftUI's `scrollPosition(id:)` answer `nil`
/// after a user scroll (27.0), so the content's position is read from its first row.
struct ParityRow: View {
    static let height: CGFloat = 44
    let index: Int
    var tag = ""
    var box: ParityBox?
    var probe = false
    var body: some View {
        let row = Text("Row \(index)")
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
            .background(index % 2 == 0 ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
        if probe, let box {
            row.modifier(ParityProbe(tag: tag, box: box))
        } else {
            row
        }
    }
}

/// SwiftUI's column: `.id` on every row, a scroll target layout.
@available(iOS 17, *)
struct ParityNativeColumn: View {
    let rows: Range<Int>
    let lazy: Bool
    let tag: String
    let box: ParityBox
    var body: some View {
        if lazy {
            LazyVStack(spacing: 0) { ForEach(rows, id: \.self) { ParityRow(index: $0, tag: tag, box: box, probe: $0 == rows.lowerBound).id($0) } }
                .scrollTargetLayout()
        } else {
            VStack(spacing: 0) { ForEach(rows, id: \.self) { ParityRow(index: $0, tag: tag, box: box, probe: $0 == rows.lowerBound).id($0) } }
                .scrollTargetLayout()
        }
    }
}

/// Our column: `ztronScrollID` on every row.
struct ParityZTronColumn: View {
    let rows: Range<Int>
    let tag: String
    let box: ParityBox
    var body: some View {
        VStack(spacing: 0) { ForEach(rows, id: \.self) { ParityRow(index: $0, tag: tag, box: box, probe: $0 == rows.lowerBound).ztronScrollID($0) } }
    }
}

/// One command applied to every pane (`serial` makes a repeat a new value).
struct ParityTicket: Equatable {
    enum Command: Equatable {
        case none
        case edge(Edge)
        case point(CGPoint)
        case x(CGFloat)
        case y(CGFloat)
        case xy(CGFloat, CGFloat)
        case id(Int, UnitPoint?)
        case animatedID(Int)
        case clearID
        case reset
        /// Anchor section: a `ScrollViewReader` / `ZTronScrollViewReader` jump (id, anchor).
        case reader(Int, UnitPoint)
    }
    var command = Command.none
    var serial = 0
}

private func token(edge: Edge?) -> String {
    switch edge {
    case .top?: return "eT"
    case .bottom?: return "eB"
    case .leading?: return "eL"
    case .trailing?: return "eR"
    case nil: return ""
    }
}

private func pointText(_ p: CGPoint?) -> String {
    p.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "nil"
}

// MARK: ScrollPosition (18+) / ZTronScrollPosition

struct ParityPositionSection: View {
    let config: ParityConfig
    @State private var ticket = ParityTicket()
    @State private var info = ""
    @State private var rows: Range<Int>
    private let box = ParityBox()

    init(config: ParityConfig) {
        self.config = config
        _rows = State(initialValue: 0..<config.rows)
    }

    var body: some View {
        VStack(spacing: 3) {
            buttons
            if #available(iOS 18, *) {
                ParityNativePositionPane(config: config, rows: rows, ticket: ticket, box: box)
                ParityBridgePositionPane(config: config, rows: rows, ticket: ticket, box: box)
            } else {
                Text("ScrollPosition needs iOS 18").font(.caption2)
            }
            ParityZTronPositionPane(config: config, rows: rows, ticket: ticket, box: box)
            Text(info).font(.system(size: 7)).lineLimit(4).accessibilityIdentifier("stateInfo").accessibilityValue(info)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
    }

    private var buttons: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                send("top", .edge(.top)); send("bottom", .edge(.bottom))
                send("pt300", .point(CGPoint(x: 0, y: 300))); send("ptNeg", .point(CGPoint(x: 0, y: -100)))
                send("ptBig", .point(CGPoint(x: 0, y: 99_999))); send("ptX", .point(CGPoint(x: 50, y: 300)))
            }
            HStack(spacing: 6) {
                send("y500", .y(500)); send("yNeg", .y(-100)); send("x50", .x(50)); send("xy400", .xy(0, 400))
                send("id30", .id(30, nil)); send("id30c", .id(30, .center)); send("id30b", .id(30, .bottom))
            }
            HStack(spacing: 6) {
                send("id99", .id(99, nil)); send("id0", .id(0, nil)); send("anim60", .animatedID(60))
                Button("prepend") { rows = (rows.lowerBound - 3)..<rows.upperBound }.accessibilityIdentifier("cmd.prepend")
                Button("grow") { rows = rows.lowerBound..<(rows.upperBound + 3) }.accessibilityIdentifier("cmd.grow")
                send("Reset", .reset)
                Button("Info") { info = box.readout(["n", "b", "z"]) }.accessibilityIdentifier("Info")
            }
            ParityJumps(config: config) { ticket = ParityTicket(command: $0, serial: ticket.serial + 1) }
        }
    }

    private func send(_ name: String, _ command: ParityTicket.Command) -> some View {
        Button(name) {
            if command == .reset { box.clear() }
            ticket = ParityTicket(command: command, serial: ticket.serial + 1)
        }
        .accessibilityIdentifier(name == "Reset" ? "Reset" : "cmd.\(name)")
    }
}

/// Reader jumps that put content y = `v` (inside rows 1 and 2) at the top of the unobscured area: row 2 (top 88) with the
/// anchor `a` that makes `88 + a · (44 − H) = v`, `H` the unobscured height. They show which id SwiftUI reports for a view
/// that is partly scrolled out, and whether a programmatic scroll writes the binding.
struct ParityJumps: View {
    let config: ParityConfig
    let send: (ParityTicket.Command) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach([45, 60, 66, 70, 87], id: \.self) { v in
                Button("j\(v)") {
                    let h = ParityConfig.paneHeight - config.inset
                    send(.reader(2, UnitPoint(x: 0.5, y: (88 - CGFloat(v)) / (h - ParityRow.height))))
                }
                .accessibilityIdentifier("cmd.j\(v)")
            }
        }
    }
}

@available(iOS 18, *)
private func describe(_ p: ScrollPosition, _ tag: String) -> (token: String, fields: String) {
    let id = p.viewID(type: Int.self)
    var t = id.map { "i\($0)" } ?? (p.point.map { String(format: "p%.0f:%.0f", $0.x, $0.y) } ?? token(edge: p.edge))
    var xy = ""
    if #available(iOS 26, *) {
        xy = " \(tag).x=\(p.x.map { String(format: "%.1f", $0) } ?? "nil") \(tag).y=\(p.y.map { String(format: "%.1f", $0) } ?? "nil")"
        if t.isEmpty, p.x != nil || p.y != nil { t = "xy" }
    }
    if t.isEmpty { t = "-" }
    if p.isPositionedByUser { t += "u" }
    let fields = "\(tag).id=\(id.map(String.init) ?? "nil") \(tag).pt=\(pointText(p.point)) \(tag).edge=\(p.edge.map { "\($0)" } ?? "nil") "
        + "\(tag).user=\(p.isPositionedByUser ? 1 : 0)" + xy
    return (t, fields)
}

private func describe(_ p: ZTronScrollPosition, _ tag: String) -> (token: String, fields: String) {
    let id = p.viewID(type: Int.self)
    var t = id.map { "i\($0)" } ?? (p.point.map { String(format: "p%.0f:%.0f", $0.x, $0.y) } ?? token(edge: p.edge))
    if t.isEmpty, p.x != nil || p.y != nil { t = "xy" }
    if t.isEmpty { t = "-" }
    if p.isPositionedByUser { t += "u" }
    let xy = " \(tag).x=\(p.x.map { String(format: "%.1f", $0) } ?? "nil") \(tag).y=\(p.y.map { String(format: "%.1f", $0) } ?? "nil")"
    let fields = "\(tag).id=\(id.map(String.init) ?? "nil") \(tag).pt=\(pointText(p.point)) \(tag).edge=\(p.edge.map { "\($0)" } ?? "nil") "
        + "\(tag).user=\(p.isPositionedByUser ? 1 : 0)" + xy
    return (t, fields)
}

@available(iOS 18, *)
struct ParityNativePositionPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    /// The id type the views use: SwiftUI writes `viewID` back only for ids of the position's id type (its docs' example).
    @State private var position = ScrollPosition(idType: Int.self)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { ParityNativeColumn(rows: rows, lazy: config.lazy, tag: "n", box: box) }
                .scrollPosition($position, anchor: config.anchor)
                .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { [box] in box.visible["n"] = $0 }
                .modifier(ParityNativeGeometry(tag: "n", box: box))
                .parityPane("n", config)
                .onChange(of: ticket) { _, t in
                    if case let .reader(id, anchor) = t.command { proxy.scrollTo(id, anchor: anchor) } else { apply(t.command) }
                    if t.command == .reset { proxy.scrollTo(rows.lowerBound, anchor: .top) }   // a binding set to its value is a no-op
                }
                .onChange(of: position) { _, p in let d = describe(p, "n"); box.note("n", token: d.token, fields: d.fields) }
        }
    }

    private func apply(_ c: ParityTicket.Command) {
        switch c {
        case .none, .clearID, .reader: break
        case .reset: position = ScrollPosition(idType: Int.self, edge: .top)
        case let .edge(e): position.scrollTo(edge: e)
        case let .point(p): position.scrollTo(point: p)
        case let .x(v): position.scrollTo(x: v)
        case let .y(v): position.scrollTo(y: v)
        case let .xy(x, y): position.scrollTo(x: x, y: y)
        case let .id(i, a): position.scrollTo(id: i, anchor: a)
        case let .animatedID(i): withAnimation(.easeInOut(duration: 0.5)) { position.scrollTo(id: i) }
        }
    }
}

/// SwiftUI's `ScrollView` driven by a `ZTronScrollPosition` through `ztronScrollPosition` (the 18+ bridge).
struct ParityBridgePositionPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    @State private var position = ZTronScrollPosition(idType: Int.self)

    var body: some View {
        if #available(iOS 17, *) {
            ScrollViewReader { proxy in
                ScrollView { ParityNativeColumn(rows: rows, lazy: config.lazy, tag: "b", box: box) }
                    .ztronScrollPosition($position, anchor: config.anchor)
                    .modifier(ParityGeometryIfAvailable(tag: "b", box: box))
                    .parityPane("b", config)
                    .onChange(of: ticket) { t in
                        if case let .reader(id, anchor) = t.command { proxy.scrollTo(id, anchor: anchor) } else { apply(t.command, to: &position) }
                        if t.command == .reset { proxy.scrollTo(rows.lowerBound, anchor: .top) }
                    }
                    .onChange(of: position) { p in let d = describe(p, "b"); box.note("b", token: d.token, fields: d.fields) }
            }
        }
    }
}

struct ParityGeometryIfAvailable: ViewModifier {
    let tag: String
    let box: ParityBox
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(ParityNativeGeometry(tag: tag, box: box))
        } else {
            content
        }
    }
}

@MainActor private func apply(_ c: ParityTicket.Command, to position: inout ZTronScrollPosition) {
    switch c {
    case .none, .clearID, .reader: break
    case .reset: position = ZTronScrollPosition(idType: Int.self, edge: .top)
    case let .edge(e): position.scrollTo(edge: e)
    case let .point(p): position.scrollTo(point: p)
    case let .x(v): position.scrollTo(x: v)
    case let .y(v): position.scrollTo(y: v)
    case let .xy(x, y): position.scrollTo(x: x, y: y)
    case let .id(i, a): position.scrollTo(id: i, anchor: a)
    case let .animatedID(i):
        var copy = position
        copy.scrollTo(id: i)
        let new = copy
        withAnimation(.easeInOut(duration: 0.5)) { position = new }
    }
}

struct ParityZTronPositionPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    @State private var state = ZTronScrollState()
    @State private var position = ZTronScrollPosition(idType: Int.self)

    var body: some View {
        ZTronScrollViewReader { proxy in
            ZTronScrollView(.vertical, state: state) { ParityZTronColumn(rows: rows, tag: "z", box: box) }
                .scrollPosition($position, anchor: config.anchor)
                .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { [box] in box.visible["z"] = $0 }
                .parityPane("z", config)
                .onAppear { box.ztron["z"] = state }
                .onChange(of: ticket) { t in
                    if t.command == .reset { state.stopScrollingAndZooming() }
                    if case let .reader(id, anchor) = t.command { proxy.scrollTo(id, anchor: anchor) } else { apply(t.command, to: &position) }
                    if t.command == .reset { proxy.scrollTo(rows.lowerBound, anchor: .top) }
                }
                .onChange(of: position) { p in let d = describe(p, "z"); box.note("z", token: d.token, fields: d.fields) }
        }
    }
}

// MARK: scrollPosition(id:anchor:) (17+)

struct ParityIDSection: View {
    let config: ParityConfig
    @State private var ticket = ParityTicket()
    @State private var info = ""
    @State private var rows: Range<Int>
    private let box = ParityBox()

    init(config: ParityConfig) {
        self.config = config
        _rows = State(initialValue: 0..<config.rows)
    }

    var body: some View {
        VStack(spacing: 3) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    send("id30", .id(30, nil)); send("id60", .id(60, nil)); send("id99", .id(99, nil)); send("id0", .id(0, nil))
                    send("anim45", .animatedID(45)); send("nil", .clearID)
                }
                HStack(spacing: 6) {
                    Button("prepend") { rows = (rows.lowerBound - 3)..<rows.upperBound }.accessibilityIdentifier("cmd.prepend")
                    Button("grow") { rows = rows.lowerBound..<(rows.upperBound + 3) }.accessibilityIdentifier("cmd.grow")
                    send("Reset", .reset)
                    Button("Info") { info = box.readout(["n", "b", "z"]) }.accessibilityIdentifier("Info")
                }
                ParityJumps(config: config) { ticket = ParityTicket(command: $0, serial: ticket.serial + 1) }
            }
            if #available(iOS 17, *) {
                ParityNativeIDPane(config: config, rows: rows, ticket: ticket, box: box, twin: false)
                ParityNativeIDPane(config: config, rows: rows, ticket: ticket, box: box, twin: true)
            } else {
                Text("scrollPosition(id:) needs iOS 17").font(.caption2)
            }
            ParityZTronIDPane(config: config, rows: rows, ticket: ticket, box: box)
            Text(info).font(.system(size: 7)).lineLimit(4).accessibilityIdentifier("stateInfo").accessibilityValue(info)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
    }

    private func send(_ name: String, _ command: ParityTicket.Command) -> some View {
        Button(name) {
            if command == .reset { box.clear() }
            ticket = ParityTicket(command: command, serial: ticket.serial + 1)
        }
        .accessibilityIdentifier(name == "Reset" ? "Reset" : "cmd.\(name)")
    }
}

private func noteID(_ id: Int?, _ tag: String, _ box: ParityBox) {
    box.note(tag, token: id.map { "i\($0)" } ?? "-", fields: "\(tag).id=\(id.map(String.init) ?? "nil")")
}

private func apply(_ c: ParityTicket.Command, to id: inout Int?) {
    switch c {
    case .reset: id = 0
    case let .id(i, _): id = i
    case .clearID: id = nil
    case let .animatedID(i): withAnimation(.easeInOut(duration: 0.5)) { id = i }
    default: break
    }
}

/// `twin == false`: SwiftUI's `scrollPosition(id:anchor:)`; `true`: our twin `ztronScrollPosition(id:anchor:)` (which applies SwiftUI's).
@available(iOS 17, *)
struct ParityNativeIDPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    let twin: Bool
    @State private var id: Int? = 0
    private var tag: String { twin ? "b" : "n" }

    var body: some View {
        ScrollViewReader { proxy in
            let scroll = ScrollView { ParityNativeColumn(rows: rows, lazy: config.lazy, tag: tag, box: box) }
            Group {
                if twin {
                    scroll.ztronScrollPosition(id: $id, anchor: config.anchor)
                } else {
                    scroll.scrollPosition(id: $id, anchor: config.anchor)
                }
            }
            .modifier(ParityGeometryIfAvailable(tag: tag, box: box))
            .parityPane(tag, config)
            .onChange(of: ticket) { _, t in
                if case let .reader(i, anchor) = t.command { proxy.scrollTo(i, anchor: anchor) } else { apply(t.command, to: &id) }
                if t.command == .reset { proxy.scrollTo(rows.lowerBound, anchor: .top) }
            }
            .onChange(of: id) { _, new in noteID(new, tag, box) }
        }
    }
}

struct ParityZTronIDPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    @State private var state = ZTronScrollState()
    @State private var id: Int? = 0

    var body: some View {
        ZTronScrollViewReader { proxy in
            ZTronScrollView(.vertical, state: state) { ParityZTronColumn(rows: rows, tag: "z", box: box) }
                .scrollPosition(id: $id, anchor: config.anchor)
                .parityPane("z", config)
                .onAppear { box.ztron["z"] = state }
                .onChange(of: ticket) { t in
                    if t.command == .reset { state.stopScrollingAndZooming() }
                    if case let .reader(i, anchor) = t.command { proxy.scrollTo(i, anchor: anchor) } else { apply(t.command, to: &id) }
                    if t.command == .reset { proxy.scrollTo(rows.lowerBound, anchor: .top) }
                }
                .onChange(of: id) { new in noteID(new, "z", box) }
        }
    }
}

// MARK: defaultScrollAnchor(_:) / (_:for:) (17 / 18+)

struct ParityAnchorSection: View {
    let config: ParityConfig
    @State private var rows: Range<Int>
    @State private var ticket = ParityTicket()
    @State private var info = ""
    private let box = ParityBox()

    init(config: ParityConfig) {
        self.config = config
        _rows = State(initialValue: 0..<config.rows)
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Button("Grow") { rows = rows.lowerBound..<(rows.upperBound + 3) }.accessibilityIdentifier("cmd.grow")
                Button("Shrink") { rows = rows.lowerBound..<max(rows.lowerBound + 1, rows.upperBound - 3) }
                    .accessibilityIdentifier("cmd.shrink")
                Button("prepend") { rows = (rows.lowerBound - 3)..<rows.upperBound }.accessibilityIdentifier("cmd.prepend")
                jump("toTop", rows.lowerBound, .top)
                jump("toMid", rows.lowerBound + rows.count / 2, .top)
                jump("toBottom", rows.upperBound - 1, .bottom)
                Button("Info") { info = box.readout(["n", "b", "z"]) }.accessibilityIdentifier("Info")
            }
            if #available(iOS 17, *) {
                ParityNativeAnchorPane(config: config, rows: rows, ticket: ticket, box: box, twin: false)
                ParityNativeAnchorPane(config: config, rows: rows, ticket: ticket, box: box, twin: true)
            } else {
                Text("defaultScrollAnchor needs iOS 17").font(.caption2)
            }
            ParityZTronAnchorPane(config: config, rows: rows, ticket: ticket, box: box)
            Text(info).font(.system(size: 7)).lineLimit(4).accessibilityIdentifier("stateInfo").accessibilityValue(info)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
    }

    private func jump(_ name: String, _ id: Int, _ anchor: UnitPoint) -> some View {
        Button(name) { ticket = ParityTicket(command: .reader(id, anchor), serial: ticket.serial + 1) }
            .accessibilityIdentifier("cmd.\(name)")
    }
}

@available(iOS 17, *)
struct ParityNativeAnchorPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    let twin: Bool
    private var tag: String { twin ? "b" : "n" }

    var body: some View {
        ScrollViewReader { proxy in
            anchored(ScrollView { ParityNativeColumn(rows: rows, lazy: config.lazy, tag: tag, box: box) })
                .modifier(ParityGeometryIfAvailable(tag: tag, box: box))
                .parityPane(tag, config)
                .onChange(of: ticket) { _, t in
                    if case let .reader(id, anchor) = t.command { proxy.scrollTo(id, anchor: anchor) }
                }
        }
    }

    @ViewBuilder
    private func anchored(_ scroll: some View) -> some View {
        if twin {
            if let role = config.ztronRole {
                scroll.ztronDefaultScrollAnchor(config.anchor, for: role)
            } else {
                scroll.ztronDefaultScrollAnchor(config.anchor)
            }
        } else if #available(iOS 18, *), let role = config.ztronRole {
            scroll.defaultScrollAnchor(config.anchor, for: role.native)
        } else if config.ztronRole == nil || config.ztronRole == .initialOffset {
            scroll.defaultScrollAnchor(config.anchor)
        } else {
            scroll
        }
    }
}

struct ParityZTronAnchorPane: View {
    let config: ParityConfig
    let rows: Range<Int>
    let ticket: ParityTicket
    let box: ParityBox
    @State private var state = ZTronScrollState()

    var body: some View {
        ZTronScrollViewReader { proxy in
            anchored(ZTronScrollView(.vertical, state: state) { ParityZTronColumn(rows: rows, tag: "z", box: box) })
                .parityPane("z", config)
                .onAppear { box.ztron["z"] = state }
                .onChange(of: ticket) { t in
                    if case let .reader(id, anchor) = t.command { proxy.scrollTo(id, anchor: anchor) }
                }
        }
    }

    private func anchored(_ view: ZTronScrollView<ParityZTronColumn>) -> ZTronScrollView<ParityZTronColumn> {
        if let role = config.ztronRole { return view.defaultScrollAnchor(config.anchor, for: role) }
        return view.defaultScrollAnchor(config.anchor)
    }
}
