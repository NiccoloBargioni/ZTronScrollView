import Foundation

// Reports of silent normalizations of caller input (user request 2026-10-21: "Clamping should at least produce a log,
// otherwise it becomes hard to track an error originating from an unexpected clamp."). Foundation only (SPEC S16: no
// os / OSLog): one `NSLog` line per distinct report, in the Xcode console and the unified log (Console.app).
//
// DEBUG builds only. In release builds only `Site` remains, the report path compiles out and every normalization does
// exactly what it did before. An in-range input never reports and costs nothing beyond the range check its
// normalization already makes. Reporting schedules nothing: no SwiftUI state, no body, no layout pass; from inside
// layout it is a plain function call guarded by the dedupe set.

/// The library's DEBUG report channel for inputs it normalizes silently: a unit value clamped to `0...1`, an unusable
/// aspect ratio read as `.ideal`, a negative or non-finite length read as 0, a non-finite anchor read as 0.
///
/// Each distinct (site, subject, input) is logged once per process (until ``resetForTesting()``), so a body that
/// re-runs or a layout pass per reflow cannot flood the console; at most ``capacity`` distinct reports are kept. The
/// public initializers and constructors that normalize caller input capture their caller's `#fileID` and `#line`; a
/// literal (`let k: ZTronUnitLength = 2`, or `ZTronUnitLength(2)`, which Swift types as that literal) carries no location
/// and reports as `literal`; a value resolved in layout reports as `at layout`. To find the caller in every case, set a
/// symbolic breakpoint on `ZTronDiagnostics.report`: it is called for every out-of-range input, logged or not.
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
    }

    /// Where a normalized input came from.
    enum Site: Sendable {
        /// The caller of a public initializer or constructor (its defaulted `fileID:` / `line:` arguments).
        case caller(fileID: StaticString, line: UInt)
        /// A float or integer literal: a literal initializer cannot capture its caller's location.
        case literal
        /// A stored value resolved in layout (the overlay's anchors, an overflowing aspect ratio): no caller location.
        case layout
    }
}

#if DEBUG
extension ZTronDiagnostics {
    /// One logged report (the DEBUG test hook, ``recorded``).
    struct Entry: Sendable, Equatable {
        let kind: Kind
        /// The logged line: `[ZTronScrollView] <Type>.<what>: <input> -> <result> (<fileID>:<line> | literal | at layout)`.
        let message: String
        /// The caller's `#fileID`; `nil` for a literal or a layout report.
        let fileID: String?
        /// The caller's `#line`; `nil` for a literal or a layout report.
        let line: UInt?
    }

    /// The most distinct reports kept per process: beyond it, new reports are neither logged nor recorded (one line
    /// says so), so the set never grows past it.
    static let capacity = 512

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

    /// Forgets every report, so the next one of each key logs again (DEBUG test hook). The breakpoint hint stays once
    /// per process.
    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        keys.removeAll()
        entries.removeAll()
        saturated = false
    }

    /// Reports that `subject` (a component, e.g. `ZTronUnitSize.width`) `what` (e.g. `is outside 0...1`) and was
    /// normalized: logs `[ZTronScrollView] <subject> <what>: <input> -> <result> (<where>)` the first time this
    /// (kind, subject, site, input bits) is seen. `bits` is the input (one or two values) that identifies the report;
    /// `input` and `result` are formatted only for a new report. Never inlined: a symbolic breakpoint on
    /// `ZTronDiagnostics.report` stops at every out-of-range input, logged or not, with the caller on the stack.
    @inline(never)
    static func report(_ kind: Kind, _ subject: StaticString, _ what: StaticString, bits: (CGFloat, CGFloat),
                       site: Site, input: @autoclosure () -> String, result: @autoclosure () -> String) {
        let key = Key(kind: kind, subject: StaticText(subject), site: SiteKey(site),
                      bits: (Double(bits.0).bitPattern, Double(bits.1).bitPattern))
        var lines: [String] = []
        lock.lock()
        if keys.contains(key) {
            lock.unlock()
            return
        }
        if keys.count >= capacity {
            if !saturated {
                saturated = true
                lines.append("[ZTronScrollView] \(capacity) distinct reports: further ones are not logged")
            }
        } else {
            keys.insert(key)
            let line = "[ZTronScrollView] \(subject) \(what): \(input()) -> \(result()) (\(site.label))"
            entries.append(Entry(kind: kind, message: line, fileID: site.fileID, line: site.line))
            if !hinted {
                hinted = true
                lines.append("[ZTronScrollView] set a symbolic breakpoint on ZTronDiagnostics.report to stop at the caller")
            }
            lines.append(line)
        }
        lock.unlock()
        for line in lines { NSLog("%@", line as NSString) }
    }

    // MARK: Storage

    // Every static below is read and written only while holding `lock` (the unit types are `Sendable` and their
    // initializers may run on any thread; layout reports run on the main thread).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys = Set<Key>()
    nonisolated(unsafe) private static var entries: [Entry] = []
    nonisolated(unsafe) private static var saturated = false
    /// Once per process (not reset by `resetForTesting()`).
    nonisolated(unsafe) private static var hinted = false

    private struct Key: Hashable {
        let kind: Kind
        let subject: StaticText
        let site: SiteKey
        let bits: (UInt64, UInt64)

        static func == (a: Key, b: Key) -> Bool {
            a.kind == b.kind && a.bits == b.bits && a.site == b.site && a.subject == b.subject
        }

        func hash(into h: inout Hasher) {
            h.combine(kind)
            h.combine(bits.0)
            h.combine(bits.1)
            h.combine(site)
            h.combine(subject)
        }
    }

    private enum SiteKey: Hashable {
        case caller(StaticText, UInt)
        case literal
        case layout

        init(_ site: Site) {
            switch site {
            case .caller(let fileID, let line): self = .caller(StaticText(fileID), line)
            case .literal: self = .literal
            case .layout: self = .layout
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
        case .layout: return "at layout"
        }
    }

    var fileID: String? {
        if case .caller(let fileID, _) = self { return "\(fileID)" }
        return nil
    }

    var line: UInt? {
        if case .caller(_, let line) = self { return line }
        return nil
    }
}
#endif
