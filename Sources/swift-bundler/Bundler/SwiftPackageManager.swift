import Foundation
import ArgumentParser

/// A utility for interacting with the Swift package manager and performing some other package related operations.
enum SwiftPackageManager {
  /// The path to the swift executable.
  static let swiftExecutable = "/usr/bin/swift"

  /// A Swift build configuration.
  enum BuildConfiguration: String, CaseIterable {
    case debug
    case release
  }

  /// An architecture to build for.
  enum Architecture: String, CaseIterable, ExpressibleByArgument {
    case x86_64 // swiftlint:disable:this identifier_name
    case arm64

    #if arch(x86_64)
    static let current: Architecture = .x86_64
    #elseif arch(arm64)
    static let current: Architecture = .arm64
    #endif

    var defaultValueDescription: String {
      rawValue
    }
  }

  /// Creates a new package using the given directory as the package's root directory.
  /// - Parameters:
  ///   - directory: The package's root directory (will be created if it doesn't exist).
  ///   - name: The name for the package.
  /// - Returns: If an error occurs, a failure is returned.
  static func createPackage(
    in directory: URL,
    name: String
  ) -> Result<Void, SwiftPackageManagerError> {
    // Create the package directory if it doesn't exist
    let createPackageDirectory: () -> Result<Void, SwiftPackageManagerError> = {
      if !FileManager.default.itemExists(at: directory, withType: .directory) {
        do {
          try FileManager.default.createDirectory(at: directory)
        } catch {
          return .failure(.failedToCreatePackageDirectory(directory, error))
        }
      }
      return .success()
    }

    // Run the init command
    let runInitCommand: () -> Result<Void, SwiftPackageManagerError> = {
      let arguments = [
        "package", "init",
        "--type=executable",
        "--name=\(name)"
      ]

      let process = Process.create(
        Self.swiftExecutable,
        arguments: arguments,
        directory: directory)
      process.setOutputPipe(Pipe())

      return process.runAndWait()
        .mapError { error in
          .failedToRunSwiftInit(command: "\(Self.swiftExecutable) \(arguments.joined(separator: " "))", error)
        }
    }

    // Create the configuration file
    let createConfigurationFile: () -> Result<Void, SwiftPackageManagerError> = {
      Configuration.createConfigurationFile(in: directory, app: name, product: name)
        .mapError { error in
          .failedToCreateConfigurationFile(error)
        }
    }

    // Compose the function
    let create = flatten(
      createPackageDirectory,
      runInitCommand,
      createConfigurationFile)

    return create()
  }

  /// Builds the specified product of a Swift package.
  /// - Parameters:
  ///   - product: The product to build.
  ///   - packageDirectory: The root directory of the package containing the product.
  ///   - configuration: The build configuration to use.
  ///   - architectures: The set of architectures to build for.
  /// - Returns: If an error occurs, returns a failure.
  static func build(
    product: String,
    packageDirectory: URL,
    configuration: SwiftPackageManager.BuildConfiguration,
    architectures: [Architecture]
  ) -> Result<Void, SwiftPackageManagerError> {
    log.info("Starting \(configuration.rawValue) build")

    let arguments = [
      "build",
      "-c", configuration.rawValue,
      "--product", product
    ] + architectures.flatMap {
      ["--arch", $0.rawValue]
    }

    let process = Process.create(
      Self.swiftExecutable,
      arguments: arguments,
      directory: packageDirectory)

    return process.runAndWait()
      .mapError { error in
        .failedToRunSwiftBuild(command: "\(Self.swiftExecutable) \(arguments.joined(separator: " "))", error)
      }
  }

  /// Gets the device's target triple.
  /// - Returns: The device's target triple. If an error occurs, a failure is returned.
  static func getSwiftTargetTriple() -> Result<String, SwiftPackageManagerError> {
    let process = Process.create(
      "/usr/bin/swift",
      arguments: ["-print-target-info"])

    return process.getOutputData()
      .mapError { error in
        .failedToGetTargetTriple(error)
      }
      .flatMap { output in
        let object: Any
        do {
          object = try JSONSerialization.jsonObject(
            with: output,
            options: [])
        } catch {
          return .failure(.failedToDeserializeTargetInfo(error))
        }

        guard
          let dictionary = object as? [String: Any],
          let targetDictionary = dictionary["target"] as? [String: Any],
          let unversionedTriple = targetDictionary["unversionedTriple"] as? String
        else {
          return .failure(.invalidTargetInfoJSONFormat)
        }

        return .success(unversionedTriple)
      }
  }

  /// Gets the default products directory for the specified package and configuration.
  /// - Parameters:
  ///   - packageDirectory: The package's root directory.
  ///   - buildConfiguration: The current build configuration.
  ///   - architectures: The architectures that the build was for.
  /// - Returns: The default products directory. If ``getSwiftTargetTriple()`` fails, a failure is returned.
  static func getProductsDirectory(
    in packageDirectory: URL,
    buildConfiguration: BuildConfiguration,
    architectures: [Architecture]
  ) -> Result<URL, SwiftPackageManagerError> {
    if architectures.count == 1 {
      let architecture = architectures[0]
      return getSwiftTargetTriple()
        .map { targetTriple in
          let targetTriple = targetTriple.replacingOccurrences(of: Architecture.current.rawValue, with: architecture.rawValue)
          return packageDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent(targetTriple)
            .appendingPathComponent(buildConfiguration.rawValue)
        }
    } else {
      return .success(packageDirectory
        .appendingPathComponent(".build/apple/Products")
        .appendingPathComponent(buildConfiguration.rawValue.capitalized))
    }
  }
}
