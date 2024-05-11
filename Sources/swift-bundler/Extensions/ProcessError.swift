import Foundation

/// An error returned by custom methods added to `Process`.
enum ProcessError: LocalizedError {
  case invalidUTF8Output(output: Data)
  case nonZeroExitStatus(Int)
  case nonZeroExitStatusWithOutput(Data, Int)
  case failedToRunProcess(Error)

  var errorDescription: String? {
    switch self {
      case .invalidUTF8Output:
        return "Command output was not valid utf-8 data"
      case .nonZeroExitStatus(let status):
        return "The process returned a non-zero exit status (\(status))"
      case .nonZeroExitStatusWithOutput(let data, let status):
        return
          "The process returned a non-zero exit status (\(status))\n\(String(data: data, encoding: .utf8) ?? "invalid utf8")"
      case .failedToRunProcess:
        return "The process failed to run"
    }
  }
}
