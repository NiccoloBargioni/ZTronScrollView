import Foundation
import Testing
@testable import ZTronScrollView

/// Availability scaffolding (SPEC S3, docs/design/M1-physics.md §6-7).
/// Touches the process-wide force-fallback switch, hence `.serialized` and every check inside `withOSPath`.
@MainActor
@Suite(.serialized)
struct AvailabilityTests {
    // MARK: - Table

    /// `minimumOS` against the design-note matrix (a hand-copied table: the SDK itself is checked by hand, see
    /// docs/design/M1-physics.md §6).
    @Test func minimumOSMatchesDesignMatrix() {
        let expected: [ZTronCapability: (major: Int, minor: Int)] = [
            .perPropertyObservation: (17, 0), .layoutProtocol: (16, 0), .geometryChange: (16, 0),
            .visualEffect: (17, 0), .spatialEvents: (18, 0), .magnifyGesture: (17, 0),
            .liveMagnifyCentroid: (18, 0), .gestureInputKinds: (27, 0), .nativeCurves: (17, 0),
            .animationCompletion: (17, 0), .keyPathTransaction: (17, 0), .keyboardScrolling: (17, 0),
            .accessibilityZoom: (16, 0), .sensoryFeedback: (17, 0), .namedCoordinateSpace: (17, 0),
            .subviewContainers: (18, 0), .scrollBounceBehaviorType: (16, 4), .frameClock: (15, 0),
        ]
        #expect(Set(expected.keys) == Set(ZTronCapability.allCases))
        for capability in ZTronCapability.allCases {
            guard let want = expected[capability] else { continue }
            #expect(capability.minimumOS == want, "\(capability)")
        }
    }

