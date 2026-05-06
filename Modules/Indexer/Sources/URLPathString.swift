extension String {
    func trimmingTrailingSlash() -> String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    func withLeadingSlash() -> String {
        hasPrefix("/") ? self : "/\(self)"
    }
}
