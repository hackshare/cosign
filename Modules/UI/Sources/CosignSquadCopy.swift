import Foundation

extension CosignCopy {
    enum Squads {
        static let memberSection = String(localized: "Member", bundle: .module)
        static let screenTitle = String(localized: "Squads", bundle: .module)
        static let copyMemberAddress = String(localized: "Copy Member Address", bundle: .module)
        static let unableToLoadSquadsTitle = String(localized: "Unable to Load Squads", bundle: .module)
        static let sectionTitle = String(localized: "Squads", bundle: .module)
        static let emptySignerAddressMessage = String(
            localized: "The signer public key could not be encoded.",
            bundle: .module
        )
        static let copySquadAddress = String(localized: "Copy Squad Address", bundle: .module)
        static let noTransactions = String(localized: "No proposals", bundle: .module)

        static func pendingCount(_ count: Int) -> String {
            count == 1
                ? String(localized: "1 pending", bundle: .module)
                : String(localized: "\(count) pending", bundle: .module)
        }

        static func transactionSummary(transactionIndex: UInt64, staleTransactionIndex: UInt64) -> String {
            guard transactionIndex > 0 || staleTransactionIndex > 0 else {
                return noTransactions
            }
            return String(localized: "tx \(transactionIndex) · stale \(staleTransactionIndex)", bundle: .module)
        }

        static func threshold(
            _ threshold: some BinaryInteger,
            memberCount: some BinaryInteger
        ) -> String {
            "\(threshold) / \(memberCount)"
        }
    }

    enum SquadDetail {
        static let navigationTitle = String(localized: "Squad", bundle: .module)
        static let unableToLoadSquadTitle = String(localized: "Unable to Load Squad", bundle: .module)
        static let emptySquadAddressMessage = String(localized: "The Squad address is empty.", bundle: .module)
        static let combinedBalance = String(localized: "Combined balance", bundle: .module)
        static let usdSymbol = String(localized: "USD", bundle: .module)
        static let tokensMetric = String(localized: "Tokens", bundle: .module)
        static let nftsMetric = String(localized: "NFTs", bundle: .module)
        static let vaultsMetric = String(localized: "Vaults", bundle: .module)
        static let proposalsTab = String(localized: "Proposals", bundle: .module)
        static let activityTab = String(localized: "Activity", bundle: .module)
        static let latestTransactionMetric = String(localized: "Latest tx", bundle: .module)
        static let staleTransactionMetric = String(localized: "Stale tx", bundle: .module)
        static let timelockMetric = String(localized: "Timelock", bundle: .module)
        static let noMembersTitle = String(localized: "No Members", bundle: .module)
        static let noMembersMessage = String(
            localized: "This Squad did not return any member accounts.",
            bundle: .module
        )
        static let membersSection = String(localized: "Members", bundle: .module)
        static let unavailable = String(localized: "Unavailable", bundle: .module)
        static let none = String(localized: "None", bundle: .module)
        static let initiatePermission = String(localized: "Initiate", bundle: .module)
        static let votePermission = String(localized: "Vote", bundle: .module)
        static let executePermission = String(localized: "Execute", bundle: .module)

        static func header(threshold: some BinaryInteger, memberCount: Int) -> String {
            String(localized: "Squad · \(threshold) of \(memberCount)", bundle: .module)
        }

        static func vaultCount(_ count: Int) -> String {
            count == 1
                ? String(localized: "1 vault", bundle: .module)
                : String(localized: "\(count) vaults", bundle: .module)
        }

        static func memberCount(_ count: Int) -> String {
            count == 1
                ? String(localized: "1 member", bundle: .module)
                : String(localized: "\(count) members", bundle: .module)
        }

        static func knownBalance(_ balance: String) -> String {
            String(localized: "\(balance) known", bundle: .module)
        }

        static func estimatedUSD(_ amount: String) -> String {
            "≈ \(amount) \(usdSymbol)"
        }

        static func staleTransaction(index: UInt64) -> String {
            index == 0 ? none : "#\(index)"
        }

        static func latestTransaction(index: UInt64) -> String {
            index == 0 ? none : "#\(index)"
        }

        static func timeLock(seconds: UInt32) -> String {
            seconds == 0 ? none : "\(seconds)s"
        }
    }

    enum Vaults {
        static let sectionTitle = String(localized: "Vaults", bundle: .module)
        static let holdingsSection = String(localized: "Holdings", bundle: .module)
        static let nftsSection = String(localized: "NFTs", bundle: .module)
        static let solSymbol = String(localized: "SOL", bundle: .module)
        static let solBalanceSubtitle = String(localized: "Balance (SOL)", bundle: .module)
        static let token2022Badge = String(localized: "Token-2022", bundle: .module)
        static let unknownToken = String(localized: "Unknown token", bundle: .module)
        static let unknownAmount = String(localized: "Unknown", bundle: .module)
        static let balanceUnavailable = String(localized: "Balance unavailable", bundle: .module)
        static let copyVaultAddress = String(localized: "Copy Vault Address", bundle: .module)

