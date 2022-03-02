//import Foundation
//import ArgumentParser
//
//struct Bundle: ParsableCommand {
//  @Option(name: [.customLong("products-dir"), .customShort("P")], help: "The directory containing the built executable and bundles", transform: URL.init(fileURLWithPath:))
//  var productsDir: URL?
//
//  @Option(name: .shortAndLong, help: "The path to the executable", transform: URL.init(fileURLWithPath:))
//  var executable: URL?
//
//  @Option(name: [.customLong("directory"), .customShort("d")], help: "The directory containing the package being bundled", transform: URL.init(fileURLWithPath:))
//  var packageDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
//
//  @Option(name: .shortAndLong, help: "The directory to output the bundled .app to", transform: URL.init(fileURLWithPath:))
//  var outputDir: URL?
//
//  @Flag(name: .long, help: "Leave bundles exactly as they are and just copy them across")
//  var dontFixBundles = true
//
//  @Flag(name: [.customShort("p"), .customLong("progress")], help: "Display progress in a window")
//  var displayProgress = false
//
//  func run() throws {
//    // Load configuration
//    let config = Configuration.load(packageDir)
//
//    if displayProgress {
//      runProgressJob({ setMessage, setProgress in
//        // A helper function to update the progress window (if present)
//        Bundler.bundle(
//          packageDir: packageDir,
//          target: config.target,
//          productsDir: productsDir,
//          executable: executable,
//          outputDir: outputDir,
//          config: config,
//          fixBundles: !dontFixBundles,
//          updateProgress: { message, progress, shouldLog in
//            if shouldLog {
//              log.info(message)
//            }
//            setMessage(message)
//            setProgress(progress)
//          })
//      },
//      title: "Bundling",
//      maxProgress: 1)
//    } else {
//      Bundler.bundle(
//        packageDir: packageDir,
//        target: config.target,
//        productsDir: productsDir,
//        executable: executable,
//        outputDir: outputDir,
//        config: config,
//        fixBundles: !dontFixBundles)
//    }
//  }
//}
//
//extension Bundler {
//  static func bundle(
//    packageDir: URL,
//    target: String,
//    productsDir: URL? = nil,
//    executable: URL? = nil,
//    outputDir: URL? = nil,
//    config: Configuration,
//    fixBundles: Bool,
//    updateProgress updateProgressClosure: (@escaping (_ message: String, _ progress: Double, _ shouldLog: Bool) -> Void) = { _, _, _ in }
//  ) {
//    func updateProgress(_ message: String, _ progress: Double, shouldLog: Bool = true) {
//      updateProgressClosure(message, progress, shouldLog)
//    }
//
//    guard let executable = executable ?? productsDir?.appendingPathComponent("\(target)") else {
//      terminate("Please provide the `products-dir` option and/or the `executable` option")
//    }
//
//    let outputDir = outputDir ?? packageDir.appendingPathComponent(".build/bundler")
//
//    // Create app folder structure
//    updateProgress("Creating .app skeleton", 0)
//    let app = outputDir.appendingPathComponent("\(target).app")
//    let appContents = app.appendingPathComponent("Contents")
//    let appResources = appContents.appendingPathComponent("Resources")
//    let appMacOS = appContents.appendingPathComponent("MacOS")
//
//    do {
//      if FileManager.default.itemExists(at: app, withType: .directory) {
//        try FileManager.default.removeItem(at: app)
//      }
//      try FileManager.default.createDirectory(at: appResources)
//      try FileManager.default.createDirectory(at: appMacOS)
//    } catch {
//      terminate("Failed to create .app folder structure; \(error)")
//    }
//
//    // Copy dynamic libraries
//    updateProgress("Copying dynamic libraries (frameworks)", 0.2)
//    if let productsDir = productsDir {
//      do {
//        let packageFrameworksDir = productsDir.appendingPathComponent("PackageFrameworks")
//        let libDir = appContents.appendingPathComponent("lib")
//        try FileManager.default.createDirectory(at: libDir)
//
//        let contents = try FileManager.default.contentsOfDirectory(at: productsDir, includingPropertiesForKeys: nil, options: [])
//        for file in contents where file.pathExtension == "dylib" {
//          log.info("Copying '\(file.lastPathComponent)' to app bundle")
//          try FileManager.default.copyItem(at: file, to: libDir.appendingPathComponent(file.lastPathComponent))
//
//          // Update the executable's library path for this dylib
//          Shell.runSilently("install_name_tool -change @rpath/\(file.lastPathComponent) @rpath/../lib/\(file.lastPathComponent) \(executable.path)")
//        }
//
//        if FileManager.default.itemExists(at: packageFrameworksDir, withType: .directory) { // The app was built with Xcode
//          let contents = try FileManager.default.contentsOfDirectory(at: packageFrameworksDir, includingPropertiesForKeys: nil, options: [])
//          for framework in contents where framework.pathExtension == "framework" {
//            log.info("Converting '\(framework.lastPathComponent)' to dylib and copying to app bundle")
//            let libName = framework.deletingPathExtension().lastPathComponent
//            let dylib = framework.appendingPathComponent("Versions/A/\(libName)")
//            try FileManager.default.copyItem(at: dylib, to: libDir.appendingPathComponent("lib\(libName).dylib"))
//
//            let resources = dylib.deletingLastPathComponent().appendingPathComponent("Resources")
//            let contents = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil, options: [])
//            for file in contents {
//              if file.lastPathComponent != "Info.plist" {
//                terminate("Swift Bundler currently doesn't support frameworks with resources; '\(framework.lastPathComponent)' contains resources")
//              }
//            }
//
//            // Update the executable's library path for this framework
//            Shell.runSilently("install_name_tool -change @rpath/\(libName).framework/Versions/A/\(libName) @rpath/../lib/lib\(libName).dylib \(executable.escapedPath)")
//          }
//        }
//      } catch {
//        terminate("Failed to copy dynamic libraries to app bundle; \(error)")
//      }
//    }
//
//    // Copy executable
//    updateProgress("Copying executable", 0.3)
//    do {
//      Shell.runSilently("install_name_tool -add_rpath @executable_path \(executable.escapedPath)")
//      try FileManager.default.copyItem(at: executable, to: appMacOS.appendingPathComponent(target))
//    } catch {
//      terminate("Failed to copy built executable to \(appMacOS.appendingPathComponent(target).escapedPath); \(error)")
//    }
//
//    // Create app icon
//    updateProgress("Creating app icon", 0.4)
//    let appIcns = packageDir.appendingPathComponent("AppIcon.icns")
//    do {
//      if FileManager.default.itemExists(at: appIcns, withType: .file) {
//        log.info("Using precompiled AppIcon.icns")
//        try FileManager.default.copyItem(at: appIcns, to: appResources.appendingPathComponent("AppIcon.icns"))
//      } else {
//        let iconFile = packageDir.appendingPathComponent("Icon1024x1024.png")
//        if FileManager.default.itemExists(at: iconFile, withType: .file) {
//          log.info("Compiling Icon1024x1024.png into AppIcon.icns")
//          try createIcns(from: iconFile, outDir: appResources)
//        } else {
//          log.warning("No app icon found. Create an Icon1024x1024.png or AppIcon.icns in the root directory to add an app icon.")
//        }
//      }
//    } catch {
//      terminate("Failed to create app icon; \(error)")
//    }
//
//    // Create PkgInfo
//    updateProgress("Creating PkgInfo", 0.6)
//    var pkgInfo: [UInt8] = [0x41, 0x50, 0x50, 0x4c, 0x3f, 0x3f, 0x3f, 0x3f]
//    let pkgInfoFile = appContents.appendingPathComponent("PkgInfo")
//    do {
//      try Data(bytes: &pkgInfo, count: pkgInfo.count).write(to: pkgInfoFile)
//    } catch {
//      terminate("Failed to create PkgInfo; \(error)")
//    }
//
//    // Create Info.plist
//    updateProgress("Creating Info.plist", 0.7)
//    let infoPlistFile = appContents.appendingPathComponent("Info.plist")
//    do {
//      let infoPlist = try createAppInfoPlist(
//        appName: target,
//        bundleIdentifier: config.bundleIdentifier,
//        versionString: config.versionString,
//        buildNumber: config.buildNumber,
//        category: config.category,
//        minOSVersion: config.minOSVersion,
//        extraEntries: config.extraInfoPlistEntries)
//      try infoPlist.write(to: infoPlistFile)
//    } catch {
//      terminate("Failed to create Info.plist at '\(infoPlistFile.path)'; \(error)")
//    }
//
//    // Copy bundles
//    updateProgress("Copying bundles", 0.85)
//    if let productsDir = productsDir {
//      let contents: [URL]
//      do {
//        contents = try FileManager.default.contentsOfDirectory(at: productsDir, includingPropertiesForKeys: nil, options: [])
//      } catch {
//        terminate("Failed to enumerate contents of products directory (\(productsDir)); \(error)")
//      }
//
//      let bundles = contents.filter { $0.pathExtension == "bundle" }
//      for bundle in bundles {
//        updateProgress("Copying \(bundle.lastPathComponent)", 0.7)
//        let outputBundle = appResources.appendingPathComponent(bundle.lastPathComponent)
//        if !fixBundles {
//          // Universal builds actually produce correct bundles and automatically compile metal shaders! woohoo
//          do {
//            try FileManager.default.copyItem(at: bundle, to: outputBundle)
//          } catch {
//            terminate("Failed to copy '\(bundle.lastPathComponent)'; \(error)")
//          }
//        } else {
//          let contents: [URL]
//          do {
//            contents = try FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil, options: [])
//          } catch {
//            terminate("Failed to enumerate contents of '\(bundle.lastPathComponent)'; \(error)")
//          }
//
//          let bundleContents = outputBundle.appendingPathComponent("Contents")
//          let bundleResources = bundleContents.appendingPathComponent("Resources")
//          do {
//            try FileManager.default.createDirectory(at: bundleResources, withIntermediateDirectories: true, attributes: nil)
//
//            for file in contents {
//              try FileManager.default.copyItem(at: file, to: bundleResources.appendingPathComponent(file.lastPathComponent))
//            }
//          } catch {
//            terminate("Failed to create copy of '\(bundle.lastPathComponent)'; \(error)")
//          }
//
//          // Create Info.plist if missing
//          let bundleName = bundle.deletingPathExtension().lastPathComponent
//          let bundleIdentifier = bundleName.replacingOccurrences(of: "_", with: "-").appending("-resources")
//          let infoPlistFile = bundleContents.appendingPathComponent("Info.plist")
//          if !FileManager.default.itemExists(at: infoPlistFile, withType: .file) {
//            log.info("Creating Info.plist for \(bundle.lastPathComponent)")
//            do {
//              let infoPlist = try createBundleInfoPlist(bundleIdentifier: bundleIdentifier, bundleName: bundleName, minOSVersion: config.minOSVersion)
//              try infoPlist.write(to: infoPlistFile)
//            } catch {
//              terminate("Failed to create Info.plist for '\(bundle.lastPathComponent)'; \(error)")
//            }
//          }
//
//          // Metal shader compilation
//          let metalFiles = contents.filter { $0.pathExtension == "metal" }
//          if metalFiles.isEmpty {
//            continue
//          }
//
//          updateProgress("Compiling metal shaders in \(bundle.lastPathComponent)", 0.85)
//
//          for metalFile in metalFiles {
//            let path = metalFile.deletingPathExtension().escapedPath
//            if Shell.getExitStatus("xcrun -sdk macosx metal -c \(path).metal -o \(path).air", silent: false) != 0 {
//              terminate("Failed to compile '\(metalFile.lastPathComponent)")
//            }
//          }
//
//          let airFilePaths = metalFiles.map { $0.deletingPathExtension().appendingPathExtension("air").escapedPath }
//          if Shell.getExitStatus("xcrun -sdk macosx metal-ar rcs \(outputBundle.escapedPath)/default.metal-ar \(airFilePaths.joined(separator: " "))", silent: false) != 0 {
//            terminate("Failed to combine compiled metal shaders into a metal archive")
//          }
//          if Shell.getExitStatus("xcrun -sdk macosx metallib \(outputBundle.escapedPath)/default.metal-ar -o \(bundleResources.escapedPath)/default.metallib", silent: false) != 0 {
//            terminate("Failed to convert metal archive to metal library")
//          }
//          Shell.runSilently("rm \(outputBundle.escapedPath)/default.metal-ar")
//        }
//      }
//    }
//
//    updateProgress("Bundling completed", 1)
//  }
//}
