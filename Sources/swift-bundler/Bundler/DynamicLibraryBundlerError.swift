import Foundation

/// An error returned by ``DynamicLibraryBundler``.
enum DynamicLibraryBundlerError: LocalizedError {
  case failedToEnumerateDynamicLibraries(directory: URL, Error)
  case failedToCopyDynamicLibrary(source: URL, destination: URL, Error)
  case failedToUpdateLibraryInstallName(library: String, original: String, new: String, ProcessError)
  case failedToGetOutputPathRelativeToExecutable(outputPath: URL, executable: URL)
  case failedToGetOriginalPathRelativeToSearchDirectory(library: String, originalPath: URL, searchDirectory: URL)
  case failedToUpdateAppRPath(original: String, new: String, ProcessError)
  
  var errorDescription: String? {
    switch self {
      case .failedToEnumerateDynamicLibraries(let directory, _):
        return "Failed to enumerate dynamic libraries in '\(directory.relativePath)'"
      case .failedToCopyDynamicLibrary(let source, let destination, _):
        return "Failed to copy dynamic library from '\(source.relativePath)' to '\(destination.relativePath)'"
      case .failedToUpdateLibraryInstallName(let library, let original, let new, let processError):
        return "Failed to update dynamic library install name of '\(library)' from '\(original)' to '\(new)': \(processError.localizedDescription)"
      case .failedToGetOutputPathRelativeToExecutable(let outputPath, let executable):
        return "Failed to get output path '\(outputPath.relativePath)' relative to executable at '\(executable.relativePath)'"
      case .failedToGetOriginalPathRelativeToSearchDirectory(let library, let originalPath, let searchDirectory):
        return "Failed to get original path of '\(library)' at '\(originalPath.relativePath)' relative to search directory '\(searchDirectory.relativePath)'"
      case .failedToUpdateAppRPath(let original, let new, let processError):
        return "Failed to update the app's rpath from '\(original)' to '\(new)': \(processError.localizedDescription)"
    }
  }
}
