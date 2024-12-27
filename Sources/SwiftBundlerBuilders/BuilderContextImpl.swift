import Foundation

// TODO: Use `package` access level when we bump to Swift 5.9
/// Implementation detail, may have breaking changes from time to time.
/// "Hidden" from users to avoid exposing implementation details such as
/// the ``Codable`` conformance, since the builder API has to be pretty
/// much perfectly backwards compatible.
public struct _BuilderContextImpl: BuilderContext, Codable {
  public var buildDirectory: URL

  public init(buildDirectory: URL) {
    self.buildDirectory = buildDirectory
  }

  enum Error: LocalizedError {
    case nonZeroExitStatus(Int)
  }

  #if os(Linux)
    private func bashQuote(_ string: String) -> String {
      let escapedContents = string.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "$", with: "\\$")
        .replacingOccurrences(of: "`", with: "\\`")
      return "\"\(escapedContents)\""
    }
  #endif

  public func run(_ command: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments

    try process.run()
    process.waitUntilExit()

    let exitStatus = Int(process.terminationStatus)
    guard exitStatus == 0 else {
      throw Error.nonZeroExitStatus(exitStatus)
    }
  }
}
