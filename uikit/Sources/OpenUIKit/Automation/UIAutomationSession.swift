// Headless automation of a running app. Owner: automation module
// (docs/AUTOMATION.md).
//
// A session rides an application host loop (SwiftUI's `App` loop calls
// `OpenUIKitRuntime.hostTurnHook` once per turn) and drives the app the way
// `stupidsim` drives the iOS Simulator: taps, swipes, typed text and keys
// in normalized screen coordinates, then a screenshot and the accessibility
// tree (UIAutomationTree) to read back. Input goes through the ordinary
// event path — `UIWindow.sendTouch` (hit testing, gesture recognizers,
// scroll physics, the software keyboard window), `sendText`, `sendKey` —
// on the host loop's own clock, one touch phase per turn, as a finger on a
// device produces them.
//
// After every input the session runs turns until the app settles: the
// frame fingerprint (`_UIKeyboardChrome._hostFrameFingerprint`, everything
// the next frame would draw) is unchanged for `settleStableTurns`
// consecutive turns and no scroll deceleration, navigation transition,
// sheet spring or UIView animation is in flight. It fails loudly when that
// does not happen within `settleTimeoutTurns`.
//
// Commands come from a script (one per line, run in order, the session
// ends after the last) or from a control directory (live mode): a client
// publishes `<dir>/request` by renaming a complete file into place, the
// session executes it and publishes `<dir>/response` the same way —
// `exit <code>` on the first line, the command's output after it.

import CPortableIO

extension OpenUIKitRuntime {
    /// Called by an application host loop once per turn, after the main
    /// queue drained and the windows ticked, with the turn's host-clock
    /// time. Returning false ends the loop: the app terminates as it does at
    /// a bounded turn count. With a hook installed the SwiftUI `App` loop
    /// needs no `OPENUIKIT_HOST_TURNS` bound. Installed by
    /// `UIAutomationSession.install()`; nil (the default) changes nothing.
    public static var hostTurnHook: (@MainActor (Double) -> Bool)?
}

/// One automation step. The text forms (`UIAutomationCommand.parse`) are
/// the script syntax and the live control protocol.
public enum UIAutomationCommand: Equatable {
    /// `wait <turns>`: run this many host turns.
    case wait(turns: Int)
    /// `wait idle`: run turns until the app settles.
    case waitIdle
    /// `wait <n>s` / `wait <n>ms`: run turns until this much host-clock
    /// time has passed (screens that never settle, such as a story whose
    /// progress timer runs, are captured at a time after the input).
    case waitTime(seconds: Double)
    /// `tap <x> <y> [--hold-milliseconds 90] [--verify] [--no-settle]`.
    /// `--no-settle` ends the command once the finger lifts, as
    /// `stupidsim tap` returns, instead of waiting for the app to settle.
    case tap(x: Double, y: Double, holdMilliseconds: Double, verify: Bool, settle: Bool = true)
    /// `swipe <x1> <y1> <x2> <y2> [<duration-ms>] [--steps 16] [--verify]
    /// [--no-settle]`.
    case swipe(fromX: Double, fromY: Double, toX: Double, toY: Double,
               durationMilliseconds: Double, steps: Int, verify: Bool, settle: Bool = true)
    /// `type [--verify] <text…>`: the rest of the line, one character per
    /// 25 ms, to the focused text input.
    case type(text: String, verify: Bool)
    /// `key <name>… [--repeat N] [--verify]`: backspace (delete), return
    /// (enter), left, right, up, down, space, tab, or a single character.
    case key(names: [String], repeatCount: Int, verify: Bool)
    /// `snapshot <name>`: `<name>.png`, `<name>.tree.txt`, `<name>.tree.json`.
    case snapshot(name: String)
    /// `screenshot <path>` (or `-o <path>`): a PNG at the session scale.
    case screenshot(path: String)
    /// `ui-tree [--json] [--labelled] [-o <path>]`.
    case uiTree(json: Bool, labelled: Bool, path: String?)
    /// `quit`: end the session (and the app).
    case quit

    public struct ParseError: Error, Equatable {
        public let message: String
    }

