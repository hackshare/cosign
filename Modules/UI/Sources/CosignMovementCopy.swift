import Foundation

public extension CosignCopy {
    enum Movement {
        static let sectionPredicted = String(localized: "Asset movement · predicted", bundle: .module)
        static let sectionExecuted = String(localized: "Asset movement", bundle: .module)
        static let sectionAttempted = String(localized: "Asset movement · attempted", bundle: .module)
        static let fromLabel = String(localized: "from", bundle: .module)
        static let toLabel = String(localized: "to", bundle: .module)

        static func leg(source: String) -> String {
            String(localized: "\(fromLabel) \(source)", bundle: .module)
        }

        static func leg(destination: String) -> String {
            String(localized: "\(toLabel) \(destination)", bundle: .module)
        }
    }
}
