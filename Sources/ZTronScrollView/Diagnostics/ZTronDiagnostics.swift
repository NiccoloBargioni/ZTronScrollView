import Foundation

// Reports of silent normalizations of caller input (user request 2026-10-21: "Clamping should at least produce a log,
// otherwise it becomes hard to track an error originating from an unexpected clamp."). Foundation only (SPEC S16: no
// os / OSLog): one `NSLog` line per distinct report, in the Xcode console and the unified log (Console.app).
//
// DEBUG builds only. In release builds only `Site` and an empty `CallSite` remain, the report path compiles out and
// every normalization does exactly what it did before. Not quite zero: the public initializers, constructors and
// modifiers that report take defaulted `fileID:` / `line:` arguments, which every call site still passes in a release
// build (a `StaticString` and a line number; the file ID string lives in the client's binary). An in-range input never
// reports and costs nothing beyond the range check its normalization already makes. Reporting schedules nothing: no
// SwiftUI state, no body, no layout pass; from inside layout it is a plain function call guarded by the dedupe set.

/// The library's DEBUG report channel for inputs it normalizes silently: a unit value clamped to `0...1`, an unusable
/// aspect ratio read as `.ideal`, a negative or non-finite length read as 0, a non-finite anchor read as 0.
///
/// Each distinct (kind, subject, site, input) is logged once per process (until ``resetForTesting(includingHint:)``),
/// so a body that re-runs or a layout pass per reflow cannot flood the console. Two bounds keep a value that changes
/// every frame (a drag that clamps) from flooding it or from silencing other sites: at most ``perSiteLimit`` distinct
/// values per (kind, subject, call site), then one line says further values there are not logged; at most
/// ``capacity`` distinct reports per process, a backstop. A literal site (literal values are source constants) and an
/// unlocated layout site (internal callers only) take many sources' values, so only the backstop bounds them.
///
/// Locations: the public initializers and constructors that normalize caller input capture their caller's `#fileID`
/// and `#line`; a literal (`let k: ZTronUnitLength = 2`, or `ZTronUnitLength(2)`, which Swift types as that literal)
/// carries no location and reports as `literal`, and again with the location of the constructor that receives it
/// (`.relative(width: 50, height: 0.5)`); a value resolved in layout (an anchor, an overflowing aspect ratio) reports
/// with the location of the `scrollContentIntegralOverlay` call that declared the overlay, marked `at layout`. A
/// symbolic breakpoint on `ZTronDiagnostics.report` stops at every out-of-range input, logged or not: with the caller
/// on the stack for a constructor or a literal; for a layout report the stack holds SwiftUI's layout frames only, and
/// the logged location is the way back to the call.
enum ZTronDiagnostics {
    /// What was normalized.
    enum Kind: String, Sendable, CaseIterable {
        /// A ``ZTronUnitLength`` / ``ZTronUnitSize`` / ``ZTronUnitPoint`` component outside `0...1` or NaN, clamped.
        case unitClamped
        /// An aspect ratio that is zero, negative or non-finite, read as ``ZTronContentOverlayLength/ideal``.
        case aspectRatioIgnored
        /// An absolute length or size component that is negative or non-finite, read as 0.
        case absoluteLengthZeroed
        /// In layout: a positive aspect ratio whose length (`W / r` or `H · r`) overflows `CGFloat`, drawn as 0.
        case aspectRatioOverflow
        /// In layout: a non-finite component of a ``ZTronContentOverlayAnchor/absolute(_:)`` point, read as 0.
        case anchorNotFinite
        /// In layout: a non-finite component of an overlay's `overlayAnchor`, read as 0.
        case overlayAnchorNotFinite
        /// A non-finite component of ``SwiftUI/View/ztronScrollCounterScaled(anchor:fileID:line:)``'s `anchor`, read
        /// as 0.
        case counterScaleAnchorNotFinite
    }

    /// Where a normalized input came from.
    enum Site: Sendable {
        /// The caller of a public initializer or constructor (its defaulted `fileID:` / `line:` arguments).
        case caller(fileID: StaticString, line: UInt)
        /// A float or integer literal: a literal initializer cannot capture its caller's location.
        case literal
        /// A stored value resolved in layout (the overlay's anchors, an overflowing aspect ratio), from the overlay
        /// declared at `fileID:line` (the modifier's caller); `fileID` is `nil` for an internal caller without one.
        case layout(fileID: StaticString?, line: UInt)
    }

