import Foundation
import XCTest
@testable import VeloopCore

final class UpdateCheckerTests: XCTestCase {
    func testAutomaticCheckIsSuppressedUntilDueWithoutFetching() async throws {
        let context = makeContext(data: manifestData(version: "0.2.4"))
        context.preferences.recordAutomaticAttempt(at: context.now)

        let result = await context.checker.check(.automatic)
        let callCount = await context.fetcher.callCount

        XCTAssertEqual(result, .suppressed)
        XCTAssertEqual(callCount, 0)
    }

    func testAutomaticCheckRecordsCompletedFailedAttempt() async throws {
        let context = makeContext(error: TestError.unavailable)

        let result = await context.checker.check(.automatic)

        XCTAssertEqual(result, .failed)
        XCTAssertFalse(context.preferences.isAutomaticCheckDue(
            at: context.now.addingTimeInterval(60)
        ))
    }

    func testManualCheckBypassesIntervalAndVersionSuppression() async throws {
        let context = makeContext(data: manifestData(version: "0.2.4"))
        let version = try NumericVersion("0.2.4")
        context.preferences.recordAutomaticAttempt(at: context.now)
        context.preferences.skip(version)
        context.preferences.remindLater(about: version, at: context.now)

        let result = await context.checker.check(.manual)
        let callCount = await context.fetcher.callCount

        guard case let .available(manifest) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(manifest.version, version)
        XCTAssertEqual(callCount, 1)
    }

    func testAutomaticCheckAppliesSkipAndDeferralToMatchingVersion() async throws {
        let skipped = makeContext(data: manifestData(version: "0.2.4"))
        skipped.preferences.skip(try NumericVersion("0.2.4"))
        let skippedResult = await skipped.checker.check(.automatic)
        XCTAssertEqual(skippedResult, .suppressed)

        let deferred = makeContext(data: manifestData(version: "0.2.4"))
        deferred.preferences.remindLater(about: try NumericVersion("0.2.4"), at: deferred.now)
        let deferredResult = await deferred.checker.check(.automatic)
        XCTAssertEqual(deferredResult, .suppressed)

        let newer = makeContext(data: manifestData(version: "0.2.5"))
        newer.preferences.skip(try NumericVersion("0.2.4"))
        guard case .available = await newer.checker.check(.automatic) else {
            return XCTFail("A newer version must bypass an older skip")
        }
    }

    func testReportsUpToDateWhenRemoteIsNotNewer() async {
        let context = makeContext(data: manifestData(version: "0.2.3"))
        let result = await context.checker.check(.manual)
        XCTAssertEqual(result, .upToDate)
    }

    func testConcurrentChecksShareOneFetch() async {
        let fetcher = SuspendedManifestFetcher(data: manifestData(version: "0.2.4"))
        let context = makeContext(fetcher: fetcher)

        async let first = context.checker.check(.manual)
        await fetcher.waitUntilCalled()
        async let second = context.checker.check(.manual)
        await Task.yield()
        await fetcher.resume()

        guard case .available = await first, case .available = await second else {
            return XCTFail("Both checks must receive the shared result")
        }
        let callCount = await fetcher.callCount
        XCTAssertEqual(callCount, 1)
    }

    private func makeContext(
        data: Data? = nil,
        error: Error? = nil,
        fetcher: (any UpdateManifestFetching)? = nil
    ) -> Context {
        let suite = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = UpdatePreferenceStore(defaults: defaults)
        let scripted = ScriptedManifestFetcher(result: error.map(Result.failure)
            ?? .success(data ?? manifestData(version: "0.2.4")))
        let selectedFetcher = fetcher ?? scripted
        let now = Date(timeIntervalSince1970: 10_000)
        return Context(
            checker: UpdateChecker(
                currentVersion: try! NumericVersion("0.2.3"),
                fetcher: selectedFetcher,
                preferences: preferences,
                now: { now }
            ),
            preferences: preferences,
            fetcher: scripted,
            now: now
        )
    }

    private func manifestData(version: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "version": version,
            "releaseURL": "https://github.com/talentdedcat/Veloop/releases/tag/v\(version)",
            "notes": ["en": ["Change"], "zh-Hans": ["修改"]],
        ])
    }

    private struct Context {
        let checker: UpdateChecker
        let preferences: UpdatePreferenceStore
        let fetcher: ScriptedManifestFetcher
        let now: Date
    }
}

private actor ScriptedManifestFetcher: UpdateManifestFetching {
    private(set) var callCount = 0
    let result: Result<Data, Error>

    init(result: Result<Data, Error>) {
        self.result = result
    }

    func fetch() async throws -> Data {
        callCount += 1
        return try result.get()
    }
}

private actor SuspendedManifestFetcher: UpdateManifestFetching {
    private(set) var callCount = 0
    private let data: Data
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchContinuation: CheckedContinuation<Void, Never>?

    init(data: Data) {
        self.data = data
    }

    func fetch() async throws -> Data {
        callCount += 1
        callWaiters.forEach { $0.resume() }
        callWaiters.removeAll()
        await withCheckedContinuation { fetchContinuation = $0 }
        return data
    }

    func waitUntilCalled() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func resume() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }
}

private enum TestError: Error {
    case unavailable
}
