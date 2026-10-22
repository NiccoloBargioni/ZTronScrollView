import SwiftUI
import ZTronScrollView

/// `-ZTronScreen mixed` (DBG-s5, DBG-s8): `ZTronScrollView`s inside a vertical page between bands: a horizontal carousel and a vertical list. The page is
/// SwiftUI's own `ScrollView` (docs/design/NESTED-arbitration.md §6 row B), or with `-ZTronMixedPage ztron` a vertical `ZTronScrollView` (the supported
/// nesting: the library's arbiter decides). `Info` prints the inner offsets (`cx` carousel x, `ly` list y, `py` the ZTron page's y); how far a native page
/// scrolled is read from the carousel's accessibility frame by `MixedTopologyUITests`.
struct MixedTopologyScreen: View {
    static var ztronPage: Bool {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-ZTronMixedPage"), i + 1 < a.count else { return false }
        return a[i + 1] == "ztron"
    }

    @State private var carousel = ZTronScrollState()
    @State private var list = ZTronScrollState()
    @State private var page = ZTronScrollState()
    @State private var info = ""

    var body: some View {
        VStack(spacing: 4) {
            Button("Info") {
                info = "cx=\(Int(carousel.contentOffset.x.rounded())) ly=\(Int(list.contentOffset.y.rounded())) py=\(Int(page.contentOffset.y.rounded()))"
            }
            .accessibilityIdentifier("Info")
            Text(info).font(.caption2).accessibilityIdentifier("mixedInfo").accessibilityValue(info)
            Group {
                if Self.ztronPage {
                    ZTronScrollView(.vertical, state: page) { pageContent }
                } else {
                    ScrollView(.vertical) { pageContent }
                }
            }
            .border(Color.gray)
        }
        .padding(8)
    }

    private var pageContent: some View {
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
}
