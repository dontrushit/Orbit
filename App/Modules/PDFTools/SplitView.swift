import OrbitKit
import SwiftUI

/// Pages of one document: pick some, then save them in one file or each in its own.
struct SplitView: View {
    @Bindable var model: PDFPagesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Picker("Save As", selection: $model.splitOutput) {
                    Text("Selected pages in one file").tag(PDFPagesModel.SplitOutput.oneFile)
                    Text("Each selected page as a separate file").tag(PDFPagesModel.SplitOutput.separateFiles)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Spacer()
                Button("Select All") { model.arrangement.setAllIncluded(true) }
                    .keyboardShortcut("a")
                Button("Deselect All") { model.arrangement.setAllIncluded(false) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            .disabled(model.phase != .ready)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if model.phase == .loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PageGrid(arrangement: $model.arrangement, thumbnails: model.thumbnails, style: .selection)
                    .disabled(model.phase == .saving)
            }

            Divider()

            HStack {
                if model.phase == .saving {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.splitOutput == .oneFile ? LocalizedStringKey("Extracting…") : "Splitting…")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Click a page to select it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.phase == .ready {
                    Text("\(model.arrangement.includedCount) selected")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.phase == .saving)
                // "Split" for separate files; one file is taken out of the document rather than split from it.
                Button(model.splitOutput == .oneFile ? LocalizedStringKey("Extract") : "Split", action: model.perform)
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
