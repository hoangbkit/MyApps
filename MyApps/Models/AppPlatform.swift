import Foundation

enum AppPlatform: String, CaseIterable, Identifiable, Codable {
    case iOS
    case macOS
    case universal = "iOS + macOS"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .iOS:
            "iphone"
        case .macOS:
            "macbook"
        case .universal:
            "laptopcomputer.and.iphone"
        }
    }
}
