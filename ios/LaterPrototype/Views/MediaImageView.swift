import SwiftUI

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Displays an image from either a local file URL (imported media) or a
/// remote https URL (sample data), with a graceful placeholder.
struct MediaImageView: View {
    let urlString: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
            if url.isFileURL {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else if phase.error != nil {
                        placeholder
                    } else {
                        ProgressView()
                    }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(.tertiary)
    }
}
