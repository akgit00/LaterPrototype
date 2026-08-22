import SwiftUI

/// Search-and-jump for the Explore globe: type to find a memory by name (or
/// a place pinned inside it), narrow by year and month, then tap a result to
/// fly there and open its room.
struct MemorySearchSheet: View {
    let viewModel: LaterViewModel
    let onSelect: (Memory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var filterYear: Int?
    @State private var filterMonth: Int?

    private var availableYears: [Int] {
        let calendar = Calendar.current
        return Set(viewModel.memories.map { calendar.component(.year, from: $0.date) })
            .sorted(by: >)
    }

    private func availableMonths(in year: Int) -> [Int] {
        let calendar = Calendar.current
        return Set(
            viewModel.memories
                .filter { calendar.component(.year, from: $0.date) == year }
                .map { calendar.component(.month, from: $0.date) }
        ).sorted()
    }

    private func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard (1...12).contains(month) else { return "" }
        return symbols[month - 1]
    }

    private var hasActiveFilter: Bool { filterYear != nil }

    /// Memories matching the query text and date filter, newest first.
    private var results: [Memory] {
        let calendar = Calendar.current
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.memories
            .filter { memory in
                if let year = filterYear {
                    let comps = calendar.dateComponents([.year, .month], from: memory.date)
                    guard comps.year == year else { return false }
                    if let month = filterMonth, comps.month != month { return false }
                }
                guard !trimmed.isEmpty else { return true }
                if memory.title.localizedStandardContains(trimmed) { return true }
                if memory.subtitle.localizedStandardContains(trimmed) { return true }
                return memory.subMemories.contains { $0.title.localizedStandardContains(trimmed) }
            }
            .sorted { $0.date > $1.date }
    }

    private var scopeText: String {
        guard let year = filterYear else { return "All memories" }
        if let month = filterMonth { return "\(monthName(month)) \(String(year))" }
        return String(year)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { memory in
                        resultRow(memory)
                    }
                } header: {
                    Text("\(scopeText) · \(results.count) \(results.count == 1 ? "match" : "matches")")
                }
            }
            .overlay {
                if results.isEmpty {
                    if query.isEmpty && !hasActiveFilter {
                        ContentUnavailableView {
                            Label("No memories yet", systemImage: "mappin.slash")
                        } description: {
                            Text("Pin a memory on the globe first, then find it here.")
                        }
                    } else {
                        ContentUnavailableView.search
                    }
                }
            }
            .navigationTitle("Find a Memory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by name or place"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    dateFilterMenu
                }
            }
            .onChange(of: filterYear) { _, _ in filterMonth = nil }
        }
    }

    /// Year + month narrowing, mirroring the collection view's filter.
    private var dateFilterMenu: some View {
        Menu {
            Picker("Year", selection: $filterYear) {
                Text("All Time").tag(Int?.none)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
            if let year = filterYear {
                Picker("Month", selection: $filterMonth) {
                    Text("Any Month").tag(Int?.none)
                    ForEach(availableMonths(in: year), id: \.self) { month in
                        Text(monthName(month)).tag(Int?.some(month))
                    }
                }
            }
            if hasActiveFilter {
                Button(role: .destructive) {
                    filterYear = nil
                    filterMonth = nil
                } label: {
                    Label("Clear Filter", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: hasActiveFilter ? "calendar.circle.fill" : "calendar.circle")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func resultRow(_ memory: Memory) -> some View {
        Button {
            onSelect(memory)
        } label: {
            HStack(spacing: 12) {
                Color(.tertiarySystemFill)
                    .frame(width: 52, height: 52)
                    .overlay {
                        MediaImageView(urlString: memory.photoURLs.first)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(memory.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !memory.subtitle.isEmpty {
                        Text(memory.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(memory.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
