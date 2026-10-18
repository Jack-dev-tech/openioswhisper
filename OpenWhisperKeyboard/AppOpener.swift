import UIKit

/// Opens the containing app from the keyboard.
///
/// `UIApplication.shared` isn't available to extensions, but the application object is still
/// in the keyboard's responder chain, and `open(_:options:completionHandler:)` works when
/// called on it through the Objective-C runtime.
@MainActor
enum AppOpener {
    private typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void

    static func open(_ url: URL, from responder: UIResponder) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var current: UIResponder? = responder
        while let candidate = current {
            if candidate is UIApplication, candidate.responds(to: selector) {
                let implementation = candidate.method(for: selector)
                let open = unsafeBitCast(implementation, to: OpenURL.self)
                open(candidate, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            current = candidate.next
        }
        return false
    }
}
