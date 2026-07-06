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

    /// Derive a keypair from a raw 64-byte Solana secret key (32-byte seed
    /// followed by the 32-byte public key, as written by `solana-cli`). Throws
    /// `CryptoError.InvalidKeyLength` when the input is not 64 bytes and
    /// `CryptoError.InvalidSecretKey` when the bytes are not a valid ed25519
    /// keypair.
    public static func keypairFromSecretBytes(secretBytes: Data) throws -> KeyPair {
        // The module and this enum share the name `CosignCore`, so the
        // UniFFI free function cannot be referenced through a qualifier, and a
        // static method with the same name would recurse. Route through a
        // module-scope shim where only the free function is in scope.
        try keypairFromSecretBytesFFI(secretBytes)
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

    public static func buildSquadsConfigChangeProposal(
        _ request: ConfigChangeProposalRequest
    ) throws -> PreparedProposalCreation {
        try squadsBuildConfigChangeProposalTransaction(
            rpcUrl: request.rpcURL,
            multisigAddress: request.multisigAddress,
            memberPubkey: request.memberPubkey,
            addedMembers: request.addedMembers,
            removedMembers: request.removedMembers,
            newThreshold: request.newThreshold,
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

    public static func buildSquadsCreateMultisig(
        _ request: CreateMultisigTransactionRequest
    ) throws -> PreparedMultisigCreation {
        try squadsBuildCreateMultisigTransaction(
            rpcUrl: request.rpcURL,
            creatorPubkey: request.creatorPubkey,
            memberPubkeys: request.memberPubkeys,
            threshold: request.threshold
        )
    }

    public static func estimateSquadsCreateMultisigCost(
        _ request: CreateMultisigTransactionRequest
    ) throws -> CreateMultisigCost {
        try squadsEstimateCreateMultisigCost(
            rpcUrl: request.rpcURL,
            creatorPubkey: request.creatorPubkey,
            memberPubkeys: request.memberPubkeys,
            threshold: request.threshold
        )
    }

    public static func sendSquadsMultisigCreate(
        rpcURL: String,
        messageBytes: Data,
        creatorSignature: Data,
        createKey: String,
        createKeySignature: Data
    ) throws -> TransactionSubmission {
        try squadsSendMultisigCreateTransaction(
            rpcUrl: rpcURL,
            messageBytes: messageBytes,
            creatorSignature: creatorSignature,
            createKeyPubkey: createKey,
            createKeySignature: createKeySignature
        )
    }

    /// Wraps the generated `requestDevnetAirdrop` free function. Renamed to
    /// avoid shadowing the free function with a same-named static method.
    public static func airdropDevnet(
        rpcURL: String,
        address: String,
        lamports: UInt64
    ) throws -> String {
        try requestDevnetAirdrop(rpcUrl: rpcURL, address: address, lamports: lamports)
    }

    public static func solBalance(rpcURL: String, address: String) throws -> UInt64 {
        try getSolBalance(rpcUrl: rpcURL, address: address)
    }
}

private func keypairFromSecretBytesFFI(_ secretBytes: Data) throws -> KeyPair {
    try keypairFromSecretBytes(secretBytes: secretBytes)
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

public struct ConfigChangeProposalRequest: Sendable {
    public var rpcURL = ""
    public var multisigAddress = ""
    public var memberPubkey = ""
    public var addedMembers: [String] = []
    public var removedMembers: [String] = []
    public var newThreshold: UInt16 = 1
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

public struct CreateMultisigTransactionRequest: Sendable {
    public var rpcURL = ""
    public var creatorPubkey = ""
    public var memberPubkeys: [String] = []
    public var threshold: UInt16 = 1

    public init() {}
}
