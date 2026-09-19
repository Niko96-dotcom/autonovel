import SwiftUI

struct DashboardLiveConsoleView: View {
    @Bindable var store: StudioStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Live output")
                Spacer()
                StatusPill(
                    text: store.runner.isRunning ? "Running" : (store.runner.exitCode == 0 ? "Finished" : "Stopped"),
                    color: store.runner.isRunning ? StudioTheme.accent : (store.runner.exitCode == 0 ? StudioTheme.success : .secondary),
                    animated: store.runner.isRunning
                )
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(String(store.runner.output.suffix(12_000)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(16)
                        .id("console-end")
                }
                .frame(minHeight: 140, maxHeight: 260)
                .background(StudioTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white.opacity(0.78))
                .onChange(of: store.runner.output) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo("console-end", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("console-end", anchor: .bottom) }
                    }
                }
            }
        }
    }
}
