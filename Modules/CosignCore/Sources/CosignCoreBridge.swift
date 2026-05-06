@_exported import cosign_coreFFI
import Foundation

/// Public façade for the Rust core. Wrappers are renamed to avoid name
/// collisions with the top-level UniFFI-generated functions in the same module.
public enum CosignCore {
    public static func makeMnemonic(wordCount: UInt8) throws -> String {
        try generateMnemonic(wordCount: wordCount)
    }

    public static func deriveKeyPair(from mnemonic: String, passphrase: String = "") throws -> KeyPair {
        try keypairFromMnemonic(mnemonic: mnemonic, passphrase: passphrase)
    }

    public static func signBytes(privateKey: Data, message: Data) -> Data {
        sign(privateKey: privateKey, message: message)
    }

    public static func verifyBytes(publicKey: Data, message: Data, signature: Data) -> Bool {
        verify(publicKey: publicKey, message: message, signature: signature)
    }

    public static func base58(_ publicKey: Data) -> String {
        pubkeyToBase58(publicKey: publicKey)
    }

    public static func isValidSolanaPubkey(_ pubkey: String) -> Bool {
        isValidPubkey(pubkey: pubkey)
    }

    public static func deriveAssociatedTokenAccountAddress(
        owner: String,
        mint: String,
        tokenProgramID: String
    ) throws -> String {
        try associatedTokenAccountAddress(
            ownerPubkey: owner,
            mintPubkey: mint,
            tokenProgramId: tokenProgramID
        )
    }

    public static func buildSquadsVoteTransaction(
        rpcURL: String,
        multisigAddress: String,
        transactionIndex: UInt64,
        memberPubkey: String,
        vote: VoteType
    ) throws -> PreparedTransaction {
        try squadsBuildVoteTransaction(
            rpcUrl: rpcURL,
            multisigAddress: multisigAddress,
            transactionIndex: transactionIndex,
            memberPubkey: memberPubkey,
            vote: vote
        )
    }

    public static func buildSquadsSOLTransferProposalTransaction(
        _ request: SOLTransferProposalTransactionRequest
    ) throws -> PreparedProposalCreation {
        try squadsBuildSolTransferProposalTransaction(
            rpcUrl: request.rpcURL,
            multisigAddress: request.multisigAddress,
            vaultIndex: request.vaultIndex,
            memberPubkey: request.memberPubkey,
            recipientPubkey: request.recipientPubkey,
            lamports: request.lamports,
            memo: request.memo
        )
    }

    public static func buildSquadsTokenTransferProposalTransaction(
        _ request: TokenTransferProposalTransactionRequest
    ) throws -> PreparedProposalCreation {
        try squadsBuildTokenTransferProposalTransaction(params: TokenTransferProposalParams(
            rpcUrl: request.rpcURL,
            multisigAddress: request.multisigAddress,
            vaultIndex: request.vaultIndex,
            memberPubkey: request.memberPubkey,
            recipientOwnerPubkey: request.recipientOwnerPubkey,
            mintPubkey: request.mintPubkey,
            amount: request.amount,
            decimals: request.decimals,
            tokenProgramId: request.tokenProgramID,
            memo: request.memo
        ))
    }

    public static func buildSquadsExecuteTransaction(
        rpcURL: String,
        multisigAddress: String,
        transactionIndex: UInt64,
        memberPubkey: String
    ) throws -> PreparedTransaction {
        try squadsBuildExecuteTransaction(
            rpcUrl: rpcURL,
            multisigAddress: multisigAddress,
            transactionIndex: transactionIndex,
            memberPubkey: memberPubkey
        )
    }

    public static func simulateSquadsTransaction(
        rpcURL: String,
        messageBytes: Data,
        signatureBytes: Data
    ) throws -> SimulationResult {
        try squadsSimulateSignedTransaction(
            rpcUrl: rpcURL,
            messageBytes: messageBytes,
            signatureBytes: signatureBytes
        )
    }

    public static func sendSquadsTransaction(
        rpcURL: String,
        messageBytes: Data,
        signatureBytes: Data
    ) throws -> TransactionSubmission {
        try squadsSendSignedTransaction(
            rpcUrl: rpcURL,
            messageBytes: messageBytes,
            signatureBytes: signatureBytes
        )
    }

    public static func getSquadsSignatureStatus(
        rpcURL: String,
        signature: String
    ) throws -> SignatureStatus {
        try squadsGetSignatureStatus(rpcUrl: rpcURL, signature: signature)
    }
}

public struct SOLTransferProposalTransactionRequest: Sendable {
    public var rpcURL = ""
    public var multisigAddress = ""
    public var vaultIndex: UInt8 = 0
    public var memberPubkey = ""
    public var recipientPubkey = ""
    public var lamports: UInt64 = 0
    public var memo: String?

    public init() {}
}

public struct TokenTransferProposalTransactionRequest: Sendable {
    public var rpcURL = ""
    public var multisigAddress = ""
    public var vaultIndex: UInt8 = 0
    public var memberPubkey = ""
    public var recipientOwnerPubkey = ""
    public var mintPubkey = ""
    public var amount: UInt64 = 0
    public var decimals: UInt8 = 0
    public var tokenProgramID = ""
    public var memo: String?

    public init() {}
}
