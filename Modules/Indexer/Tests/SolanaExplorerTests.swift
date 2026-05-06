import Foundation
import Testing
@testable import Indexer

struct SolanaExplorerTests {
    @Test func buildsDevnetTransactionURLWithoutRPCSecrets() throws {
        let rpcURL = try #require(URL(string: "https://devnet.helius-rpc.com/?api-key=secret"))
        let url = try #require(SolanaExplorer.transactionURL(signature: "abc123", rpcURL: rpcURL))

        #expect(url.absoluteString == "https://explorer.solana.com/tx/abc123?cluster=devnet")
    }

    @Test func buildsLocalTransactionURLWithCustomRPCURL() throws {
        let rpcURL = try #require(URL(string: "http://127.0.0.1:57142"))
        let url = try #require(SolanaExplorer.transactionURL(signature: "abc123", rpcURL: rpcURL))

        #expect(
            url.absoluteString ==
                "https://explorer.solana.com/tx/abc123?cluster=custom&customUrl=http://127.0.0.1:57142"
        )
    }

    @Test func buildsInspectorURLForKnownClusterWithoutRPCSecrets() throws {
        let rpcURL = try #require(URL(string: "https://devnet.helius-rpc.com/?api-key=secret"))
        let url = try #require(SolanaExplorer.transactionInspectorURL(rpcURL: rpcURL))

        #expect(url.absoluteString == "https://explorer.solana.com/tx/inspector?cluster=devnet")
    }

    @Test func buildsAddressURLForKnownClusterWithoutRPCSecrets() throws {
        let rpcURL = try #require(URL(string: "https://devnet.helius-rpc.com/?api-key=secret"))
        let url = try #require(SolanaExplorer.addressURL(address: "vault-account", rpcURL: rpcURL))

        #expect(url.absoluteString == "https://explorer.solana.com/address/vault-account?cluster=devnet")
    }

    @Test func buildsInspectorURLForCredentialFreeCustomRPC() throws {
        let rpcURL = try #require(URL(string: "https://solana-rpc.web.helium.io/"))
        let url = try #require(SolanaExplorer.transactionInspectorURL(rpcURL: rpcURL))

        #expect(
            url.absoluteString ==
                "https://explorer.solana.com/tx/inspector?cluster=custom&customUrl=https://solana-rpc.web.helium.io/"
        )
    }

    @Test func buildsSquadsTransactionInspectorURL() throws {
        let rpcURL = try #require(URL(string: "https://api.devnet.solana.com"))
        let url = try #require(
            SolanaExplorer.squadsTransactionInspectorURL(
                transactionAddress: "DwnpZBEPSzvsrx8uFYZg8Ty5KN8kM8PCNXUcyXSeka",
                rpcURL: rpcURL
            )
        )

        #expect(
            url.absoluteString ==
                "https://explorer.solana.com/tx/inspector?cluster=devnet&squadsTx=DwnpZBEPSzvsrx8uFYZg8Ty5KN8kM8PCNXUcyXSeka"
        )
    }

    @Test func executedProposalLinkPrefersExecutionSignature() throws {
        let rpcURL = try #require(URL(string: "https://api.devnet.solana.com"))
        let link = try #require(SolanaExplorer.executedProposalLink(
            executionSignature: "signature-123",
            transactionAddress: "transaction-account",
            rpcURL: rpcURL
        ))

        #expect(link.kind == .executedTransaction)
        #expect(link.url.absoluteString == "https://explorer.solana.com/tx/signature-123?cluster=devnet")
    }

    @Test func executedProposalLinkFallsBackToTransactionAccount() throws {
        let rpcURL = try #require(URL(string: "https://api.devnet.solana.com"))
        let link = try #require(SolanaExplorer.executedProposalLink(
            executionSignature: nil,
            transactionAddress: "transaction-account",
            rpcURL: rpcURL
        ))

        #expect(link.kind == .transactionAccount)
        #expect(link.url.absoluteString == "https://explorer.solana.com/address/transaction-account?cluster=devnet")
    }

    @Test func executedProposalLinkRequiresShareableURL() throws {
        let rpcURL = try #require(URL(string: "https://rpc.example.com/?api-key=secret"))

        #expect(SolanaExplorer.executedProposalLink(
            executionSignature: nil,
            transactionAddress: "transaction-account",
            rpcURL: rpcURL
        ) == nil)
    }

    @Test func omitsCredentialedUnknownRPCURL() throws {
        let rpcURL = try #require(URL(string: "https://rpc.example.com/?api-key=secret"))

        #expect(SolanaExplorer.transactionURL(signature: "abc123", rpcURL: rpcURL) == nil)
        #expect(SolanaExplorer.addressURL(address: "vault-account", rpcURL: rpcURL) == nil)
    }

    @Test func omitsUnknownRPCURLWithPath() throws {
        let rpcURL = try #require(URL(string: "https://rpc.example.com/v2/secret"))

        #expect(SolanaExplorer.transactionURL(signature: "abc123", rpcURL: rpcURL) == nil)
        #expect(SolanaExplorer.transactionInspectorURL(rpcURL: rpcURL) == nil)
    }
}
