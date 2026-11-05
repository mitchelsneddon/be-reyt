import Foundation
import ImageIO
import ReytKit
import UIKit

/// Draws the journal as a PDF with `UIGraphicsPDFRenderer` and TextKit 1 (`NSLayoutManager`, one text container
/// per page). No WebKit and no HTML print formatters. Runs off the main thread; photos are decoded one at a time at
/// the size they are drawn and released straight after.
enum PDFExporter {
    static func export(
        journal: ReadableJournal, paths: Paths, generation: URL, today: DateKey,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ReadableExportResult {
        try await Task.detached(priority: .userInitiated) {
            let scratch = try ScratchSpace.make()
            let url = scratch.appending(
                path: "be reyt journal \(ReadableExportSource.stamp(today)).pdf", directoryHint: .notDirectory)
            do {
                let composer = PDFComposer(journal: journal, paths: paths, generation: generation, progress: progress)
                try composer.write(to: url)
                ReadableExportSource.protect(url)
                return ReadableExportResult(url: url, scratch: scratch)
            } catch {
                ScratchSpace.remove(scratch)
                throw error
            }
        }.value
    }
}

/// Lays out blocks down a page and starts a new one when the next block does not fit. Used on one thread only.
private final class PDFComposer {
    static let margin: CGFloat = 54
    static let photoMaxHeightShare: CGFloat = 0.4

    let journal: ReadableJournal
    let paths: Paths
    let generation: URL
    let progress: @Sendable (Double) -> Void
    let page: CGRect
    var content: CGRect { page.insetBy(dx: Self.margin, dy: Self.margin) }

    private var context: UIGraphicsPDFRendererContext?
    private var y: CGFloat = 0
    private var pageNumber = 0

    init(journal: ReadableJournal, paths: Paths, generation: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.journal = journal
        self.paths = paths
        self.generation = generation
        self.progress = progress
        // US Letter in the US, Canada and Mexico, A4 everywhere else.
        let letter: Set<String> = ["US", "CA", "MX"]
        let region = Locale.current.region?.identifier ?? ""
        page =
            letter.contains(region)
            ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595, height: 842)
    }

    // MARK: Fonts

    private func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func attributes(font: UIFont, color: UIColor = .black, lineSpacing: CGFloat = 3, after: CGFloat = 0)
        -> [NSAttributedString.Key: Any]
    {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = after
        style.alignment = .natural
        style.baseWritingDirection = .natural
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] { attributes(font: .systemFont(ofSize: 11)) }
    private var mutedAttributes: [NSAttributedString.Key: Any] {
        attributes(font: .systemFont(ofSize: 10), color: .darkGray, lineSpacing: 2)
    }

    // MARK: Pages

    func write(to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        var failure: Error?
        try renderer.writePDF(to: url) { ctx in
            context = ctx
            do {
                try compose()
            } catch {
                failure = error
            }
            context = nil
        }
        if let failure { throw failure }
    }

    private func beginPage(numbered: Bool = true) {
        context?.beginPage()
        pageNumber += 1
        y = content.minY
        guard numbered else { return }
        let footer = NSAttributedString(
            string: String(pageNumber), attributes: attributes(font: .systemFont(ofSize: 9), color: .gray))
        let size = footer.size()
        footer.draw(at: CGPoint(x: page.midX - size.width / 2, y: page.maxY - Self.margin / 2 - size.height / 2))
    }

    private var atTop: Bool { y <= content.minY + 0.5 }

    private func ensureSpace(_ height: CGFloat) {
        if y + height > content.maxY, !atTop { beginPage() }
    }

    private func space(_ height: CGFloat) {
        if !atTop { y += height }
    }

    // MARK: Compose

