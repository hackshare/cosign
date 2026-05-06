import Foundation
import Testing
@testable import Indexer

struct HTTPRelayClientTests {
    @Test func buildsMemberSquadsURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.memberSquadsURL(for: MemberSquadsRequest(memberAddress: "member111"))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/members/member111/squads?token=secret")
    }

    @Test func buildsProposalInspectionURL() throws {
        let client = try HTTPRelayClient(baseURL: #require(URL(string: "https://relay.cosign.example/api/")))

        let url = client.proposalInspectionURL(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/squads/squad111/transactions/7/inspection")
    }

    @Test func gatesURLsByAdvertisedCapabilities() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api/")),
            capabilities: [.proposalInspection]
        )

        #expect(client.proposalInspectionURL(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        )) != nil)
        #expect(client.squadDetailURL(for: SquadDetailRequest(squadAddress: "squad111")) == nil)
    }

    @Test func buildsSquadDetailURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.squadDetailURL(for: SquadDetailRequest(squadAddress: "squad111"))

        #expect(url?.absoluteString == "https://relay.cosign.example/api/cosign/v1/squads/squad111?token=secret")
    }

    @Test func buildsSquadProposalsURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.squadProposalsURL(for: SquadProposalsRequest(
            squadAddress: "squad111",
            fromIndex: 2,
            toIndex: 4
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/squads/squad111/proposals?token=secret&from=2&to=4")
    }

    @Test func buildsSquadProposalURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.squadProposalURL(for: SquadProposalRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/squads/squad111/proposals/7?token=secret")
    }

    @Test func buildsAccountActivityURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.accountActivityURL(for: AccountActivityRequest(
            address: "account111",
            beforeSignature: "signature111",
            limit: 25
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/accounts/account111/activity?token=secret&limit=25&before=signature111")
    }

    @Test func preservesRelayQueryItems() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.proposalInspectionURL(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/squads/squad111/transactions/7/inspection?token=secret")
    }

    @Test func buildsProposalInspectionJSONURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.proposalInspectionJSONURL(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/squads/squad111/transactions/7/inspection?token=secret&format=json")
    }

    @Test func buildsExecutedTransactionInspectionURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.executedTransactionInspectionURL(for: ExecutedTransactionInspectionRequest(
            signature: "signature111"
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/transactions/signature111/inspection?token=secret")
    }

    @Test func buildsExecutedTransactionInspectionJSONURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.executedTransactionInspectionJSONURL(for: ExecutedTransactionInspectionRequest(
            signature: "signature111"
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/transactions/signature111/inspection?token=secret&format=json")
    }

    @Test func buildsTransactionStatusURL() throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example/api?token=secret"))
        )

        let url = client.transactionStatusURL(for: TransactionStatusRequest(signature: "signature111"))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/api/cosign/v1/transactions/signature111/status?token=secret")
    }

    @Test func doesNotPutRPCURLIntoInspectionLinks() throws {
        let client = try HTTPRelayClient(baseURL: #require(URL(string: "https://relay.cosign.example")))

        let url = client.proposalInspectionURL(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(url?
            .absoluteString ==
            "https://relay.cosign.example/cosign/v1/squads/squad111/transactions/7/inspection")
    }
}

struct HTTPRelayClientResponseTests {
    @Test func decodesMemberSquadsResponse() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: memberSquadsJSON)
        )

        let response = try await client.memberSquads(for: MemberSquadsRequest(memberAddress: "member111"))

        #expect(response.member == "member111")
        #expect(response.squads.count == 2)
        #expect(response.squads.first?.address == "squad111")
        #expect(response.squads.first?.threshold == 1)
    }

    @Test func decodesSquadDetailResponse() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: squadDetailJSON)
        )

        let response = try await client.squadDetail(for: SquadDetailRequest(squadAddress: "squad111"))

        #expect(response.squad.address == "squad111")
        #expect(response.squad.threshold == 2)
        #expect(response.squad.members.first?.pubkey == "member111")
        #expect(response.squad.members.first?.canVote == true)
        #expect(response.squad.vaults.first?.address == "vault111")
    }

    @Test func decodesSquadProposalsResponse() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: squadProposalsJSON)
        )

        let response = try await client.squadProposals(for: SquadProposalsRequest(
            squadAddress: "squad111",
            fromIndex: 1,
            toIndex: 2
        ))

        #expect(response.squad == "squad111")
        #expect(response.range.fromIndex == 1)
        #expect(response.proposals.first?.transactionIndex == 2)
        #expect(response.proposals.first?.votesYes == 1)
    }

    @Test func decodesSquadProposalResponse() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: squadProposalJSON)
        )

        let response = try await client.squadProposal(for: SquadProposalRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(response.squad == "squad111")
        #expect(response.proposal.transactionIndex == 7)
        #expect(response.proposal.votes.approve == 1)
        #expect(response.proposal.instructions.first?.summary == "Transfer 1 SOL")
    }

    @Test func decodesAccountActivityResponse() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: accountActivityJSON)
        )

        let response = try await client.accountActivity(for: AccountActivityRequest(address: "account111", limit: 5))

        #expect(response.address == "account111")
        #expect(response.limit == 5)
        #expect(response.activity.first?.signature == "signature111")
        #expect(response.activity.first?.slot == 42)
        #expect(response.activity.first?.action?.summary == "Transfer 0.001 SOL")
    }

    @Test func decodesTransactionStatusResponse() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: transactionStatusJSON)
        )

        let response = try await client.transactionStatus(
            for: TransactionStatusRequest(signature: "signature111")
        )

        #expect(response.signature == "signature111")
        #expect(response.status.status == "confirmed")
        #expect(response.status.slot == 42)
        #expect(response.status.error == nil)
    }

    @Test func decodesProposalInspectionReport() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: proposalInspectionJSON)
        )

        let report = try await client.proposalInspectionReport(for: ProposalInspectionRequest(
            squadAddress: "squad111",
            transactionIndex: 7
        ))

        #expect(report.squad == "squad111")
        #expect(report.simulation.status == "succeeded")
        #expect(report.simulation.feePayer == "fee111")
        #expect(report.proposal.transactionIndex == 7)
        #expect(report.proposal.votes.approve == 1)
        #expect(report.action?.classification == "sol_transfer")
        #expect(report.action?.effects.first?.amount == "1 SOL")
        #expect(report.proposal.instructions.first?.summary == "Transfer 1 SOL")
    }

    @Test func decodesExecutedTransactionInspectionReport() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(response: executedTransactionInspectionJSON)
        )

        let report = try await client.executedTransactionInspectionReport(
            for: ExecutedTransactionInspectionRequest(signature: "signature111")
        )

        #expect(report.signature == "signature111")
        #expect(report.status.status == "finalized")
        #expect(report.action.classification == "sol_transfer")
        #expect(report.action.effects.first?.destination == "destination111")
        #expect(report.logs.first == "Program log: success")
    }

    @Test func surfacesRelayJSONErrorMessages() async throws {
        let client = try HTTPRelayClient(
            baseURL: #require(URL(string: "https://relay.cosign.example")),
            session: mockRelaySession(
                response: """
                {
                  "ok": false,
                  "error": {
                    "code": "rpc_error",
                    "message": "upstream RPC unavailable"
                  }
                }
                """,
                statusCode: 502
            )
        )

        do {
            _ = try await client.memberSquads(for: MemberSquadsRequest(memberAddress: "member111"))
            Issue.record("Expected relay request to fail.")
        } catch let error as RelayClientError {
            #expect(error == .httpStatus(502, message: "upstream RPC unavailable"))
            #expect(error.localizedDescription == "Relay returned HTTP 502: upstream RPC unavailable")
        }
    }
}
