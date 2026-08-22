import SwiftUI

/// Which story pages a collection's Wrapped can show, in order. Pages with no
/// data behind them are skipped.
private enum WrapSlideKind: Hashable {
    case intro
    case tally
    case places
    case distance
    case months
    case people
    case soundtrack
    case mood
    case persona
    case recap
    case empty
}

/// The alternate way to take in a whole collection: a swipeable, full-screen
/// "Wrapped"-style story of stats — memories made, brand-new places, miles
/// covered, the cast, the soundtrack, and a final persona reveal.
struct CollectionWrappedView: View {
    let display: CollectionDisplay
    let stats: WrappedStats
    let onExploreWeb: () -> Void

    @State private var slideIndex: Int = 0

    private var slides: [WrapSlideKind] {
        guard stats.memoryCount > 0 else { return [.empty] }
        var kinds: [WrapSlideKind] = [.intro, .tally]
        if stats.placeCount > 0 { kinds.append(.places) }
        if stats.totalDistanceKm >= 1 { kinds.append(.distance) }
        if stats.busiestMonthIndex != nil && stats.memoryCount >= 2 { kinds.append(.months) }
        if !stats.topCompanions.isEmpty { kinds.append(.people) }
        if !stats.topSongs.isEmpty { kinds.append(.soundtrack) }
        if stats.topMood != nil { kinds.append(.mood) }
        kinds.append(.persona)
        kinds.append(.recap)
        return kinds
    }

