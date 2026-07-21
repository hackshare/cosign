import Indexer

public struct DecodeSpecInterpreter: Sendable {
    public init() {}

    public func interpret(
        _ instruction: SquadDecodedInstruction,
        spec: DecodeSpec,
        resolvedIDL: ResolvedProgramIDL?,
        accounts: [String],
        mints: [String: MintInfo],
        crossCheck: CrossCheckContext? = nil
    ) -> DecodedInstructionDisplay? {
        guard !spec.discriminator.isEmpty else {
            return nil
        }

        guard
            let bytes = InstructionDecoder.bytes(fromHex: instruction.rawDataHex),
            bytes.count >= spec.discriminator.count,
            Array(bytes.prefix(spec.discriminator.count)) == spec.discriminator
        else {
            return nil
        }

        guard let fields = fields(for: spec, resolvedIDL: resolvedIDL) else {
            return nil
        }
        let args = decodeArguments(bytes: bytes, offset: spec.discriminator.count, fields: fields)

        // M1: the chosen variant's referenced args must all be present, else fall through.
        guard
            let variant = spec.template.first(where: { WhenPredicate.holds($0.when, args: args) }),
            Self.referencedArgNames(in: variant.text).allSatisfy({ args[$0] != nil }),
            let statement = DecodeSpecTemplateRenderer().render(
                spec.template, args: args, accounts: accounts, roleIndexes: spec.accounts, mints: mints
            )
        else {
            return nil
        }

        let verdict: CrossCheckVerdict? = crossCheck.map { context in
            let expected = ExpectedAssetMovementBuilder.build(
                spec: spec, args: args, accounts: accounts, resolvedMints: context.resolvedMints
            )
            return EffectCrossCheck.verdict(expected: expected, simulated: context.simulated)
        }

        let resolvedName: String? = if let name = resolvedIDL?.document.name, !name.isEmpty { name } else { nil }
        let boundProgram = spec.mode == .bindIdl ? resolvedName : nil
        return DecodedInstructionDisplay(
            programLabel: resolvedName ?? InstructionDecoder.shortAddress(instruction.program),
            kind: spec.action,
            summary: statement,
            accounts: accounts,
            dataHex: instruction.rawDataHex,
            provenance: .registry(action: spec.action, source: "Cosign", boundProgram: boundProgram),
            crossCheck: verdict
        )
    }

    /// Names referenced by `{name}` / `{name:sol}` / `{name:token(role)}` tokens. A
    /// `{role:token}` token (formatter is exactly "token") names an account role, not
    /// an arg, so it is excluded from the presence check.
    static func referencedArgNames(in text: String) -> [String] {
        var names = [String]()
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let token = rest[rest.index(after: open) ..< close]
            let parts = token.split(separator: ":", maxSplits: 1)
            if let lhs = parts.first, !(parts.count > 1 && parts[1] == "token") {
                names.append(String(lhs))
            }
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    private func fields(for spec: DecodeSpec, resolvedIDL: ResolvedProgramIDL?) -> [(
        name: String,
        type: AnchorIDLType
    )]? {
        switch spec.mode {
        case .standalone:
            return (spec.layout ?? []).map { ($0.name, $0.type) }
        case .bindIdl:
            guard
                let resolvedIDL,
                case let .onChainIDL(_, hash, _) = resolvedIDL.provenance,
                let pinned = spec.bindsIdlHash,
                pinned == hash,
                let match = resolvedIDL.document.instructions
                .first(where: { $0.discriminator == spec.discriminator })
            else { return nil }
            return match.arguments.map { ($0.name, $0.type) }
        }
    }
}
