import SwiftUI

struct AdvancedDocumentsView: View {
    @Bindable var store: StudioStore
    @State private var selection = BookDocument.advanced.first?.id

    var body: some View {
        VStack(spacing: 0) {
            selector
            Divider()
            if let selectedDocument {
                DocumentEditorView(store: store, document: selectedDocument)
                    .id(selectedDocument.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Writing Rules")
    }

    private var selector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Writing rules").font(.headline)
                    Text("Advanced and reusable. You normally do not need to change these.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BookDocument.advanced) { document in
                        Button {
                            selection = document.id
                        } label: {
                            Label(document.title, systemImage: document.symbol)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .foregroundStyle(selection == document.id ? .white : .primary)
                                .background(
                                    selection == document.id ? AnyShapeStyle(StudioTheme.plum) : AnyShapeStyle(.quaternary),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var selectedDocument: BookDocument? {
        BookDocument.advanced.first { $0.id == selection }
    }
}
