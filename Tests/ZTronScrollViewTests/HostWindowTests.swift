import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// DBG-s9: on iOS 26+ test windows that hold a `UIScrollView` stay allocated for the whole run (``ScrollViewWindows``).
/// Without that, the 25 native windows below print "Observation tracking feedback loop detected" from the 21st on (2
/// counted invalidations each at one reused address, threshold 40), and `scripts/run-filtered.sh` fails the run on it.
@MainActor
@Suite(.serialized, .enabled(if: ScrollViewWindows.isNeeded))
struct HostWindowTests {
    @Test func aWindowHoldingAScrollViewIsKeptAndRetiredWithItsScrollView() throws {
        let native = host(ScrollView { Color.red.frame(width: 100, height: 400) })
        let plain = host(Color.clear)
        let scrollView = try #require(firstScrollView(in: native))
        #expect(ScrollViewWindows.isKept(native) && ScrollViewWindows.isKept(scrollView))
        #expect(!ScrollViewWindows.isKept(plain))
        #expect(!native.isHidden && native.rootViewController != nil, "a later host() of the same test keeps it live")
        unhost(native)
        unhost(plain)
        #expect(native.isHidden && native.rootViewController == nil)
        #expect(plain.isHidden && plain.rootViewController == nil)
    }

    @Test func anotherTestsHostRetiresTheWindow() {
        let native = host(ScrollView { Color.red.frame(width: 100, height: 400) })
        ScrollViewWindows.retireFinished()
        #expect(!native.isHidden, "the running test's window stays live")
        ScrollViewWindows.retireFinished(running: nil)    // what host() does when another test runs
        #expect(native.isHidden && native.rootViewController == nil && ScrollViewWindows.isKept(native))
    }

    /// Each window is released before the next one is created, so a freed window's address would be the next one's.
    @Test func nativeScrollViewWindowsNeverShareAnAddress() {
        var addresses = Set<UInt>()
        for i in 0..<25 {
            autoreleasepool {
                let w = host(ScrollView { Color.red.frame(width: 100, height: 400) })
                addresses.insert(UInt(bitPattern: Unmanaged.passUnretained(w).toOpaque()))
                if !i.isMultiple(of: 2) { unhost(w) }
            }
            pump(0.02)
        }
        #expect(addresses.count == 25)
        for _ in 0..<3 {
            autoreleasepool { unhost(host(Color.clear)) }
            pump(0.02)
        }
    }
}
