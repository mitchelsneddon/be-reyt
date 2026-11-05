import Foundation
import Testing

@testable import ReytKit

struct AttachmentLayoutTests {
    @Test(
        "supported image types map to extensions, others are refused",
        arguments: [
            ("public.heic", "heic"), ("public.jpeg", "jpg"), ("public.png", "png"),
        ])
    func extensionMapping(uti: String, ext: String) {
        #expect(AttachmentLayout.fileExtension(forUTI: uti) == ext)
    }

    @Test(
        "unsupported types have no extension", arguments: ["public.mpeg-4", "com.adobe.pdf", "public.plain-text", ""])
    func unsupported(uti: String) {
        #expect(AttachmentLayout.fileExtension(forUTI: uti) == nil)
        #expect(AttachmentLayout.relativePath(id: UUID(), uti: uti) == nil)
    }

    @Test("relative path is a flat lowercase uuid plus extension")
    func relativePath() {
        let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        #expect(
            AttachmentLayout.relativePath(id: id, uti: "public.heic") == "abcdef01-2345-6789-abcd-ef0123456789.heic")
    }

    @Test("thumbnail path is per generation, and a bad generation id yields nil")
    func thumbnailPath() {
        let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        #expect(
            AttachmentLayout.thumbnailPath(generationID: "g2", id: id)
                == "thumbnails/g2/abcdef01-2345-6789-abcd-ef0123456789.jpg")
        #expect(AttachmentLayout.thumbnailPath(generationID: "../x", id: id) == nil)
    }

    @Test("orphans are files with no record and not mid-import")
    func orphans() {
        let found = AttachmentLayout.orphans(
            filesOnDisk: ["a.jpg", "b.heic", "c.png", "sub/d.jpg"], recordPaths: ["a.jpg", "sub/d.jpg"],
            inFlight: ["c.png"])
        #expect(found == ["b.heic"])
        #expect(AttachmentLayout.orphans(filesOnDisk: [], recordPaths: ["a.jpg"]).isEmpty)
        #expect(AttachmentLayout.orphans(filesOnDisk: ["a.jpg"], recordPaths: []) == ["a.jpg"])
    }
}
