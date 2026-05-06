import Foundation
import SwiftData

public enum PersistenceContainer {
    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema([RegisteredSigner.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([RegisteredSigner.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
