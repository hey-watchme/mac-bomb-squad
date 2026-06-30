import SwiftUI

/// History section placeholder. Review/transform history persistence is not yet
/// implemented (no data layer), so this is intentionally a "coming soon" state.
struct HistoryPlaceholderView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("履歴")
                .font(.title2.weight(.semibold))
            Text("レビュー・変換した内容の履歴は近日対応予定です。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("履歴")
    }
}
