import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

/// Access to the private Accessibility SPIs needed to reach windows that live on
/// other macOS Spaces ("Desktops").
///
/// The public `kAXWindowsAttribute` only returns windows on the active Space on
/// modern macOS. The remote-token SPI lets us build an AX element for any window
/// of a process by walking its AX element IDs, which works across Spaces.
/// Everything degrades gracefully if the symbols are unavailable.
final class PrivateAX {
    static let shared = PrivateAX()

    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateRemoteFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private let getWindow: GetWindowFn?
    private let createRemote: CreateRemoteFn?

    private init() {
        guard let handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY
        ) else {
            getWindow = nil
            createRemote = nil
            return
        }

        if let symbol = dlsym(handle, "_AXUIElementGetWindow") {
            getWindow = unsafeBitCast(symbol, to: GetWindowFn.self)
        } else {
            getWindow = nil
        }

        if let symbol = dlsym(handle, "_AXUIElementCreateWithRemoteToken") {
            createRemote = unsafeBitCast(symbol, to: CreateRemoteFn.self)
        } else {
            createRemote = nil
        }
    }

    var isAvailable: Bool {
        getWindow != nil && createRemote != nil
    }

    func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var windowID: CGWindowID = 0
        guard getWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    func isAlive(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var roleRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success
    }

    /// Walks the process's AX element IDs and returns every window element it can
    /// reach, including windows on other Spaces.
    ///
    /// The scan has to run for the full time budget because the number of windows
    /// is unknown; callers should cache the result.
    func allWindowElements(pid: pid_t, budget: TimeInterval) -> [CGWindowID: AXUIElement] {
        guard let createRemote, let getWindow else { return [:] }
        guard let token = CFDataCreateMutable(kCFAllocatorDefault, 20) else { return [:] }

        CFDataSetLength(token, 20)
        guard let bytes = CFDataGetMutableBytePtr(token) else { return [:] }
        memset(bytes, 0, 20)

        var pidField = pid
        memcpy(bytes, &pidField, 4)
        var magic = Int32(0x636f636f)
        memcpy(bytes + 8, &magic, 4)

        var found: [CGWindowID: AXUIElement] = [:]
        let start = DispatchTime.now().uptimeNanoseconds
        var elementID: UInt64 = 0

        while elementID < 500_000 {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            if elapsed > budget { break }

            var idField = elementID
            memcpy(bytes + 12, &idField, 8)

            if let element = createRemote(token)?.takeRetainedValue() {
                var windowID: CGWindowID = 0
                if getWindow(element, &windowID) == .success,
                   windowID != 0,
                   found[windowID] == nil {
                    AXUIElementSetMessagingTimeout(element, 0.1)
                    var roleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(
                        element,
                        kAXRoleAttribute as CFString,
                        &roleRef
                    ) == .success, let role = roleRef as? String, role == "AXWindow" {
                        found[windowID] = element
                    }
                }
            }

            elementID &+= 1
        }

        return found
    }
}
