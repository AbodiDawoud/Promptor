import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Models (should potentially move to Models.swift)

// Hierarchical node structure that can represent both files and folders
struct FileNode: Identifiable, Hashable {
    let id = UUID()
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
    @Published var expandedNodes: Set<UUID> = []  // Track expanded folders
    @Published var finalPrompt: String = ""
    @Published var rootFolderURL: URL?
    @Published var settings = AppSettings()
    @Published var showRemoveIcons: Bool = true
    @Published var currentTemplate: Template = Template(name: "Default", format: "{{files}}")
    
    init() {
        // Try to restore previously accessed folder on launch
        restoreLastFolderAccess()
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
        self.fileNodes = []
        self.selectedNodes = []
        self.expandedNodes = []
        
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
            
            // Also create a flat list for backward compatibility
            self.fileNodes = flattenFileTree(self.rootNode)
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
                    url: url,
                    relativePath: relativePath.isEmpty ? name : relativePath,
                    name: name,
                    isDirectory: true,
                    children: children,
                    content: nil,
                    isSelected: false,
                    isExpanded: false
                )
            } else {
                // Create a file node (content loaded on demand)
                return FileNode(
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
    func toggleExpansion(_ nodeID: UUID) {
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
        _ id: UUID,
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
        let selectedFiles = selectedNodes.filter { !$0.isDirectory }
        let sortedSelectedNodes = selectedFiles.sorted { $0.relativePath < $1.relativePath }
        for node in sortedSelectedNodes {
            // Load content if needed
            var content = node.content
            if content == nil {
                content = loadFileContent(node.url)
            }
            let header = "```\(node.relativePath)\n"
            let footer = "\n```"
            chunks.append(header + (content ?? "Error: Could not read file.") + footer)
        }
        finalPrompt = currentTemplate.render(with: chunks.joined(separator: "\n\n"))
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

    func refreshAll() {
        guard let root = rootFolderURL else { return }
        importFolder(root)
    }
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
