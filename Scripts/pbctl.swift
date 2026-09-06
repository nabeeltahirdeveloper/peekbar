import Foundation

// Sends one debug command to a running PeekBar (launched with --debug-bridge) and prints the reply.
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: pbctl <cmd> [arg]"); exit(2) }
let cmd = args[1]
let arg: String? = args.count > 2 ? args[2] : nil
var reply: String?
let obs = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.peekbar.debug.reply"), object: nil, queue: nil) { note in
    if (note.userInfo?["cmd"] as? String) == cmd { reply = note.userInfo?["result"] as? String ?? "" }
}
var info: [String: String] = ["cmd": cmd]
if let a = arg { info["arg"] = a }
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.peekbar.debug"), object: nil, userInfo: info, deliverImmediately: true)
let deadline = Date().addingTimeInterval(8)
while reply == nil && Date() < deadline { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
DistributedNotificationCenter.default().removeObserver(obs)
if let r = reply { print(r); exit(0) } else { print("TIMEOUT"); exit(1) }
