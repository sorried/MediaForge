import Foundation
import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct ProcessOutput: Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public struct ProcessRunner: Sendable {
    public init() {}
    public func run(executable: URL, arguments: [String], timeout: TimeInterval? = 30, captureStdout: Bool = true, stdoutChunk: (@Sendable (Data) -> Void)? = nil) async throws -> ProcessOutput {
        try Task.checkCancellation()
        guard executable.isFileURL else { throw MediaForgeError.fileOperation("Executable must be a local file URL.") }
        if let timeout, !timeout.isFinite || timeout <= 0 || timeout > 31_536_000 {
            throw MediaForgeError.invalidSettings("Process deadline must be finite, positive and no longer than one year.")
        }
        let execution = ProcessExecution(executable: executable, arguments: arguments, captureStdout: captureStdout, stdoutChunk: stdoutChunk)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { execution.run(continuation) }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { execution.expire() }
                }
            }
        }, onCancel: { execution.cancel() })
    }
}

// Process lifecycle flags and signalling are serialized by lock; drain buffers have separate locks.
private final class ProcessExecution: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false
    private var started = false
    private var finished = false
    private let stdoutChunk: (@Sendable (Data) -> Void)?
    private let captureStdout: Bool
    init(executable: URL, arguments: [String], captureStdout: Bool, stdoutChunk: (@Sendable (Data) -> Void)?) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        self.stdoutChunk = stdoutChunk
        self.captureStdout = captureStdout
    }
    func expire() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        timedOut = true
        lock.unlock()
        cancel()
    }
    func cancel() {
        lock.lock()
        cancelled = true
        if started && !finished && process.isRunning { process.terminate() }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(750)) { [self] in
            lock.lock()
            if started && !finished && process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            lock.unlock()
        }
    }
    func run(_ continuation: CheckedContinuation<ProcessOutput, Error>) {
        let outputPipe = Pipe(), errorPipe = Pipe()
        process.standardOutput = outputPipe; process.standardError = errorPipe
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        do { try process.run(); started = true; lock.unlock() }
        catch { lock.unlock(); continuation.resume(throwing: error); return }
        let drainGroup = DispatchGroup()
        let output = ByteBuffer(), errors = ByteBuffer()
        for (pipe, buffer, callback) in [(outputPipe, output, stdoutChunk), (errorPipe, errors, nil)] {
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { drainGroup.leave(); try? pipe.fileHandleForReading.close() }
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    if pipe === errorPipe || self.captureStdout { buffer.append(chunk) }
                    callback?(chunk)
                }
            }
        }
        process.waitUntilExit()
        lock.lock()
        finished = true
        let wasCancelled = cancelled
        let didTimeOut = timedOut
        lock.unlock()
        drainGroup.wait()
        if didTimeOut { continuation.resume(throwing: MediaForgeError.processFailed(-1, "Process exceeded its time limit.")) }
        else if wasCancelled { continuation.resume(throwing: CancellationError()) }
        else if output.overflowed && captureStdout { continuation.resume(throwing: MediaForgeError.processFailed(-1, "Standard output exceeded the 8 MiB capture limit.")) }
        else { continuation.resume(returning: ProcessOutput(exitCode: process.terminationStatus, stdout: output.bytes, stderr: errors.bytes)) }
    }
}

private final class ByteBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private var exceededLimit = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(chunk)
        // Keep diagnostics bounded while continuing to drain both pipes.
        if storage.count > 8 * 1024 * 1024 {
            exceededLimit = true
            storage.removeFirst(storage.count - 8 * 1024 * 1024)
        }
    }
    var overflowed: Bool { lock.lock(); defer { lock.unlock() }; return exceededLimit }
    var bytes: Data { lock.lock(); defer { lock.unlock() }; return storage }
}
