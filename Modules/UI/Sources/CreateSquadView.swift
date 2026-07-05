import Core
import CosignCore
import Indexer
import Persistence
import Squads
import SwiftData
import SwiftUI

public enum CreateSquadStep: Int, CaseIterable {
    case funding, members, threshold, review

    var index: Int {
        rawValue + 1
    }

    var next: Self? {
        Self(rawValue: rawValue + 1)
    }

    var previous: Self? {
        Self(rawValue: rawValue - 1)
    }

    var identifier: String {
        switch self {
        case .funding: "funding"
        case .members: "members"
        case .threshold: "threshold"
        case .review: "review"
        }
    }
}

public struct CreateSquadView: View {
    @Environment(Coordinator.self) var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.indexerEnvironment) var indexerEnvironment
    @Environment(\.squadsService) var squadsService
    @Query(sort: \RegisteredSigner.createdAt, order: .forward) var registeredSigners: [RegisteredSigner]

    let memberAddress: String

    @State var step: CreateSquadStep = .funding
    @State var extraMembers: [String] = []
    @State var newMember: String = ""
    @State var memberError: String?
    @State var threshold: Int = 1
    @State var balanceLamports: UInt64?
    @State var cost: CreateMultisigCost?
    @State var isAirdropping = false
    @State var airdropFailed = false
    @State var isCreating = false
    @State var createError: String?
    @State var result: SquadCreationResult?
    @State private var footerHeight = CosignLayout.estimatedStickyFooterHeight

    public init(memberAddress: String) {
        self.memberAddress = memberAddress
    }

    public var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            wizardHeader
            stepContent
                .accessibilityIdentifier("create-squad-step-\(step.identifier)")
        }
        .navigationTitle(CosignCopy.CreateSquad.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshBalance()
            await loadCost()
            if isFunded, demoMode?.disablesNetworkWrites != true { step = .members }
        }
        .onChange(of: step) {
            if step == .review {
                Task { await loadCost() }
            }
        }
        .sheet(item: $result) { creationResult in
            CreateSquadResultSheet(
                result: creationResult,
                threshold: threshold,
                memberCount: memberCount,
                explorerURL: explorerURL(for: creationResult.multisigAddress),
                onOpenSquad: {
                    coordinator.replaceCurrent(with: .squadDetail(creationResult.multisigAddress))
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            wizardFooter
                .cosignMeasureHeight($footerHeight)
        }
        .accessibilityIdentifier("screen.create-squad")
    }

    var memberCount: Int {
        extraMembers.count + 1
    }

    var isFunded: Bool {
        guard let cost, let balance = balanceLamports else { return false }
        return balance >= cost.total
    }
}

extension SquadCreationResult: Identifiable {
    public var id: String {
        multisigAddress
    }
}
