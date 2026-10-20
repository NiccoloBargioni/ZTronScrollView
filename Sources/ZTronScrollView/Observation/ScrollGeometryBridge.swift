import SwiftUI

// Conversions between ZTronScrollGeometry and SwiftUI's ScrollGeometry (SPEC S8-4, design M7 §2). Geometry only in M7
// session 1; the phase types follow in session 2. (Named apart from Targets/NativeBridges.swift: one module, one file name.)

@available(iOS 18, *)
extension ZTronScrollGeometry {
    /// A value geometry from SwiftUI's. Native has no zoom, so `zoomScale` is 1.
    public init(_ native: ScrollGeometry) {
        self.init(contentOffset: native.contentOffset, contentSize: native.contentSize, contentInsets: native.contentInsets,
                  containerSize: native.containerSize)
    }

    /// SwiftUI's geometry for these values (`zoomScale` is dropped: native has none).
    public var native: ScrollGeometry {
        ScrollGeometry(contentOffset: contentOffset, contentSize: contentSize, contentInsets: contentInsets,
                       containerSize: containerSize)
    }
}
