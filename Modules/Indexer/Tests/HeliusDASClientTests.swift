import Foundation
import Testing
@testable import Indexer

struct HeliusDASClientTests {
    @Test func parsesAssetsByOwnerEnvelope() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "id": "cosign",
          "result": {
            "items": [
              {
                "id": "token-mint",
                "interface": "FungibleToken",
                "content": {
                  "metadata": { "name": "USD Coin", "symbol": "USDC" },
                  "links": { "image": "https://example.com/usdc.png" }
                },
                "token_info": {
                  "symbol": "USDC",
                  "balance": "1234500",
                  "ui_amount_string": "1.2345",
                  "decimals": 6
                }
              },
              {
                "id": "nft-mint",
                "interface": "V1_NFT",
                "content": {
                  "metadata": { "name": "Cosign Pass", "symbol": "PASS" },
                  "links": { "image": "https://example.com/pass.png" }
                }
              }
            ]
          }
        }
        """

        let assets = try HeliusDASClient.decodeAssetsByOwnerResponse(Data(json.utf8))

        #expect(assets.count == 2)
        #expect(assets[0] == DASAsset(
            id: "token-mint",
            symbol: "USDC",
            name: "USD Coin",
            tokenAmount: "1234500",
            tokenDisplayAmount: "1.2345",
            decimals: 6,
            imageURI: URL(string: "https://example.com/usdc.png"),
            kind: .fungible
        ))
        #expect(assets[1].id == "nft-mint")
        #expect(assets[1].name == "Cosign Pass")
        #expect(assets[1].kind == .nft)
    }

    @Test func surfacesJSONRPCError() {
        let json = """
        {
          "jsonrpc": "2.0",
          "id": "cosign",
          "error": { "code": -32000, "message": "bad request" }
        }
        """

        do {
            _ = try HeliusDASClient.decodeAssetsByOwnerResponse(Data(json.utf8))
            Issue.record("Expected RPC error")
        } catch let error as HeliusDASClientError {
            #expect(error == .rpcError(code: -32000, message: "bad request"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func parsesTokenAccountsByOwnerEnvelope() throws {
        let assets = try HeliusDASClient.decodeTokenAccountsByOwnerResponse(
            Data(tokenAccountsByOwnerJSON.utf8)
        )

        #expect(assets == [
            DASAsset(
                id: "token-mint",
                symbol: nil,
                name: "token-mint",
                tokenAmount: "250000000",
                tokenDisplayAmount: "250",
                decimals: 6,
                accountAddress: "token-account",
                tokenProgramID: HeliusDASClient.tokenProgramID,
                imageURI: nil,
                kind: .fungible
            )
        ])
    }

    @Test func tokenAccountFallbackKeepsSuccessfulProgramResults() async throws {
        let client = try HeliusDASClient(
            rpcURL: #require(URL(string: "http://127.0.0.1:8899")),
            session: mockRPCSession(responses: [
                methodNotFoundJSON,
                tokenAccountsByOwnerJSON,
                token2022AccountsByOwnerJSON
            ])
        )

        let assets = try await client.getAssetsByOwner(owner: "vault")

        #expect(assets.map(\.id) == ["token-2022-mint", "token-mint"])
        #expect(assets.map(\.tokenAmount) == ["750000000", "250000000"])
        #expect(assets.map(\.tokenDisplayAmount) == ["750", "250"])
        #expect(assets.map(\.tokenProgramID) == [
            HeliusDASClient.token2022ProgramID,
            HeliusDASClient.tokenProgramID
        ])
    }

    @Test func tokenAccountFallbackIgnoresSingleProgramFailure() async throws {
        let client = try HeliusDASClient(
            rpcURL: #require(URL(string: "http://127.0.0.1:8899")),
            session: mockRPCSession(responses: [
                methodNotFoundJSON,
                tokenAccountsByOwnerJSON,
                token2022WrongSizeJSON
            ])
        )

        let assets = try await client.getAssetsByOwner(owner: "vault")

        #expect(assets.map(\.id) == ["token-mint"])
        #expect(assets.first?.tokenAmount == "250000000")
    }
}

private func mockRPCSession(responses: [String]) -> URLSession {
    MockRPCURLProtocol.responses = responses.map { Data($0.utf8) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockRPCURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockRPCURLProtocol: URLProtocol {
    static var responses = [Data]()

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let data = Self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let methodNotFoundJSON = """
{
  "jsonrpc": "2.0",
  "id": "cosign",
  "error": {
    "code": -32601,
    "message": "Method not found"
  }
}
"""

private let token2022WrongSizeJSON = """
{
  "jsonrpc": "2.0",
  "id": "cosign",
  "error": {
    "code": -32602,
    "message": "Invalid param: WrongSize"
  }
}
"""

private let token2022AccountsByOwnerJSON = """
{
  "jsonrpc": "2.0",
  "id": "cosign",
  "result": {
    "value": [
      {
        "pubkey": "token-2022-account",
        "account": {
          "data": {
            "parsed": {
              "info": {
                "mint": "token-2022-mint",
                "tokenAmount": {
                  "amount": "750000000",
                  "uiAmountString": "750",
                  "decimals": 6
                }
              },
              "type": "account"
            },
            "program": "spl-token-2022"
          }
        }
      }
    ]
  }
}
"""

private let tokenAccountsByOwnerJSON = """
{
  "jsonrpc": "2.0",
  "id": "cosign",
  "result": {
    "value": [
      {
        "pubkey": "token-account",
        "account": {
          "data": {
            "parsed": {
              "info": {
                "mint": "token-mint",
                "tokenAmount": {
                  "amount": "250000000",
                  "uiAmountString": "250",
                  "decimals": 6
                }
              },
              "type": "account"
            },
            "program": "spl-token"
          }
        }
      },
      {
        "pubkey": "empty-token-account",
        "account": {
          "data": {
            "parsed": {
              "info": {
                "mint": "empty-token-mint",
                "tokenAmount": {
                  "amount": "0",
                  "decimals": 9
                }
              },
              "type": "account"
            },
            "program": "spl-token"
          }
        }
      }
    ]
  }
}
"""
