// NSFileCoordinator for one process.
//
// Project-owned. File coordination serialises access between processes and file presenters (an app
// and its extensions, iCloud). A preview runs one process with no other presenters, so a
// coordinated read or write is the accessor run at once on the calling thread, which is what
// coordination reduces to when nothing else holds the item. stupid wallet coordinates writes to its
// app-group files (WalletGroupLifecycle, WalletRegistryAdoption).

import FoundationEssentials

public protocol NSFilePresenter: AnyObject {
    var presentedItemURL: URL? { get }
}

open class NSFileCoordinator: NSObject, @unchecked Sendable {
    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withoutChanges = ReadingOptions(rawValue: 1 << 0)
        public static let resolvesSymbolicLink = ReadingOptions(rawValue: 1 << 1)
        public static let immediatelyAvailableMetadataOnly = ReadingOptions(rawValue: 1 << 2)
        public static let forUploading = ReadingOptions(rawValue: 1 << 3)
    }

    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let forDeleting = WritingOptions(rawValue: 1 << 0)
        public static let forMoving = WritingOptions(rawValue: 1 << 1)
        public static let forMerging = WritingOptions(rawValue: 1 << 2)
        public static let forReplacing = WritingOptions(rawValue: 1 << 3)
        public static let contentIndependentMetadataOnly = WritingOptions(rawValue: 1 << 4)
    }

    public init(filePresenter: (any NSFilePresenter)?) {
        _ = filePresenter
        super.init()
    }

    open func coordinate(readingItemAt url: URL, options: ReadingOptions = [],
                         error outError: UnsafeMutablePointer<NSError?>?,
                         byAccessor reader: (URL) -> Void) {
        _ = (options, outError)
        reader(url)
    }

    open func coordinate(writingItemAt url: URL, options: WritingOptions = [],
                         error outError: UnsafeMutablePointer<NSError?>?,
                         byAccessor writer: (URL) -> Void) {
        _ = (options, outError)
        writer(url)
    }

    open func coordinate(readingItemAt readingURL: URL, options readingOptions: ReadingOptions = [],
                         writingItemAt writingURL: URL, options writingOptions: WritingOptions = [],
                         error outError: UnsafeMutablePointer<NSError?>?,
                         byAccessor readerWriter: (URL, URL) -> Void) {
        _ = (readingOptions, writingOptions, outError)
        readerWriter(readingURL, writingURL)
    }

    open func coordinate(writingItemAt url1: URL, options options1: WritingOptions = [],
                         writingItemAt url2: URL, options options2: WritingOptions = [],
                         error outError: UnsafeMutablePointer<NSError?>?,
                         byAccessor writer: (URL, URL) -> Void) {
        _ = (options1, options2, outError)
        writer(url1, url2)
    }

    open func cancel() {}
}
