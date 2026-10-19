import OrbitKit
import SwiftUI

/// Pages of all chosen documents in one grid: drag to reorder, click to leave a page out, then Merge.
struct MergeView: View {
    @Bindable var model: PDFPagesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: model.documents.map(\.lastPathComponent).joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.phase != .loading {
                    Text("\(model.arrangement.includedCount) of \(model.totalCount) pages")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if model.phase == .loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PageGrid(arrangement: $model.arrangement, thumbnails: model.thumbnails)
                    .disabled(model.phase == .saving)
            }

            Divider()

            HStack {
                if model.phase == .saving {
                    ProgressView()
                        .controlSize(.small)
                    Text("Merging…")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Click a page to exclude it. Drag to reorder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.phase == .saving)
                Button("Merge", action: model.perform)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canPerform)
            }
            .padding(16)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.dismissAlert() } }),
            presenting: model.alert
        ) { _ in
            Button("OK") { model.dismissAlert() }
        } message: { alert in
            Text(alert.message)
        }
    }
}
