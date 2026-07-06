public extension CosignCopy {
    enum Movement {
        static let sectionPredicted = "Asset movement · predicted"
        static let sectionExecuted = "Asset movement"
        static let sectionAttempted = "Asset movement · attempted"
        static let fromLabel = "from"
        static let toLabel = "to"

        static func leg(source: String) -> String {
            "\(fromLabel) \(source)"
        }

        static func leg(destination: String) -> String {
            "\(toLabel) \(destination)"
        }
    }
}
