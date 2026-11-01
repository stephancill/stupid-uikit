// FileManager.replaceItemAt, which FoundationEssentials' FileManager does not provide.
//
// Project-owned. stupid wallet's ClearSigningRegistry writes a temporary file and replaces its cache
// with it. The replacement is rename(2), which swaps the new item in for the original atomically as
// Darwin's implementation does on one volume; a backup name first copies the original beside it.

import FoundationEssentials
import Darwin

public extension FileManager {
    @discardableResult
    func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL,
                       backupItemName: String? = nil,
                       options: ItemReplacementOptions = []) throws -> URL? {
        var backupURL: URL?
        if let backupItemName, fileExists(atPath: originalItemURL.path) {
            let backup = originalItemURL.deletingLastPathComponent().appendingPathComponent(backupItemName)
            if fileExists(atPath: backup.path) { try removeItem(at: backup) }
            try copyItem(at: originalItemURL, to: backup)
            backupURL = backup
        }
        guard Darwin.rename(newItemURL.path, originalItemURL.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: originalItemURL.path])
        }
        if let backupURL, !options.contains(.withoutDeletingBackupItem) {
            try? removeItem(at: backupURL)
        }
        return originalItemURL
    }
}
