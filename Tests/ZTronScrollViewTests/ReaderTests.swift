import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class Counter { var runs = 0; var values: [String] = [] }

@MainActor
final class LabelModel: ObservableObject { @Published var label = "a" }

@MainActor
func host<V: View>(_ view: V) -> UIWindow {
    ScrollViewWindows.retireFinished()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    window.rootViewController = UIHostingController(rootView: view)
    window.makeKeyAndVisible()
    pump(0.1)
    ScrollViewWindows.keepIfScrolling(window)
    return window
}

@MainActor
@Suite(.serialized)
struct ReaderTests {
    @Test(arguments: OSPath.allCases) func firstFrameHasValue(path: OSPath) {
        let s = makeState(path)
        s.track(offset: CGPoint(x: 0, y: 50), zoom: 1)
        let c = Counter()
        let w = host(ZTronScrollReader(s, of: { $0.contentOffset.y }) { y in
            Color.clear.onAppear { c.values.append("\(y)") }
        })
        #expect(c.values.first == "50.0")
        _ = w
    }

    @Test(arguments: OSPath.allCases) func contentRunsOnlyWhenDerivedValueChanges(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = host(ZTronScrollReader(s, of: { $0.contentOffset.y > 100 }) { big -> Color in
            c.runs += 1
            return Color.clear
        })
        let base = c.runs
        for y in stride(from: 10.0, through: 90.0, by: 20) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.03) }
        #expect(c.runs == base)
        s.track(offset: CGPoint(x: 0, y: 150), zoom: 1); pump(0.1)
        #expect(c.runs == base + 1)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func zoomOnlyReaderIgnoresPan(path: OSPath) {
        let s = makeState(path)
        let c = Counter()
        let w = host(ZTronScrollReader(s, of: { $0.zoomScale }) { _ -> Color in
            c.runs += 1
            return Color.clear
        })
        let base = c.runs
        for y in stride(from: 10.0, through: 90.0, by: 20) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.03) }
        #expect(c.runs == base)
        s.track(offset: CGPoint(x: 0, y: 90), zoom: 2); pump(0.1)
        #expect(c.runs == base + 1)
        _ = w
    }

    @Test(arguments: OSPath.allCases) func notStaleWhenClosureCapturesChangedInput(path: OSPath) {
        struct Parent: View {
            let state: ZTronScrollState
            @ObservedObject var model: LabelModel
            let c: Counter
            var body: some View {
                ZTronScrollReader(state, of: { $0.zoomScale }) { z -> Color in
                    c.values.append("\(model.label)\(z)")
                    return Color.clear
                }
            }
        }
        let s = makeState(path)
        let model = LabelModel()
        let c = Counter()
        let w = host(Parent(state: s, model: model, c: c))
        model.label = "b"; pump(0.1)
        #expect(c.values.last == "b1.0")
        s.track(offset: .zero, zoom: 2); pump(0.1)
        #expect(c.values.last == "b2.0")
        _ = w
    }
}
