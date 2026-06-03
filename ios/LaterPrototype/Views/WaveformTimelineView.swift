import SwiftUI

struct WaveformTimelineView: View {
    let memories: [Memory]
    let onMemorySelected: (Memory) -> Void
    @State private var selectedID: UUID?

    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1
    private let sampleCount: Int = 200
    /// Inset (as a fraction of width) so markers never sit on the extreme edges.
    private let edgeInset: Double = 0.04

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

    private var contentWidth: CGFloat {
        CGFloat(sampleCount) * barWidth + CGFloat(sampleCount - 1) * barSpacing
    }

    /// Memories sorted chronologically.
    private var sortedMemories: [Memory] {
        memories.sorted { $0.date < $1.date }
    }

    private var selectedMemory: Memory? {
        guard let selectedID else { return sortedMemories.last }
        return sortedMemories.first { $0.id == selectedID } ?? sortedMemories.last
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Scrollable Timeline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let memory = selectedMemory {
                    Text(memory.date, style: .date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .center, spacing: barSpacing) {
                        ForEach(Array(waveformSamples.enumerated()), id: \.offset) { _, sample in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.primary.opacity(0.7))
                                .frame(width: barWidth, height: max(2, abs(sample) * 40 + 4))
                        }
                    }
                    .frame(width: contentWidth, height: 56)

                    ForEach(sortedMemories) { memory in
                        let x = xPosition(for: memory.date)
                        TimelineMarker(isSelected: memory.id == selectedMemory?.id) {
                            selectedID = memory.id
                            onMemorySelected(memory)
                        }
                        .position(x: x, y: 28)
                    }
                }
                .frame(width: contentWidth, height: 56)
                .padding(.horizontal, 16)
            }
            .contentMargins(.horizontal, 16)

            Text("Tap a red marker to jump to that memory")
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

    /// Maps a memory's date onto a horizontal position across the waveform.
    private func xPosition(for date: Date) -> CGFloat {
        let dates = sortedMemories.map { $0.date.timeIntervalSince1970 }
        guard let minDate = dates.first, let maxDate = dates.last else {
            return contentWidth / 2
        }
        let usableWidth = contentWidth * (1 - 2 * edgeInset)
        let startX = contentWidth * edgeInset
        guard maxDate > minDate else {
            return contentWidth / 2
        }
        let normalized = (date.timeIntervalSince1970 - minDate) / (maxDate - minDate)
        return startX + CGFloat(normalized) * usableWidth
    }
}

private struct TimelineMarker: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Circle()
                    .fill(Color.red)
                    .frame(width: isSelected ? 10 : 7, height: isSelected ? 10 : 7)
                    .shadow(color: .red.opacity(0.7), radius: isSelected ? 6 : 3)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: isSelected ? 3 : 2, height: 50)
            }
            .frame(width: 44, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isSelected)
    }
}
