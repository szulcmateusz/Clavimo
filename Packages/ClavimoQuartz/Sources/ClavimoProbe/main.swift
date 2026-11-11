import AppKit
import Foundation
import ClavimoCore
import ClavimoQuartz

// P0 feasibility probe. Runs the real event tap with a fixed rule set for
// a bounded time and prints aggregate results. It never prints key codes,
// characters, or button sequences.

struct Options {
    var command = "status"
    var seconds = 60
    var flagRewrite: EventTapController.FlagRewriteMode = .inPlace
    var policy: LeaderPolicy = .boundedWindow(milliseconds: LeaderPolicy.defaultWindowMilliseconds)
    var swapModifiers = true
}

func usage() -> Never {
    print("""
    usage: clavimo-probe status
           clavimo-probe request-access
           clavimo-probe run [--seconds N] [--flags inplace|repost]
                              [--leader bounded[:MS]|deferred|nonconsuming] [--no-swap]

    run installs a session event tap with these rules:
      - Left Command <-> Left Option (unless --no-swap)
      - F + Mouse Button 4     -> Next Space (Control + Right Arrow)
      - Shift + Mouse Button 5 -> Previous Space (Control + Left Arrow)
    It stops by itself after --seconds (default 60, max 600) or on Ctrl+C.
    """)
    exit(2)
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.dropFirst().makeIterator()
    guard let command = iterator.next() else { return options }
    options.command = command
    while let argument = iterator.next() {
        switch argument {
        case "--seconds":
            guard let value = iterator.next().flatMap(Int.init), (1...600).contains(value) else { usage() }
            options.seconds = value
        case "--flags":
            guard let value = iterator.next().flatMap(EventTapController.FlagRewriteMode.init(rawValue:)) else { usage() }
            options.flagRewrite = value
        case "--leader":
            guard let value = iterator.next() else { usage() }
            switch value.split(separator: ":").first {
            case "bounded":
                let ms = value.split(separator: ":").dropFirst().first.flatMap { Int($0) } ?? LeaderPolicy.defaultWindowMilliseconds
                options.policy = .boundedWindow(milliseconds: ms)
            case "deferred": options.policy = .deferredUntilUp
            case "nonconsuming": options.policy = .nonConsuming
            default: usage()
            }
        case "--no-swap":
            options.swapModifiers = false
        default:
            usage()
        }
    }
    return options
}

func describe(_ permissions: PermissionSnapshot) -> String {
    func mark(_ value: Bool) -> String { value ? "granted" : "NOT granted" }
    let session = ConsoleSession.isActive().map { $0 ? "active (on console)" : "inactive" } ?? "unknown"
    return """
    Accessibility:        \(mark(permissions.accessibilityTrusted))
    Input Monitoring:     \(mark(permissions.listenEventAccess))
    Event posting:        \(mark(permissions.postEventAccess))
    Console session:      \(session)
    """
}

func format(_ summary: LatencyRecorder.Summary?) -> String {
    guard let summary else { return "no samples" }
    func us(_ ns: UInt64) -> String { String(format: "%.1f us", Double(ns) / 1000) }
    return "n=\(summary.count) p50=\(us(summary.p50)) p95=\(us(summary.p95)) p99=\(us(summary.p99)) max=\(us(summary.max))"
}

// Line-buffer output so results reach a log file promptly when the
// probe runs as an app bundle launched with `open --stdout`.
setvbuf(stdout, nil, _IOLBF, 0)

let options = parse(CommandLine.arguments)

switch options.command {
case "status":
    print(describe(.current()))
    exit(0)
case "request-access":
    PermissionSnapshot.requestAccess()
    print("Requested access. Grant it in System Settings > Privacy & Security, then run `status`.")
    exit(0)
case "run":
    break
default:
    usage()
}

var definitions: [RuleDefinition] = [
    .mouseChord(id: "f-mouse4-next", leader: .key(.f, options.policy), button: .button4, action: .nextWorkspace, priority: 90),
    .mouseChord(id: "shift-mouse5-prev", leader: .modifiers(.shift), button: .button5, action: .previousWorkspace, priority: 80),
]
if options.swapModifiers {
    definitions.append(.swap(.leftCommand, .leftOption))
}

let rules: CompiledRules
switch CompiledRules.compile(definitions) {
case let .success(compiled): rules = compiled
case let .failure(failure):
    print("Invalid rules: \(failure.errors)")
    exit(1)
}

print(describe(.current()))
let executor = SystemShortcutExecutor()
let controller = EventTapController(
    rules: rules,
    flagRewrite: options.flagRewrite,
    actionHandler: { action in executor.run(action) },
    onStop: { reason in
        if reason == .tooManyTapFailures {
            print("Event tap was disabled by macOS too often; stopped (safe mode).")
        }
    }
)

do {
    try controller.start()
} catch {
    print("Could not create the event tap. Grant Accessibility (and Input Monitoring if listed) to the app running this command, then retry.")
    exit(1)
}

print("Running for \(options.seconds) s with flags=\(options.flagRewrite.rawValue), leader=\(options.policy). Press Ctrl+C to stop early.")

func finish(_ code: Int32) -> Never {
    let done = DispatchSemaphore(value: 0)
    controller.statistics { stats in
        print("""
        --- results (aggregate only, no key data) ---
        events seen:            \(stats.eventsSeen)
        pass-through callback:  \(format(stats.passThrough))
        handled callback:       \(format(stats.handled))
        tap disabled (timeout): \(stats.tapDisabledByTimeout)
        tap disabled (input):   \(stats.tapDisabledByUserInput)
        tap re-enabled:         \(stats.tapReenabled)
        """)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 2)
    controller.stop()
    Thread.sleep(forTimeInterval: 0.1)
    exit(code)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalSources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { finish(0) }
    source.resume()
    return source
}

DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(options.seconds)) { finish(0) }

let workspaceCenter = NSWorkspace.shared.notificationCenter
let resignObserver = workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
    print("Session resigned active: pausing.")
    controller.setPaused(true)
}
let becomeObserver = workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
    print("Session became active: resuming.")
    controller.setPaused(false)
}
if ConsoleSession.isActive() == false {
    print("Started in an inactive session: paused until it becomes active.")
    controller.setPaused(true)
}

// Run the main run loop (not just the main queue) so NSWorkspace session
// notifications are delivered.
withExtendedLifetime((signalSources, resignObserver, becomeObserver)) {
    RunLoop.main.run()
}
