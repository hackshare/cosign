import Indexer

public struct MintInfo: Equatable, Sendable {
    public let symbol: String
    public let decimals: Int

    public init(symbol: String, decimals: Int) {
        self.symbol = symbol
        self.decimals = decimals
    }
}

public enum WhenPredicate {
    public static func holds(_ literals: [String], args: [String: DecodedArgValue]) -> Bool {
        for literal in literals {
            let negated = literal.hasPrefix("!")
            let inner = negated ? String(literal.dropFirst()) : literal
            guard inner.hasPrefix("arg("), inner.hasSuffix(")") else { return false }
            let name = String(inner.dropFirst(4).dropLast())
            guard case let .bool(flag) = args[name] else { return false }
            if flag == negated { return false }
        }
        return true
    }
}

public struct DecodeSpecTemplateRenderer {
    public init() {}

    public func render(
        _ variants: [DecodeSpec.TemplateVariant],
        args: [String: DecodedArgValue],
        accounts: [String],
        roleIndexes: [String: Int],
        mints: [String: MintInfo]
    ) -> String? {
        guard let variant = variants.first(where: { WhenPredicate.holds($0.when, args: args) }) else {
            return nil
        }
        return interpolate(variant.text, args: args, accounts: accounts, roleIndexes: roleIndexes, mints: mints)
    }

    private func interpolate(
        _ text: String,
        args: [String: DecodedArgValue],
        accounts: [String],
        roleIndexes: [String: Int],
        mints: [String: MintInfo]
    ) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[rest.startIndex ..< open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                result += rest[open...]
                return result
            }
            let token = String(rest[rest.index(after: open) ..< close])
            result += resolve(token, args: args, accounts: accounts, roleIndexes: roleIndexes, mints: mints)
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }

    private func resolve(
        _ token: String,
        args: [String: DecodedArgValue],
        accounts: [String],
        roleIndexes: [String: Int],
        mints: [String: MintInfo]
    ) -> String {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard let lhs = parts.first else { return "?" }
        let formatter = parts.count > 1 ? parts[1] : ""

        if formatter == "token" {
            return mintSymbol(role: lhs, accounts: accounts, roleIndexes: roleIndexes, mints: mints)
        }
        if formatter == "sol" {
            return solAmount(args[lhs])
        }
        if formatter.hasPrefix("token("), formatter.hasSuffix(")") {
            let role = String(formatter.dropFirst(6).dropLast())
            return tokenAmount(args[lhs], role: role, accounts: accounts, roleIndexes: roleIndexes, mints: mints)
        }
        return args[lhs]?.rendered ?? "?"
    }

    private func mint(
        role: String,
        accounts: [String],
        roleIndexes: [String: Int],
        mints: [String: MintInfo]
    ) -> (String, MintInfo?) {
        guard let index = roleIndexes[role], accounts.indices.contains(index) else {
            return ("?", nil)
        }
        let address = accounts[index]
        return (address, mints[address])
    }

    private func mintSymbol(
        role: String,
        accounts: [String],
        roleIndexes: [String: Int],
        mints: [String: MintInfo]
    ) -> String {
        let (address, info) = mint(role: role, accounts: accounts, roleIndexes: roleIndexes, mints: mints)
        return info?.symbol ?? InstructionDecoder.shortAddress(address)
    }

    private func tokenAmount(
        _ value: DecodedArgValue?,
        role: String,
        accounts: [String],
        roleIndexes: [String: Int],
        mints: [String: MintInfo]
    ) -> String {
        guard case let .uint(raw) = value else { return value?.rendered ?? "?" }
        let (address, info) = mint(role: role, accounts: accounts, roleIndexes: roleIndexes, mints: mints)
        guard let info else {
            return "\(raw) (\(InstructionDecoder.shortAddress(address)))"
        }
        return "\(InstructionDecoder.decimalAmount(raw, decimals: UInt8(max(0, min(info.decimals, 255))))) \(info.symbol)"
    }

    private func solAmount(_ value: DecodedArgValue?) -> String {
        guard case let .uint(lamports) = value else { return value?.rendered ?? "?" }
        return InstructionDecoder.solAmount(lamports)
    }
}
