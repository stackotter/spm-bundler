import Foundation
import ArgumentParser

/// The subcommand for creating new app packages from templates.
struct CreateCommand: Command {
  static var configuration = CommandConfiguration(
    commandName: "create",
    abstract: "Create a new app package.")

  /// The app's name. Must only contain characters from the English alphabet.
  @Argument(
    help: "The app's name. Must only contain characters from the English alphabet.")
  var appName: String

  /// A custom directory to create the app in. Default: create a new directory at './[app-name]'.
  @Option(
    name: [.customShort("d"), .customLong("directory")],
		help: "Directory to create the app in. Default: create a new directory at './[app-name]'.",
    transform: URL.init(fileURLWithPath:))
  var packageDirectory: URL?

  /// Template to create the app from.
  @Option(
		name: [.customShort("t"), .customLong("template")],
		help: "Template to create the app from.")
  var templateName: String?

  /// A directory to search for the template in.
  @Option(
    name: .long,
    help: "A directory to search for the template in.",
    transform: URL.init(fileURLWithPath:))
  var templateRepository: URL?

  /// The indentation style to create the package with.
  @Option(
    name: .shortAndLong,
    help: "Custom indentation style: either 'tabs' or 'spaces=[count]'.")
  var indentation: IndentationStyle = .spaces(4)

  /// If `true`, force creation of the package even if the template does not support the current OS and installed Swift version.
  @Flag(
    name: .shortAndLong,
    help: "Force creation even if the template does not support the current OS and installed Swift version.")
  var force = false

	func wrappedValidate() throws {
		guard Self.isValidAppName(appName) else {
			throw ValidationError("Invalid app name, app names must only include uppercase and lowercase characters from the English alphabet")
		}

		if templateName == nil && templateRepository != nil {
			throw ValidationError("The '--template-repository' option can only be used with the '--template' option")
		}
	}

  func wrappedRun() throws {
    let defaultPackageDirectory = URL(fileURLWithPath: ".").appendingPathComponent(appName)
    let packageDirectory = packageDirectory ?? defaultPackageDirectory

		var template: Template? = nil
    let elapsed = try Stopwatch.time {
      // Create package from template
      if let templateRepository = templateRepository, let templateName = templateName {
        template = try Templater.createPackage(
          in: packageDirectory,
          from: templateName,
          in: templateRepository,
          packageName: appName,
          forceCreation: force,
          indentationStyle: indentation
        ).unwrap()
      } else {
        template = try Templater.createPackage(
          in: packageDirectory,
          from: templateName,
          packageName: appName,
          forceCreation: force,
          indentationStyle: indentation
        ).unwrap()
      }
    }

    log.info("Done in \(elapsed.secondsString). Package located at '\(packageDirectory.relativePath)'")

    print(Output {
      ""
			if let template = template, let dependencies = template.manifest.systemDependencies {
				Section("System dependencies") {
					"The '\(template.name)' template requires the following system dependencies to be installed:"
					""
					KeyedList {
						for (key, value) in dependencies {
							KeyedList.Entry(key) {
								Line {
									if let packages = value.brew {
										"Can be installed via '"
										ExampleCommand("brew install \(packages)", withPrompt: false)
										"'"
									} else {
										"Must be manually installed"
									}
								}
							}
						}
					}
				}
			}
      Section("Getting started") {
        ExampleCommand("cd \(packageDirectory.relativePath.quotedIfNecessary)")
        ExampleCommand("swift bundler run")
      }
    })
  }

  /// App names can only contain characters from the English alphabet (to avoid things getting a bit complex when figuring out the product name).
  /// - Parameter name: The name to verify.
  /// - Returns: Whether the app name is valid or not.
  static func isValidAppName(_ name: String) -> Bool {
    let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let characters = Set(name)

    return characters.subtracting(allowedCharacters).isEmpty
  }
}
