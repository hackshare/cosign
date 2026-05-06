import SwiftUI

enum ReadPollingInterval {
    static let activity: Duration = .seconds(5)
    static let detail: Duration = .seconds(5)
    static let list: Duration = .seconds(15)
    static let proposal: Duration = .seconds(5)
}

extension View {
    func pollingRefresh(
        id: String,
        interval: Duration,
        enabled: Bool = true,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        modifier(PollingRefreshModifier(
            id: id,
            interval: interval,
            enabled: enabled,
            action: action
        ))
    }
}

private struct PollingRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let id: String
    let interval: Duration
    let enabled: Bool
    let action: @MainActor @Sendable () async -> Void

    func body(content: Content) -> some View {
        content.task(id: taskID) {
            guard enabled, scenePhase == .active else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }
                await action()
            }
        }
    }

    private var taskID: String {
        "\(id)-\(scenePhase)-\(enabled)"
    }
}