    var body: some View {
        TabView(selection: $slideIndex) {
            ForEach(Array(slides.enumerated()), id: \.offset) { index, kind in
                slideView(for: kind, isActive: slideIndex == index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if slides.count > 1 {
                progressBar
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if slideIndex < slides.count - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { slideIndex += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.14), in: Circle())
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<slides.count, id: \.self) { index in
                Capsule()
                    .fill(index <= slideIndex ? Color.white : Color.white.opacity(0.25))
                    .frame(height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: slideIndex)
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    // MARK: - Slides

    @ViewBuilder
    private func slideView(for kind: WrapSlideKind, isActive: Bool) -> some View {
        switch kind {
        case .intro: introSlide(isActive: isActive)
        case .tally: tallySlide(isActive: isActive)
        case .places: placesSlide(isActive: isActive)
        case .distance: distanceSlide(isActive: isActive)
        case .months: monthsSlide(isActive: isActive)
        case .people: peopleSlide(isActive: isActive)
        case .soundtrack: soundtrackSlide(isActive: isActive)
        case .mood: moodSlide(isActive: isActive)
        case .persona: personaSlide(isActive: isActive)
        case .recap: recapSlide(isActive: isActive)
        case .empty: emptySlide
        }
    }

    private func introSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: display.year != nil ? "LATER · WRAPPED" : "COLLECTION REWIND",
            colors: [Color(red: 0.09, green: 0.05, blue: 0.22), Color(red: 0.31, green: 0.13, blue: 0.65), Color(red: 0.85, green: 0.25, blue: 0.95)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if display.year != nil {
                    Text(display.title)
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .reveal(isActive, delay: 0.1)
                } else {
                    Text(display.emoji)
                        .font(.system(size: 56))
                        .reveal(isActive, delay: 0.1)
                    Text(display.title)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .reveal(isActive, delay: 0.18)
                }

                Text("\(stats.memoryCount) \(stats.memoryCount == 1 ? "memory" : "memories"), mapped and remembered.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .reveal(isActive, delay: 0.3)

                if display.isInProgressYear {
                    Text("EARLY PEEK — THE YEAR ISN'T DONE YET")
                        .font(.caption.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.yellow, in: Capsule())
                        .reveal(isActive, delay: 0.42)
                }

                Label("Swipe to unwrap", systemImage: "chevron.right.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 24)
                    .reveal(isActive, delay: 0.6)
            }
        }
    }

    private func tallySlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "THE HAUL",
            colors: [Color(red: 0.17, green: 0.04, blue: 0.21), Color(red: 0.76, green: 0.09, blue: 0.36)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: -6) {
                    CountUpText(value: stats.memoryCount, isActive: isActive)
                    Text(stats.memoryCount == 1 ? "memory made" : "memories made")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .reveal(isActive, delay: 0.1)

                VStack(alignment: .leading, spacing: 10) {
                    if stats.photoCount > 0 {
                        WrapChip(icon: "photo.fill", text: "\(stats.photoCount) photos kept safe")
                            .reveal(isActive, delay: 0.35)
                    }
                    if stats.videoCount > 0 {
                        WrapChip(icon: "video.fill", text: "\(stats.videoCount) videos rolling")
                            .reveal(isActive, delay: 0.45)
                    }
                    if stats.voiceCount > 0 {
                        WrapChip(icon: "waveform", text: "\(stats.voiceCount) voice notes captured")
                            .reveal(isActive, delay: 0.55)
                    }
                    if stats.activeDayCount > 1 {
                        WrapChip(icon: "calendar", text: "\(stats.activeDayCount) days out living it")
                            .reveal(isActive, delay: 0.65)
                    }
                }
            }
        }
    }

    private func placesSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "YOUR MAP GREW",
            colors: [Color(red: 0.01, green: 0.15, blue: 0.18), Color(red: 0.0, green: 0.52, blue: 0.56)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: -6) {
                    CountUpText(value: stats.placeCount, isActive: isActive)
                    Text(stats.placeCount == 1 ? "place pinned" : "places pinned")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .reveal(isActive, delay: 0.1)

                if stats.newPlaceCount > 0 {
                    HStack(spacing: 12) {
                        Text("✨")
                            .font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(stats.newPlaceCount) brand new")
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                            Text("spots you'd never pinned before")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    .reveal(isActive, delay: 0.4)
                }

                if stats.homeBaseVisits >= 3 {
                    Text("And one spot pulled you back \(stats.homeBaseVisits) times. Home base found.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .reveal(isActive, delay: 0.55)
                }
            }
        }
    }

    private func distanceSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "THE MILES",
            colors: [Color(red: 0.04, green: 0.09, blue: 0.26), Color(red: 0.1, green: 0.45, blue: 0.9)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formattedDistance)
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("hopping memory to memory")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .reveal(isActive, delay: 0.1)

                if let comparison = stats.distanceComparison {
                    Text(comparison)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        .reveal(isActive, delay: 0.4)
                }

                if stats.farthestHopKm >= 50 {
                    WrapChip(icon: "airplane", text: "Longest leap: \(formattedKm(stats.farthestHopKm)) in one jump")
                        .reveal(isActive, delay: 0.55)
                }
            }
        }
    }

    private func monthsSlide(isActive: Bool) -> some View {
        let busiest = stats.busiestMonthIndex ?? 0
        return WrapSlideScaffold(
            kicker: "YOUR RHYTHM",
            colors: [Color(red: 0.16, green: 0.11, blue: 0.0), Color(red: 0.9, green: 0.6, blue: 0.05)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(monthName(busiest)) was your month")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(stats.monthCounts[busiest]) \(stats.monthCounts[busiest] == 1 ? "memory" : "memories") in \(monthName(busiest)) alone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .reveal(isActive, delay: 0.1)

                MonthBars(counts: stats.monthCounts, highlightIndex: busiest, isActive: isActive)
                    .reveal(isActive, delay: 0.3)
            }
        }
    }

    private func peopleSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "THE CAST",
            colors: [Color(red: 0.08, green: 0.0, blue: 0.2), Color(red: 0.48, green: 0.12, blue: 0.64)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Who showed up the most")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .reveal(isActive, delay: 0.1)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(stats.topCompanions.enumerated()), id: \.element.id) { index, companion in
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 34, alignment: .leading)
                            ConnectionAvatarView(connection: companion.connection, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(companion.connection.displayName)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("\(companion.count) shared \(companion.count == 1 ? "memory" : "memories")")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            Spacer()
                            if index == 0 {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(index == 0 ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 18))
                        .reveal(isActive, delay: 0.3 + Double(index) * 0.15)
                    }
                }
            }
        }
    }

    private func soundtrackSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "THE SOUNDTRACK",
            colors: [Color(red: 0.0, green: 0.13, blue: 0.07), Color(red: 0.0, green: 0.65, blue: 0.35)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text("What these moments sounded like")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .reveal(isActive, delay: 0.1)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(stats.topSongs.enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 12) {
                            Image(systemName: "music.note")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                            Spacer()
                            if song.count > 1 {
                                Text("×\(song.count)")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                        .reveal(isActive, delay: 0.3 + Double(index) * 0.15)
                    }
                }
            }
        }
    }

    private func moodSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "THE FEELING",
            colors: [Color(red: 0.2, green: 0.0, blue: 0.24), Color(red: 0.95, green: 0.25, blue: 0.5)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 170, height: 170)
                    Circle()
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 170, height: 170)
                    Text(stats.topMood ?? "😄")
                        .font(.system(size: 84))
                }
                .reveal(isActive, delay: 0.1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your signature mood")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tagged on \(stats.topMoodCount) \(stats.topMoodCount == 1 ? "memory" : "memories")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .reveal(isActive, delay: 0.35)
            }
        }
    }

    private func personaSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "AND FINALLY…",
            colors: [Color(red: 0.0, green: 0.0, blue: 0.02), Color(red: 0.2, green: 0.1, blue: 0.55), Color(red: 0.8, green: 0.0, blue: 0.95)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text(display.year != nil ? "This year you were" : "This era made you")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .reveal(isActive, delay: 0.1)

                ZStack {
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 130, height: 130)
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.1), .white.opacity(0.9)],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 130, height: 130)
                    Text(stats.personaEmoji)
                        .font(.system(size: 60))
                }
                .reveal(isActive, delay: 0.3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(stats.personaTitle)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Text(stats.personaLine)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .reveal(isActive, delay: 0.55)
            }
        }
    }

    private func recapSlide(isActive: Bool) -> some View {
        WrapSlideScaffold(
            kicker: "THE RECAP",
            colors: [Color(red: 0.05, green: 0.05, blue: 0.07), Color(red: 0.18, green: 0.22, blue: 0.28)],
            isActive: isActive
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(display.year != nil ? "\(display.title), on one card" : display.title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .reveal(isActive, delay: 0.1)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    RecapTile(value: "\(stats.memoryCount)", label: "memories")
                    RecapTile(value: "\(stats.placeCount)", label: "places")
                    RecapTile(value: "\(stats.newPlaceCount)", label: "new places")
                    RecapTile(value: formattedDistance, label: "traveled")
                    RecapTile(value: "\(stats.photoCount)", label: "photos")
                    RecapTile(value: "\(stats.activeDayCount)", label: "days out")
                }
                .reveal(isActive, delay: 0.25)

                HStack(spacing: 10) {
                    Text(stats.personaEmoji)
                        .font(.title2)
                    Text(stats.personaTitle)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.12), in: Capsule())
                .reveal(isActive, delay: 0.4)

                Button(action: onExploreWeb) {
                    Label("Explore the web", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .reveal(isActive, delay: 0.55)
            }
        }
    }

    private var emptySlide: some View {
        WrapSlideScaffold(
            kicker: "NOT YET",
            colors: [Color(red: 0.06, green: 0.06, blue: 0.1), Color(red: 0.2, green: 0.2, blue: 0.3)],
            isActive: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing to wrap yet")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Make some memories and this story writes itself.")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Formatting helpers

    private var formattedDistance: String {
        formattedKm(stats.totalDistanceKm)
    }

    private func formattedKm(_ km: Double) -> String {
        Measurement(value: km, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func monthName(_ index: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}

// MARK: - Slide scaffold & background

private struct WrapSlideScaffold<Content: View>: View {
    let kicker: String
    let colors: [Color]
    let isActive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            WrapBackground(colors: colors)

            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 0)

                Text(kicker)
                    .font(.caption.weight(.heavy))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.65))
                    .reveal(isActive, delay: 0)

                content()

                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 84)
            .padding(.bottom, 48)
        }
        .fontDesign(.rounded)
    }
}

