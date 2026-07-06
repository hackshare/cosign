import Squads

extension SignerHomeView {
    @MainActor
    func load(
        memberAddress: String,
        forceRefresh: Bool = false,
        showsLoading: Bool = true
    ) async {
        guard !memberAddress.isEmpty else {
            errorMessage = "The signer public key could not be encoded."
            squadRows = []
            recentActivity = []
            return
        }

        if showsLoading {
            isLoading = true
        }
        if squadRows.isEmpty || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            let summaries = if forceRefresh {
                try await squadsService.refreshSquads(forMember: memberAddress)
            } else {
                try await squadsService.squads(forMember: memberAddress)
            }
            let rows = await rows(for: summaries, forceRefresh: forceRefresh)
            squadRows = rows
            recentActivity = await loadRecentActivity(
                memberAddress: memberAddress,
                squads: summaries,
                forceRefresh: forceRefresh
            )
            errorMessage = nil
        } catch {
            if squadRows.isEmpty {
                errorMessage = String(describing: error)
            }
        }
    }

    func rows(for summaries: [SquadSummary], forceRefresh: Bool) async -> [SignerHomeSquadRow] {
        var rows = [SignerHomeSquadRow]()

        for summary in summaries {
            let proposals = await recentProposals(for: summary, forceRefresh: forceRefresh)
            rows.append(SignerHomeSquadRow(
                summary: summary,
                openProposalCount: proposals.filter(\.isOpen).count
            ))
        }

        return rows
    }

    func recentProposals(for summary: SquadSummary, forceRefresh: Bool) async -> [SquadProposalSummary] {
        guard let range = ProposalRange.recent(through: summary.transactionIndex, limit: 12) else {
            return []
        }

        do {
            if forceRefresh {
                return try await squadsService.refreshProposals(in: summary.address, range: range)
            }
            return try await squadsService.proposals(in: summary.address, range: range)
        } catch {
            return []
        }
    }

    func loadRecentActivity(
        memberAddress: String,
        squads: [SquadSummary],
        forceRefresh: Bool
    ) async -> [SquadActivityItem] {
        let directActivity = await loadActivity(forAddress: memberAddress, forceRefresh: forceRefresh)
        if !directActivity.isEmpty {
            return directActivity
        }

        return await loadAggregateActivity(for: squads, forceRefresh: forceRefresh)
    }

    func loadActivity(forAddress address: String, forceRefresh: Bool) async -> [SquadActivityItem] {
        do {
            if forceRefresh {
                return try await squadsService.refreshActivity(forAddress: address, limit: 6)
            }
            return try await squadsService.activity(forAddress: address, limit: 6)
        } catch {
            return []
        }
    }

    func loadAggregateActivity(for summaries: [SquadSummary], forceRefresh: Bool) async -> [SquadActivityItem] {
        var items = [SquadActivityItem]()

        for summary in summaries {
            do {
                let activity = if forceRefresh {
                    try await squadsService.refreshActivity(in: summary.address, limit: 3)
                } else {
                    try await squadsService.activity(in: summary.address, limit: 3)
                }
                items.append(contentsOf: activity)
            } catch {
                continue
            }
        }

        var seen = Set<String>()
        return items
            .sorted { lhs, rhs in
                if lhs.timestampUnix == rhs.timestampUnix {
                    return lhs.slot > rhs.slot
                }
                return lhs.timestampUnix > rhs.timestampUnix
            }
            .filter { item in
                seen.insert(item.signature).inserted
            }
            .prefix(6)
            .map(\.self)
    }
}
