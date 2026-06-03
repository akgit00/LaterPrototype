import SwiftUI

struct TimeCapsuleView: View {
    @State private var capsules: [TimeCapsule] = []
    @State private var showCreateSheet: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(capsules) { capsule in
                        TimeCapsuleCard(capsule: capsule)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Time Capsules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCapsuleSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

nonisolated struct TimeCapsule: Identifiable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let recipient: String
    let deliveryDate: Date
    let createdDate: Date
    let isDelivered: Bool

    init(id: UUID = UUID(), title: String, message: String, recipient: String, deliveryDate: Date, createdDate: Date, isDelivered: Bool = false) {
        self.id = id
        self.title = title
        self.message = message
        self.recipient = recipient
        self.deliveryDate = deliveryDate
        self.createdDate = createdDate
        self.isDelivered = isDelivered
    }

}

struct TimeCapsuleCard: View {
    let capsule: TimeCapsule

    private var daysUntilDelivery: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: capsule.deliveryDate).day ?? 0
    }

    private var progress: Double {
        let total = capsule.deliveryDate.timeIntervalSince(capsule.createdDate)
        let elapsed = Date().timeIntervalSince(capsule.createdDate)
        guard total > 0 else { return 1.0 }
        return min(max(elapsed / total, 0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(capsule.title)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text("To: \(capsule.recipient)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: capsule.isDelivered ? "envelope.open.fill" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(capsule.isDelivered ? .green : .orange)
                    .symbolEffect(.pulse, isActive: !capsule.isDelivered)
            }

            Text(capsule.isDelivered ? capsule.message : String(repeating: "•", count: min(capsule.message.count, 40)))
                .font(.subheadline)
                .foregroundStyle(capsule.isDelivered ? .primary : .tertiary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .green : .blue)

                HStack {
                    Text("Opens \(capsule.deliveryDate, style: .date)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if daysUntilDelivery > 0 {
                        Text("\(daysUntilDelivery) days left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Text("Ready to open")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CreateCapsuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var message: String = ""
    @State private var recipient: String = ""
    @State private var deliveryDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

    var body: some View {
        NavigationStack {
            Form {
                Section("Capsule Details") {
                    TextField("Title", text: $title)
                    TextField("Recipient", text: $recipient)
                    DatePicker("Delivery Date", selection: $deliveryDate, in: Date()..., displayedComponents: .date)
                }

                Section("Message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }

                Section("Attachments") {
                    Button {
                    } label: {
                        Label("Add Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                    } label: {
                        Label("Add Voice Note", systemImage: "mic.fill")
                    }
                }
            }
            .navigationTitle("New Time Capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seal") { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty || message.isEmpty)
                }
            }
        }
    }
}