    /// Parse one line. Blank lines and `#` comments are nil.
    public static func parse(_ line: String) throws -> UIAutomationCommand? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let verb = words[0]
        var arguments = Array(words.dropFirst())

        func fail(_ message: String) -> ParseError { ParseError(message: "\(verb): \(message)") }
        func flag(_ name: String) -> Bool {
            guard let index = arguments.firstIndex(of: name) else { return false }
            arguments.remove(at: index)
            return true
        }
        func option(_ names: String...) throws -> String? {
            guard let index = arguments.firstIndex(where: { names.contains($0) }) else { return nil }
            guard index + 1 < arguments.count else { throw fail("\(arguments[index]) needs a value") }
            let value = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
            return value
        }
        func number(_ text: String, _ what: String) throws -> Double {
            guard let value = Double(text), value.isFinite else { throw fail("\(what) must be a number, got \(text)") }
            return value
        }
        func coordinate(_ text: String, _ what: String) throws -> Double {
            let value = try number(text, what)
            guard (0...1).contains(value) else { throw fail("\(what) must be between 0 and 1, got \(text)") }
            return value
        }
        func noneLeft() throws {
            if !arguments.isEmpty { throw fail("unexpected \(arguments.joined(separator: " "))") }
        }

        switch verb {
        case "wait":
            guard arguments.count == 1 else { throw fail("takes a turn count, idle, or a time (2s, 500ms)") }
            if arguments[0] == "idle" { return .waitIdle }
            for (suffix, unit) in [("ms", 0.001), ("s", 1.0)] where arguments[0].hasSuffix(suffix) {
                guard let value = Double(arguments[0].dropLast(suffix.count)), value > 0, value.isFinite else {
                    throw fail("time must be a positive number of s or ms")
                }
                return .waitTime(seconds: value * unit)
            }
            guard let turns = Int(arguments[0]), turns > 0 else { throw fail("turn count must be a positive integer") }
            return .wait(turns: turns)
        case "tap":
            let verify = flag("--verify")
            let settle = !flag("--no-settle")
            if verify, !settle { throw fail("--verify compares the settled screen; it cannot be combined with --no-settle") }
            let hold = try option("--hold-milliseconds", "--hold").map { try number($0, "hold") } ?? 90
            var x = try option("--x")
            var y = try option("--y")
            if x == nil, y == nil, arguments.count >= 2 {
                x = arguments.removeFirst()
                y = arguments.removeFirst()
            }
            guard let x, let y else { throw fail("takes <x> <y>") }
            try noneLeft()
            guard hold >= 0 else { throw fail("hold must not be negative") }
            return .tap(x: try coordinate(x, "x"), y: try coordinate(y, "y"), holdMilliseconds: hold, verify: verify,
                        settle: settle)
        case "swipe":
            let verify = flag("--verify")
            let settle = !flag("--no-settle")
            if verify, !settle { throw fail("--verify compares the settled screen; it cannot be combined with --no-settle") }
            let steps = try option("--steps").map { text -> Int in
                guard let steps = Int(text), steps > 0 else { throw fail("--steps must be a positive integer") }
                return steps
            } ?? 16
            let stepMilliseconds = try option("--step-milliseconds").map { try number($0, "step milliseconds") }
            var points = [try option("--from-x"), try option("--from-y"), try option("--to-x"), try option("--to-y")]
            if points.allSatisfy({ $0 == nil }), arguments.count >= 4 {
                points = (0..<4).map { _ in arguments.removeFirst() }
            }
            guard points.allSatisfy({ $0 != nil }) else { throw fail("takes <x1> <y1> <x2> <y2> [duration-ms]") }
            var duration = Double(steps) * (stepMilliseconds ?? 12)
            if let text = arguments.first {
                guard stepMilliseconds == nil else { throw fail("give a duration or --step-milliseconds, not both") }
                duration = try number(text, "duration")
                arguments.removeFirst()
            }
            try noneLeft()
            guard duration > 0 else { throw fail("duration must be positive") }
            let values = try zip(points, ["x1", "y1", "x2", "y2"]).map { try coordinate($0.0!, $0.1) }
            return .swipe(fromX: values[0], fromY: values[1], toX: values[2], toY: values[3],
                          durationMilliseconds: duration, steps: steps, verify: verify, settle: settle)
        case "type":
            // The text is the rest of the line, verbatim after one separator.
            var rest = trimmed.dropFirst(verb.count)
            if rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
            var verify = false
            if rest.hasPrefix("--verify ") || rest == "--verify" {
                verify = true
                rest = rest.dropFirst("--verify".count)
                if rest.first == " " { rest = rest.dropFirst() }
            }
            guard !rest.isEmpty else { throw fail("takes the text to type") }
            return .type(text: String(rest), verify: verify)
        case "key":
            let verify = flag("--verify")
            let repeatCount = try option("--repeat").map { text -> Int in
                guard let count = Int(text), count > 0 else { throw fail("--repeat must be a positive integer") }
                return count
            } ?? 1
            guard !arguments.isEmpty else { throw fail("takes key names") }
            for name in arguments where UIAutomationSession.keyStroke(named: name) == nil {
                throw fail("unsupported key \(name) (backspace, delete, return, enter, left, right, up, down, space, tab or one character)")
            }
            return .key(names: arguments, repeatCount: repeatCount, verify: verify)
        case "snapshot":
            guard arguments.count == 1 else { throw fail("takes one name") }
            return .snapshot(name: arguments[0])
        case "screenshot":
            let path = try option("-o", "--output") ?? arguments.first.map { _ in arguments.removeFirst() }
            try noneLeft()
            guard let path else { throw fail("takes an output path") }
            return .screenshot(path: path)
        case "ui-tree":
            let json = flag("--json")
            let labelled = flag("--labelled")
            let path = try option("-o", "--output")
            try noneLeft()
            return .uiTree(json: json, labelled: labelled, path: path)
        case "quit":
            try noneLeft()
            return .quit
        default:
            throw ParseError(message: "unknown command \(verb) (wait, tap, swipe, type, key, snapshot, screenshot, ui-tree, quit)")
        }
    }
}