    /// The `scrollContentIntegralOverlay` call that declared an overlay, carried to layout for the reports made there.
    /// Empty in release builds (no storage, no work); never part of an `==`.
    struct CallSite: Sendable {
        #if DEBUG
        let site: Site
        #endif

        @inline(__always)
        init(fileID: StaticString, line: UInt) {
            #if DEBUG
            site = .layout(fileID: fileID, line: line)
            #endif
        }

        @inline(__always)
        private init() {
            #if DEBUG
            site = .layout(fileID: nil, line: 0)
            #endif
        }

        /// No location: an internal caller (the layout key's default value, the math's tests).
        static var unlocated: CallSite { CallSite() }
    }
}

#if DEBUG
extension ZTronDiagnostics {
    /// One logged report (the DEBUG test hook, ``recorded``).
    struct Entry: Sendable, Equatable {
        let kind: Kind
        /// The logged line: `[ZTronScrollView] <subject> <what>: <input> -> <result> (<where>)`, `<where>` being
        /// `<fileID>:<line>`, `literal`, `<fileID>:<line>, at layout` or `at layout`.
        let message: String
        /// The caller's `#fileID` (for a layout report, the declaring modifier's); `nil` for a literal or an unlocated
        /// layout report.
        let fileID: String?
        /// The caller's `#line`, as `fileID`.
        let line: UInt?
    }

    /// The most distinct reports kept per process: beyond it, new reports are neither logged nor recorded (one line
    /// says so), so the set never grows past it. A backstop: ``perSiteLimit`` bounds each call site well before it.
    static let capacity = 512

    /// The most distinct values logged per (kind, subject, call site): beyond it, one line says further values there
    /// are not logged, and that site adds nothing to the set. Not applied to the `literal` site or to an unlocated
    /// layout site, which gather many sources (``capacity`` bounds them).
    static let perSiteLimit = 8

