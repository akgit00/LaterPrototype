import SwiftUI

struct ProfileView: View {
    @State private var selectedSegment: ProfileSegment = .timeline

    enum ProfileSegment: String, CaseIterable {
        case timeline = "Timeline"
        case connections = "Connections"
        case legacy = "Legacy"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                        .padding(.bottom, 20)

                    statsRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    Picker("Section", selection: $selectedSegment) {
                        ForEach(ProfileSegment.allCases, id: \.self) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    switch selectedSegment {
                    case .timeline:
                        timelineContent
                    case .connections:
                        connectionsContent
                    case .legacy:
                        legacyContent
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Text("S")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("Samantherr")
                    .font(.title2.weight(.bold))

                Text("Collecting moments across time & space")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                    Text("New York, NY")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "47", label: "Memories")
            Divider().frame(height: 32)
            statItem(value: "12", label: "Capsules")
            Divider().frame(height: 32)
            statItem(value: "8", label: "Connections")
            Divider().frame(height: 32)
            statItem(value: "3", label: "Cities")
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var timelineContent: some View {
        VStack(spacing: 12) {
            ForEach(0..<5) { i in
                let entries: [(String, String, String)] = [
                    ("Aug 15", "Poconos Trip 2025", "4 friends, 12 photos"),
                    ("Jul 4", "NYC Fourth of July", "2 friends, 6 photos"),
                    ("Mar 20", "Tokyo Spring 2025", "Solo trip, 8 photos"),
                    ("Jan 1", "New Year's Eve", "3 friends, 15 photos"),
                    ("Dec 25", "Christmas at Home", "Family, 10 photos")
                ]
                let entry = entries[i]

                HStack(spacing: 12) {
                    Text(entry.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)

                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.1)
                            .font(.subheadline.weight(.semibold))
                        Text(entry.2)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 32)
    }

    private var connectionsContent: some View {
        VStack(spacing: 12) {
            ForEach(0..<4) { i in
                let people: [(String, String, String)] = [
                    ("K", "Kool-Aidd", "3 shared memories"),
                    ("T", "Trist0", "2 shared memories"),
                    ("A", "AkaWild", "1 shared memory"),
                    ("J", "Jay", "1 shared memory")
                ]
                let person = people[i]

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text(person.0)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.1)
                            .font(.subheadline.weight(.semibold))
                        Text(person.2)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "message.fill")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 32)
    }

    private var legacyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.purple)

            Text("Your Digital Legacy")
                .font(.title3.weight(.bold))

            Text("Your public profile showcases your shared memories and connections. This is how friends and future connections will remember you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
            } label: {
                Text("Customize Legacy")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(.vertical, 24)
    }
}