@preconcurrency @MainActor
public final class UIAutomationSession {
    public enum Source {
        /// Lines of a script, run in order; the session ends after the last.
        case script([String])
        /// Live mode: requests published in this directory.
        case controlDirectory(String)
    }

    public struct Configuration {
        /// Where `snapshot <name>` writes (relative names resolve here).
        public var outputDirectory: String
        /// Screenshot backing scale (the device's, for comparisons).
        public var scale: CGFloat = 2
        /// The Application element's label (iOS: the display name).
        public var applicationLabel: String?
        /// Host turns before the first command (launch work, first layout).
        public var startupTurns = 120
        /// Consecutive unchanged, animation-free turns that count as settled.
        public var settleStableTurns = 12
        /// Turns after which settling fails loudly (~15 s at 60 Hz).
        public var settleTimeoutTurns = 900
        /// `--verify` compares frames rendered at this scale.
        public var verifyScale: CGFloat = 1
        /// Runs once on the first turn, before anything else (for example a
        /// host's screenshot status bar).
        public var prepare: (@MainActor (UIWindow) -> Void)?
        /// Also called for `snapshot <name>` with the output path minus
        /// extension (a host's own diagnostic dumps).
        public var snapshotExtras: (@MainActor (UIWindow, String) -> Void)?
        public var log: @MainActor (String) -> Void = { message in cpio_log_stderr(message) }
        /// Log which views differ between unsettled turns (debugging an app
        /// that never settles).
        public var diagnoseSettling = false
        /// Log each touch phase: the view it hit and its recognizers' states
        /// (debugging an input that has no effect).
        public var diagnoseInput = false

        public init(outputDirectory: String) {
            self.outputDirectory = outputDirectory
        }
    }

