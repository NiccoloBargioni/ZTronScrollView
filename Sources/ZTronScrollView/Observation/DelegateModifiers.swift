import SwiftUI

// Delegate callbacks as modifiers (SPEC S11 amendment 2026-10-19, design M8-chrome §7b, task M8-8). Every
// `UIScrollViewDelegate` method has an `onZTronScroll…` modifier as an alternative to the delegate object: a member of
// `ZTronScrollView` returning `Self` (binds to that view) and a same-name `View` twin carried by the environment (binds to
// every `ZTronScrollView` below it, nesting included). Both write a recipe the container turns into a `DelegateObserverBox`
// on the state's `ObserverHub` (appended, never replaced; closures re-assigned on every body of their owner, so never stale).
// The boxes are cold: a callback causes no view update. `viewForZooming` has no modifier (replaced by `zoomRange`).

// MARK: Call sites: the delegate first, then the modifiers in registration order (environment twins outermost first,
// then the members). One code path on every OS; the cadence and the order of the delegate are unchanged.

extension ZTronScrollState {
    func notifyDidScroll() { delegate?.scrollViewDidScroll(self); observers.didScroll(self) }
    func notifyDidZoom() { delegate?.scrollViewDidZoom(self); observers.didZoom(self) }
    func notifyWillBeginDragging() { delegate?.scrollViewWillBeginDragging(self); observers.willBeginDragging(self) }
    func notifyWillBeginDecelerating() { delegate?.scrollViewWillBeginDecelerating(self); observers.willBeginDecelerating(self) }
    func notifyDidEndDecelerating() { delegate?.scrollViewDidEndDecelerating(self); observers.didEndDecelerating(self) }
    func notifyDidEndScrollingAnimation() {
        delegate?.scrollViewDidEndScrollingAnimation(self)
        observers.didEndScrollingAnimation(self)
    }
    func notifyWillBeginZooming() { delegate?.scrollViewWillBeginZooming(self); observers.willBeginZooming(self) }
    func notifyDidScrollToTop() { delegate?.scrollViewDidScrollToTop(self); observers.didScrollToTop(self) }
    func notifyDidChangeAdjustedContentInset() {
        delegate?.scrollViewDidChangeAdjustedContentInset(self)
        observers.didChangeAdjustedContentInset(self)
    }
    func notifyDidEndDragging(willDecelerate: Bool) {
        delegate?.scrollViewDidEndDragging(self, willDecelerate: willDecelerate)
        observers.didEndDragging(self, willDecelerate: willDecelerate)
    }
    func notifyDidEndZooming(atScale scale: CGFloat) {
        delegate?.scrollViewDidEndZooming(self, atScale: scale)
        observers.didEndZooming(self, atScale: scale)
    }
    /// `velocity` in pt/ms; `target` threads through the delegate and then each modifier: the last value is the landing.
    func notifyWillEndDragging(velocity: CGPoint, target: inout CGPoint) {
        delegate?.scrollViewWillEndDragging(self, withVelocity: velocity, targetContentOffset: &target)
        observers.willEndDragging(self, velocity: velocity, target: &target)
    }
    /// The conjunction of the delegate's answer and every predicate's (any veto wins).
    func notifyShouldScrollToTop() -> Bool {
        let delegateAnswer = delegate?.scrollViewShouldScrollToTop(self) ?? true
        let predicates = observers.shouldScrollToTop(self)
        return delegateAnswer && predicates
    }
}

// MARK: Members

extension ZTronScrollView {
    fileprivate func appendingDelegate(_ kind: DelegateObserverBox.Kind, _ handler: DelegateObserverBox.Handler) -> Self {
        var copy = self
        copy.config.observers.append(.delegate(key: "member.\(config.observers.count)", kind: kind, handler: handler))
        return copy
    }