/// A slowly drifting, blurred color-blob backdrop behind each slide.
private struct WrapBackground: View {
    let colors: [Color]
    @State private var drift: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill((colors.last ?? .purple).opacity(0.55))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: drift ? 130 : -50, y: drift ? -190 : -70)

            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: drift ? -120 : 90, y: drift ? 250 : 130)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - Reusable pieces

/// Staggered entrance: fades and floats content in when its slide becomes
/// active, and resets silently when the slide goes off screen.
private struct RevealEffect: ViewModifier {
    let isActive: Bool
    let delay: Double
    @State private var shown: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 26)
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    withAnimation(.spring(duration: 0.7).delay(delay)) { shown = true }
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { shown = false }
                }
            }
    }
}

extension View {
    fileprivate func reveal(_ isActive: Bool, delay: Double = 0) -> some View {
        modifier(RevealEffect(isActive: isActive, delay: delay))
    }
}

/// A big number that rolls up from zero when its slide appears.
private struct CountUpText: View {
    let value: Int
    let isActive: Bool

    @State private var shown: Int = 0
    @State private var generation: Int = 0

    var body: some View {
        Text("\(shown)")
            .font(.system(size: 108, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(shown)))
            .onChange(of: isActive, initial: true) { _, active in
                generation += 1
                if active {
                    animate(generation)
                } else {
                    shown = 0
                }
            }
    }

    private func animate(_ run: Int) {
        shown = 0
        guard value > 0 else { return }
        let steps = 22
        Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(42))
                guard run == generation else { return }
                let progress = Double(step) / Double(steps)
                let eased = 1 - pow(1 - progress, 3)
                withAnimation(.easeOut(duration: 0.06)) {
                    shown = Int((Double(value) * eased).rounded())
                }
            }
            if run == generation { shown = value }
        }
    }
}

private struct WrapChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.15), in: Circle())
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

private struct RecapTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Twelve animated month bars with the busiest month highlighted.
private struct MonthBars: View {
    let counts: [Int]
    let highlightIndex: Int?
    let isActive: Bool

    @State private var grown: Bool = false

    private static let letters: [String] = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        let maxCount = max(counts.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(0..<12, id: \.self) { index in
                let ratio = Double(counts[index]) / Double(maxCount)
                let isHighlight = index == highlightIndex
                VStack(spacing: 6) {
                    Capsule()
                        .fill(isHighlight ? Color.white : Color.white.opacity(0.3))
                        .frame(height: grown ? max(116 * ratio, 5) : 5)
                        .animation(.spring(duration: 0.55).delay(Double(index) * 0.045), value: grown)
                    Text(Self.letters[index])
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isHighlight ? .white : .white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140, alignment: .bottom)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                grown = true
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { grown = false }
            }
        }
    }
}
