import SwiftUI

/// Preview shown when a collection share link arrives (deep link tap or
/// clipboard import). Importing creates the recipient's own copy of the
/// collection; only memories shared with them will render inside it.
struct CollectionImportSheet: View {
    let payload: SharedCollectionPayload
    let viewModel: LaterViewModel
    var onImported: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var tint: Color { MemoryPinStyle.color(named: payload.colorName) }

    /// How many of the shared memories already exist in this user's library.
    private var visibleCount: Int {
        let ids = Set(payload.memoryIDs)
        return viewModel.memories.count { ids.contains($0.id) }
    }

    private var alreadyImported: Bool {
        viewModel.lifeCollections.contains {
            $0.name == payload.name && $0.memoryIDs == payload.memoryIDs
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(payload.emoji)
                .font(.system(size: 52))
                .frame(width: 96, height: 96)
                .background(tint.opacity(0.16), in: Circle())
                .overlay {
                    Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
                }
                .padding(.top, 12)

            VStack(spacing: 5) {
                Text(payload.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Shared collection · \(payload.memoryIDs.count) \(payload.memoryIDs.count == 1 ? "memory" : "memories")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 1)
                Text(visibleCount == payload.memoryIDs.count
                     ? "All \(payload.memoryIDs.count) memories are already in your library."
                     : "\(visibleCount) of \(payload.memoryIDs.count) memories are in your library right now. The rest appear automatically if they're shared with you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            if alreadyImported {
                Label("You've already imported this collection.", systemImage: "checkmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    viewModel.importSharedCollection(payload)
                    dismiss()
                    onImported?()
                } label: {
                    Text(alreadyImported ? "Import Again" : "Import Collection")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(tint, in: RoundedRectangle(cornerRadius: 15))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("Not Now") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
