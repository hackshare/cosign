import Squads

enum ActivityFilter: CaseIterable, Identifiable {
    case all
    case decoded
    case errors

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .all:
            CosignCopy.Activity.filterAll
        case .decoded:
            CosignCopy.Activity.filterDecoded
        case .errors:
            CosignCopy.Activity.filterErrors
        }
    }

    func includes(_ item: SquadActivityItem) -> Bool {
        switch self {
        case .all:
            true
        case .decoded:
            item.action != nil
        case .errors:
            item.error != nil
        }
    }
}
