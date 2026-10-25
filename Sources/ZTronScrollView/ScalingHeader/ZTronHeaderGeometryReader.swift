import SwiftUI

/// The only way a header child reads the live geometry (SPEC S10 "The reactive-geometry pattern", design M8b §2.5): a
/// derived reader of the S4 tier table over `ZTronScrollGeometry.header`, on the same engine as ``ZTronScrollReader``
/// (tracked reads on 17+, channel subscription on 15–16). `content` re-renders only when `transform(geometry)` changes
/// (every frame for the identity form, at most `steps + 1` times per full collapse for `quantizedProgress(steps:)`); the
/// header around it and the scroll view's content never do.
///
/// ```swift
/// struct BannerTitle: View {
///     let header: ZTronHeaderProxy
///     var body: some View {
///         ZTronHeaderGeometryReader(header, of: \.height) { h in Text("Title").font(.system(size: 17 + 0.1 * h)) }
///     }
/// }
/// ```
/// Without a proxy it reads the nearest enclosing `ZTronScrollView`'s header. It reports the geometry on screen (the
/// presentation offset), frame by frame; nothing is drawn while the scroll view has no header.
public struct ZTronHeaderGeometryReader<Value: Equatable, Content: View>: View {
    private let header: ZTronHeaderProxy?
    private let transform: (ZTronHeaderGeometry) -> Value
    private let content: (Value) -> Content

    public init(_ header: ZTronHeaderProxy? = nil, of transform: @escaping (ZTronHeaderGeometry) -> Value,
                @ViewBuilder content: @escaping (Value) -> Content) {
        self.header = header
        self.transform = transform
        self.content = content
    }

    public init(_ header: ZTronHeaderProxy? = nil, @ViewBuilder content: @escaping (ZTronHeaderGeometry) -> Content)
        where Value == ZTronHeaderGeometry {
        self.header = header
        self.transform = { $0 }
        self.content = content
    }

    public var body: some View {
        let transform = transform, content = content
        return ZTronScrollReader(header?.state, of: { $0.header.map(transform) }) { value in
            if let value { content(value) }
        }
    }
}
