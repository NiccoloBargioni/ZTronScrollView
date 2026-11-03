import SwiftUI
import ZTronScrollView

/// `-ZTronScreen mixed` (DBG-s5): `ZTronScrollView`s inside SwiftUI's own vertical `ScrollView` (docs/design/NESTED-arbitration.md
/// §6 row B): a horizontal carousel and a vertical list between native bands. `Info` prints the two inner offsets; how far the
/// page itself scrolled is read from the carousel's accessibility frame by `MixedTopologyUITests`.
struct MixedTopologyScreen: View {
    @State private var carousel = ZTronScrollState()
    @State private var list = ZTronScrollState()
    @State private var info = ""

    var body: some View {
        VStack(spacing: 4) {
            Button("Info") {
                info = "cx=\(Int(carousel.contentOffset.x.rounded())) ly=\(Int(list.contentOffset.y.rounded()))"
            }
            .accessibilityIdentifier("Info")
            Text(info).font(.caption2).accessibilityIdentifier("mixedInfo").accessibilityValue(info)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Color.red.frame(height: 120)
                    ZTronScrollView(.horizontal, state: carousel) {
                        HStack(spacing: 8) {
                            ForEach(0..<20, id: \.self) { i in
                                Text("Card \(i)").frame(width: 120, height: 100).background(Color.blue.opacity(0.3))
                            }
                        }
                    }
                    .frame(height: 100)
                    .accessibilityIdentifier("mixed.carousel")
                    Color.green.frame(height: 120)
                    ZTronScrollView(.vertical, state: list) {
                        VStack(spacing: 0) {
                            ForEach(0..<40, id: \.self) { Text("Row \($0)").frame(maxWidth: .infinity).padding(.vertical, 10) }
                        }
                    }
                    .frame(height: 220)
                    .accessibilityIdentifier("mixed.list")
                    Color.orange.frame(height: 900)
                }
            }
            .border(Color.gray)
        }
        .padding(8)
    }
}
