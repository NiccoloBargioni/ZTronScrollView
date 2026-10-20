import Foundation
import Testing
@testable import ZTronScrollView

/// Which side of every `#available` gate a test exercises.
///
/// Usage (suites that touch the switch are `.serialized`):
/// ```swift
/// @MainActor @Suite(.serialized) struct SomeSuite {
///     @Test(arguments: OSPath.allCases) func x(path: OSPath) async throws {
///         try await withOSPath(path) { … }
///     }
/// }
/// ```
/// A body without `await` resolves to the synchronous overload, which runs atomically on the main actor.
/// A body that awaits resolves to the async overload, which holds a process-wide gate across its suspension
/// points, so scopes from different (parallel) suites never interleave.
///
/// Rules (the forced set is process-wide state):
/// - Every suite that reads ``ZTronAvailability`` is `@MainActor` and reads it only inside `withOSPath`.
/// - Inside an async scope, do not run `withOSPath` (or switch reads) concurrently with the scope's own body: no
///   `async let` / task-group children or unstructured `Task {}` that enter scopes while the body runs. Sequential
///   nesting in the same task is fine. A sibling scope entered while another nested scope of the same parent is
///   active is reported as a test issue; a task that outlives its scope simply waits for the gate like any other.
enum OSPath: String, CaseIterable, Sendable, CustomStringConvertible {
    /// The running OS's preferred APIs: no fallback forced.
    case preferred
    /// Every gated capability force-fallbacked (DEBUG builds only; release builds cannot force).
    case forcedFallback

    var description: String { rawValue }

    /// The forced set this path installs.
    var forcedSet: Set<ZTronCapability> {
        switch self {
        case .preferred:
            return []
        case .forcedFallback:
            return ZTronAvailability.isForcingSupported ? RunningOS.gatedCapabilities : []
        }
    }
}

/// Runs `body` with the forced-fallback switch set for `path`, then restores the previous forced set
/// (nesting is balanced). Synchronous on the main actor, so no other main-actor code observes the switch meanwhile.
@MainActor
func withOSPath<T>(_ path: OSPath, _ body: () throws -> T) rethrows -> T {
    let previous = ZTronAvailability.forcedFallbacks
    OSPathSwitch.install(path.forcedSet)
    defer { OSPathSwitch.install(previous) }
    return try body()
}

/// Async variant: also holds a process-wide FIFO gate for the whole scope, so async scopes in parallel
/// suites never interleave their switch settings across suspension points. A call nested in a scope that is still
/// active (same task, or a child task inheriting the scope token) reuses the gate instead of deadlocking; a task that
/// outlives the scope that created it acquires the gate like a top-level call.
@MainActor
func withOSPath<T>(_ path: OSPath, _ body: @MainActor () async throws -> T) async rethrows -> T {
    let gate = OSPathGate.shared
    let parent = OSPathGate.currentScope.flatMap { gate.isActive($0) ? $0 : nil }
    if parent == nil { await gate.acquire() }
    let scope = gate.push(parent: parent)
    defer {
        gate.pop(scope)
        if parent == nil { gate.release() }
    }
    return try await OSPathGate.$currentScope.withValue(scope) {
        try await OSPathSwitch.scoped(path, body)
    }
}

/// Facts about the running OS, usable from `@Sendable` trait conditions.
enum RunningOS {
    static func isAtLeast(_ version: (major: Int, minor: Int)) -> Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: version.major, minorVersion: version.minor, patchVersion: 0)
        )
    }

    /// `true` when the running OS runs `capability`'s preferred API: from its `minimumOS` up and, for the one old-OS
    /// capability (`uikitTouchObserver`, iOS 15-16), below its `preferredOSCeiling`.
    static func shipsPreferred(_ capability: ZTronCapability) -> Bool {
        isAtLeast(capability.minimumOS) && !(capability.preferredOSCeiling.map(isAtLeast) ?? false)
    }

    /// `true` when the running OS is at or above every capability's `minimumOS` (iOS 27+ today); capabilities whose
    /// preferred path is the old-OS one still need ``shipsPreferred(_:)``.
    static var shipsEveryCapability: Bool {
        ZTronCapability.allCases.allSatisfy { isAtLeast($0.minimumOS) }
    }

    static var gatedCapabilities: Set<ZTronCapability> {
        Set(ZTronCapability.allCases.filter(\.isGated))
    }
}

@MainActor
private enum OSPathSwitch {
    /// One locked write: no reader ever sees a partially installed set.
    static func install(_ forced: Set<ZTronCapability>) {
        ZTronAvailability.replaceForcedFallbacks(with: forced)
    }

    static func scoped<T>(_ path: OSPath, _ body: @MainActor () async throws -> T) async rethrows -> T {
        let previous = ZTronAvailability.forcedFallbacks
        install(path.forcedSet)
        defer { install(previous) }
        return try await body()
    }
}

/// FIFO async mutex on the main actor guarding the process-wide switch for async `withOSPath` scopes, plus the stack
/// of active scope tokens that tells a nested call from an unrelated or outlived one.
@MainActor
private final class OSPathGate {
    static let shared = OSPathGate()

    /// Token of the innermost async scope around the current task (inherited by child tasks).
    @TaskLocal static var currentScope: UInt64? = nil

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var nextToken: UInt64 = 0
    /// Active scopes, outermost first; non-empty exactly while a top-level scope holds the gate.
    private var active: [UInt64] = []

    func isActive(_ token: UInt64) -> Bool { active.contains(token) }

    /// Registers a scope. A nested scope must sit directly on its parent: otherwise a sibling scope of the same parent
    /// is running concurrently and the two would interleave their forced sets.
    func push(parent: UInt64?) -> UInt64 {
        if let parent, active.last != parent {
            Issue.record("withOSPath: concurrent scopes inside one scope interleave the forced-fallback set")
        }
        nextToken += 1
        active.append(nextToken)
        return nextToken
    }

    func pop(_ token: UInt64) {
        active.removeAll { $0 == token }
    }

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        // Ownership is handed over directly by `release()`.
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
