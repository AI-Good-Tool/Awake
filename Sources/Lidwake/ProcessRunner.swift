import Darwin
import Foundation

struct ProcessExecutionResult: Sendable {
    var terminationStatus: Int32
    var output: String
}

enum ProcessRunnerError: LocalizedError {
    case unableToCreateOutputFile
    case timedOut(executable: String, seconds: TimeInterval)
    case unableToTerminate(executable: String)

    var errorDescription: String? {
        switch self {
        case .unableToCreateOutputFile:
            "无法创建命令输出临时文件。"
        case .timedOut(let executable, let seconds):
            "命令超时（\(Int(seconds)) 秒）：\(executable)"
        case .unableToTerminate(let executable):
            "超时后仍无法终止命令：\(executable)"
        }
    }
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessExecutionResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidwake-process-\(UUID().uuidString).log")
        let created = FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else { throw ProcessRunnerError.unableToCreateOutputFile }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var outputHandle: FileHandle? = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle?.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            waitForExit(process, timeout: 1)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                waitForExit(process, timeout: 1)
            }
            if process.isRunning {
                throw ProcessRunnerError.unableToTerminate(executable: executable)
            }
            throw ProcessRunnerError.timedOut(executable: executable, seconds: timeout)
        }

        try? outputHandle?.synchronize()
        try? outputHandle?.close()
        outputHandle = nil
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return ProcessExecutionResult(
            terminationStatus: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
