import XCTest
@testable import VeloopCore

final class UpdateManifestTests: XCTestCase {
    private let decoder = UpdateManifestDecoder()

    func testDecodesTrustedBilingualManifest() throws {
        let manifest = try decoder.decode(data(version: "0.2.4"))

        XCTAssertEqual(manifest.version, try NumericVersion("0.2.4"))
        XCTAssertEqual(manifest.notes(for: .english, preferredLocalizations: []), ["Fixed input placement"])
        XCTAssertEqual(manifest.notes(for: .simplifiedChinese, preferredLocalizations: []), ["修复输入定位"])
        XCTAssertEqual(
            manifest.releaseURL.absoluteString,
            "https://github.com/talentdedcat/Veloop/releases/tag/v0.2.4"
        )
    }

    func testFollowSystemUsesChineseOnlyForSimplifiedChinesePreference() throws {
        let manifest = try decoder.decode(data(version: "0.2.4"))

        XCTAssertEqual(manifest.notes(for: .system, preferredLocalizations: ["zh-Hans-CN"]), ["修复输入定位"])
        XCTAssertEqual(manifest.notes(for: .system, preferredLocalizations: ["fr"]), ["Fixed input placement"])
    }

    func testRejectsUnsupportedOrUnsafeDocuments() {
        XCTAssertThrowsError(try decoder.decode(data(version: "0.2.4", schemaVersion: 2)))
        XCTAssertThrowsError(try decoder.decode(data(version: "release")))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            releaseURL: "http://github.com/talentdedcat/Veloop/releases/tag/v0.2.4"
        )))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            releaseURL: "https://github.com/other/Veloop/releases/tag/v0.2.4"
        )))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            releaseURL: "https://user:secret@github.com/talentdedcat/Veloop/releases/tag/v0.2.4"
        )))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            releaseURL: "https://github.com/talentdedcat/Veloop/releases/tag/v0.2.5"
        )))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            releaseURL: "https://github.com/talentdedcat/Veloop/releases/tag/../v0.2.4"
        )))
    }

    func testRequiresBothNonemptyTranslations() {
        XCTAssertThrowsError(try decoder.decode(data(version: "0.2.4", chineseNotes: [])))
        XCTAssertThrowsError(try decoder.decode(data(version: "0.2.4", englishNotes: ["  "])))
    }

    func testReleaseVersionMustUseCanonicalThreeComponentSpelling() {
        for version in ["0.3", "0.3.0.0", "00.3.0"] {
            XCTAssertThrowsError(try decoder.decode(data(
                version: version,
                releaseURL: "https://github.com/talentdedcat/Veloop/releases/tag/v\(version)"
            )), version)
        }
    }

    func testEnforcesBodyAndNoteBounds() {
        XCTAssertThrowsError(try decoder.decode(Data(repeating: 0x20, count: UpdateManifestDecoder.maximumBodyBytes + 1)))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            englishNotes: Array(repeating: "Change", count: UpdateManifestDecoder.maximumNotesPerLanguage + 1)
        )))
        XCTAssertThrowsError(try decoder.decode(data(
            version: "0.2.4",
            englishNotes: [String(repeating: "a", count: UpdateManifestDecoder.maximumNoteScalars + 1)]
        )))
    }

    private func data(
        version: String,
        schemaVersion: Int = 1,
        releaseURL: String = "https://github.com/talentdedcat/Veloop/releases/tag/v0.2.4",
        englishNotes: [String] = ["Fixed input placement"],
        chineseNotes: [String] = ["修复输入定位"]
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": schemaVersion,
            "version": version,
            "releaseURL": releaseURL,
            "notes": ["en": englishNotes, "zh-Hans": chineseNotes],
        ])
    }
}
