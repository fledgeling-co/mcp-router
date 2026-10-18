import Foundation
import Synchronization

/// How a stdio child ended, as `Process` reports it.
public enum ChildExit: Sendable, Equatable {
    /// It exited on its own with this status.
    case status(Int32)
    /// A signal stopped it. The number is the signal's, which is what `Process` reports and what
    /// the TypeScript router prints after mapping Node's name for it.
    case signal(Int32)

    init(_ process: Process) {
        self = process.terminationReason == .uncaughtSignal
            ? .signal(process.terminationStatus)
            : .status(process.terminationStatus)
    }

    /// The words both routers print after the upstream's name, so the two wires can be compared.
    var phrase: String {
        switch self {
        case let .status(code): "exited with status \(code)"
        case let .signal(number): "exited on signal \(number)"
        }
    }
}

/// A one-shot "the child exited" signal, awaited by any number of callers.
///
/// It carries how the child ended when there was a child to end. An HTTP session has no process, so
/// it fires the signal bare, and everything that awaits it treats the two the same.
final class EndSignal: Sendable {
    private struct State {
        var fired = false
        var exit: ChildExit?
        var waiters: [CheckedContinuation<ChildExit?, Never>] = []
    }

    private let state = Mutex(State())

    func fire(_ exit: ChildExit? = nil) {
        let waiting = state.withLock { current -> [CheckedContinuation<ChildExit?, Never>] in
            current.fired = true
            current.exit = exit
            let waiters = current.waiters
            current.waiters = []
            return waiters
        }
        for continuation in waiting {
            continuation.resume(returning: exit)
        }
    }

    /// Resolves once the signal has fired, with how the child ended if that was recorded.
    @discardableResult
    func wait() async -> ChildExit? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ChildExit?, Never>) in
            let ready = state.withLock { current -> (fired: Bool, exit: ChildExit?) in
                if current.fired { return (true, current.exit) }
                current.waiters.append(continuation)
                return (false, nil)
            }
            // Resumed outside the lock: resuming a continuation can run arbitrary code, and running
            // it while holding this mutex is how a deadlock gets built.
            if ready.fired { continuation.resume(returning: ready.exit) }
        }
    }
}
