import Indexer
import Squads
import SwiftUI

public extension EnvironmentValues {
    @Entry var indexerEnvironment: IndexerEnvironment = .devnet

    @Entry var squadsService: SquadsService = .init(environment: .devnet)
}
