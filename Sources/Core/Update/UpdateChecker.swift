import Foundation

public enum UpdateCheckMode: Equatable, Sendable {
    case automatic
    case manual
}

public enum UpdateCheckResult: Equatable, Sendable {
    case suppressed
    case upToDate
    case available(UpdateManifest)
    case failed
}

public protocol UpdateManifestFetching: Sendable {
    func fetch() async throws -> Data
}

public final class URLSessionUpdateManifestFetcher: UpdateManifestFetching, @unchecked Sendable {
    public static let endpoint = URL(
        string: "https://github.com/talentdedcat/Veloop/releases/latest/download/update.json"
    )!

    private let session: URLSession
    private let endpoint: URL

    public convenience init(endpoint: URL = URLSessionUpdateManifestFetcher.endpoint) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        self.init(endpoint: endpoint, session: URLSession(configuration: configuration))
    }

    init(endpoint: URL, session: URLSession) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetch() async throws -> Data {
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.url?.scheme?.lowercased() == "https",
                  (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= Int64(UpdateManifestDecoder.maximumBodyBytes) else {
                throw UpdateFetchError.invalidResponse
            }
            var data = Data()
            data.reserveCapacity(max(0, Int(http.expectedContentLength)))
            for try await byte in bytes {
                guard data.count < UpdateManifestDecoder.maximumBodyBytes else {
                    throw UpdateFetchError.invalidResponse
                }
                data.append(byte)
            }
            return data
        } catch {
            AppLogger.failure(category: "update-check", error: error)
            throw error
        }
    }
}

public actor UpdateChecker {
    private let currentVersion: NumericVersion
    private let fetcher: any UpdateManifestFetching
    private let preferences: UpdatePreferenceStore
    private let decoder: UpdateManifestDecoder
    private let now: @Sendable () -> Date
    private var inFlight: (id: UUID, task: Task<Data, Error>)?

    public init(
        currentVersion: NumericVersion,
        fetcher: any UpdateManifestFetching = URLSessionUpdateManifestFetcher(),
        preferences: UpdatePreferenceStore = UpdatePreferenceStore(),
        decoder: UpdateManifestDecoder = UpdateManifestDecoder(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.preferences = preferences
        self.decoder = decoder
        self.now = now
    }

    public func check(_ mode: UpdateCheckMode) async -> UpdateCheckResult {
        let checkDate = now()
        if mode == .automatic, !preferences.isAutomaticCheckDue(at: checkDate) {
            return .suppressed
        }

        let requestID: UUID
        let task: Task<Data, Error>
        if let inFlight {
            requestID = inFlight.id
            task = inFlight.task
        } else {
            let fetcher = fetcher
            let created = Task { try await fetcher.fetch() }
            requestID = UUID()
            inFlight = (requestID, created)
            task = created
        }

        let data: Data
        do {
            data = try await task.value
        } catch {
            clearInFlight(requestID)
            if mode == .automatic { preferences.recordAutomaticAttempt(at: checkDate) }
            return .failed
        }
        clearInFlight(requestID)
        if mode == .automatic { preferences.recordAutomaticAttempt(at: checkDate) }

        let manifest: UpdateManifest
        do {
            manifest = try decoder.decode(data)
        } catch {
            AppLogger.failure(category: "update-check", error: error)
            return .failed
        }
        guard manifest.version > currentVersion else { return .upToDate }
        if mode == .automatic,
           (preferences.isSkipped(manifest.version)
                || preferences.isDeferred(manifest.version, at: checkDate)) {
            return .suppressed
        }
        return .available(manifest)
    }

    private func clearInFlight(_ requestID: UUID) {
        if inFlight?.id == requestID { inFlight = nil }
    }
}

private enum UpdateFetchError: Error {
    case invalidResponse
}
