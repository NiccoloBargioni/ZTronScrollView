import SwiftUI

/// Mirrors `ScrollPosition` (iOS 18) for every OS this library supports (design M6 §2). A value you bind with
/// `scrollPosition(_:anchor:)`: set it (`scrollTo(id:)`, `scrollTo(edge:)`, `scrollTo(point:)` …) to scroll, read it to see
/// where the user left the view. The scroll view writes it back only when a user gesture decided where it lands and when
/// that motion settled (`isPositionedByUser` is then `true`), never per frame and never after a programmatic request.
///
/// A point is in content space, like SwiftUI's: `scrollTo(point:)` puts it at the top-leading corner of the unobscured area
/// (the offset is the point minus the leading insets), and `scrollTo(x:)` / `scrollTo(y:)` do the same on one axis, leaving
/// `point` and `edge` `nil` (``x`` / ``y`` read them back, like SwiftUI's on iOS 26).
///
/// A user scroll writes `viewID` (the `ztronScrollID` view under the position's anchor) when one is there, else `point`.
public struct ZTronScrollPosition: Equatable, Sendable {
    enum Request: Equatable, @unchecked Sendable {
        case id(AnyHashable, UnitPoint?)
        case edge(Edge)
        case point(CGPoint)
        case x(CGFloat)
        case y(CGFloat)
        case xy(CGPoint)
    }

    /// What the position asks for (or, after a write-back, where the user left the view).
    var request: Request?
    /// Bumped on every `scrollTo` and part of `==`, so asking for the same thing again scrolls again.
    var serial: UInt64
    /// `true` once the scroll view wrote the position after a user scroll; `false` for a value you set.
    public private(set) var isPositionedByUser: Bool
    /// The id as the app gave it when it is `Sendable` (or as SwiftUI wrote it back). SwiftUI's `ScrollPosition(id:)` matches
    /// views by the id's own type, so the iOS 18+ bridge hands it over unwrapped: an `AnyHashable` wrapper never matched a view
    /// (PARITY-s1). Not part of `==` (the request carries the same id).
    var sendableID: (any Hashable & Sendable)?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastSerial: UInt64 = 0
    private static func nextSerial() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        lastSerial += 1
        return lastSerial
    }

    /// No request: the view stays where it is.
    public init() {
        request = nil
        serial = 0
        isPositionedByUser = false
    }

    public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        request = .id(AnyHashable(id), anchor)
        serial = Self.nextSerial()
        isPositionedByUser = false
    }

    /// SwiftUI's own shape (`some Hashable & Sendable`); chosen for every `Sendable` id, so the native bridge can pass it on.
    public init<ID: Hashable & Sendable>(id: ID, anchor: UnitPoint? = nil) {
        request = .id(AnyHashable(id), anchor)
        serial = Self.nextSerial()
        isPositionedByUser = false
        sendableID = id
    }

    public init(point: CGPoint) { self.init(.point(point)) }
    public init(edge: Edge) { self.init(.edge(edge)) }
    public init(x: CGFloat) { self.init(.x(x)) }
    public init(y: CGFloat) { self.init(.y(y)) }
    public init(x: CGFloat, y: CGFloat) { self.init(.xy(CGPoint(x: x, y: y))) }

    private init(_ request: Request) {
        self.request = request
        serial = Self.nextSerial()
        isPositionedByUser = false
    }

    /// Library-internal: a value with an explicit serial (a write-back keeps the serial it was answering; the `id` binding uses 0).
    init(request: Request?, serial: UInt64, isPositionedByUser: Bool) {
        self.request = request
        self.serial = serial
        self.isPositionedByUser = isPositionedByUser
    }

    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) { self = ZTronScrollPosition(id: id, anchor: anchor) }
    public mutating func scrollTo<ID: Hashable & Sendable>(id: ID, anchor: UnitPoint? = nil) {
        self = ZTronScrollPosition(id: id, anchor: anchor)
    }
    public mutating func scrollTo(edge: Edge) { self = ZTronScrollPosition(edge: edge) }
    public mutating func scrollTo(point: CGPoint) { self = ZTronScrollPosition(point: point) }
    public mutating func scrollTo(x: CGFloat) { self = ZTronScrollPosition(x: x) }
    public mutating func scrollTo(y: CGFloat) { self = ZTronScrollPosition(y: y) }
    public mutating func scrollTo(x: CGFloat, y: CGFloat) { self = ZTronScrollPosition(x: x, y: y) }

    /// The id of the view the position names (type-erased); `nil` when it names a point or an edge.
    public var viewID: (any Hashable)? {
        if case let .id(id, _)? = request { return id.base as? any Hashable }
        return nil
    }

    /// The id as `type`, when the position names a view of that type.
    public func viewID<T: Hashable>(type: T.Type) -> T? {
        if case let .id(id, _)? = request { return id.base as? T }
        return nil
    }

    /// The content-space point the position names (see the type's notes on content space).
    public var point: CGPoint? {
        switch request {
        case let .point(p)?, let .xy(p)?: return p
        default: return nil
        }
    }

    /// The x value of a `scrollTo(x:)` / `scrollTo(x:y:)` request (SwiftUI's `x`, iOS 26).
    public var x: CGFloat? {
        switch request {
        case let .x(v)?: return v
        case let .xy(p)?: return p.x
        default: return nil
        }
    }

    /// The y value of a `scrollTo(y:)` / `scrollTo(x:y:)` request (SwiftUI's `y`, iOS 26).
    public var y: CGFloat? {
        switch request {
        case let .y(v)?: return v
        case let .xy(p)?: return p.y
        default: return nil
        }
    }

    public var edge: Edge? {
        if case let .edge(e)? = request { return e }
        return nil
    }

    public static func == (lhs: ZTronScrollPosition, rhs: ZTronScrollPosition) -> Bool {
        lhs.request == rhs.request && lhs.serial == rhs.serial && lhs.isPositionedByUser == rhs.isPositionedByUser
    }

    /// The `ZTronScrollPosition` after a user scroll (the driver's write-back): same serial as the value it answers.
    func positioned(by request: Request, serial: UInt64) -> ZTronScrollPosition {
        ZTronScrollPosition(request: request, serial: serial, isPositionedByUser: true)
    }
}
