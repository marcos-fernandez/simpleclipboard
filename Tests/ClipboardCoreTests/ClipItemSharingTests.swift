import Foundation
import Testing
@testable import ClipboardCore

/// The menu of a card and the share button ask the same question: one answer, so a card is never offered in one
/// and refused in the other. And what a secured app copied is never offered.
struct ClipItemSharingTests {
    private func item(kind: ClipItem.Kind = .text, text: String? = "copied", isConcealed: Bool = false) -> ClipItem {
        ClipItem(
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            kind: kind,
            text: text,
            imageFileName: kind == .image
                ? "image.png"
                : nil,
            contentHash: "h",
            source: SourceApp(bundleID: nil, name: nil),
            isConcealed: isConcealed,
            expiresAt: nil
        )
    }

    @Test func textIsShared() {
        #expect(item().canBeShared(imageIsReadable: false))
    }

    @Test(arguments: ["", nil] as [String?])
    func textWithNothingInItIsNotShared(text: String?) {
        #expect(!item(text: text).canBeShared(imageIsReadable: true))
    }

    @Test func anImageIsSharedWhileItsFileCanBeRead() {
        #expect(item(kind: .image, text: nil).canBeShared(imageIsReadable: true))
        #expect(!item(kind: .image, text: nil).canBeShared(imageIsReadable: false))
    }

    @Test(arguments: [ClipItem.Kind.image, .text])
    func whatASecuredAppCopiedIsNeverShared(kind: ClipItem.Kind) {
        #expect(!item(kind: kind, isConcealed: true).canBeShared(imageIsReadable: true))
    }
}
