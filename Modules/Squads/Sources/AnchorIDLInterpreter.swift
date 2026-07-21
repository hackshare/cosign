import Indexer

public struct ResolvedProgramIDL: Equatable, Sendable {
    public let document: AnchorIDLDocument
    public let provenance: DecodeProvenance

    public init(document: AnchorIDLDocument, provenance: DecodeProvenance) {
        self.document = document
        self.provenance = provenance
    }
}

public struct AnchorIDLInterpreter: Sendable {
    public init() {}

    public func interpret(
        _ instruction: SquadDecodedInstruction,
        resolved: ResolvedProgramIDL,
        accounts: [String]
    ) -> DecodedInstructionDisplay? {
        guard
            let bytes = InstructionDecoder.bytes(fromHex: instruction.rawDataHex),
            bytes.count >= 8
        else {
            return nil
        }

        let discriminator = Array(bytes.prefix(8))
        guard let match = resolved.document.instructions.first(where: { $0.discriminator == discriminator })
        else {
            return nil
        }

        let arguments = renderArguments(match.arguments, bytes: bytes)
        let label = resolved.document.name.isEmpty
            ? InstructionDecoder.shortAddress(instruction.program)
            : resolved.document.name

        return DecodedInstructionDisplay(
            programLabel: label,
            kind: match.name,
            summary: "\(match.name)(\(arguments.joined(separator: ", ")))",
            accounts: accounts,
            dataHex: instruction.rawDataHex,
            provenance: resolved.provenance
        )
    }

    private func renderArguments(_ arguments: [AnchorIDLArgument], bytes: [UInt8]) -> [String] {
        var reader = BorshArgumentReader(bytes: bytes, offset: 8)
        var rendered = [String]()

        for (index, argument) in arguments.enumerated() {
            switch reader.read(argument.type) {
            case let .rendered(value):
                rendered.append("\(argument.name): \(value)")
            case .skipped:
                rendered.append(argument.name)
            case .stop:
                rendered.append(contentsOf: arguments[index...].map(\.name))
                return rendered
            }
        }
        return rendered
    }
}
