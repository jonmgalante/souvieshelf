import ImageIO
import SwiftUI

extension String {
    /// Keep a long saved story short enough for one card and one VoiceOver stop.
    var galleryStoryExcerpt: String? {
        let text = split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        guard text.count > 140 else { return text }
        let prefix = text.prefix(140)
        let end = prefix.lastIndex(of: " ") ?? prefix.endIndex
        return String(prefix[..<end]) + "…"
    }
}

struct GalleryAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GalleryTheme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(GalleryTheme.accent, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add souvenir")
    }
}

struct GalleryEmptyShelf: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(GalleryTheme.secondary)
                .accessibilityHidden(true)
            Text("Your first souvenir")
                .font(.system(.largeTitle, design: .serif))
                .accessibilityAddTraits(.isHeader)
            Text("Save a photo of something you brought home. You can add its story later.")
                .font(.body)
                .foregroundStyle(GalleryTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GalleryAddButton(title: "Add souvenir", action: onAdd)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 30)
        .padding(.horizontal, 22)
        .background(GalleryTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 24)
    }
}

struct GalleryNotice: View {
    let title: String
    let detail: String
    let icon: String

    init(_ title: String, _ detail: String, icon: String) {
        self.title = title
        self.detail = detail
        self.icon = icon
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(GalleryTheme.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct GalleryObject<Photo: View>: View {
    let title: String
    let location: String?
    let story: String?
    let featured: Bool
    let anniversary: Bool
    @ViewBuilder var photo: () -> Photo
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if featured && !typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 18) {
                    framedPhoto(ratio: 0.9).frame(maxWidth: .infinity)
                    featureCaption.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: featured ? 14 : 8) {
                    framedPhoto(ratio: 1.15)
                    if featured { featureCaption } else { tileCaption }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([anniversary ? "On This Day" : nil, title, location, featured ? story : nil].compactMap { $0 }.joined(separator: ". "))
    }

    private func framedPhoto(ratio: CGFloat) -> some View {
        GalleryTheme.surface
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { photo() }
            .clipShape(RoundedRectangle(cornerRadius: featured ? 12 : 9))
            .accessibilityHidden(true)
    }

    private var featureCaption: some View {
        VStack(alignment: .leading, spacing: 9) {
            if anniversary {
                Label("On This Day", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GalleryTheme.accent)
            }
            if let location {
                Text(location)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(GalleryTheme.accent)
            }
            Text(title)
                .font(.system(.title, design: .serif, weight: .medium))
                .foregroundStyle(GalleryTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let story {
                Text(story)
                    .font(.subheadline)
                    .lineSpacing(2)
                    .foregroundStyle(GalleryTheme.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 4)
            }
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GalleryTheme.accent)
        }
    }

    private var tileCaption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(GalleryTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let location {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(GalleryTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GalleryPlaceholder: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(.largeTitle, weight: .light))
            .foregroundStyle(GalleryTheme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GalleryTheme.surface)
            .accessibilityHidden(true)
    }
}

struct GalleryPhoto: View {
    @ObservedObject var photo: PhotoAsset
    let featured: Bool

    var body: some View {
        if let image = image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            GalleryPlaceholder(symbol: "photo")
        }
    }

    private var image: UIImage? {
        if !featured, let thumb = photo.thumbnailData, let image = UIImage(data: thumb) { return image }
        // Older photos can have display bytes only. Decode at the size used on the shelf.
        if let bytes = photo.displayImageData,
           let image = Self.downsample(bytes, maxPixels: featured ? 720 : 320) { return image }
        return photo.thumbnailData.flatMap { UIImage(data: $0) }
    }

    nonisolated static func downsample(_ bytes: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct GalleryBrowseRow: View {
    let title: String
    let detail: String?
    let count: Int
    let thumbnail: Data?
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            GalleryTheme.surface
                .frame(width: 66, height: 66)
                .overlay {
                    if let thumbnail, let photo = UIImage(data: thumbnail) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Image(systemName: symbol).foregroundStyle(GalleryTheme.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(GalleryTheme.secondary) }
                Text(count == 1 ? "1 souvenir" : "\(count) souvenirs").font(.subheadline).foregroundStyle(GalleryTheme.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(GalleryTheme.secondary).accessibilityHidden(true)
        }
        .foregroundStyle(GalleryTheme.ink)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(GalleryTheme.rule).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Souvenir {
    var galleryPhoto: PhotoAsset? {
        orderedPhotos.first { photo in
            Self.hasImage(photo.thumbnailData) || Self.hasImage(photo.displayImageData)
        }
    }

    var primaryThumbnailData: Data? {
        guard let photo = galleryPhoto else { return nil }
        if let thumb = photo.thumbnailData, Self.hasImage(thumb) { return thumb }
        guard let display = photo.displayImageData else { return nil }
        return GalleryPhoto.downsample(display, maxPixels: 320)?.jpegData(compressionQuality: 0.8)
    }

    private static func hasImage(_ data: Data?) -> Bool {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