    private func compose() throws {
        titlePage()
        beginPage()
        let total = Double(max(journal.days.count, 1))
        for (index, day) in journal.days.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            try autoreleasepoolThrowing { try drawDay(day) }
            progress(Double(index + 1) / total)
        }
        if !journal.weeks.isEmpty { drawWeeks() }
    }

    private func titlePage() {
        beginPage(numbered: false)
        y = page.height * 0.3
        let range: String
        if let first = journal.days.first, let last = journal.days.last {
            range = "\(ReadableFormat.shortDate(first.key)) to \(ReadableFormat.shortDate(last.key))"
        } else {
            range = ""
        }
        let workouts = journal.includeWorkouts ? "workouts included, copied from apple health" : "workouts not included"
        let text = NSMutableAttributedString()
        text.append(
            NSAttributedString(string: "be reyt\n", attributes: attributes(font: serif(40, .semibold), after: 10)))
        text.append(NSAttributedString(string: "\(range)\n", attributes: attributes(font: serif(16), after: 6)))
        text.append(
            NSAttributedString(
                string: "\(workouts)\n",
                attributes: attributes(font: .systemFont(ofSize: 12), color: .darkGray, after: 6)))
        text.append(
            NSAttributedString(
                string: "this export isn't encrypted. keep it somewhere private.",
                attributes: attributes(font: .systemFont(ofSize: 12), color: .darkGray)))
        drawText(text)
    }

    private func drawDay(_ day: ReadableDay) throws {
        ensureSpace(150)
        if !atTop {
            y += 14
            hairline()
            y += 18
        }
        drawText(NSAttributedString(string: day.heading, attributes: attributes(font: serif(20, .semibold), after: 6)))

        var meta: [String] = []
        if let score = day.scoreLabel { meta.append("day score: \(score)") }
        if !day.moods.isEmpty { meta.append("moods: \(day.moods.joined(separator: ", "))") }
        if !day.tags.isEmpty { meta.append("tags: \(day.tags.joined(separator: ", "))") }
        if !meta.isEmpty {
            drawText(NSAttributedString(string: meta.joined(separator: "\n"), attributes: mutedAttributes))
            y += 8
        }
        if let text = day.text {
            drawText(NSAttributedString(string: text, attributes: bodyAttributes))
            y += 8
        }
        for answer in day.answers { section(answer.title, answer.body) }
        if let plan = day.plan {
            let body = [plan.categoryLabel, ReadableFormat.nonblank(plan.text)].compactMap { $0 }.joined(
                separator: "\n")
            section(ReadableFormat.planTitle, body)
        }
        if let followUp = day.followUp {
            let body = [followUp.plan.map { "you planned: \($0)" }, followUp.note].compactMap { $0 }.joined(
                separator: "\n")
            section(ReadableFormat.followUpTitle, body)
        }
        for photo in day.photos {
            if Task.isCancelled { throw CancellationError() }
            drawPhoto(photo)
        }
        if !day.workouts.isEmpty {
            section("workouts", day.workouts.joined(separator: "\n"), note: "workouts copied from apple health")
        }
    }

    private func drawWeeks() {
        beginPage()
        drawText(
            NSAttributedString(string: "weekly reviews", attributes: attributes(font: serif(20, .semibold), after: 10)))
        for week in journal.weeks {
            section(
                "\(ReadableFormat.shortDate(week.weekStart)) to \(ReadableFormat.shortDate(week.weekEnd))",
                "more of this: \(week.moreOfThis)")
        }
    }

    private func section(_ title: String, _ body: String, note: String? = nil) {
        ensureSpace(60)
        let text = NSMutableAttributedString(
            string: title + "\n", attributes: attributes(font: serif(12, .semibold), after: 3))
        if let note { text.append(NSAttributedString(string: note + "\n", attributes: mutedAttributes)) }
        text.append(NSAttributedString(string: body, attributes: bodyAttributes))
        drawText(text)
        y += 8
    }

    private func hairline() {
        guard let cg = context?.cgContext else { return }
        cg.setStrokeColor(UIColor.lightGray.cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: content.minX, y: y))
        cg.addLine(to: CGPoint(x: content.maxX, y: y))
        cg.strokePath()
    }

    // MARK: Text

    /// Draws `text` from the current position, flowing onto new pages as needed.
    private func drawText(_ text: NSAttributedString) {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        while true {
            let available = content.maxY - y
            let container = NSTextContainer(size: CGSize(width: content.width, height: max(available, 1)))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let glyphs = layout.glyphRange(for: container)
            if glyphs.length == 0 {
                // Nothing fits below the cursor. On an empty page that means the content cannot be laid out.
                if atTop { return }
                beginPage()
                continue
            }
            let origin = CGPoint(x: content.minX, y: y)
            layout.drawBackground(forGlyphRange: glyphs, at: origin)
            layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            y += layout.usedRect(for: container).height
            if NSMaxRange(glyphs) >= layout.numberOfGlyphs { return }
            beginPage()
        }
    }

    // MARK: Photos

    private func drawPhoto(_ photo: ReadableDay.Photo) {
        guard let url = try? paths.resolveAttachment(relativePath: photo.relativePath, in: generation) else { return }
        autoreleasepool {
            guard let image = Self.downsampled(url, maxPixel: 1600) else { return }
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            guard width > 0, height > 0 else { return }
            var drawWidth = content.width
            var drawHeight = drawWidth * height / width
            let maxHeight = page.height * Self.photoMaxHeightShare
            if drawHeight > maxHeight {
                drawHeight = maxHeight
                drawWidth = drawHeight * width / height
            }
            ensureSpace(drawHeight + 10)
            UIImage(cgImage: image).draw(in: CGRect(x: content.minX, y: y, width: drawWidth, height: drawHeight))
            y += drawHeight + 10
        }
    }

    /// Decodes at no more than `maxPixel` on the long side, applying the photo's orientation.
    private static func downsampled(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func autoreleasepoolThrowing(_ body: () throws -> Void) throws {
        var thrown: Error?
        autoreleasepool {
            do { try body() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }
}
