import XCTest
@testable import VeloopCore

final class UpdateReleaseContractTests: XCTestCase {
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
        XCTAssertTrue(source.contains("http.url?.scheme == \"https\""))
        XCTAssertFalse(source.contains("session.data(for: request)"))
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
}
