enum SolanaConstants {
    static let systemProgram = "11111111111111111111111111111111"

    static let squadsV4Program = "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf"
    /// Squads v3 (Mesh). Not transactable from Cosign yet, but accounts owned by
    /// it are recoverable, so we recognize rather than warn.
    static let squadsV3Program = "SMPLecH534NA9acpos4G6x7uf3LWbCAwZQE9e8ZekMu"

    /// Program owners whose accounts are multisig-controlled and recoverable —
    /// recipients here are recognized, not flagged as risky.
    static let squadsPrograms: Set<String> = [squadsV4Program, squadsV3Program]
}

/// How a transfer recipient is owned on-chain — the basis for the builder's
/// safety read. A Squads-controlled account is program-owned but recoverable
/// (funds stay under multisig control), so it is NOT lumped with risky
/// program/token accounts.
public enum RecipientClassification: Sendable {
    case wallet
    case squadsControlled
    case programOwned
}
