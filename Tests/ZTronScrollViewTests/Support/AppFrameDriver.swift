import SwiftUI
import UIKit
@testable import ZTronScrollView

/// The hosted rig's stand-in for the app's update cycle (open item 34, M8b-s8 s2).
///
/// In this app-less test process (`UIApplication.shared` is nil) SwiftUI draws an animation's frames off the main thread
/// (its asynchronous renderer) as long as nothing in the animated subtree needs the main thread; when something does, it
/// asks for a main-thread pass that only the app's update cycle provides, and the animation stops after the frame it
/// drew. An animated insertion (a `ForEach` growing in `withAnimation`, its rows fading in) stops after one frame in plain
/// SwiftUI here (27.0 and 17.5), and so does any animation under a `geometryGroup()` on 27.0, which the library puts above
/// the content and the header (`ContentLayerGroup`, `HeaderLayerGroup`). The app draws every frame (seam lab `rows`, three
/// lanes). A native `ScrollView` ticks here: its content lives in a `UIScrollView`, whose layout passes run on the main
/// thread. Measured in the rig: a per-frame `setNeedsLayout()` of the hosting view un-stalls it too (`layoutIfNeeded`,
/// `setNeedsDisplay`, `updateProperties` or a `CATransaction` flush alone do not).
///
/// A running `TimelineView(.animation)` beside the hosted view (outside the library, so no library body or layout is
/// involved) updates the graph on the main thread every display frame, so every frame of every animation is drawn there,
/// as the app draws it. Hosted tests that count an animation's drawn frames (the ≥ 20 frames in 0.5 s gates) host through
/// `hostDriven`; tests of the asynchronous path itself pass `driven: false`.
struct AppFrameDriver<Content: View>: View {
    let content: Content

    var body: some View {
        content.background(TimelineView(.animation) { ctx in
            Color.clear.frame(width: 0, height: 0).onChangeCompat(of: ctx.date) { _ in }
        })
    }
}

/// A window of `size` (default a 402 x 874 pt phone, the size it is created with) hosting `view`, beside an
/// `AppFrameDriver` when `driven`.
@MainActor
func hostDriven<V: View>(_ view: V, driven: Bool = true, size: CGSize = CGSize(width: 402, height: 874)) -> UIWindow {
    ScrollViewWindows.retireFinished()
    let w = UIWindow(frame: CGRect(origin: .zero, size: size))
    w.rootViewController = driven ? UIHostingController(rootView: AnyView(AppFrameDriver(content: view)))
        : UIHostingController(rootView: AnyView(view))
    w.makeKeyAndVisible()
    pump(0.6)
    ScrollViewWindows.keepIfScrolling(w)
    return w
}
