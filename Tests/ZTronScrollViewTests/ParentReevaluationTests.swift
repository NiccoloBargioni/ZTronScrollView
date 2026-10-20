import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class TallModel: ObservableObject { @Published var tall = false }

/// A parent re-evaluation that resizes a sibling of the content (M6-s1 Open 3, Orchestration open item 6).
private struct SiblingResizeParent: View {
    @ObservedObject var model: TallModel
    let state: ZTronScrollState
    let counts: BodyCount
    var body: some View {
        ZTronScrollView(.vertical, state: state) {
            StatefulContent(counts: counts)
            Color.blue.frame(height: model.tall ? 200 : 100)
        }
    }
}

@MainActor
@Suite(.serialized)
struct ParentReevaluationTests {
    /// The content keeps one identity (one `@State`, one `onAppear`) across a parent re-evaluation, whether or not the
    /// re-evaluation runs inside the forced-fallback scope that built the view.
    @Test(arguments: OSPath.allCases) func siblingResizeKeepsContentIdentity(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let model = TallModel()
        let w = withOSPath(path) { host(SiblingResizeParent(model: model, state: s, counts: counts)) }
        #expect(counts.ids.count == 1 && counts.appears == 1)
        withOSPath(path) { model.tall = true; pump(0.15) }
        #expect(counts.ids.count == 1, "inside scope")
        #expect(counts.appears == 1, "inside scope")
        model.tall = false; pump(0.15)
        #expect(counts.ids.count == 1, "outside scope")
        #expect(counts.appears == 1, "outside scope")
        _ = w
    }
}
