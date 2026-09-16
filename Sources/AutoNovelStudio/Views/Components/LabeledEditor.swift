import SwiftUI

struct LabeledEditor: View {
    let title: String
    var prompt: String = ""
    @Binding var text: String
    var minHeight: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: minHeight)
                if text.isEmpty, !prompt.isEmpty {
                    Text(prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(.quaternary)
            }
        }
    }
}
