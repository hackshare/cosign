import CosignCore
import SwiftUI

extension AddLedgerView {
    var checklistStep: some View {
        CosignAnchoredFooterScreen {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(CosignCopy.Ledger.checklistEyebrow.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(CosignCopy.Ledger.checklistTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.Ledger.checklistSubtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Ledger.labelFieldTitle)
                CosignCard {
                    TextField(CosignCopy.Ledger.defaultLabel, text: $label)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .cosignField()
                }
            }

            LedgerChecklistCard(items: checklistItems)

            CosignInlineBanner(tone: .neutral) {
                Text(CosignCopy.Ledger.privacyNote)
            }
        } footer: {
            Button(CosignCopy.Ledger.startScanButton) {
                Task { await startScan() }
            }
            .buttonStyle(CosignButtonStyle(kind: .accent))
            .disabled(trimmedLabel.isEmpty)
            .accessibilityIdentifier("ledger-start-scan")
        }
    }

    private var checklistItems: [LedgerChecklistItem] {
        [
            LedgerChecklistItem(title: CosignCopy.Ledger.checklistStepUnlock, state: .done),
            LedgerChecklistItem(title: CosignCopy.Ledger.checklistStepSolanaApp, state: .done),
            LedgerChecklistItem(title: CosignCopy.Ledger.checklistStepBluetooth, state: .active),
            LedgerChecklistItem(title: CosignCopy.Ledger.checklistStepProximity, state: .pending)
        ]
    }

    var searchingStep: some View {
        CosignAnchoredFooterScreen {
            header

            VStack(spacing: 18) {
                LedgerRadarView()
                VStack(spacing: 6) {
                    Text(CosignCopy.Ledger.searchingTitle)
                        .font(CosignTheme.FontStyle.titleL)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.Ledger.searchingSubtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            if phase == .found {
                VStack(alignment: .leading, spacing: 10) {
                    CosignSectionTitle(title: CosignCopy.Ledger.foundSectionTitle(count: devices.count))
                    ForEach(devices) { device in
                        LedgerFoundDeviceRow(device: device, isSelected: selectedDeviceID == device.id) {
                            selectedDeviceID = device.id
                        }
                    }
                }
            }
        } footer: {
            Button(CosignCopy.Ledger.connectButton) {
                guard let selectedDevice else { return }
                Task { await connectAndVerify(selectedDevice) }
            }
            .buttonStyle(CosignButtonStyle(kind: .accent, isLoading: phase == .searching))
            .disabled(selectedDevice == nil)
            .accessibilityIdentifier("ledger-connect")
        }
    }

    var connectingStep: some View {
        CosignScreen {
            header
            VStack(spacing: 18) {
                LedgerRadarView()
                Text(CosignCopy.Ledger.connectingTitle(deviceName: connectingDeviceName ?? ""))
                    .font(CosignTheme.FontStyle.titleL)
                    .foregroundStyle(CosignTheme.ink)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    var verifyStep: some View {
        CosignScreen {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(CosignCopy.Ledger.verifyEyebrow.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(CosignCopy.Ledger.verifyTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.Ledger.verifySubtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            CosignCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CosignCopy.Ledger.addressFieldTitle.uppercased())
                        .font(CosignTheme.FontStyle.eyebrow)
                        .foregroundStyle(CosignTheme.inkFaint)
                    Text(derivedAddress ?? "")
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(CosignTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 8) {
                LedgerDeviceMark(size: 110)
                HStack(spacing: 8) {
                    Circle().fill(CosignTheme.riskAmber).frame(width: 8, height: 8)
                    Text(CosignCopy.Ledger.waitingForApproval)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.riskAmber)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            CosignInlineBanner(tone: .amber) {
                Text(CosignCopy.Ledger.verifyCautionNote)
            }
        }
    }

    var readyStep: some View {
        CosignAnchoredFooterScreen {
            header

            VStack(spacing: 18) {
                CosignGlyphView(glyph: .check, size: 30, color: CosignTheme.mint)
                    .frame(width: 72, height: 72)
                    .background(CosignTheme.mintWash, in: .circle)
                    .overlay { Circle().stroke(CosignTheme.mint.opacity(0.40), lineWidth: 1) }

                VStack(spacing: 8) {
                    Text(CosignCopy.Ledger.readyTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.Ledger.readySubtitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            LedgerSignerSummaryCard(
                deviceName: pairedDevice?.name ?? trimmedLabel,
                address: pairedAddress ?? ""
            )
        } footer: {
            Button(CosignCopy.Ledger.doneButtonTitle) {
                dismiss()
            }
            .buttonStyle(CosignButtonStyle(kind: .primary))
            .accessibilityIdentifier("ledger-done")
        }
    }

    var recoveryStep: some View {
        CosignScreen {
            header
            if let recovery {
                LedgerRecoveryCard(recovery: recovery) {
                    Task { await performRecovery(recovery) }
                }
            }
        }
    }
}
