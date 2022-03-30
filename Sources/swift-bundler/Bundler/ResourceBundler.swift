import Foundation

/// A utility for handling resource bundles.
enum ResourceBundler {
  /// Copies the resource bundles present in a source directory into a destination directory. If the bundles
  /// were built by SwiftPM, they will get fixed up to be consistent with bundles built by Xcode.
  /// - Parameters:
  ///   - sourceDirectory: The directory containing generated bundles.
  ///   - destinationDirectory: The directory to copy the bundles to, fixing them if required.
  ///   - fixBundles: If `false`, bundles will be left alone when copying them.
  ///   - minimumMacOSVersion: The minimum macOS version that the app should run on. Used to create the `Info.plist` for each bundle when `isXcodeBuild` is `false`.
  /// - Returns: If an error occurs, a failure is returned.
  static func copyResourceBundles(
    from sourceDirectory: URL,
    to destinationDirectory: URL,
    fixBundles: Bool,
    minimumMacOSVersion: String?
  ) -> Result<Void, ResourceBundlerError> {
    let contents: [URL]
    do {
      contents = try FileManager.default.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil, options: [])
    } catch {
      return .failure(.failedToEnumerateBundles(directory: sourceDirectory, error))
    }
    
    for file in contents where file.pathExtension == "bundle" {
      guard FileManager.default.itemExists(at: file, withType: .directory) else {
        continue
      }
      
      let result: Result<Void, ResourceBundlerError>
      if !fixBundles {
        result = copyResourceBundle(
          file,
          to: destinationDirectory)
      } else {
        result = fixAndCopyResourceBundle(
          file,
          to: destinationDirectory,
          minimumMacOSVersion: minimumMacOSVersion)
      }
      
      if case .failure(_) = result {
        return result
      }
    }
    
    return .success()
  }
  
  /// Copies the specified resource bundle into a destination directory.
  /// - Parameters:
  ///   - bundle: The bundle to copy.
  ///   - destination: The directory to copy the bundle to.
  /// - Returns: If an error occurs, a failure is returned.
  static func copyResourceBundle(_ bundle: URL, to destination: URL) -> Result<Void, ResourceBundlerError> {
    log.info("Copying resource bundle '\(bundle.lastPathComponent)'")
    
    let destinationBundle = destination.appendingPathComponent(bundle.lastPathComponent)
    
    do {
      try FileManager.default.copyItem(at: bundle, to: destinationBundle)
    } catch {
      return .failure(.failedToCopyBundle(source: bundle, destination: destinationBundle, error))
    }
    
    return .success()
  }
  
  /// Copies the specified resource bundle into a destination directory. Before copying, the bundle
  /// is fixed up to be consistent with bundles built by Xcode.
  ///
  /// Creates the proper bundle structure, adds an `Info.plist` and compiles any metal shaders present in the bundle.
  /// - Parameters:
  ///   - bundle: The bundle to fix and copy.
  ///   - destination: The directory to copy the bundle to.
  ///   - minimumMacOSVersion: The minimum macOS version that the app should run on. Used to created the bundle's `Info.plist`.
  /// - Returns: If an error occurs, a failure is returned.
  static func fixAndCopyResourceBundle(
    _ bundle: URL,
    to destination: URL,
    minimumMacOSVersion: String?
  ) -> Result<Void, ResourceBundlerError> {
    log.info("Fixing and copying resource bundle '\(bundle.lastPathComponent)'")
    
    let destinationBundle = destination.appendingPathComponent(bundle.lastPathComponent)
    let destinationBundleResources = destinationBundle
      .appendingPathComponent("Contents")
      .appendingPathComponent("Resources")
    
    // The bundle was generated by SwiftPM, so it's gonna need a bit of fixing
    let copyBundle = flatten(
      { createResourceBundleDirectoryStructure(at: destinationBundle) },
      { createResourceBundleInfoPlist(in: destinationBundle, minimumMacOSVersion: minimumMacOSVersion) },
      { copyResources(from: bundle, to: destinationBundleResources) },
      {
        MetalCompiler.compileMetalShaders(in: destinationBundleResources, keepSources: false)
          .mapError { error in
            .failedToCompileMetalShaders(error)
          }
      })
    
    return copyBundle()
  }
  
  // MARK: Private methods
  
  /// Creates the following structure for the specified resource bundle directory:
  ///
  /// - `Contents`
  ///   - `Info.plist`
  ///   - `Resources`
  /// - Parameter bundle: The bundle to create.
  /// - Returns: If an error occurs, a failure is returned.
  private static func createResourceBundleDirectoryStructure(at bundle: URL) -> Result<Void, ResourceBundlerError> {
    let bundleContents = bundle.appendingPathComponent("Contents")
    let bundleResources = bundleContents.appendingPathComponent("Resources")
    
    do {
      try FileManager.default.createDirectory(at: bundleResources)
    } catch {
      return .failure(.failedToCreateBundleDirectory(bundle, error))
    }
    
    return .success()
  }
  
  /// Creates the `Info.plist` file for a resource bundle.
  /// - Parameter bundle: The bundle to create the `Info.plist` file for.
  /// - Parameter minimumMacOSVersion: The minimum macOS version that the resource bundle should work on.
  /// - Returns: If an error occurs, a failure is returned.
  private static func createResourceBundleInfoPlist(in bundle: URL, minimumMacOSVersion: String?) -> Result<Void, ResourceBundlerError> {
    let bundleName = bundle.deletingPathExtension().lastPathComponent
    let infoPlist = bundle
      .appendingPathComponent("Contents")
      .appendingPathComponent("Info.plist")
    
    let result = PlistCreator.createResourceBundleInfoPlist(
      at: infoPlist,
      bundleName: bundleName,
      minimumMacOSVersion: minimumMacOSVersion)
    
    if case let .failure(error) = result {
      return .failure(.failedToCreateInfoPlist(file: infoPlist, error))
    }
    
    return .success()
  }
  
  /// Copies the resources from a source directory to a destination directory.
  ///
  /// If any of the resources are metal shader sources, they get compiled into a `default.metallib`.
  /// After compilation, the sources are deleted.
  /// - Parameters:
  ///   - source: The source directory.
  ///   - destination: The destination directory.
  /// - Returns: If an error occurs, a failure is returned.
  private static func copyResources(from source: URL, to destination: URL) -> Result<Void, ResourceBundlerError> {
    let contents: [URL]
    do {
      contents = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
    } catch {
      return .failure(.failedToEnumerateBundleContents(directory: source, error))
    }
    
    for file in contents {
      let fileDestination = destination.appendingPathComponent(file.lastPathComponent)
      do {
        try FileManager.default.copyItem(
          at: file,
          to: fileDestination)
      } catch {
        return .failure(.failedToCopyResource(source: file, destination: fileDestination))
      }
    }
    
    return .success()
  }
}
