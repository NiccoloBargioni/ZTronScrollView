import SwiftUI

/// One call recorded by ``ReferenceScrollArbiter/log``, for assertions in tests and spikes.
public enum ScrollArbitrationLogEntry: Sendable, Equatable {
    /// A ``ReferenceScrollArbiter/register(_:frame:)`` call and the token it returned.
    case register(ScrollArbitrationToken, frame: CGRect)
    /// An ``ReferenceScrollArbiter/update(_:frame:)`` call; `known == false` means it was ignored.
    case update(ScrollArbitrationToken, frame: CGRect, known: Bool)
    /// An ``ReferenceScrollArbiter/unregister(_:)`` call; `known == false` means the token was already unknown.
    case unregister(ScrollArbitrationToken, known: Bool)
    /// A ``ReferenceScrollArbiter/beginSequence()`` call. `started == false`: a sequence was already active
    /// (`id` is that sequence's) and the call did nothing.
    case beginSequence(id: Int, started: Bool)
    /// An ``ReferenceScrollArbiter/endSequence()`` call. `id == nil`, `ended == false`: no sequence was active.
    case endSequence(id: Int?, ended: Bool)
    /// An ownership question, from ``ReferenceScrollArbiter/owner(ofDragFrom:translation:touchCount:participant:)``
    /// (`askedBy: .participant`) or ``ReferenceScrollArbiter/containerOwner(ofDragFrom:translation:touchCount:)``
    /// (`askedBy: .container`, `caller` is the participant under `start` or a token no arbiter issues).
    ///
    /// `sequence` is the active sequence's id, `nil` when idle. `resolved` is the participant the swipe
    /// belongs to (`nil` when there is none). `decided` is `true` exactly on the call that ran
    /// ``ScrollArbitrationRules/decide(_:)``, and only then is `input` non-nil. `result` is what the caller got.
    case owner(caller: ScrollArbitrationToken, askedBy: ScrollOwner, start: CGPoint, translation: CGSize,
               touchCount: Int, sequence: Int?, resolved: ScrollArbitrationToken?,
               input: ScrollArbitrationInput?, decided: Bool, result: ScrollOwner)
}
