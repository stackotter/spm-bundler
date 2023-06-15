import Foundation
import ArgumentParser
import Version
import Parsing

import class PackageModel.Manifest
import class Workspace.Workspace
import struct TSCBasic.AbsolutePath
import class Basics.ObservabilitySystem
import struct Basics.Diagnostic

/// A utility for interacting with the Swift package manager and performing some other package
/// related operations.
enum SwiftPackageManager {
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
        "swift",
        arguments: arguments,
        directory: directory)
      process.setOutputPipe(Pipe())

      return process.runAndWait()
        .mapError { error in
          .failedToRunSwiftInit(
            command: "swift \(arguments.joined(separator: " "))",
            error
          )
        }
    }

    // Create the configuration file
    let createConfigurationFile: () -> Result<Void, SwiftPackageManagerError> = {
      PackageConfiguration.createConfigurationFile(in: directory, app: name, product: name)
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
  ///   - platform: The platform to build for.
  ///   - platformVersion: The platform version to build for.
  /// - Returns: If an error occurs, returns a failure.
  static func build(
    product: String,
    packageDirectory: URL,
    configuration: BuildConfiguration,
    architectures: [BuildArchitecture],
    platform: Platform,
    platformVersion: String
  ) -> Result<Void, SwiftPackageManagerError> {
    log.info("Starting \(configuration.rawValue) build")

    return createBuildArguments(
      product: product,
      configuration: configuration,
      architectures: architectures,
      platform: platform,
      platformVersion: platformVersion
    ).flatMap { arguments in
      let process = Process.create(
        "swift",
        arguments: arguments,
        directory: packageDirectory,
        runSilentlyWhenNotVerbose: false
      )

      return process.runAndWait().mapError { error in
        return .failedToRunSwiftBuild(
          command: "swift \(arguments.joined(separator: " "))",
          error
        )
      }
    }
  }

  /// Creates the arguments for the Swift build command.
  /// - Parameters:
  ///   - product: The product to build.
  ///   - configuration: The build configuration to use.
  ///   - architectures: The architectures to build for.
  ///   - platform: The platform to build for.
  ///   - platformVersion: The platform version to target.
  /// - Returns: The build arguments, or a failure if an error occurs.
  static func createBuildArguments(
    product: String?,
    configuration: BuildConfiguration,
    architectures: [BuildArchitecture],
    platform: Platform,
    platformVersion: String
  ) -> Result<[String], SwiftPackageManagerError> {
    let platformArguments: [String]
    switch platform {
      case .iOS:
        let sdkPath: String
        switch getLatestSDKPath(for: platform) {
          case .success(let path):
            sdkPath = path
          case .failure(let error):
            return .failure(error)
        }

        let targetTriple = "arm64-apple-ios\(platformVersion)"
        platformArguments = [
          "-sdk", sdkPath,
          "-target", targetTriple
        ].flatMap { ["-Xswiftc", $0] } + [
          "--target=\(targetTriple)",
          "-isysroot", sdkPath
        ].flatMap { ["-Xcc", $0] }
      case .iOSSimulator:
        let sdkPath: String
        switch getLatestSDKPath(for: platform) {
          case .success(let path):
            sdkPath = path
          case .failure(let error):
            return .failure(error)
        }

        // TODO: Make target triple generation generic
        let architecture = BuildArchitecture.current.rawValue
        let targetTriple = "\(architecture)-apple-ios\(platformVersion)-simulator"
        platformArguments = [
          "-sdk", sdkPath,
          "-target", targetTriple
        ].flatMap { ["-Xswiftc", $0] } + [
          "--target=\(targetTriple)",
          "-isysroot", sdkPath
        ].flatMap { ["-Xcc", $0] }
      case .macOS:
        platformArguments = []
    }

    let architectureArguments = architectures.flatMap {
      ["--arch", $0.rawValue]
    }

    let productArguments: [String]
    if let product = product {
      productArguments = ["--product", product]
    } else {
      productArguments = []
    }

    let arguments = [
      "build",
      "-c", configuration.rawValue
    ] + productArguments + architectureArguments + platformArguments

    return .success(arguments)
  }

  /// Gets the path to the latest SDK for a given platform.
  /// - Parameter platform: The platform to get the SDK path for.
  /// - Returns: The SDK's path, or a failure if an error occurs.
  static func getLatestSDKPath(for platform: Platform) -> Result<String, SwiftPackageManagerError> {
    return Process.create(
      "/usr/bin/xcrun",
      arguments: [
        "--sdk", platform.sdkName,
        "--show-sdk-path"
      ]
    ).getOutput().map { output in
      return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }.mapError { error in
      return .failedToGetLatestSDKPath(platform, error)
    }
  }

  /// Gets the version of the current Swift installation.
  /// - Returns: The swift version, or a failure if an error occurs.
  static func getSwiftVersion() -> Result<Version, SwiftPackageManagerError> {
    let process = Process.create(
      "swift",
      arguments: ["--version"])

    return process.getOutput()
      .mapError { error in
        .failedToGetSwiftVersion(error)
      }
      .flatMap { output in
        // The first two examples are for release versions of Swift (the first on macOS, the second on Linux).
        // The next two examples are for snapshot versions of Swift (the first on macOS, the second on Linux).
        // Sample: "swift-driver version: 1.45.2 Apple Swift version 5.6 (swiftlang-5.6.0.323.62 clang-1316.0.20.8)"
        //     OR: "swift-driver version: 1.45.2 Swift version 5.6 (swiftlang-5.6.0.323.62 clang-1316.0.20.8)"
        //     OR: "Apple Swift version 5.9-dev (LLVM 464b04eb9b157e3, Swift 7203d52cb1e074d)"
        //     OR: "Swift version 5.9-dev (LLVM 464b04eb9b157e3, Swift 7203d52cb1e074d)"
        let parser = OneOf {
          Parse {
            "swift-driver version"
            Prefix { $0 != "(" }
            "(swiftlang-"
            Parse({ Version(major: $0, minor: $1, patch: $2) }) {
              Int.parser(of: Substring.self, radix: 10)
              "."
              Int.parser(of: Substring.self, radix: 10)
              "."
              Int.parser(of: Substring.self, radix: 10)
            }
            Rest<Substring>()
          }.map { (_: Substring, version: Version, _: Substring) in
            version
          }

          Parse {
            Optionally {
              "Apple "
            }
            "Swift version "
            Parse({ Version(major: $0, minor: $1, patch: 0) }) {
              Int.parser(of: Substring.self, radix: 10)
              "."
              Int.parser(of: Substring.self, radix: 10)
            }
            Rest<Substring>()
          }.map { (_: Void?, version: Version, _: Substring) in
            version
          }
        }

        do {
          let version = try parser.parse(output)
          return .success(version)
        } catch {
          return .failure(.invalidSwiftVersionOutput(output, error))
        }
      }
  }

  /// Gets the default products directory for the specified package and configuration.
  /// - Parameters:
  ///   - packageDirectory: The package's root directory.
  ///   - configuration: The current build configuration.
  ///   - architectures: The architectures that the build was for.
  ///   - platform: The platform that was built for.
  ///   - platformVersion: The platform version that was built for.
  /// - Returns: The default products directory. If `swift build --show-bin-path ... # extra args`
  ///   fails, a failure is returned.
  static func getProductsDirectory(
    in packageDirectory: URL,
    configuration: BuildConfiguration,
    architectures: [BuildArchitecture],
    platform: Platform,
    platformVersion: String
  ) -> Result<URL, SwiftPackageManagerError> {
    return createBuildArguments(
      product: nil,
      configuration: configuration,
      architectures: architectures,
      platform: platform,
      platformVersion: platformVersion
    ).flatMap { arguments in
      let process = Process.create(
        "swift",
        arguments: arguments + ["--show-bin-path"],
        directory: packageDirectory
      )

      return process.getOutput().flatMap { output in
        let path = output.trimmingCharacters(in: .newlines)
        return .success(URL(fileURLWithPath: path))
      }.mapError { error in
        let command = "swift " + arguments.joined(separator: " ")
        return .failedToGetProductsDirectory(command: command, error)
      }
    }
  }

  /// Loads a root package manifest from a package's root directory.
  /// - Parameter packageDirectory: The package's root directory.
  /// - Returns: The loaded manifest, or a failure if an error occurs.
  static func loadPackageManifest(
    from packageDirectory: URL
  ) async -> Result<Manifest, SwiftPackageManagerError> {
    let diagnostics: Box<[Basics.Diagnostic]> = Box([])
    let result: Result<Manifest, Error>
    do {
      let packagePath = try AbsolutePath(validating: packageDirectory.path)
      let scope = ObservabilitySystem({ _, diagnostic in
        diagnostics.wrapped.append(diagnostic)
      }).topScope

      let workspace = try Workspace(forRootPackage: packagePath)
      result = await Task { () -> Manifest in
        return try await withCheckedThrowingContinuation { (
          continuation: CheckedContinuation<Manifest, Error>
        ) in
          workspace.loadRootManifest(
            at: packagePath,
            observabilityScope: scope,
            completion: { result in
              switch result {
                case .success(let value):
                  continuation.resume(returning: value)
                case .failure(let error):
                  continuation.resume(throwing: error)
              }
            }
          )
        }
      }.result
    } catch {
      return .failure(.failedToLoadPackageManifest(directory: packageDirectory, [], error))
    }

    return result.mapError { error in
      return .failedToLoadPackageManifest(directory: packageDirectory, diagnostics.wrapped, error)
    }
  }
}
