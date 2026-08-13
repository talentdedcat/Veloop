import XCTest
@testable import VeloopCore

final class UpdateReleaseContractTests: XCTestCase {
    override func tearDown() {
        StubUpdateURLProtocol.handler = nil
        super.tearDown()
    }

    func testProductionEndpointUsesExactLatestReleaseAssetName() {
        XCTAssertEqual(
            URLSessionUpdateManifestFetcher.endpoint.absoluteString,
            "https://github.com/talentdedcat/Veloop/releases/latest/download/update.json"
        )
    }

    func testProductionFetcherStreamsAndValidatesTheFinalResponse() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Core/Update/UpdateChecker.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("session.bytes(for: request)"))
        XCTAssertTrue(source.contains("data.count < UpdateManifestDecoder.maximumBodyBytes"))
        XCTAssertTrue(source.contains("http.url?.scheme?.lowercased() == \"https\""))
        XCTAssertFalse(source.contains("session.data(for: request)"))
        XCTAssertTrue(source.contains("AppLogger.failure(category: \"update-check\""))
        XCTAssertFalse(source.contains("localizedDescription"))
    }

    func testProductionFetcherAcceptsOnlyBoundedSuccessfulHTTPSResponses() async throws {
        let valid = Data("manifest".utf8)
        StubUpdateURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(valid.count)"]
            )!
            return (response, valid)
        }
        let fetcher = URLSessionUpdateManifestFetcher(
            endpoint: URL(string: "https://updates.veloop.test/update.json")!,
            session: stubSession()
        )

        let fetched = try await fetcher.fetch()
        XCTAssertEqual(fetched, valid)
    }

    func testProductionFetcherRejectsHTTPFailuresAndOversizedBodies() async throws {
        let endpoint = URL(string: "https://updates.veloop.test/update.json")!
        let session = stubSession()
        let fetcher = URLSessionUpdateManifestFetcher(endpoint: endpoint, session: session)

        StubUpdateURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("not found".utf8))
        }
        await XCTAssertThrowsErrorAsync { _ = try await fetcher.fetch() }

        StubUpdateURLProtocol.handler = { request in
            let body = Data(repeating: 0x61, count: UpdateManifestDecoder.maximumBodyBytes + 1)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        await XCTAssertThrowsErrorAsync { _ = try await fetcher.fetch() }
    }

    func testReleaseManifestVersionAndTagMustMatch() throws {
        let version = "0.2.4"
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "version": version,
            "releaseURL": "https://github.com/talentdedcat/Veloop/releases/tag/v\(version)",
            "notes": [
                "en": ["Improved update checking."],
                "zh-Hans": ["改进更新检查。"],
            ],
        ])

        let manifest = try UpdateManifestDecoder().decode(data)

        XCTAssertEqual(manifest.version.description, version)
        XCTAssertEqual(manifest.releaseURL.lastPathComponent, "v\(version)")
        XCTAssertFalse(manifest.notes(for: .english).isEmpty)
        XCTAssertFalse(manifest.notes(for: .simplifiedChinese).isEmpty)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubUpdateURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubUpdateURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
