import Foundation

func mockRelaySession(response: String, statusCode: Int = 200) -> URLSession {
    MockRelayURLProtocol.response = Data(response.utf8)
    MockRelayURLProtocol.statusCode = statusCode
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockRelayURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class MockRelayURLProtocol: URLProtocol {
    static var response = Data()
    static var statusCode = 200

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

let memberSquadsJSON = """
{
  "kind": "member_squads",
  "member": "member111",
  "cluster": null,
  "squads": [
    {
      "address": "squad111",
      "threshold": 1,
      "memberCount": 2,
      "transactionIndex": 7,
      "staleTransactionIndex": 0
    },
    {
      "address": "squad222",
      "threshold": 2,
      "memberCount": 3,
      "transactionIndex": 9,
      "staleTransactionIndex": 1
    }
  ]
}
"""

let squadDetailJSON = """
{
  "kind": "squad_detail",
  "cluster": null,
  "squad": {
    "address": "squad111",
    "threshold": 2,
    "timeLockSeconds": 30,
    "transactionIndex": 7,
    "staleTransactionIndex": 1,
    "members": [
      {
        "pubkey": "member111",
        "canInitiate": true,
        "canVote": true,
        "canExecute": false
      }
    ],
    "vaults": [
      {
        "index": 0,
        "address": "vault111"
      }
    ]
  }
}
"""

let squadProposalsJSON = """
{
  "kind": "squad_proposals",
  "squad": "squad111",
  "cluster": null,
  "range": {
    "from": 1,
    "to": 2
  },
  "proposals": [
    {
      "transactionIndex": 2,
      "status": "approved",
      "votesYes": 1,
      "votesNo": 0,
      "votesCancelled": 0,
      "threshold": 1
    },
    {
      "transactionIndex": 1,
      "status": "active",
      "votesYes": 0,
      "votesNo": 0,
      "votesCancelled": 0,
      "threshold": 1
    }
  ]
}
"""

let squadProposalJSON = """
{
  "kind": "squad_proposal",
  "squad": "squad111",
  "cluster": null,
  "proposal": {
    "transactionIndex": 7,
    "status": "Approved",
    "kind": "Vault",
    "threshold": 1,
    "votes": {
      "approve": 1,
      "reject": 0,
      "cancel": 0
    },
    "voters": {
      "approve": ["member111"],
      "reject": [],
      "cancel": []
    },
    "transactionAddress": "transaction111",
    "accountsReferenced": ["source111", "destination111"],
    "instructions": [
      {
        "program": "System Program",
        "kind": "transfer",
        "summary": "Transfer 1 SOL",
        "accounts": ["source111", "destination111"],
        "rawDataHex": "0200000000ca9a3b00000000"
      }
    ]
  }
}
"""

let accountActivityJSON = """
{
  "kind": "account_activity",
  "address": "account111",
  "cluster": null,
  "before": null,
  "limit": 5,
  "activity": [
    {
      "signature": "signature111",
      "slot": 42,
      "timestampUnix": 1778107000,
      "kind": "transaction",
      "error": null,
      "action": {
        "classification": "sol_transfer",
        "summary": "Transfer 0.001 SOL",
        "confidence": "high",
        "effects": [],
        "warnings": []
      }
    }
  ]
}
"""

let transactionStatusJSON = """
{
  "kind": "transaction_status",
  "signature": "signature111",
  "cluster": null,
  "status": {
    "slot": 42,
    "status": "confirmed",
    "error": null
  }
}
"""

let proposalInspectionJSON = """
{
  "kind": "squads_proposal_inspection",
  "squad": "squad111",
  "cluster": null,
  "action": {
    "classification": "sol_transfer",
    "summary": "Transfer 1 SOL",
    "confidence": "high",
    "effects": [
      {
        "kind": "sol_transfer",
        "summary": "Transfer 1 SOL",
        "program": "System Program",
        "asset": "SOL",
        "amount": "1 SOL",
        "source": "source111",
        "destination": "destination111"
      }
    ],
    "warnings": []
  },
  "simulation": {
    "status": "succeeded",
    "message": "Execution simulation completed successfully.",
    "error": null,
    "logs": ["Program log: success"],
    "feePayer": "fee111",
    "recentBlockhash": "blockhash111"
  },
  "proposal": {
    "transactionIndex": 7,
    "status": "Approved",
    "kind": "Vault",
    "threshold": 1,
    "votes": {
      "approve": 1,
      "reject": 0,
      "cancel": 0
    },
    "voters": {
      "approve": ["member111"],
      "reject": [],
      "cancel": []
    },
    "transactionAddress": "transaction111",
    "accountsReferenced": ["source111", "destination111"],
    "instructions": [
      {
        "program": "System Program",
        "kind": "transfer",
        "summary": "Transfer 1 SOL",
        "accounts": ["source111", "destination111"],
        "rawDataHex": "0200000000ca9a3b00000000"
      }
    ]
  }
}
"""

let executedTransactionInspectionJSON = """
{
  "kind": "executed_transaction_inspection",
  "signature": "signature111",
  "cluster": null,
  "status": {
    "status": "finalized",
    "slot": 42,
    "blockTime": 1778107000,
    "error": null
  },
  "action": {
    "classification": "sol_transfer",
    "summary": "Transfer 1 SOL",
    "confidence": "high",
    "effects": [
      {
        "kind": "sol_transfer",
        "summary": "Transfer 1 SOL",
        "program": "System Program",
        "asset": "SOL",
        "amount": "1 SOL",
        "source": "source111",
        "destination": "destination111"
      }
    ],
    "warnings": []
  },
  "logs": ["Program log: success"]
}
"""