    /// Exit codes, as `stupidsim` uses them for --verify.
    public enum ExitCode {
        public static let ok: Int32 = 0
        public static let failed: Int32 = 1
        /// --verify: the screen did not change.
        public static let unchanged: Int32 = 2
        /// --verify: the screen was already changing too much to tell.
        public static let alreadyChanging: Int32 = 3
        /// The app did not settle after the input.
        public static let unsettled: Int32 = 4
    }

    public let source: Source
    public let configuration: Configuration
    /// The script's result: 0, or the code of the step that failed.
    public private(set) var exitCode: Int32 = ExitCode.ok

    public init(source: Source, configuration: Configuration) {
        self.source = source
        self.configuration = configuration
        if case .script(let lines) = source { scriptLines = lines }
    }

    /// Hand the session to the host loop. It also holds the caret solid, so
    /// frames (and settling) do not depend on where the blink cycle is.
    public func install() {
        precondition(OpenUIKitRuntime.hostTurnHook == nil, "an automation session is already installed")
        UITextInputState.solidHold = .infinity
        OpenUIKitRuntime.hostTurnHook = { [self] time in turn(at: time) }
    }

    // MARK: - State

    private var scriptLines: [String] = []
    private var scriptIndex = 0
    private var turns = 0
    private var window: UIWindow?
    private var phase: Phase = .startup
    private var finished = false

    private enum Phase {
        case startup
        case idle
        case waiting(remaining: Int)
        case waitingUntil(Double?, seconds: Double)
        case settling(Settle)
        case input(Input)
    }

    private enum SettlePurpose {
        case startup
        case command
        /// Before a --verify input: the input starts once settled.
        case beforeVerify(Input)
        case afterInput(before: Bitmap?)
    }

    private struct Settle {
        var purpose: SettlePurpose
        var fingerprint: UInt64?
        var stable = 0
        var spent = 0
        /// Why the last unsettled turn was unsettled (for the timeout message).
        var reason = ""
        var frameChanges = 0
    }

    fileprivate enum Event {
        case touch(UITouch.Phase, CGPoint)
        case text(String)
        case key(UIKeyEventKey)
    }

    private struct Input {
        var name: String
        var events: [(offset: Double, event: Event)]
        var start: Double?
        var next = 0
        var verify: Bool
        var settle = true
    }

    /// The current request when live; nil for script steps.
    private var pendingResponse = false
    private var currentLine = ""

    // MARK: - The turn

    private func turn(at time: Double) -> Bool {
        turns += 1
        if window == nil {
            guard let window = UIApplication.shared.keyWindow ?? UIApplication.shared.windows.first else {
                return true
            }
            self.window = window
            configuration.prepare?(window)
            log("automation: started (\(sourceDescription))")
        }
        guard let window else { return true }

        switch phase {
        case .startup:
            if turns >= configuration.startupTurns {
                phase = .settling(Settle(purpose: .startup))
            }
        case .idle:
            nextCommand(window: window, time: time)
        case .waiting(let remaining):
            // A device commits layout every frame; without it a state change
            // made by an input (a SwiftUI presentation, a push) waited for
            // the next snapshot's layout (MEASURED: a story viewer cover
            // tapped with --no-settle only appeared at the snapshot after
            // `wait 2s`, two seconds late).
            window.layoutIfNeeded()
            if remaining <= 1 {
                finishCommand(ExitCode.ok, "")
            } else {
                phase = .waiting(remaining: remaining - 1)
            }
        case .waitingUntil(let start, let seconds):
            window.layoutIfNeeded()
            let begin = start ?? time
            if time - begin >= seconds {
                finishCommand(ExitCode.ok, "")
            } else {
                phase = .waitingUntil(begin, seconds: seconds)
            }
        case .settling(var settle):
            window.layoutIfNeeded()
            let fingerprint = Self.modelFingerprint(of: window)
            let busy = animating(at: time, window: window)
            if fingerprint == settle.fingerprint, busy == nil {
                settle.stable += 1
            } else {
                settle.stable = 0
                if fingerprint != settle.fingerprint, settle.fingerprint != nil { settle.frameChanges += 1 }
                settle.reason = busy ?? "the frame changed"
            }
            if configuration.diagnoseSettling { diagnose(window, turn: settle.spent) }
            settle.fingerprint = fingerprint
            settle.spent += 1
            if settle.stable >= configuration.settleStableTurns {
                settled(settle.purpose, window: window, time: time)
            } else if settle.spent >= configuration.settleTimeoutTurns {
                unsettled(settle)
            } else {
                phase = .settling(settle)
            }
        case .input(var input):
            window.layoutIfNeeded()
            if input.start == nil { input.start = time }
            deliver(&input, window: window, time: time)
            if input.next >= input.events.count {
                if !input.settle {
                    finishCommand(ExitCode.ok, "")
                } else if input.verify {
                    phase = .settling(Settle(purpose: .afterInput(before: verifyBefore)))
                } else {
                    phase = .settling(Settle(purpose: .afterInput(before: nil)))
                }
            } else {
                phase = .input(input)
            }
        }
        if finished {
            if case .controlDirectory(let directory) = source { _ = cpio_remove(directory + "/ready") }
            OpenUIKitRuntime.hostTurnHook = nil
            return false
        }
        return true
    }

