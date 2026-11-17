import Foundation
import Testing
@testable import FarmCore

// MARK: - Bonjour address → site URL (the "Looking for the farm… forever" bug)

@Test func bonjourHostNameBecomesSiteURL() {
    #expect(SiteAddress.url(host: "farm.local.", port: 80)?.absoluteString == "http://farm.local/")
    #expect(SiteAddress.url(host: "farm.local", port: 8080)?.absoluteString == "http://farm.local:8080/")
}

@Test func interfaceScopeIsStripped() {
    // NWEndpoint prints IPv4 addresses with the interface ("…%en0"); URL(string:) rejects that.
    #expect(SiteAddress.url(host: "192.0.2.41%en0", port: 80)?.absoluteString == "http://192.0.2.41/")
    #expect(SiteAddress.url(host: "fe80::1%en0", port: 80)?.absoluteString == "http://[fe80::1]/")
    #expect(SiteAddress.url(host: "[2001:db8::5]", port: 3000)?.absoluteString == "http://[2001:db8::5]:3000/")
}

@Test func emptyHostOrPortIsRejected() {
    #expect(SiteAddress.url(host: "", port: 80) == nil)
    #expect(SiteAddress.url(host: ".", port: 80) == nil)
    #expect(SiteAddress.url(host: "farm.local", port: 0) == nil)
}

@Test func typedAddressesBecomeSiteRoots() {
    #expect(SiteAddress.parse("farm.local")?.absoluteString == "http://farm.local/")
    #expect(SiteAddress.parse("  http://farm-server:8080/jobs/12?x=1#top ")?.absoluteString == "http://farm-server:8080/")
    #expect(SiteAddress.parse("https://farm.example")?.absoluteString == "https://farm.example/")
    #expect(SiteAddress.parse("ftp://farm.local") == nil)
    #expect(SiteAddress.parse("") == nil)
    #expect(SiteAddress.parse(nil) == nil)
}

// MARK: - Recent files: hide what isn't the student's own work

private let home = "/Users/student"

@Test(arguments: [
    "/Users/student/Projects/farm/jobs/0b9c1e2a-9317-41bd-bdf8-83ca12345678/source.blend",   // farm job copy (UUID)
    "/Users/student/Projects/farm/jobs/a1b2c3d4e5f6a7b8/source.blend",                      // hash-named folder
    "/Users/student/Projects/x/b0c4e/project/shots/one.blend",                              // /project/ job copy
    "/Users/student/Projects/farm-mac/Tests/fixtures/scene.blend",
    "/Users/student/Projects/app/.build/debug/x.blend",
    "/Users/student/Library/Caches/thing/x.blend",
    "/Users/student/.Trash/old.blend",
    "/Users/student/Downloads/blender-5.3-splash.blend",
    "/Users/student/Downloads/farm-collect.a1B2c3/staging/scene.blend",                     // mktemp folder
    "/private/var/folders/ab/T/farm-1234/scene/scene.blend",                                // outside home
    "/Users/student/Art/scene.blend1",
])
func junkIsHidden(_ path: String) {
    #expect(BlendFilter.isJunk(path, home: home))
}

@Test(arguments: [
    "/Users/student/Desktop/robot arm.blend",
    "/Users/student/Documents/School/Year 10/desert temple v3.blend",
    "/Users/student/Downloads/classroom-packed.blend",
    "/Users/student/Projects/my-project/scene.blend",            // "my-project" is not "project"
    "/Users/student/Documents/blender 2024/forest_scene.blend",
    "/Users/student/Documents/final.v2/space station.blend",     // a dot in a real folder name
])
func ownWorkIsShown(_ path: String) {
    #expect(!BlendFilter.isJunk(path, home: home))
}

@Test func recentIsNewestFirstAndCapped() {
    struct File { var path: String; var date: Date }
    let now = Date()
    let files = (0..<10).map { File(path: "\(home)/Art/scene\($0).blend", date: now.addingTimeInterval(Double(-$0) * 60)) }
        + [File(path: "\(home)/Downloads/blender-5.3-splash.blend", date: now.addingTimeInterval(60))]
    let recent = BlendFilter.recent(files.shuffled(), path: \.path, date: \.date, limit: 6, home: home)
    #expect(recent.map(\.path) == (0..<6).map { "\(home)/Art/scene\($0).blend" })
}
