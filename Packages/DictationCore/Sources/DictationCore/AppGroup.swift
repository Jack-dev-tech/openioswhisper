import Foundation

/// Finds the App Group the app and keyboard actually share.
///
/// Sideloading tools (Sideloadly, AltStore) re-sign the app with the user's own team and often
/// rename the App Group, for example by adding the team ID. The real name is in the
/// `embedded.mobileprovision` they put in each bundle, so read it from there and fall back
/// to the built-in name (App Store and TestFlight builds have no embedded profile).
public enum AppGroup {
    /// Group identifiers to try, best first.
    public static func candidates(profileGroups: [String], defaultID: String = IPC.appGroupID) -> [String] {
        let ours = profileGroups.filter { $0.localizedCaseInsensitiveContains("openwhisper") }
        let others = profileGroups.filter { !ours.contains($0) && !$0.contains("*") }
        var result: [String] = []
        for id in ours + [defaultID] + others where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    /// The `com.apple.security.application-groups` entitlement in a provisioning profile.
    /// The profile is a signed CMS envelope with the plist stored as plain text inside it.
    public static func groups(inProvisioningProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return [] }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// Groups from this bundle's embedded provisioning profile, if it has one.
    public static func groupsInEmbeddedProfile(bundle: Bundle = .main) -> [String] {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return groups(inProvisioningProfile: data)
    }
}
