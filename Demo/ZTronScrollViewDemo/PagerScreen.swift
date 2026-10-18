import SwiftUI
import ScrollArbitration
import ZTronScrollView

/// M3-c stand-in container: a SwiftUI-driven horizontal pager (two pages) whose arbiter is a `ReferenceScrollArbiter`.
/// Page 0 holds a two-axis `ZTronScrollView` (the participant); page 1 is plain. The container asks the arbiter
/// for each swipe (`containerOwner`) and only pages when the answer is `.container`.
@MainActor
final class DemoPager: ObservableObject {
    let arbiter = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: "demo.pager")
    @Published var page = 0
    @Published var drag: CGFloat = 0
    private var ownsSwipe: Bool?

    func changed(_ v: DragGesture.Value) {
        arbiter.beginSequence()
        guard hypot(v.translation.width, v.translation.height) >= 10 else { return }
        if ownsSwipe == nil {
            ownsSwipe = arbiter.containerOwner(ofDragFrom: v.startLocation, translation: v.translation, touchCount: 1) == .container
        }
        if ownsSwipe == true { drag = v.translation.width }
    }

    func ended(_ v: DragGesture.Value, width: CGFloat) {
        if ownsSwipe == true {
            let dx = v.predictedEndTranslation.width
            if dx < -width / 3 || v.translation.width < -width / 3 { page = min(1, page + 1) }
            else if dx > width / 3 || v.translation.width > width / 3 { page = max(0, page - 1) }
        }
        withAnimation(.easeOut(duration: 0.2)) { drag = 0 }
        ownsSwipe = nil
        arbiter.endSequence()
        arbiter.clearLog()
    }
}

struct PagerScreen: View {
    @StateObject private var pager = DemoPager()
    @State private var state = ZTronScrollState()
    @State private var info = ""

    var body: some View {
        VStack(spacing: 6) {
            Button("Info") {
                info = "page=\(pager.page) x=\(Int(state.contentOffset.x)) y=\(Int(state.contentOffset.y))"
            }.accessibilityIdentifier("Info")
            Button("Reset") {
                state.stopScrollingAndZooming(); state.setContentOffset(.zero, animated: false)
                pager.page = 0
            }.accessibilityIdentifier("Reset")
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ZTronScrollView([.horizontal, .vertical], state: state) {
                        PagerContent()
                    }
                    .environment(\.scrollArbiter, pager.arbiter)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pager.scroller")
                    Color.orange.opacity(0.3).overlay(Text("Page 2"))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .offset(x: -CGFloat(pager.page) * geo.size.width + pager.drag)
                .coordinateSpace(name: pager.arbiter.coordinateSpaceName)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(pager.arbiter.coordinateSpaceName))
                        .onChanged { pager.changed($0) }
                        .onEnded { pager.ended($0, width: geo.size.width) })
            }
            .frame(height: 320)
            .border(Color.gray)
            Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
        }
        .padding(8)
    }
}

struct PagerContent: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue, .green, .yellow], startPoint: .leading, endPoint: .trailing)
            Text("Scroller 900x900")
        }
        .frame(width: 900, height: 900)
    }
}
