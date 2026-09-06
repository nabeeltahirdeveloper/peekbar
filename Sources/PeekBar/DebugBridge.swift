import AppKit

/// Test hook, active only when launched with `--debug-bridge`. Lets the smoke test drive the
/// app through distributed notifications without needing Accessibility for the test runner.
@MainActor
final class DebugBridge {
    static let name = Notification.Name("com.peekbar.debug")
    static let replyName = Notification.Name("com.peekbar.debug.reply")
    private var observer: Any?
    private let handler: (String, String?) -> String

    init(handler: @escaping (String, String?) -> String) {
        self.handler = handler
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let cmd = note.userInfo?["cmd"] as? String ?? ""
            let arg = note.userInfo?["arg"] as? String
            Task { @MainActor in
                let result = self.handler(cmd, arg)
                DistributedNotificationCenter.default().postNotificationName(Self.replyName, object: nil, userInfo: ["cmd": cmd, "result": result], deliverImmediately: true)
            }
        }
        log.info("Debug bridge enabled")
    }
}
