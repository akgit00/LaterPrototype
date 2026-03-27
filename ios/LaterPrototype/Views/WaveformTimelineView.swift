import SwiftUI

struct WaveformTimelineView: View {
    let memories: [Memory]
    let onMemorySelected: (Memory) -> Void
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedIndex: Int = 0

    private let waveformSamples: [CGFloat] = {
        var samples: [CGFloat] = []
        for i in 0..<200 {
            let x = Double(i) / 200.0
            let base = sin(x * .pi * 6) * 0.3
            let mid = sin(x * .pi * 14) * 0.2
            let detail = sin(x * .pi * 40) * 0.15
            let envelope = sin(x * .pi) * 0.8 + 0.2
            let noise = Double.random(in: -0.1...0.1)
            samples.append(CGFloat((base + mid + detail + noise) * envelope))
        }
        return samples
    }()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Scrollable Timeline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if memories.indices.contains(selectedIndex) {
                    Text(memories[selectedIndex].date, style: .date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 1) {
                    ForEach(Array(waveformSamples.enumerated()), id: \.offset) { index, sample in
                        let isHighlighted = isNearMemoryMarker(index: index)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isHighlighted ? Color.red : Color.primary.opacity(0.7))
                            .frame(width: 2, height: max(2, abs(sample) * 40 + 4))
                    }
                }
                .frame(height: 50)
                .padding(.horizontal, 16)
            }
            .contentMargins(.horizontal, 16)

            HStack(spacing: 0) {
                ForEach(Array(memories.enumerated()), id: \.element.id) { index, memory in
                    Button {
                        selectedIndex = index
                        onMemorySelected(memory)
                    } label: {
                        Text(shortDate(memory.date))
                            .font(.system(size: 10, weight: selectedIndex == index ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(selectedIndex == index ? .primary : .tertiary)
                    }
                    if index < memories.count - 1 {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)

            Text("Line gets larger and smaller at points with more memory pins dropped")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func isNearMemoryMarker(index: Int) -> Bool {
        guard !memories.isEmpty else { return false }
        let segmentSize = waveformSamples.count / max(memories.count, 1)
        for i in 0..<memories.count {
            let markerIndex = i * segmentSize + segmentSize / 2
            if abs(index - markerIndex) < 3 {
                return true
            }
        }
        return false
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M-dd-yy"
        return formatter.string(from: date)
    }
}
