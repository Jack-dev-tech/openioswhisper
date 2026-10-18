import XCTest
@testable import DictationCore

final class AppGroupTests: XCTestCase {
    func testReadsGroupsFromProfileEnvelope() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>Sideloaded</string>
            <key>Entitlements</key>
            <dict>
                <key>com.apple.security.application-groups</key>
                <array><string>group.com.jackmatsuzaki.openwhisper.ABCDE12345</string></array>
            </dict>
        </dict>
        </plist>
        """
        // Binary CMS bytes around the plist, as in a real profile.
        var data = Data([0x30, 0x82, 0x1F, 0x00, 0xFF])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x82, 0x00]))

        XCTAssertEqual(AppGroup.groups(inProvisioningProfile: data), ["group.com.jackmatsuzaki.openwhisper.ABCDE12345"])
        XCTAssertEqual(AppGroup.groups(inProvisioningProfile: Data([1, 2, 3])), [])
    }

    func testCandidatesPreferRenamedGroupThenDefault() {
        XCTAssertEqual(AppGroup.candidates(profileGroups: []), [IPC.appGroupID])
        XCTAssertEqual(
            AppGroup.candidates(profileGroups: ["group.other", "group.com.jackmatsuzaki.openwhisper.TEAM", "group.*"]),
            ["group.com.jackmatsuzaki.openwhisper.TEAM", IPC.appGroupID, "group.other"]
        )
        XCTAssertEqual(AppGroup.candidates(profileGroups: [IPC.appGroupID]), [IPC.appGroupID])
    }
}
