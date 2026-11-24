import Testing
@testable import ClipboardCore

struct StatusIconTests {
    @Test func withoutAnUpdateTheIconIsThePlainOne() {
        #expect(StatusIcon.symbol(hasUpdate: false, isDownloading: false) == StatusIcon.plainSymbol)
    }

    @Test func anUpdateOnOfferShowsTheArrowUp() {
        #expect(StatusIcon.symbol(hasUpdate: true, isDownloading: false) == StatusIcon.updateSymbol)
    }

    @Test func aDownloadUnderWayWinsOverTheNoticeOfTheUpdate() {
        // Choosing the update closes the menu: the icon is all that says the download started.
        #expect(StatusIcon.symbol(hasUpdate: true, isDownloading: true) == StatusIcon.downloadingSymbol)
    }
}
