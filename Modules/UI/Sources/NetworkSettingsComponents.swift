import Indexer
import SwiftUI

struct EndpointDetailsSection: View {
    let title: String
    let info: RPCURLInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: title)
            CosignCard {
                VStack(spacing: 0) {
                    CosignKeyValueRow(
                        label: CosignCopy.Network.provider,
                        value: CosignCopy.Network.providerName(info.provider)
                    )
                    CosignKeyValueRow(
                        label: CosignCopy.Network.cluster,
                        value: CosignCopy.Network.clusterName(info.cluster)
                    )
                    CosignKeyValueRow(label: CosignCopy.Network.host, value: info.host)
                    CosignKeyValueRow(
                        label: CosignCopy.Network.credentials,
                        value: CosignCopy.Network.credentialsValue(hasCredentials: info.hasCredentials),
                        isLast: true
                    )
                }
            }
        }
    }
}
