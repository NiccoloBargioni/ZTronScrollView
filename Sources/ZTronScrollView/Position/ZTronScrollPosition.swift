import SwiftUI

/// Mirrors `ScrollPosition` (iOS 18) for every OS this library supports (design M6 §2). A value you bind with
/// `scrollPosition(_:anchor:)`: set it (`scrollTo(id:)`, `scrollTo(edge:)`, `scrollTo(point:)` …) to scroll, read it to see
/// where the user is. Like SwiftUI's (PARITY-s1, measured on 18.6 / 26.5 / 27.0), while the user moves the view the scroll
/// view writes the view it is positioned at (`viewID`) each time that view changes, for views whose id has the position's id
/// type (`idType:`, or the type of the id you asked for); with no such views (`ZTronScrollPosition()` is `idType: Never`) it
/// writes once per gesture, naming nothing. A programmatic scroll writes nothing. `isPositionedByUser` is `true` on every
/// write-back (SwiftUI's stays `false` once it writes a view id: a documented native defect, PARITY-s1).
///
/// A point is in content space, like SwiftUI's: `scrollTo(point:)` puts it at the top-leading corner of the unobscured area
/// (the offset is the point minus the leading insets), and `scrollTo(x:)` / `scrollTo(y:)` do the same on one axis, leaving
/// `point` and `edge` `nil` (``x`` / ``y`` read them back, like SwiftUI's on iOS 26).
///
/// The view a user scroll reports is the registered target whose anchor point is nearest the anchor point of the unobscured
/// area (the modifier's anchor, top-leading by default): the row whose top is nearest the top edge, the row holding the center.
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
    /// The id type a user scroll reports; `nil` reports no view (SwiftUI's `idType: Never`). Not part of `==`.
    var idType: IDType?

    /// An id type, compared by identity. On iOS 18+ it also builds SwiftUI's position of that id type for the bridge (stored as
    /// `Any`, so nothing here needs an iOS 18 type before iOS 18).
    struct IDType: @unchecked Sendable {
        let identifier: ObjectIdentifier
        let native: Any?

        init<T: Hashable & Sendable>(_ type: T.Type) {
            identifier = ObjectIdentifier(type)
            if #available(iOS 18, *) { native = Self.nativeMaker(type) } else { native = nil }
        }

        init<T: Hashable>(nonSendable type: T.Type) {
            identifier = ObjectIdentifier(type)
            native = nil
        }

        /// `true` for an id of exactly this type (`Never` matches nothing).
        func matches(_ id: AnyHashable) -> Bool { ObjectIdentifier(Swift.type(of: id.base)) == identifier }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastSerial: UInt64 = 0
    private static func nextSerial() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        lastSerial += 1
        return lastSerial
    }

    /// No request: the view stays where it is. A user scroll reports views whose id is of `idType` (SwiftUI's shape).
    public init(idType: (some Hashable & Sendable).Type = Never.self) {
        request = nil
        serial = 0
        isPositionedByUser = false
        self.idType = Self.reported(idType)
    }

    public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        request = .id(AnyHashable(id), anchor)
        serial = Self.nextSerial()
        isPositionedByUser = false
        idType = IDType(nonSendable: ID.self)
    }

    /// SwiftUI's own shape (`some Hashable & Sendable`); chosen for every `Sendable` id, so the native bridge can pass it on.
    public init<ID: Hashable & Sendable>(id: ID, anchor: UnitPoint? = nil) {
        request = .id(AnyHashable(id), anchor)
        serial = Self.nextSerial()
        isPositionedByUser = false
        sendableID = id
        idType = IDType(ID.self)
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, point: CGPoint) { self.init(.point(point), idType) }
    public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) { self.init(.edge(edge), idType) }
    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat) { self.init(.x(x), idType) }
    public init(idType: (some Hashable & Sendable).Type = Never.self, y: CGFloat) { self.init(.y(y), idType) }
    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat, y: CGFloat) {
        self.init(.xy(CGPoint(x: x, y: y)), idType)
    }

    private init<T: Hashable & Sendable>(_ request: Request, _ idType: T.Type) {
        self.request = request
        serial = Self.nextSerial()
        isPositionedByUser = false
        self.idType = Self.reported(idType)
    }

    /// `Never` reports nothing: stored as `nil`.
    private static func reported<T: Hashable & Sendable>(_ type: T.Type) -> IDType? {
        type == Never.self ? nil : IDType(type)
    }

    /// Library-internal: a value with an explicit serial (a write-back keeps the serial it was answering; the `id` binding uses 0).
    init(request: Request?, serial: UInt64, isPositionedByUser: Bool, idType: IDType? = nil) {
        self.request = request
        self.serial = serial
        self.isPositionedByUser = isPositionedByUser
        self.idType = idType
    }

    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) { self = ZTronScrollPosition(id: id, anchor: anchor) }
    public mutating func scrollTo<ID: Hashable & Sendable>(id: ID, anchor: UnitPoint? = nil) {
        self = ZTronScrollPosition(id: id, anchor: anchor)
    }
    // The other requests keep the id type the position reports.
    public mutating func scrollTo(edge: Edge) { replace(.edge(edge)) }
    public mutating func scrollTo(point: CGPoint) { replace(.point(point)) }
    public mutating func scrollTo(x: CGFloat) { replace(.x(x)) }
    public mutating func scrollTo(y: CGFloat) { replace(.y(y)) }
    public mutating func scrollTo(x: CGFloat, y: CGFloat) { replace(.xy(CGPoint(x: x, y: y))) }

    private mutating func replace(_ new: Request) {
        request = new
        serial = Self.nextSerial()
        isPositionedByUser = false
        sendableID = nil
    }

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

    /// The value of a `scrollTo(x:)` request (SwiftUI's `x`, iOS 26: `nil` after `scrollTo(x:y:)`, which reads back as `point`).
    public var x: CGFloat? {
        if case let .x(v)? = request { return v }
        return nil
    }

    /// The value of a `scrollTo(y:)` request (SwiftUI's `y`, iOS 26: `nil` after `scrollTo(x:y:)`, which reads back as `point`).
    public var y: CGFloat? {
        if case let .y(v)? = request { return v }
        return nil
    }

    public var edge: Edge? {
        if case let .edge(e)? = request { return e }
        return nil
    }

    public static func == (lhs: ZTronScrollPosition, rhs: ZTronScrollPosition) -> Bool {
        lhs.request == rhs.request && lhs.serial == rhs.serial && lhs.isPositionedByUser == rhs.isPositionedByUser
    }

    /// The `ZTronScrollPosition` after a user scroll (the driver's write-back): same serial and id type as the value it answers.
    func positioned(by request: Request?, serial: UInt64) -> ZTronScrollPosition {
        ZTronScrollPosition(request: request, serial: serial, isPositionedByUser: true, idType: idType)
    }
}