    private var sourceDescription: String {
        switch source {
        case .script(let lines): return "script, \(lines.count) lines"
        case .controlDirectory(let directory): return "control directory \(directory)"
        }
    }

    /// What keeps the app from being settled this turn, or nil.
    private func animating(at time: Double, window: UIWindow) -> String? {
        if !window.activeTouches.isEmpty { return "a touch is down" }
        if UIScrollView._hasActiveScrollAnimations { return "a scroll view is decelerating or bouncing" }
        if UINavigationController._hasActiveTransition { return "a navigation transition is running" }
        if UIViewController._hasActiveSheetInteraction { return "a sheet is settling" }
        if UIView._hasPendingAnimationCompletions { return "UIView animation completions are pending" }
        if time <= OpenUIKitRuntime.animationWorkDeadline {
            return "animations run until t=\(OpenUIKitRuntime.animationWorkDeadline) (now \(time))"
        }
        return nil
    }

    private func settled(_ purpose: SettlePurpose, window: UIWindow, time: Double) {
        switch purpose {
        case .startup:
            log("automation: settled after launch (turn \(turns), t=\(Int(time)) s)")
            if case .controlDirectory(let directory) = source {
                _ = cpio_remove(directory + "/request")
                _ = cpio_remove(directory + "/response")
                write(Array("ready\n".utf8), to: directory + "/ready")
            }
            phase = .idle
        case .command:
            finishCommand(ExitCode.ok, "")
        case .beforeVerify(let input):
            verifyBefore = render(window, scale: configuration.verifyScale)
            phase = .input(input)
        case .afterInput(let before):
            guard let before else {
                finishCommand(ExitCode.ok, "")
                return
            }
            let after = render(window, scale: configuration.verifyScale)
            verifyBefore = nil
            if after.width == before.width, after.height == before.height, after.pixels == before.pixels {
                finishCommand(ExitCode.unchanged, "the screen did not change")
            } else {
                finishCommand(ExitCode.ok, "")
            }
        }
    }

    private var verifyBefore: Bitmap?

