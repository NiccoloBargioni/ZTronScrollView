import SwiftUI
import ZTronScrollView

@MainActor
final class ImageProbe: ZTronScrollViewDelegate {
    var minY: CGFloat = 0
    func scrollViewDidScroll(_ state: ZTronScrollState) { minY = min(minY, state.contentOffset.y) }
}

/// The user's real-app usage (vertical scroll view, resizable fit image) plus a zoom range. The readouts live outside
/// the scroller and read the state, so the scroller uses the `state:` initializer; `-ZTronImageStateless` runs the
/// exact stateless snippet with the readout inside the content instead.
struct ImageScreen: View {
    static let viewport = CGSize(width: 300, height: 360)
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var probe = ImageProbe()
    private static var stateless: Bool { ProcessInfo.processInfo.arguments.contains("-ZTronImageStateless") }

    var body: some View {
        VStack(spacing: 6) {
            Button("Snapshot") { takeSnapshot() }.accessibilityIdentifier("Snapshot")
            if Self.stateless {
                ZTronScrollView(.vertical, showsIndicators: false) {
                    Image("app.global.about.us.snapshot")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .topLeading) {
                            ZTronScrollReader(of: { (g: ZTronScrollGeometry) -> CGFloat in g.zoomScale }) { (z: CGFloat) in
                                Text(String(format: "zoom %.2f", z)).font(.caption2)
                                    .accessibilityIdentifier("zoomReadout").accessibilityValue(String(format: "%.3f", z))
                            }
                        }
                }
                .zoomRange(min: .absolute(1), max: .absolute(4))
                .frame(width: Self.viewport.width, height: Self.viewport.height)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
            } else {
                ZTronScrollView(.vertical, state: state) {
                    ImageContent(fits: ProcessInfo.processInfo.arguments.contains("-ZTronImageFits"))
                }
                .zoomRange(min: .absolute(1), max: .absolute(4))
                .frame(width: Self.viewport.width, height: Self.viewport.height)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
                ZTronScrollReader(state, of: { (g: ZTronScrollGeometry) -> CGFloat in g.zoomScale }) { (z: CGFloat) in
                    Text(String(format: "zoom %.2f", z)).accessibilityIdentifier("zoomReadout")
                        .accessibilityValue(String(format: "%.3f", z))
                }
                Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
                CounterRow(key: "content.body", value: counter)
            }
        }
        .padding(8)
        .onAppear { state.delegate = probe }
    }

    @State private var counter = 0

    private func takeSnapshot() {
        #if DEBUG
        counter = ZTronRenderCounters.snapshot["content.body"] ?? 0
        #endif
        let o = state.contentOffset
        info = String(format: "z=%.4f ox=%.2f oy=%.2f miny=%.2f", state.zoomScale, o.x, o.y, probe.minY)
    }
}

/// Same content as the user's snippet, with a body counter.
/// `fits` (flag `-ZTronImageFits`) narrows the image to 100 pt so it is smaller than the viewport.
struct ImageContent: View {
    let fits: Bool
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Image("app.global.about.us.snapshot")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: fits ? 100 : .infinity)
    }
}
