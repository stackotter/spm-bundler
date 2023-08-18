import Foundation

/// A device that can be used to run apps.
enum Device {
  case macOS
  case iOS
  case visionOS
  case linux
  case iOSSimulator(id: String)
  case visionOSSimulator(id: String)
}
