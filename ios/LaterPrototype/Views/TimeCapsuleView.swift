import SwiftUI

struct TimeCapsuleView: View {
    @State private var capsules: [TimeCapsule] = []
    @State private var showCreateSheet: Bool = false
    @State private var openedCapsule: TimeCapsule?

    var body: some View {
        NavigationStack {
            Group {
                if capsules.isEmpty {
                    CapsuleEmptyState(onCreate: { showCreateSheet = true })
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(capsules) { capsule in
                                Button {
                                    if capsule.isDelivered {
                                        openedCapsule = capsule
                                    }
                                } label: {
                                    TimeCapsuleCard(capsule: capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
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
                CreateCapsuleSheet { newCapsule in
                    capsules.insert(newCapsule, at: 0)
                    CapsuleStore.save(capsules)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $openedCapsule) { capsule in
                CapsuleDetailSheet(capsule: capsule)
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            if let stored = CapsuleStore.load() {
                capsules = stored
            }
        }
    }
}

struct CapsuleEmptyState: View {
    let onCreate: () -> Void
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 1.1 : 0.95)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 8) {
                Text("No capsules yet")
                    .font(.title2.weight(.bold))
                Text("Seal a message to your future self or a friend. We'll keep it locked until the day you choose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                onCreate()
            } label: {
                Label("Create your first capsule", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.blue, in: Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

nonisolated struct TimeCapsule: Identifiable, Sendable, Codable {
    let id: UUID
    let title: String
    let message: String
    let recipient: String
    let deliveryDate: Date
    let createdDate: Date

    /// A capsule is delivered once its delivery date has arrived.
    var isDelivered: Bool {
        deliveryDate <= Date()
    }

    init(id: UUID = UUID(), title: String, message: String, recipient: String, deliveryDate: Date, createdDate: Date) {
        self.id = id
        self.title = title
        self.message = message
        self.recipient = recipient
        self.deliveryDate = deliveryDate
        self.createdDate = createdDate
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
    let onSeal: (TimeCapsule) -> Void
    @State private var title: String = ""
    @State private var message: String = ""
    @State private var recipient: String = ""
    @State private var deliveryDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

    private func seal() {
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespaces)
        let capsule = TimeCapsule(
            title: title.trimmingCharacters(in: .whitespaces),
            message: message,
            recipient: trimmedRecipient.isEmpty ? "Future me" : trimmedRecipient,
            deliveryDate: deliveryDate,
            createdDate: Date()
        )
        onSeal(capsule)
        dismiss()
    }

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
            }
            .navigationTitle("New Time Capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seal") { seal() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct CapsuleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let capsule: TimeCapsule

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.open.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capsule.title)
                                .font(.title3.weight(.bold))
                            Text("To: \(capsule.recipient)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(capsule.message)
                        .font(.body)

                    Divider()

                    HStack {
                        Label("Sealed \(capsule.createdDate, style: .date)", systemImage: "lock")
                        Spacer()
                        Label("Opened \(capsule.deliveryDate, style: .date)", systemImage: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
