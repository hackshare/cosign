import Squads
import SwiftUI

extension ManageSquadConfigView {
    // MARK: - Time lock section

    /// Decompose a raw second count into the largest whole unit representable
    /// by the custom input (days → hours → minutes; empty string when zero).
    static func decomposeTimeLock(_ seconds: UInt32) -> (String, TimeLockUnit) {
        guard seconds > 0 else { return ("", .hours) }
        if seconds % TimeLockUnit.days.seconds == 0 {
            return (String(seconds / TimeLockUnit.days.seconds), .days)
        }
        if seconds % TimeLockUnit.hours.seconds == 0 {
            return (String(seconds / TimeLockUnit.hours.seconds), .hours)
        }
        if seconds % TimeLockUnit.minutes.seconds == 0 {
            return (String(seconds / TimeLockUnit.minutes.seconds), .minutes)
        }
        // Sub-minute granularity is not representable by any unit picker option.
        return ("", .hours)
    }

    private static let timeLockPresets: [(label: String, seconds: UInt32)] = [
        (CosignCopy.ManageSquad.timeLockOff, 0),
        ("1h", 3600),
        ("6h", 21600),
        ("24h", 86400),
        ("3d", 259_200),
        ("7d", 604_800)
    ]

    func timeLockSection(_ detail: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ManageSquad.timeLockSection)
            CosignCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(CosignCopy.ManageSquad.timeLockSubtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                    Text(CosignCopy.ManageSquad.timeLockCurrent(cosignTimeLockDisplay(seconds: detail.timeLockSeconds)))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)

                    timeLockPresetChips(detail)

                    if timeLockCustomExpanded {
                        timeLockCustomInput
                    }

                    if timeLockSeconds != detail.timeLockSeconds {
                        Text(CosignCopy.ManageSquad.timeLockDiff(
                            old: cosignTimeLockDisplay(seconds: detail.timeLockSeconds),
                            new: cosignTimeLockDisplay(seconds: timeLockSeconds)
                        ))
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.mint)
                        .accessibilityIdentifier("manage-squad-timelock-diff")
                    }
                }
            }
        }
    }

    func timeLockPresetChips(_ detail: SquadDetail) -> some View {
        let staged = timeLockSeconds != detail.timeLockSeconds
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.timeLockPresets, id: \.label) { preset in
                    let selected = !timeLockCustomExpanded && timeLockSeconds == preset.seconds
                    timeLockChip(
                        label: preset.label,
                        selected: selected,
                        staged: selected && staged,
                        id: "manage-squad-timelock-preset-\(preset.label.lowercased())"
                    ) {
                        timeLockCustomExpanded = false
                        timeLockSeconds = preset.seconds
                    }
                }
                timeLockChip(
                    label: CosignCopy.ManageSquad.timeLockCustom,
                    selected: timeLockCustomExpanded,
                    staged: timeLockCustomExpanded && staged,
                    id: "manage-squad-timelock-preset-custom"
                ) {
                    timeLockCustomExpanded = true
                    // Seed the field from the current value so it's consistent with
                    // timeLockSeconds from the moment Custom is opened.
                    let (val, unit) = Self.decomposeTimeLock(timeLockSeconds)
                    timeLockCustomUnit = unit
                    timeLockCustomValue = val
                }
            }
        }
    }

    func timeLockChip(
        label: String,
        selected: Bool,
        staged: Bool,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(staged ? CosignTheme.mint : (selected ? CosignTheme.ink : CosignTheme.inkDim))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(
                    staged ? CosignTheme.mintWash : (selected ? CosignTheme.accentWash : CosignTheme.surface2),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    var timeLockCustomInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(CosignCopy.ManageSquad.timeLockCustomPlaceholder, text: $timeLockCustomValue)
                    .keyboardType(.numberPad)
                    .cosignField()
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("manage-squad-timelock-custom-value")
                    .onChange(of: timeLockCustomValue) { applyCustomTimeLock() }
                Picker("", selection: $timeLockCustomUnit) {
                    ForEach(TimeLockUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: timeLockCustomUnit) { applyCustomTimeLock() }
            }
            Text(CosignCopy.ManageSquad.timeLockCustomHint)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkFaint)
        }
    }
}