    /// The literal `#available` branches and the declared `minimumOS` agree **on the running OS** (and the API is
    /// compiled in). This only discriminates boundaries at or below the running OS: run it on the 17.5, 18.x, 26.x
    /// and 27.0 simulators; the 16.0/16.4 rows cannot be discriminated on this host.
    @Test(arguments: OSPath.allCases)
    func osSupportsAgreesWithMinimumOS(path: OSPath) {
        withOSPath(path) {
            for capability in ZTronCapability.allCases {
                // The literal `#available` branch and the declared minimum agree on the running OS ...
                #expect(
                    ZTronAvailability.osSupports(capability)
                        == (RunningOS.isAtLeast(capability.minimumOS) && capability.isInBuildSDK),
                    "\(capability)"
                )
                // ... and the resolver is exactly "OS ships it and not forced".
                #expect(ZTronAvailability.isAvailable(capability) == expectedAvailability(capability, path: path),
                        "\(capability)")
            }
        }
    }

    @Test(.enabled(if: RunningOS.shipsEveryCapability, "needs an OS that ships every preferred API (iOS 27+)"))
    func everyCapabilityResolvesPreferredOnNewestOS() {
        withOSPath(.preferred) {
            #expect(ZTronAvailability.forcedFallbacks.isEmpty)
            for capability in ZTronCapability.allCases {
                #expect(ZTronAvailability.osSupports(capability), "\(capability)")
                #expect(ZTronAvailability.isAvailable(capability), "\(capability)")
            }
        }
    }

    @Test func forcedFallbackPathDisablesEveryGatedCapability() {
        withOSPath(.forcedFallback) {
            for capability in ZTronCapability.allCases {
                let available = ZTronAvailability.isAvailable(capability)
                if capability.isGated && ZTronAvailability.isForcingSupported {
                    #expect(!available, "\(capability)")
                } else {
                    #expect(available == ZTronAvailability.osSupports(capability), "\(capability)")
                }
            }
        }
    }

    // MARK: - Switch

    /// On the preferred path forcing one capability turns exactly it off; on the forced path clearing one
    /// turns exactly it back on (when the OS ships it). Every other capability keeps its value.
    @Test(arguments: OSPath.allCases, ZTronCapability.allCases.filter(\.isGated))
    func forcedFallbackDisablesCapability(path: OSPath, capability: ZTronCapability) {
        withOSPath(path) {
            let baseline = snapshot()
            let baselineForced = ZTronAvailability.forcedFallbacks
            let force = path == .preferred

            ZTronAvailability.forceFallback(capability, force)
            let after = snapshot()

            let forcedNow = ZTronAvailability.isForcingSupported ? force : false
            #expect(after[capability] == (ZTronAvailability.osSupports(capability) && !forcedNow))
            for other in ZTronCapability.allCases where other != capability {
                #expect(after[other] == baseline[other], "\(other) changed when toggling \(capability)")
            }
            if ZTronAvailability.isForcingSupported, RunningOS.shipsEveryCapability {
                #expect(after[capability] != baseline[capability], "\(capability) did not flip")
            }
            var expectedForced = baselineForced
            if forcedNow { expectedForced.insert(capability) } else { expectedForced.remove(capability) }
            #expect(ZTronAvailability.forcedFallbacks == expectedForced)

            ZTronAvailability.forceFallback(capability, !force)
            #expect(snapshot() == baseline)
            #expect(ZTronAvailability.forcedFallbacks == baselineForced)
        }
    }

    @Test func forceAllThenClearRestoresPreferred() {
        withOSPath(.preferred) {
            ZTronAvailability.forceAllFallbacks(true)
            #expect(ZTronAvailability.forcedFallbacks == OSPath.forcedFallback.forcedSet)

            ZTronAvailability.forceAllFallbacks(false)
            #expect(ZTronAvailability.forcedFallbacks.isEmpty)
            for capability in ZTronCapability.allCases {
                #expect(ZTronAvailability.isAvailable(capability) == ZTronAvailability.osSupports(capability),
                        "\(capability)")
            }
        }
    }

    @Test(arguments: OSPath.allCases)
    func frameClockIsNeverFallbacked(path: OSPath) {
        withOSPath(path) {
            #expect(!ZTronCapability.frameClock.isGated)
            ZTronAvailability.forceFallback(.frameClock, true)
            ZTronAvailability.forceAllFallbacks(true)
            #expect(!ZTronAvailability.forcedFallbacks.contains(.frameClock))
            #expect(ZTronAvailability.isAvailable(.frameClock))
        }
    }

    /// Only APIs newer than the Xcode 26 SDK can be compiled out; with this toolchain everything is compiled in.
    @Test func onlySDK27CapabilitiesCanBeCompiledOut() {
        for capability in ZTronCapability.allCases where capability != .gestureInputKinds {
            #expect(capability.isInBuildSDK, "\(capability)")
        }
        #if compiler(>=6.4)
        #expect(ZTronCapability.gestureInputKinds.isInBuildSDK)
        #else
        #expect(!ZTronCapability.gestureInputKinds.isInBuildSDK)
        #expect(!ZTronAvailability.isAvailable(.gestureInputKinds))
        #endif
    }

    /// The test helper installs a whole set in one locked write; ungated capabilities are dropped.
    @Test func replaceForcedFallbacksSwapsTheWholeSet() {
        withOSPath(.preferred) {
            let some: Set<ZTronCapability> = [.visualEffect, .spatialEvents]
            ZTronAvailability.replaceForcedFallbacks(with: some.union([.frameClock]))
            #expect(ZTronAvailability.forcedFallbacks == (ZTronAvailability.isForcingSupported ? some : []))
            ZTronAvailability.replaceForcedFallbacks(with: [.layoutProtocol])
            #expect(ZTronAvailability.forcedFallbacks == (ZTronAvailability.isForcingSupported ? [.layoutProtocol] : []))
            ZTronAvailability.replaceForcedFallbacks(with: [])
            #expect(ZTronAvailability.forcedFallbacks.isEmpty)
        }
    }

    @Test func capabilitiesWithoutFallbackReportIt() {
        let withoutFallback = Set(ZTronCapability.allCases.filter { !$0.hasFallback })
        #expect(withoutFallback == [.frameClock, .gestureInputKinds])
        // Every capability but the frame clock is gated, so the switch can exercise its absence or fallback.
        #expect(RunningOS.gatedCapabilities == Set(ZTronCapability.allCases).subtracting([.frameClock]))
    }

    /// DEBUG builds can force; release builds cannot (the switch functions are inert no-ops).
    /// Run the suite with `-configuration Release ENABLE_TESTABILITY=YES` to exercise the release branch.
    @Test func forcingIsDebugOnly() {
        withOSPath(.preferred) {
            #if DEBUG
            #expect(ZTronAvailability.isForcingSupported)
            ZTronAvailability.forceFallback(.visualEffect, true)
            #expect(ZTronAvailability.forcedFallbacks == [.visualEffect])
            #expect(!ZTronAvailability.isAvailable(.visualEffect))
            #else
            #expect(!ZTronAvailability.isForcingSupported)
            ZTronAvailability.forceAllFallbacks(true)
            ZTronAvailability.forceFallback(.visualEffect, true)
            #expect(ZTronAvailability.forcedFallbacks.isEmpty)
            for capability in ZTronCapability.allCases {
                #expect(ZTronAvailability.isAvailable(capability) == ZTronAvailability.osSupports(capability),
                        "\(capability)")
            }
            #endif
        }
    }

    // MARK: - OSPath helper

    @Test func osPathHelperIsBalanced() {
        let before = ZTronAvailability.forcedFallbacks
        let outer: Set<ZTronCapability> = ZTronAvailability.isForcingSupported ? [.spatialEvents] : []
        withOSPath(.preferred) {
            ZTronAvailability.forceFallback(.spatialEvents, true)
            #expect(ZTronAvailability.forcedFallbacks == outer)

            withOSPath(.forcedFallback) {
                #expect(ZTronAvailability.forcedFallbacks == OSPath.forcedFallback.forcedSet)
                withOSPath(.preferred) {
                    #expect(ZTronAvailability.forcedFallbacks.isEmpty)
                }
                #expect(ZTronAvailability.forcedFallbacks == OSPath.forcedFallback.forcedSet)
            }
            #expect(ZTronAvailability.forcedFallbacks == outer)

            // A throwing body still restores.
            struct Boom: Error {}
            #expect(throws: Boom.self) {
                try withOSPath(.forcedFallback) { throw Boom() }
            }
            #expect(ZTronAvailability.forcedFallbacks == outer)
        }
        #expect(ZTronAvailability.forcedFallbacks == before)
    }

    /// The async overload (chosen when the body awaits) nests inside the same task without deadlocking
    /// on its gate and restores the enclosing set, also when the body throws.
    @Test func asyncOSPathHelperIsBalanced() async {
        let before = ZTronAvailability.forcedFallbacks
        let outer: Set<ZTronCapability> = ZTronAvailability.isForcingSupported ? [.spatialEvents] : []
        await withOSPath(.preferred) {
            await Task.yield()
            ZTronAvailability.forceFallback(.spatialEvents, true)
            #expect(ZTronAvailability.forcedFallbacks == outer)

            await withOSPath(.forcedFallback) {
                await Task.yield()
                #expect(ZTronAvailability.forcedFallbacks == OSPath.forcedFallback.forcedSet)
                await withOSPath(.preferred) {
                    await Task.yield()
                    #expect(ZTronAvailability.forcedFallbacks.isEmpty)
                }
                #expect(ZTronAvailability.forcedFallbacks == OSPath.forcedFallback.forcedSet)
            }
            #expect(ZTronAvailability.forcedFallbacks == outer)

            struct Boom: Error {}
            await #expect(throws: Boom.self) {
                try await withOSPath(.forcedFallback) {
                    await Task.yield()
                    throw Boom()
                }
            }
            #expect(ZTronAvailability.forcedFallbacks == outer)
        }
        #expect(ZTronAvailability.forcedFallbacks == before)
    }

    /// Concurrent async scopes take turns: each sees only its own forced set across suspension points.
    @Test func asyncOSPathScopesDoNotInterleave() async {
        let paths: [OSPath] = [.preferred, .forcedFallback, .preferred, .forcedFallback, .forcedFallback, .preferred]
        let tasks = paths.map { path in
            Task { @MainActor in
                await withOSPath(path) {
                    for _ in 0..<4 {
                        await Task.yield()
                        #expect(ZTronAvailability.forcedFallbacks == path.forcedSet, "\(path)")
                    }
                }
            }
        }
        for task in tasks {
            await task.value
        }
    }

    /// A task created inside a scope that outlives it must not inherit the gate: it waits for later scopes instead
    /// of installing its set in the middle of them.
    @Test func outlivingTaskDoesNotBypassTheGate() async {
        var spawned: Task<Void, Never>?
        await withOSPath(.preferred) {
            await Task.yield()                                      // async overload: the task inherits its token
            spawned = Task { @MainActor in
                await withOSPath(.forcedFallback) {
                    for _ in 0..<4 {
                        await Task.yield()
                        #expect(ZTronAvailability.forcedFallbacks == OSPath.forcedFallback.forcedSet)
                    }
                }
            }
        }
        await withOSPath(.preferred) {
            for _ in 0..<8 {
                await Task.yield()
                #expect(ZTronAvailability.forcedFallbacks.isEmpty, "an outlived task interleaved this scope")
            }
        }
        await spawned?.value
    }

    @Test func smokePackageLinks() {
        #expect(!ZTronCapability.allCases.isEmpty)
    }

    // MARK: - Helpers

    private func snapshot() -> [ZTronCapability: Bool] {
        Dictionary(uniqueKeysWithValues: ZTronCapability.allCases.map { ($0, ZTronAvailability.isAvailable($0)) })
    }

    private func expectedAvailability(_ capability: ZTronCapability, path: OSPath) -> Bool {
        ZTronAvailability.osSupports(capability) && !path.forcedSet.contains(capability)
    }
}