        static func title(index: UInt8) -> String {
            String(localized: "Vault \(index)", bundle: .module)
        }

        static func indexBadge(index: UInt8) -> String {
            "\(index)"
        }

        static func tokenCount(_ count: Int) -> String {
            count == 1
                ? String(localized: "1 token", bundle: .module)
                : String(localized: "\(count) tokens", bundle: .module)
        }

        static func nftCount(_ count: Int) -> String {
            count == 1
                ? String(localized: "1 NFT", bundle: .module)
                : String(localized: "\(count) NFTs", bundle: .module)
        }

        static func mintSubtitle(_ mint: String) -> String {
            String(localized: "Mint \(mint)", bundle: .module)
        }

        static func tokenAmount(_ amount: String, symbol: String?) -> String {
            guard let symbol, amount != unknownAmount else {
                return amount
            }
            return "\(amount) \(symbol)"
        }
    }

    enum VaultDetail {
        static let unableToLoadVaultTitle = String(localized: "Unable to Load Vault", bundle: .module)
        static let balance = String(localized: "Balance", bundle: .module)
        static let propose = String(localized: "Propose", bundle: .module)
        static let inspect = String(localized: "Inspect", bundle: .module)
        static let history = String(localized: "History", bundle: .module)
        static let usdValueColumn = String(localized: "USD value", bundle: .module)
        static let usdUnavailable = String(localized: "—", bundle: .module)
        static let priceUnavailable = String(localized: "Price unavailable", bundle: .module)
        static let pricesUnavailableBannerTitle = String(localized: "Prices unavailable", bundle: .module)
        static let openInExplorerAccessibilityLabel = String(localized: "Open Vault in Explorer", bundle: .module)

        static func missingVaultMessage(index: UInt8) -> String {
            String(localized: "Vault \(index) was not returned for this Squad.", bundle: .module)
        }

        static func header(squadName: String, vaultIndex: UInt8) -> String {
            "\(squadName) · \(CosignCopy.Vaults.title(index: vaultIndex))"
        }

        static func holdingsTitle(assetCount: Int) -> String {
            String(localized: "Holdings · \(assetCount) assets", bundle: .module)
        }

        /// Stale-age label. Returns "· Nm old" (U+00B7 middle dot).
        static func minutesOld(_ minutes: Int) -> String {
            String(localized: "\u{00B7} \(minutes)m old", bundle: .module)
        }

        /// Delta label for the 24h price change. Returns "▲ X.X%" (mint),
        /// "▼ X.X%" (red), or "0.0%" (flat / rounds to zero). No em dashes.
        static func priceChange24h(_ pct: Double) -> String {
            let formatted = String(format: "%.1f", Swift.abs(pct))
            if formatted == "0.0" {
                return "0.0%"
            }
            return pct > 0 ? "\u{25B2} \(formatted)%" : "\u{25BC} \(formatted)%"
        }
    }

    enum VaultInspection {
        static let navigationTitle = String(localized: "Vault Inspection", bundle: .module)
        static let unableToLoadTitle = String(localized: "Unable to Load Vault Inspection", bundle: .module)
        static let identitySection = String(localized: "Vault identity", bundle: .module)
        static let authorityLabel = String(localized: "Authority", bundle: .module)
        static let ownerLabel = String(localized: "owner", bundle: .module)
        static let squadsProgramLabel = String(localized: "Squads v4", bundle: .module)
        static let holdingsLabel = String(localized: "Holdings", bundle: .module)
        static let recentMovementSection = String(localized: "Recent movement · 30D", bundle: .module)
        static let noRecentMovementTitle = String(localized: "No recent movement", bundle: .module)
        static let noRecentMovementMessage = String(
            localized: "No recent transactions were returned for this vault.",
            bundle: .module
        )
        static let copyAddress = String(localized: "Copy address", bundle: .module)
        static let openInExplorer = String(localized: "Open in Explorer", bundle: .module)

        static func header(squadName: String, vaultIndex: UInt8) -> String {
            String(localized: "Vault inspection · \(squadName) · Vault \(vaultIndex)", bundle: .module)
        }

        static func vaultSubtitle(address: String) -> String {
            "\(address) · \(ownerLabel) · \(squadsProgramLabel)"
        }

        static func holdingsValue(sol: String, tokenCount: Int) -> String {
            String(localized: "\(sol) SOL · \(tokenCount) tokens", bundle: .module)
        }
    }
}

extension SquadDetailTab {
    var title: String {
        switch self {
        case .vaults:
            CosignCopy.Vaults.sectionTitle
        case .proposals:
            CosignCopy.SquadDetail.proposalsTab
        case .activity:
            CosignCopy.SquadDetail.activityTab
        case .members:
            CosignCopy.SquadDetail.membersSection
        }
    }
}
