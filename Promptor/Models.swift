import Foundation
import UniformTypeIdentifiers

struct AppSettings: Codable, Equatable {
    // MARK: - User-visible options
    var includeSubfolders : Bool = true
    var ignoreSuffixes    : Set<String> = DefaultIgnore.suffixes
    var ignoreFolders     : Set<String> = DefaultIgnore.folders
    var maxFileSize       : Int = 500 * 1024         // Bytes

    // MARK: - Hard rules (never exposed in UI)

    /// Central gatekeeper used by the importer.
    func shouldImport(_ url: URL) -> Bool {
        // Folder name filters – cheap early exit
        if url.hasDirectoryPath,
           url.pathComponents.contains(where: { ignoreFolders.contains($0.lowercased()) }) {
            return false
        }

        // Suffix filters (only files reach here)
        if !url.hasDirectoryPath,
           ignoreSuffixes.contains("." + url.pathExtension.lowercased()) {
            return false
        }

        // File size gate
        if let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           sz > maxFileSize {
            return false
        }

        return true
    }
}

/// Canonical ignore lists. Trim/extend as you see fit.
enum DefaultIgnore {
    static let suffixes: Set<String> = [
        // binary / media
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf",
        ".mp4", ".mov", ".mp3", ".wav",
        // archives & build artefacts
        ".zip", ".tar", ".gz", ".rar", ".7z",
        ".class", ".jar", ".war", ".ear", ".o", ".a", ".so", ".dylib",
        ".exe", ".dll", ".app", ".bin", ".pyc",
        // editor & OS noise
        ".ds_store", "thumbs.db"
    ]

    static let folders: Set<String> = [
        // VCS & editors
        ".git", ".github", ".svn", ".hg", ".idea", ".vscode",
        // dependency / build output
        "node_modules", "Pods", "Carthage", "target",
        "build", "dist", "out", "deriveddata", ".next", ".parcel-cache",
        // misc
        ".venv", ".mypy_cache", ".gradle", ".terraform"
    ]
} 