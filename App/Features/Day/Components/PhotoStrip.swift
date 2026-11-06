import PhotosUI
import ReytKit
import SwiftData
import SwiftUI
import UIKit

private let photoSide: CGFloat = 72

/// The day's photos: a horizontal strip of 72 pt thumbnails and an add button. Empty days show only the button.
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
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.Photos.title).font(.footnote).foregroundStyle(Palette.ink2)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(refs.enumerated()), id: \.element.id) { index, ref in
                        Button {
                            viewing = ref
                        } label: {
                            PhotoThumbnail(model: model, photo: ref, side: photoSide)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Copy.Photos.thumbnailLabel(index + 1, of: refs.count))
                        .accessibilityHint(Copy.Photos.thumbnailHint)
                    }
                    addButton
                }
                .padding(.vertical, 2)
            }
            if let progress = model.progress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(Copy.Photos.importing(progress.current, of: progress.total))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
            }
            if let message = model.message {
                Button(action: model.dismissMessage) {
                    Text(message).font(.footnote).foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(model: model, photo: photo)
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: photoSide, height: photoSide)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.border, lineWidth: 1))
        }
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

private struct PhotoThumbnail: View {
    let model: PhotosModel
    let photo: PhotoRef
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Palette.card)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.border, lineWidth: 1))
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
                Text(Copy.Photos.loadFailed).font(.footnote).foregroundStyle(.white)
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
