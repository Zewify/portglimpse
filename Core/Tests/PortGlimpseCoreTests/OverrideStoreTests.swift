import Foundation
import Testing
@testable import PortGlimpseCore

struct OverrideStoreTests {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("portglimpse-overrides-\(UUID().uuidString)")
        .appendingPathComponent("nested/overrides.json")

    @Test func startsEmptyWhenNoFileExists() {
        #expect(OverrideStore(fileURL: file).overrides.isEmpty)
    }

    @Test func savedOverridesSurviveAReload() throws {
        let store = OverrideStore(fileURL: file)
        try store.set(.dev, for: "/Applications/Postgres.app/Contents/MacOS/postgres")
        try store.set(.appsAndSystem, for: "/usr/local/bin/node")
        let reloaded = OverrideStore(fileURL: file)
        #expect(reloaded.overrides == [
            "/Applications/Postgres.app/Contents/MacOS/postgres": .dev,
            "/usr/local/bin/node": .appsAndSystem,
        ])
    }

    @Test func settingNilRemovesTheOverride() throws {
        let store = OverrideStore(fileURL: file)
        try store.set(.dev, for: "/a")
        try store.set(nil, for: "/a")
        #expect(store.overrides.isEmpty)
        #expect(OverrideStore(fileURL: file).overrides.isEmpty)
    }

    @Test func aCorruptFileIsTreatedAsEmpty() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(OverrideStore(fileURL: file).overrides.isEmpty)
    }

    @Test func defaultLocationIsApplicationSupport() {
        #expect(OverrideStore.defaultURL.path.hasSuffix("Library/Application Support/PortGlimpse/overrides.json"))
    }
}