    /// What the window shows, by value: geometry, visibility, colours, text,
    /// images and content versions of every visible view, but not object
    /// identity. The SwiftUI layer rebuilds its UIViews on every layout pass,
    /// so a frame fingerprint keyed on layer identity
    /// (`_UIKeyboardChrome._hostFrameFingerprint`) never repeats for a
    /// SwiftUI screen even when nothing visible changed. Presentation-only
    /// animation progress is covered by `animating(at:window:)` instead.
    static func modelFingerprint(of window: UIWindow) -> UInt64 {
        var h = Hasher()
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.001 else {
                h.combine(0 as UInt8)
                return
            }
            h.combine(ObjectIdentifier(type(of: view)))
            let f = view.frame
            h.combine(f.minX); h.combine(f.minY); h.combine(f.width); h.combine(f.height)
            h.combine(view.bounds.minX); h.combine(view.bounds.minY)
            h.combine(view.alpha)
            let t = view.transform
            h.combine(t.a); h.combine(t.b); h.combine(t.c); h.combine(t.d); h.combine(t.tx); h.combine(t.ty)
            h.combine(view.contentVersion)
            if let color = view.backgroundColor?.resolvedCGColor(with: view.traitCollection) {
                h.combine(color.red); h.combine(color.green); h.combine(color.blue); h.combine(color.alpha)
            }
            switch view {
            case let label as UILabel:
                h.combine(label.text)
            case let field as UITextField:
                h.combine(field.text)
            case let textView as UITextView:
                h.combine(textView.text)
            case let imageView as UIImageView:
                if let image = imageView.image {
                    h.combine(image.size.width); h.combine(image.size.height)
                    h.combine(image._systemSymbolName)
                }
            case let control as UIControl:
                h.combine(control.isHighlighted); h.combine(control.isSelected); h.combine(control.isEnabled)
            default:
                break
            }
            h.combine(view.subviews.count)
            view.subviews.forEach(visit)
        }
        visit(window)
        h.combine(window.firstResponder.map { ObjectIdentifier($0) })
        return UInt64(bitPattern: Int64(h.finalize()))
    }
    private var lastSignatures: [String: String] = [:]

    /// Logs the views whose geometry or content changed since the
    /// previous call (configuration.diagnoseSettling).
    private func diagnose(_ window: UIWindow, turn: Int) {
        var signatures: [String: String] = [:]
        func visit(_ view: UIView, path: String) {
            var signature = "\(view.frame) \(view.bounds.origin) a=\(view.alpha) h=\(view.isHidden) v=\(view.contentVersion) t=\(view.transform)"
            if let label = view as? UILabel { signature += " text=\(label.text ?? "")" }
            signatures[path] = signature
            for (index, child) in view.subviews.enumerated() {
                visit(child, path: path + "/\(index):\(type(of: child))")
            }
        }
        visit(window, path: "window")
        if !lastSignatures.isEmpty {
            let changed = signatures.keys.filter { lastSignatures[$0] != signatures[$0] }.sorted()
            let removed = lastSignatures.keys.filter { signatures[$0] == nil }.count
            if !changed.isEmpty || removed > 0 {
                log("automation: settle turn \(turn): \(changed.count) views changed, \(removed) removed")
                for path in changed.prefix(6) {
                    log("  \(path)\n    was \(lastSignatures[path] ?? "-")\n    now \(signatures[path]!)")
                }
            }
        }
        lastSignatures = signatures
    }

    private func unsettled(_ settle: Settle) {
        let detail = "\(settle.reason); the frame changed on \(settle.frameChanges) of \(settle.spent) turns"
        let seconds = Double(configuration.settleTimeoutTurns) / 60
        switch settle.purpose {
        case .startup:
            log("FAIL: automation: the app did not settle within \(configuration.settleTimeoutTurns) turns (~\(Int(seconds)) s) after launch: \(detail)")
            exitCode = ExitCode.unsettled
            finished = true
        case .beforeVerify:
            finishCommand(ExitCode.alreadyChanging, "the screen was already changing too much to tell (not settled within \(configuration.settleTimeoutTurns) turns: \(detail))")
        case .command, .afterInput:
            verifyBefore = nil
            finishCommand(ExitCode.unsettled, "the app did not settle within \(configuration.settleTimeoutTurns) turns (~\(Int(seconds)) s): \(detail)")
        }
    }

    // MARK: - Commands

    private func nextCommand(window: UIWindow, time: Double) {
        let line: String
        switch source {
        case .script:
            guard scriptIndex < scriptLines.count else {
                log("automation: script finished")
                finished = true
                return
            }
            line = scriptLines[scriptIndex]
            scriptIndex += 1
        case .controlDirectory(let directory):
            let path = directory + "/request"
            guard let bytes = read(path) else { return }
            _ = cpio_remove(path)
            line = String(decoding: bytes, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            pendingResponse = true
        }
        currentLine = line
        let command: UIAutomationCommand
        do {
            guard let parsed = try UIAutomationCommand.parse(line) else {
                if pendingResponse { finishCommand(ExitCode.failed, "empty request") }
                return
            }
            command = parsed
        } catch let error as UIAutomationCommand.ParseError {
            finishCommand(ExitCode.failed, error.message)
            return
        } catch {
            finishCommand(ExitCode.failed, "\(error)")
            return
        }
        if case .script = source { log("automation: \(line)") }
        run(command, window: window, time: time)
    }

    private func run(_ command: UIAutomationCommand, window: UIWindow, time: Double) {
        let size = window.bounds.size
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: window.bounds.minX + CGFloat(x) * size.width, y: window.bounds.minY + CGFloat(y) * size.height)
        }
        switch command {
        case .wait(let count):
            phase = .waiting(remaining: count)
        case .waitIdle:
            phase = .settling(Settle(purpose: .command))
        case .waitTime(let seconds):
            phase = .waitingUntil(nil, seconds: seconds)
        case .tap(let x, let y, let hold, let verify, let settle):
            let at = point(x, y)
            begin(Input(name: "tap", events: [(0, .touch(.began, at)), (hold / 1000, .touch(.ended, at))], verify: verify,
                        settle: settle))
        case .swipe(let fromX, let fromY, let toX, let toY, let duration, let steps, let verify, let settle):
            let from = point(fromX, fromY)
            let to = point(toX, toY)
            var events: [(offset: Double, event: Event)] = [(0, .touch(.began, from))]
            for step in 1...steps {
                let f = CGFloat(step) / CGFloat(steps)
                let p = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
                events.append((duration / 1000 * Double(f), .touch(.moved, p)))
            }
            events.append((duration / 1000, .touch(.ended, to)))
            begin(Input(name: "swipe", events: events, verify: verify, settle: settle))
        case .type(let text, let verify):
            guard window.firstResponder is UIKeyInput else {
                finishCommand(ExitCode.failed, "type: nothing has keyboard focus (tap a text field first)")
                return
            }
            let events = text.enumerated().map { index, character in
                (offset: Double(index) * 0.025, event: Event.text(String(character)))
            }
            begin(Input(name: "type", events: events, verify: verify))
        case .key(let names, let repeatCount, let verify):
            guard window.firstResponder != nil else {
                finishCommand(ExitCode.failed, "key: nothing has keyboard focus (tap a text field first)")
                return
            }
            var events: [(offset: Double, event: Event)] = []
            for name in names {
                for _ in 0..<repeatCount {
                    events.append((Double(events.count) * 0.025, Self.keyStroke(named: name)!))
                }
            }
            begin(Input(name: "key", events: events, verify: verify))
        case .snapshot(let name):
            let base = name.hasPrefix("/") ? name : configuration.outputDirectory + "/" + name
            // The tree reads frames: lay out first, as the render does, so a
            // view positioned in layoutSubviews is where the PNG shows it.
            window.layoutIfNeeded()
            let tree = UIAutomationTree.snapshot(of: window, applicationLabel: configuration.applicationLabel)
            write(Array(UIAutomationTree.text(tree).utf8), to: base + ".tree.txt")
            write(Array(UIAutomationTree.json(tree).utf8), to: base + ".tree.json")
            write(render(window, scale: configuration.scale).pngData(), to: base + ".png")
            configuration.snapshotExtras?(window, base)
            finishCommand(ExitCode.ok, base + ".png\n")
        case .screenshot(let path):
            write(render(window, scale: configuration.scale).pngData(), to: path)
            finishCommand(ExitCode.ok, path + "\n")
        case .uiTree(let json, let labelled, let path):
            window.layoutIfNeeded()
            let tree = UIAutomationTree.snapshot(of: window, applicationLabel: configuration.applicationLabel)
            let text = json ? UIAutomationTree.json(tree) : UIAutomationTree.text(tree, labelled: labelled)
            if let path {
                write(Array(text.utf8), to: path)
                finishCommand(ExitCode.ok, path + "\n")
            } else {
                if case .script = source { log(text) }
                finishCommand(ExitCode.ok, text)
            }
        case .quit:
            finishCommand(ExitCode.ok, "")
            finished = true
        }
    }

    private func begin(_ input: Input) {
        if input.verify {
            phase = .settling(Settle(purpose: .beforeVerify(input)))
        } else {
            phase = .input(input)
        }
    }

    /// Delivers the input's due events, each stamped with its scheduled
    /// time (never earlier than the previous one), so a drag keeps its
    /// intermediate positions and velocity even when host turns are slow.
    /// A touch-down and a lift each end the turn they are delivered in (the
    /// lift waits for the next turn when moves came first), so the app lays
    /// out and the recognizers see time pass between phases, as on a device.
    private func deliver(_ input: inout Input, window: UIWindow, time: Double) {
        guard let start = input.start else { return }
        var deliveredThisTurn = 0
        while input.next < input.events.count, start + input.events[input.next].offset <= time {
            let event = input.events[input.next].event
            if case .touch(let phase, _) = event, phase == .ended || phase == .cancelled, deliveredThisTurn > 0 {
                return
            }
            let timestamp = Swift.min(time, Swift.max(lastEventTime, start + input.events[input.next].offset))
            lastEventTime = timestamp
            input.next += 1
            deliveredThisTurn += 1
            switch event {
            case .touch(let phase, let point):
                let touch = window.sendTouch(phase, at: point, timestamp: timestamp)
                if configuration.diagnoseInput {
                    let recognizers = (touch?.gestureRecognizers ?? []).map {
                        "\(type(of: $0))@\($0.view.map { "\(type(of: $0))" } ?? "-")=\($0.state)"
                    }
                    log("automation: touch \(phase) at \(point) t=\(timestamp) view=\(touch?.view.map { "\(type(of: $0))" } ?? "none") recognizers=\(recognizers)")
                }
                if phase != .moved { return }
            case .text(let text):
                window.sendText(text, timestamp: timestamp)
            case .key(let key):
                window.sendKey(key, timestamp: timestamp)
            }
        }
    }

    private var lastEventTime = -Double.infinity

    fileprivate static func keyStroke(named name: String) -> Event? {
        switch name.lowercased() {
        case "backspace", "delete": return .key(.backspace)
        case "return", "enter": return .key(.return)
        case "left": return .key(.left)
        case "right": return .key(.right)
        case "up": return .key(.up)
        case "down": return .key(.down)
        case "space": return .text(" ")
        case "tab": return .text("\t")
        default: return name.count == 1 ? .text(name) : nil
        }
    }

    private func finishCommand(_ code: Int32, _ output: String) {
        phase = .idle
        switch source {
        case .script:
            if code != ExitCode.ok {
                log("FAIL: automation: line \(scriptIndex) `\(currentLine)` exit \(code): \(output)")
                exitCode = code
                finished = true
            }
        case .controlDirectory(let directory):
            guard pendingResponse else { return }
            pendingResponse = false
            write(Array("exit \(code)\n\(output)".utf8), to: directory + "/response.tmp")
            guard cpio_rename(directory + "/response.tmp", directory + "/response") != 0 else {
                log("FAIL: automation: could not publish \(directory)/response")
                exitCode = ExitCode.failed
                finished = true
                return
            }
        }
    }

    // MARK: - I/O

    private func render(_ window: UIWindow, scale: CGFloat) -> Bitmap {
        window.layoutIfNeeded()
        return _UIKeyboardChrome.renderCapture(appWindow: window, scale: scale)
    }

    private func read(_ path: String) -> [UInt8]? {
        var size = 0
        guard let buffer = cpio_read_file(path, &size) else { return nil }
        defer { cpio_free(buffer) }
        return Array(UnsafeBufferPointer(start: buffer, count: size))
    }

    private func write(_ bytes: [UInt8], to path: String) {
        let ok = bytes.withUnsafeBufferPointer { cpio_write_file(path, $0.baseAddress, $0.count) != 0 }
        if !ok {
            log("FAIL: automation: could not write \(path)")
            exitCode = ExitCode.failed
            finished = true
        }
    }

    private func log(_ message: String) { configuration.log(message) }
}