    /// `scrollViewDidScroll`: every offset change (zoom, programmatic, transaction-driven and refresh motion included), at most once per frame. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidScroll(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.didScroll, .plain(action))
    }

    /// `scrollViewDidZoom`: every scale change, at most once per frame. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidZoom(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.didZoom, .plain(action))
    }

    /// `scrollViewWillBeginDragging`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollWillBeginDragging(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.willBeginDragging, .plain(action))
    }

    /// `scrollViewWillBeginDecelerating`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollWillBeginDecelerating(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.willBeginDecelerating, .plain(action))
    }

    /// `scrollViewDidEndDecelerating`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidEndDecelerating(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.didEndDecelerating, .plain(action))
    }

    /// `scrollViewDidEndScrollingAnimation`: a programmatic animation finished. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidEndScrollingAnimation(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.didEndScrollingAnimation, .plain(action))
    }

    /// `scrollViewWillBeginZooming` (no zoom view). Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollWillBeginZooming(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.willBeginZooming, .plain(action))
    }

    /// `scrollViewDidScrollToTop`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidScrollToTop(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.didScrollToTop, .plain(action))
    }

    /// `scrollViewDidChangeAdjustedContentInset`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidChangeAdjustedContentInset(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> Self {
        appendingDelegate(.didChangeAdjustedContentInset, .plain(action))
    }

    /// `scrollViewWillEndDragging(_:withVelocity:targetContentOffset:)`: `velocity` in pt/ms, `targetContentOffset` threaded through the delegate and each modifier (the last value is the landing). Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollWillEndDragging(_ action: @MainActor @escaping (ZTronScrollState, _ velocity: CGPoint, _ targetContentOffset: inout CGPoint) -> Void) -> Self {
        appendingDelegate(.willEndDragging, .willEndDragging(action))
    }

    /// `scrollViewDidEndDragging(_:willDecelerate:)`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidEndDragging(_ action: @MainActor @escaping (ZTronScrollState, _ willDecelerate: Bool) -> Void) -> Self {
        appendingDelegate(.didEndDragging, .didEndDragging(action))
    }

    /// `scrollViewDidEndZooming(_:with:atScale:)`. Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollDidEndZooming(_ action: @MainActor @escaping (ZTronScrollState, _ scale: CGFloat) -> Void) -> Self {
        appendingDelegate(.didEndZooming, .didEndZooming(action))
    }

    /// `scrollViewShouldScrollToTop`: the answer is the conjunction of the delegate's and every predicate's (any veto wins). Fires after the delegate; appends (several modifiers all fire).
    public func onZTronScrollShouldScrollToTop(_ predicate: @MainActor @escaping (ZTronScrollState) -> Bool) -> Self {
        appendingDelegate(.shouldScrollToTop, .shouldScrollToTop(predicate))
    }
}

// MARK: Twins

extension View {

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidScroll(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidScroll(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didScroll, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidZoom(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidZoom(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didZoom, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollWillBeginDragging(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollWillBeginDragging(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .willBeginDragging, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollWillBeginDecelerating(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollWillBeginDecelerating(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .willBeginDecelerating, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidEndDecelerating(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidEndDecelerating(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didEndDecelerating, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidEndScrollingAnimation(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidEndScrollingAnimation(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didEndScrollingAnimation, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollWillBeginZooming(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollWillBeginZooming(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .willBeginZooming, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidScrollToTop(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidScrollToTop(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didScrollToTop, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidChangeAdjustedContentInset(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidChangeAdjustedContentInset(_ action: @MainActor @escaping (ZTronScrollState) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didChangeAdjustedContentInset, handler: .plain(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollWillEndDragging(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollWillEndDragging(_ action: @MainActor @escaping (ZTronScrollState, _ velocity: CGPoint, _ targetContentOffset: inout CGPoint) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .willEndDragging, handler: .willEndDragging(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidEndDragging(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidEndDragging(_ action: @MainActor @escaping (ZTronScrollState, _ willDecelerate: Bool) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didEndDragging, handler: .didEndDragging(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollDidEndZooming(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollDidEndZooming(_ action: @MainActor @escaping (ZTronScrollState, _ scale: CGFloat) -> Void) -> some View {
        modifier(DelegateObserverModifier(kind: .didEndZooming, handler: .didEndZooming(action)))
    }

    /// Environment twin of ``ZTronScrollView/onZTronScrollShouldScrollToTop(_:)``: binds to every `ZTronScrollView` below.
    public func onZTronScrollShouldScrollToTop(_ predicate: @MainActor @escaping (ZTronScrollState) -> Bool) -> some View {
        modifier(DelegateObserverModifier(kind: .shouldScrollToTop, handler: .shouldScrollToTop(predicate)))
    }
}

/// The twin's recipe goes down the environment (appended, so the outermost twin is registered first).
struct DelegateObserverModifier: ViewModifier {
    let kind: DelegateObserverBox.Kind
    let handler: DelegateObserverBox.Handler
    @State private var key = ObserverKey()

    func body(content: Content) -> some View {
        let descriptor = ObserverDescriptor.delegate(key: key, kind: kind, handler: handler)
        return content.transformEnvironment(\.ztronScrollConfig) { $0.observers.append(descriptor) }
    }
}