    /// The logged reports, oldest first (DEBUG test hook).
    static var recorded: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// The number of distinct keys held (equals `recorded.count`; DEBUG test hook for the lock invariant).
    static var recordedKeyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return keys.count
    }

    /// Where the lines go: `NSLog` (``nsLogSink``) unless a test captures them (DEBUG test hook). Called outside the
    /// lock, in order, on the reporting thread.
    static var sink: @Sendable (String) -> Void {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentSink
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            currentSink = newValue
        }
    }

    /// The default ``sink``: one `NSLog` per line (Xcode console, unified log).
    static let nsLogSink: @Sendable (String) -> Void = { NSLog("%@", $0 as NSString) }

    /// The breakpoint hint, logged once per process before the first report.
    static let hint = "[ZTronScrollView] set a symbolic breakpoint on ZTronDiagnostics.report to stop where a value is "
        + "normalized (a layout report's location is in its line)"

    /// Forgets every report, so the next one of each key logs again (DEBUG test hook). The breakpoint hint stays once
    /// per process unless `includingHint`.
    static func resetForTesting(includingHint: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        keys.removeAll()
        entries.removeAll()
        perSite.removeAll()
        saturated = false
        if includingHint { hinted = false }
    }

    /// Reports that `subject` (a component, e.g. `ZTronUnitSize.width`) `what` (e.g. `is outside 0...1`) and was
    /// normalized: logs `[ZTronScrollView] <subject> <what>: <input> -> <result> (<where>)` the first time this
    /// (kind, subject, site, input bits) is seen. `bits` is the one input value that was normalized (a component, never
    /// the whole point: a healthy component that changes does not make a new report); `input` and `result` are
    /// formatted only for a new report. Never inlined: a symbolic breakpoint on `ZTronDiagnostics.report` stops at
    /// every out-of-range input, logged or not.
    @inline(never)
    static func report(_ kind: Kind, _ subject: StaticString, _ what: StaticString, bits: CGFloat,
                       site: Site, input: @autoclosure () -> String, result: @autoclosure () -> String) {
        let slot = Slot(kind: kind, subject: StaticText(subject), site: SiteKey(site))
        let key = Key(slot: slot, bits: Double(bits).bitPattern)
        var lines: [String] = []
        lock.lock()
        if keys.contains(key) {
            lock.unlock()
            return
        }
        let limited = site.isLimited
        let count = limited ? perSite[slot, default: 0] : 0
        if limited && count >= perSiteLimit {
            if count == perSiteLimit {   // the first value past the limit: say so once (count perSiteLimit + 1 = said)
                perSite[slot] = count + 1
                lines.append("[ZTronScrollView] \(subject) (\(site.label)): \(perSiteLimit) distinct values reported, "
                             + "further ones are not logged")
            }
        } else if keys.count >= capacity {
            if !saturated {
                saturated = true
                lines.append("[ZTronScrollView] \(capacity) distinct reports: further ones are not logged")
            }
        } else {
            keys.insert(key)
            if limited { perSite[slot] = count + 1 }   // `perSite` never holds more slots than `keys` holds keys
            let line = "[ZTronScrollView] \(subject) \(what): \(input()) -> \(result()) (\(site.label))"
            entries.append(Entry(kind: kind, message: line, fileID: site.fileID, line: site.line))
            if !hinted {
                hinted = true
                lines.append(hint)
            }
            lines.append(line)
        }
        let out = currentSink
        lock.unlock()
        for line in lines { out(line) }
    }

    // MARK: Storage

    // Every static below is read and written only while holding `lock` (the unit types are `Sendable` and their
    // initializers may run on any thread; layout reports run on the main thread).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys = Set<Key>()
    nonisolated(unsafe) private static var entries: [Entry] = []
    /// Distinct values logged per slot (kind, subject, limited site); `perSiteLimit + 1` once the limit line is out.
    nonisolated(unsafe) private static var perSite: [Slot: Int] = [:]
    nonisolated(unsafe) private static var saturated = false
    /// Once per process (reset only by `resetForTesting(includingHint: true)`).
    nonisolated(unsafe) private static var hinted = false
    nonisolated(unsafe) private static var currentSink: @Sendable (String) -> Void = nsLogSink

    /// Where and what: one call site's reports of one component.
    private struct Slot: Hashable {
        let kind: Kind
        let subject: StaticText
        let site: SiteKey
    }

    private struct Key: Hashable {
        let slot: Slot
        let bits: UInt64
    }

    private enum SiteKey: Hashable {
        case caller(StaticText, UInt)
        case literal
        case layout(StaticText?, UInt)

        init(_ site: Site) {
            switch site {
            case .caller(let fileID, let line): self = .caller(StaticText(fileID), line)
            case .literal: self = .literal
            case .layout(let fileID, let line): self = .layout(fileID.map(StaticText.init), line)
            }
        }
    }

    /// A `StaticString` compared and hashed by its bytes, without allocating.
    private struct StaticText: Hashable {
        let text: StaticString
        init(_ text: StaticString) { self.text = text }

        static func == (a: StaticText, b: StaticText) -> Bool {
            a.text.withUTF8Buffer { x in b.text.withUTF8Buffer { y in x.elementsEqual(y) } }
        }

        func hash(into h: inout Hasher) {
            text.withUTF8Buffer { h.combine(bytes: UnsafeRawBufferPointer($0)) }
        }
    }
}

extension ZTronDiagnostics.Site {
    /// The location as logged.
    var label: String {
        switch self {
        case .caller(let fileID, let line): return "\(fileID):\(line)"
        case .literal: return "literal"
        case .layout(let fileID?, let line): return "\(fileID):\(line), at layout"
        case .layout(nil, _): return "at layout"
        }
    }

    var fileID: String? {
        switch self {
        case .caller(let fileID, _), .layout(let fileID?, _): return "\(fileID)"
        default: return nil
        }
    }

    var line: UInt? {
        switch self {
        case .caller(_, let line), .layout(_?, let line): return line
        default: return nil
        }
    }

    /// Whether ``ZTronDiagnostics/perSiteLimit`` applies: a real call site, not one that gathers many sources.
    var isLimited: Bool {
        switch self {
        case .caller, .layout(_?, _): return true
        case .literal, .layout(nil, _): return false
        }
    }
}
#endif
