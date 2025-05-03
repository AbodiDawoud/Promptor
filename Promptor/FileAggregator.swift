import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Models (should potentially move to Models.swift)

// Hierarchical node structure that can represent both files and folders
struct FileNode: Identifiable, Hashable {
    let id: String
    let url: URL
    var relativePath: String
    var name: String  // Just the filename or directory name
    var isDirectory: Bool
    var children: [FileNode]?  // For directories
    var content: String?  // For files
    var isSelected: Bool = false
    var isExpanded: Bool = false  // For UI expansion state
    
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Template structure - Identifiable for use in ForEach
struct Template: Identifiable, Hashable {
    var id: String { name } // Use name as the unique ID
    var name: String
    var format: String
    func render(with content: String) -> String {
        format.replacingOccurrences(of: "{{files}}", with: content)
    }
}

// MARK: - FileAggregator ViewModel

class FileAggregator: ObservableObject {
    @Published var rootNode: FileNode?  // Root of our file tree
    @Published var fileNodes: [FileNode] = []  // Flat list for backward compatibility
    @Published var selectedNodes: Set<FileNode> = []
    @Published var expandedNodes: Set<String> = []  // Track expanded folders by String ID
    @Published var finalPrompt: String = ""
    @Published var rootFolderURL: URL?
    @Published var settings = AppSettings()
    @Published var showRemoveIcons: Bool = true
    @Published var currentTemplate: Template = Template(name: "Default", format: "{{files}}")
    
    // --- NEW: Folder Watcher Properties ---
    private var watcher: FolderWatcher?
    private var cancellables = Set<AnyCancellable>()
    private let treeDidChange = PassthroughSubject<Void, Never>()
    // --- END NEW ---

