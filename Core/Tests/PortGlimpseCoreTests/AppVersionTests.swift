import Foundation
import Testing
@testable import PortGlimpseCore

struct AppVersionTests {
    @Test func parsesWithOrWithoutAV() {
        #expect(AppVersion("v1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("1.2.3")?.parts == [1, 2, 3])
    }

    @Test func rejectsNonsense() {
        #expect(AppVersion("beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumerically() {
        #expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
        #expect(AppVersion("v1.0.1")! > AppVersion("1.0.0")!)
    }

    @Test func missingPartsCountAsZero() {
        #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
        #expect(!(AppVersion("1.0")! < AppVersion("1.0.0")!))
    }

    @Test func printsWithoutTheV() {
        #expect(AppVersion("v1.2.0")!.description == "1.2.0")
    }

    @Test func readsTheLatestReleaseTag() throws {
        let json = Data(#"{"tag_name":"v1.0.1","name":"PortGlimpse 1.0.1","draft":false}"#.utf8)
        #expect(try ReleaseFeed.latestVersion(fromJSON: json) == AppVersion("1.0.1"))
    }

    @Test func aResponseWithoutATagThrows() {
        #expect(throws: DecodingError.self) { try ReleaseFeed.latestVersion(fromJSON: Data(#"{"message":"Not Found"}"#.utf8)) }
    }
}
