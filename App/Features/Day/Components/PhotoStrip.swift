import PhotosUI
import ReytKit
import SwiftData
import SwiftUI
import UIKit

/// Polaroid geometry from the board: 148 wide with 8 / 8 / 0 padding, a 124 pt image and a 36 pt caption strip.
private enum Polaroid {
    static let width: CGFloat = 148
    static let imageHeight: CGFloat = 124
    static let captionHeight: CGFloat = 36
    static let rotations: [Double] = [-3, 2.5, -2]
    static let tapeRotations: [Double] = [4, -5, 3]
    static let tapeInsets: [CGFloat] = [44, 40, 46]
}

/// The day's photos as polaroids, two to a row. Empty days show only the title and the add button.
struct PhotoStrip: View {
    let model: PhotosModel
    @Query private var records: [Attachment]
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: PhotoRef?

    init(model: PhotosModel) {
        self.model = model
        let key = model.dateKey.string
        _records = Query(
            filter: #Predicate<Attachment> { $0.entryDateKey == key },
            sort: [SortDescriptor(\Attachment.createdAt), SortDescriptor(\Attachment.relativePath)])
    }

    private var refs: [PhotoRef] { records.map { PhotoRef(id: $0.id, relativePath: $0.relativePath) } }

    var body: some View {
        let refs = refs
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle(Copy.Photos.title)
                Spacer()
                addButton
            }
            .padding(.bottom, 4)
            if !refs.isEmpty || model.isImporting {
                FlowLayout(spacing: 18) {
                    ForEach(Array(refs.enumerated()), id: \.element.id) { index, ref in
                        Button {
                            viewing = ref
                        } label: {
                            PolaroidFrame(index: index) { PhotoImage(model: model, photo: ref) }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, index % 2 == 1 ? 14 : 0)
                        .accessibilityLabel(Copy.Photos.thumbnailLabel(index + 1, of: refs.count))
                        .accessibilityHint(Copy.Photos.thumbnailHint)
                    }
                    if model.isImporting {
                        PolaroidFrame(index: refs.count) {
                            ZStack {
                                Palette.chip
                                ProgressRing(size: 30, lineWidth: 2.6)
                            }
                        }
                        .padding(.top, refs.count % 2 == 1 ? 14 : 0)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Copy.Photos.beingAdded)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 12)
            }
            if let progress = model.progress {
                Text(Copy.Photos.importing(progress.current, of: progress.total))
                    .brFont(.banner).foregroundStyle(Palette.ink2)
                    .padding(.top, 28)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let message = model.message {
                Button(action: model.dismissMessage) {
                    HStack(alignment: .top, spacing: 10) {
                        SymbolGlyph(systemName: "exclamationmark.circle").foregroundStyle(Palette.danger)
                        Text(message).brFont(.banner).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(model: model, photo: photo)
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
            AddLabel()
        }
        .padding(.trailing, -8)
        .disabled(model.isImporting)
        .accessibilityLabel(Copy.Photos.add)
        .accessibilityHint(Copy.Photos.addHint)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await model.importItems(items) }
        }
    }
}

private struct AddLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            SymbolGlyph(systemName: "plus")
            Text(Copy.Photos.addShort).brFont(.chip)
        }
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
    }
}

/// One taped, slightly turned polaroid. `index` picks the rotation and tape from the board's repeating pattern.
/// Photos carry no caption in the model, so the caption strip stays blank.
private struct PolaroidFrame<Content: View>: View {
    let index: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        let slot = index % Polaroid.rotations.count
        VStack(spacing: 0) {
            content()
                .frame(width: Polaroid.width - 16, height: Polaroid.imageHeight)
                .clipped()
            Color.clear.frame(height: Polaroid.captionHeight)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(width: Polaroid.width)
        .background(Palette.polaroid, in: RoundedRectangle(cornerRadius: 2))
        .polaroidShadow()
        .overlay(alignment: .topLeading) {
            Rectangle().fill(Palette.tape)
                .frame(width: 60, height: 20)
                .rotationEffect(.degrees(Polaroid.tapeRotations[slot]))
                .offset(x: Polaroid.tapeInsets[slot], y: -10)
                .accessibilityHidden(true)
        }
        .rotationEffect(.degrees(Polaroid.rotations[slot]))
    }
}

private struct PhotoImage: View {
    let model: PhotosModel
    let photo: PhotoRef
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.chip
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: Polaroid.width - 16, height: Polaroid.imageHeight)
        .clipped()
        .task(id: photo.id) {
            if let data = await model.thumbnailData(for: photo) { image = UIImage(data: data) }
        }
    }
}

/// Full-screen photo with close and remove. Remove asks first.
private struct PhotoViewer: View {
    let model: PhotosModel
    let photo: PhotoRef
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var confirming = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel(Copy.Photos.viewerLabel)
            } else if failed {
                Text(Copy.Photos.loadFailed).brFont(.label).foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Copy.Photos.close)
                Spacer()
                Button {
                    confirming = true
                } label: {
                    Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Copy.Photos.remove)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
        }
        .confirmationDialog(Copy.Photos.removeConfirm, isPresented: $confirming, titleVisibility: .visible) {
            Button(Copy.Photos.removeAction, role: .destructive) {
                Task { if await model.delete(photo) { dismiss() } }
            }
            Button(Copy.Photos.keep, role: .cancel) {}
        }
        .task {
            if let data = await model.viewerData(for: photo), let loaded = UIImage(data: data) {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}