    init() {
        // Try to restore previously accessed folder on launch
        restoreLastFolderAccess()
        
        // --- NEW: Setup Debouncer for Folder Watcher ---
        // Debounce rapid bursts of file system events
        treeDidChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] in
                print("FSEvent triggered rescanTree()") // Add logging
                self?.rescanTree()
            }
            .store(in: &cancellables)
        // --- END NEW ---
    }
    
    // Restore access to previously selected folder if available
    private func restoreLastFolderAccess() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "LastFolderBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, 
                                 options: .withSecurityScope, 
                                 relativeTo: nil, 
                                 bookmarkDataIsStale: &isStale)
                
                if isStale {
                    print("Bookmark is stale, not restoring previous folder")
                    return
                }
                
                // We have successfully resolved the bookmark
                DispatchQueue.main.async {
                    self.importFolder(url)
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    func importFolder(_ root: URL) {
        self.rootFolderURL = root
        
        // --- Preserve state before clearing ---
        let previousSelectedIDs = Set(selectedNodes.map { $0.id })
        let previousExpandedIDs = expandedNodes // Keep existing expanded set
        // --- End Preserve ---

        self.fileNodes = [] // Still clear flat list if needed
        // Don't clear selectedNodes/expandedNodes here, restore them later
        
        let fm = FileManager.default
        
        // Ensure we have access to the folder
        var hasAccess = true
        
        // Store a security-scoped bookmark to maintain access to this folder
        do {
            // Store security-scoped bookmark
            let bookmarkData = try root.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "LastFolderBookmark")
        } catch {
            print("Failed to create security-scoped bookmark: \(error)")
        }
        
        // Access the folder with security scope
        if root.startAccessingSecurityScopedResource() {
            defer { root.stopAccessingSecurityScopedResource() }
            
            // Create the hierarchical structure
            self.rootNode = createFileTree(at: root, relativeTo: root, fileManager: fm)
            
            // Restore selection and expansion state
            restoreSelectionAndExpansion(selectedIDs: previousSelectedIDs, expandedIDs: previousExpandedIDs)

            // Recompute folder selections based on restored state
            recomputeFolderSelections()

            // Assemble initial prompt
            assemblePrompt() // Assemble after restoring state
            
            // Also create a flat list for backward compatibility if needed
            // self.fileNodes = flattenFileTree(self.rootNode) // Can be done if flat list is still used

            // --- NEW: Start watcher after successful import ---
            startWatching(root)
            // --- END NEW ---
        } else {
            print("Error: Cannot access security-scoped resource.")
            hasAccess = false
        }
        
        // Update UI on main thread
        DispatchQueue.main.async {
            if !hasAccess {
                self.finalPrompt = "Error: Cannot access the selected folder. Please check permissions."
            }
        }
    }
    
    // Recursively create a file tree
    private func createFileTree(at url: URL, relativeTo rootURL: URL, fileManager fm: FileManager) -> FileNode? {
        // Apply global import filter rules first.
        guard settings.shouldImport(url) else { return nil }
        
        do {
            // Get required attributes
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey, .fileSizeKey]
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            
            // Calculate relative path
            let relativePath = url.path.replacingOccurrences(of: rootURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            // Get name for display
            let name = resourceValues.name ?? url.lastPathComponent
            
            // Is this a directory or file?
            let isDirectory = resourceValues.isDirectory ?? false
            
            // --- NEW: Use url.path for stable ID ---
            let nodeID = url.path
            // --- END NEW ---
            
            if isDirectory {
                // For directories, recursively process contents
                var children: [FileNode] = []
                
                if settings.includeSubfolders || url == rootURL {
                    do {
                        let directoryContents = try fm.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: resourceKeys,
                            options: [.skipsHiddenFiles, .skipsPackageDescendants]
                        )
                        for itemURL in directoryContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                            if let childNode = createFileTree(at: itemURL, relativeTo: rootURL, fileManager: fm) {
                                children.append(childNode)
                            }
                        }
                    } catch {
                        print("Error listing directory contents: \(error)")
                    }
                }
                
                return FileNode(
                    id: nodeID, // NEW ID
                    url: url,
                    relativePath: relativePath.isEmpty ? name : relativePath,
                    name: name,
                    isDirectory: true,
                    children: children,
                    content: nil,
                    isSelected: false,
                    isExpanded: false // Default expansion state
                )
            } else {
                // Create a file node (content loaded on demand)
                return FileNode(
                    id: nodeID, // NEW ID
                    url: url,
                    relativePath: relativePath.isEmpty ? name : relativePath,
                    name: name,
                    isDirectory: false,
                    children: nil,
                    content: nil,
                    isSelected: false
                )
            }
        } catch {
            print("Error processing \(url.path): \(error)")
            return nil
        }
    }
    
    // Flatten the tree into a list (for backward compatibility)
    private func flattenFileTree(_ node: FileNode?) -> [FileNode] {
        guard let node = node else { return [] }
        
        var result: [FileNode] = []
        
        // Add files (not directories) to the list
        if !node.isDirectory {
            result.append(node)
        }
        
        // Recursively add children
        if let children = node.children {
            for child in children {
                result.append(contentsOf: flattenFileTree(child))
            }
        }
        
        return result
    }
    
    // Recursively collect all nodes
    private func collectAllNodes(_ node: FileNode?) -> [FileNode] {
        guard let n = node else { return [] }
        var arr: [FileNode] = [n]
        if let children = n.children {
            for c in children { arr.append(contentsOf: collectAllNodes(c)) }
        }
        return arr
    }

    // Toggle node selection (only flips the node, then recompute tree)
    func toggleSelection(_ node: FileNode) {
        _ = findAndUpdateNode(node.id, in: &rootNode) { n in
            var copy = n
            copy.isSelected.toggle()
            return copy
        }
        recomputeFolderSelections()
        assemblePrompt()
    }

    // Recursive selection set / unset
    func setSelectionRecursively(node: FileNode, select: Bool) {
        _ = findAndUpdateNode(node.id, in: &rootNode) { n in
            var copy = n; copy.isSelected = select; return copy }
        if let children = node.children {
            for child in children {
                setSelectionRecursively(node: child, select: select)
            }
        }
        recomputeFolderSelections()
        assemblePrompt()
    }

    // Toggle folder expansion
    func toggleExpansion(_ nodeID: String) {
        if expandedNodes.contains(nodeID) {
            expandedNodes.remove(nodeID)
        } else {
            expandedNodes.insert(nodeID)
        }
        
        // Also update the node's state if needed
        _ = findAndUpdateNode(
            nodeID,
            in: &rootNode,
            update: { node in
                var updatedNode = node
                updatedNode.isExpanded = expandedNodes.contains(nodeID)
                return updatedNode
            }
        )
    }
    
    // Helper to find and update a node in the tree
    private func findAndUpdateNode(
        _ id: String,
        in node: inout FileNode?,
        update: (FileNode) -> FileNode
    ) -> FileNode? {
        guard let nodeUnwrapped = node else { return nil }
        
        if nodeUnwrapped.id == id {
            // Found the node, update it
            let updatedNode = update(nodeUnwrapped)
            node = updatedNode
            return updatedNode
        }
        
        // Search in children if this is a directory
        if nodeUnwrapped.isDirectory, let children = nodeUnwrapped.children {
            var mutableChildren = children
            for i in 0..<mutableChildren.count {
                let childNode = mutableChildren[i]
                var childCopy: FileNode? = childNode // Create a mutable copy
                if let updatedChild = findAndUpdateNode(id, in: &childCopy, update: update) {
                    // Update the child in the array
                    mutableChildren[i] = childCopy!
                    // Update the children array in the node
                    var mutableNode = nodeUnwrapped
                    mutableNode.children = mutableChildren
                    node = mutableNode
                    return updatedChild
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Recompute parent folder selection states
    private func recomputeFolderSelections() {
        // propagate upward selection logic
        func dfs(_ node: inout FileNode?) -> Bool {
            guard var n = node else { return false }
            if let children = n.children {
                var allSelected = true
                var newChildren = children
                for i in newChildren.indices {
                    var child: FileNode? = newChildren[i]
                    let childSelected = dfs(&child)
                    newChildren[i] = child!
                    allSelected = allSelected && childSelected
                }
                n.children = newChildren
                if !n.children!.isEmpty {
                    n.isSelected = allSelected
                }
            }
            node = n
            return n.isSelected
        }
        dfs(&rootNode)

        // rebuild selectedNodes (include folders & files)
        let all = collectAllNodes(rootNode)
        selectedNodes = Set(all.filter { $0.isSelected })
    }

    // Assemble the final prompt using only selected files
    func assemblePrompt() {
        var chunks: [String] = []
        // Make sure selectedNodes is up-to-date before assembling
        let currentSelectedFiles = collectAllNodes(rootNode).filter { $0.isSelected && !$0.isDirectory }

        let sortedSelectedNodes = currentSelectedFiles.sorted { $0.relativePath < $1.relativePath }

        // --- Clear cache for selected files before assembling ---
        // This ensures we re-read content during assembly if needed
        for node in sortedSelectedNodes {
             _ = findAndUpdateNode(node.id, in: &rootNode) { n in
                 var copy = n
                 copy.content = nil // Clear cache
                 return copy
             }
        }
        // --- End Clear Cache ---

        for node in sortedSelectedNodes {
            // Reload content by calling loadFileContent directly here
            // Content cache was cleared above, so this will re-read if necessary
            let content = loadFileContent(node.url)
            // Update node's content cache (optional, but can avoid re-reading immediately)
            // _ = findAndUpdateNode(node.id, in: &rootNode) { n in var copy = n; copy.content = content; return copy }

            let header = "```\(node.relativePath)\n"
            let footer = "\n```"
            chunks.append(header + (content ?? "Error: Could not read file.") + footer)
        }
        finalPrompt = currentTemplate.render(with: chunks.joined(separator: "\n\n"))
        print("Prompt assembled with \(sortedSelectedNodes.count) files.") // Add logging
    }
    
    // Helper to safely load file content
    private func loadFileContent(_ url: URL) -> String? {
        // First make sure we can access the file with security scope
        if !url.startAccessingSecurityScopedResource() {
            print("Cannot access file with security scope: \(url.path)")
            
            // Try another approach - access through the root folder
            if let rootURL = rootFolderURL, rootURL.startAccessingSecurityScopedResource() {
                defer { rootURL.stopAccessingSecurityScopedResource() }
            } else {
                // Try to resolve from bookmark as last resort
                if let bookmarkData = UserDefaults.standard.data(forKey: "LastFolderBookmark") {
                    do {
                        var isStale = false
                        let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, 
                                                 options: .withSecurityScope, 
                                                 relativeTo: nil, 
                                                 bookmarkDataIsStale: &isStale)
                        
                        if resolvedURL.startAccessingSecurityScopedResource() {
                            defer { resolvedURL.stopAccessingSecurityScopedResource() }
                        }
                    } catch {
                        print("Failed to resolve bookmark: \(error)")
                        
                        // Post notification about the error
                        NotificationCenter.default.post(
                            name: NSNotification.Name("FileAccessError"),
                            object: "Failed to access the selected folder. You may need to re-select it."
                        )
                        
                        return "Error: Permission issue. Please re-select the folder."
                    }
                }
            }
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Now try to read the file
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Error reading file \(url.path): \(error)")
            
            // Post notification about the error
            NotificationCenter.default.post(
                name: NSNotification.Name("FileAccessError"),
                object: "Failed to read file \(url.lastPathComponent): \(error.localizedDescription)"
            )
            
            return "Error reading file. Please check permissions or try selecting the folder again."
        }
    }

    // MARK: - Expand / Collapse All
    func toggleTreeExpansion() {
        // If any directory is collapsed -> expand all else collapse all
        var needExpand = false
        func checkCollapsed(_ node: FileNode?) {
            guard let n = node else { return }
            if n.isDirectory {
                if !expandedNodes.contains(n.id) { needExpand = true }
                n.children?.forEach { checkCollapsed($0) }
            }
        }
        checkCollapsed(rootNode)
        if needExpand {
            // expand all
            func expand(_ node: FileNode?) {
                guard let n = node else { return }
                if n.isDirectory { expandedNodes.insert(n.id) }
                n.children?.forEach { expand($0) }
            }
            expand(rootNode)
        } else {
            expandedNodes.removeAll()
        }
    }

    // --- NEW: Refresh Methods ---
    /// Re-scans the folder hierarchy (slow but thorough), preserving state.
    func rescanTree() {
        print("Starting rescanTree...") // Add logging
        guard let root = rootFolderURL else { return }
        // Call importFolder which now preserves state
        importFolder(root)
        print("Finished rescanTree.") // Add logging
    }

    /// Only re-loads content of files already in the tree (fast).
    func reloadContents() {
        print("Starting reloadContents...") // Add logging
        // Collect all nodes currently in the tree
        let allNodesInTree = collectAllNodes(rootNode)

        // Filter for files (not directories)
        let filesToRefresh = allNodesInTree.filter { !$0.isDirectory }

        var cacheClearedCount = 0
        // Iterate through the files and clear their cached content
        for fileNode in filesToRefresh {
            // Use findAndUpdateNode to clear the content cache in the main tree structure
             let updatedNode = findAndUpdateNode(fileNode.id, in: &rootNode) { node in
                var copy = node
                if copy.content != nil { // Only clear if it was actually cached
                    copy.content = nil
                    cacheClearedCount += 1
                }
                return copy
            }
             // Optional: Log if a node wasn't found, though it shouldn't happen if collected correctly
             // if updatedNode == nil { print("Warning: Could not find node \(fileNode.id) to clear cache.") }
        }
        print("Cleared cache for \\(cacheClearedCount) files.") // Add logging

        // Re-assemble the prompt. assemblePrompt() will now call loadFileContent()
        // for selected files because their cache is empty.
        assemblePrompt()
        print("Finished reloadContents.") // Add logging
    }
    // --- END NEW Refresh Methods ---

    // --- NEW: Folder Watcher Management ---
    private func startWatching(_ folder: URL) {
        // Stop existing watcher if any
        watcher?.stop()
        watcher = nil
        
        // Create and start a new watcher
        watcher = FolderWatcher(url: folder) { [weak self] in
             print("FolderWatcher event received.") // Add logging
             self?.treeDidChange.send() // Signal that something changed
        }
        if watcher == nil {
             print("Error: Failed to initialize FolderWatcher for \(folder.path)")
        }
    }
    // --- END NEW ---
}

// MARK: - Selection Count Helpers (Moved into Extension)
extension FileAggregator {
    func countForNode(_ node: FileNode) -> (selected: Int, total: Int) {
        if !node.isDirectory {
            return (node.isSelected ? 1 : 0, 1)
        }
        
        var selected = 0
        var total = 0
        
        if let children = node.children {
            for child in children {
                let childCount = countForNode(child)
                selected += childCount.selected
                total += childCount.total
            }
        }
        
        return (selected, total)
    }
}

extension FileAggregator {
    /// Deselect every node and rebuild the prompt.
    func clearSelections() {
        // 1. Walk the tree and mark every node unselected.
        func deselect(_ node: inout FileNode?) {
            guard var n = node else { return }
            n.isSelected = false
            if var children = n.children {
                for i in children.indices {
                    var child: FileNode? = children[i]
                    deselect(&child)
                    children[i] = child!
                }
                n.children = children
            }
            node = n
        }

        deselect(&rootNode)

        // 2. Empty the selection set and prompt.
        selectedNodes.removeAll()
        assemblePrompt()
    }

    /// Remove all imported files and reset state.
    func removeAll() {
        rootNode          = nil
        fileNodes.removeAll()
        selectedNodes.removeAll()
        expandedNodes.removeAll()
        finalPrompt       = ""
        rootFolderURL     = nil
        showRemoveIcons   = true
    }
}

// --- NEW: Restore Selection and Expansion State ---
extension FileAggregator {
    private func restoreSelectionAndExpansion(selectedIDs: Set<String>, expandedIDs: Set<String>) {
        self.selectedNodes = [] // Clear before restoring
        self.expandedNodes = expandedIDs // Directly restore expanded IDs

        func restoreRecursively(_ node: inout FileNode?) {
            guard var n = node else { return }

            if selectedIDs.contains(n.id) {
                n.isSelected = true
                self.selectedNodes.insert(n) // Add to the set
            } else {
                n.isSelected = false // Ensure others are not selected
            }

            n.isExpanded = expandedIDs.contains(n.id) // Restore expansion

            if var children = n.children {
                for i in children.indices {
                    var child: FileNode? = children[i]
                    restoreRecursively(&child)
                    children[i] = child! // Assign back the potentially modified child
                }
                n.children = children
            }
            node = n // Assign back the potentially modified node
        }

        restoreRecursively(&rootNode)
    }
}
