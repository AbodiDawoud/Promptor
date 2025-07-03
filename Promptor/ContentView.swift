import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var vm: FileAggregator
    @State private var showingFileImporter = false
    @State private var pickedFolderURL: URL?
    @State private var showImportOptions = false
    @State private var copied = false
    
    var body: some View {
        NavigationSplitView {
            FileTreeSidebar()
                .environmentObject(vm)
                .navigationTitle("Files")
                .toolbar {
                    // Forward controls to the file manager actions
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                    }
                }
        } detail: {
            let tokenCount = Int(round(Double(vm.finalPrompt.count) / 4.0)) // Calculate token count

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Text("\(tokenCount) tokens") // Display token count
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8) // Add some spacing

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(vm.finalPrompt, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now()+1) { copied = false }
                    } label: {
                        Label(copied ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy Prompt to Clipboard")
                }
                .padding([.top, .trailing])
                
                TextEditor(text: $vm.finalPrompt)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Prompt")
        }
        .toolbar { PromptToolbar() }
        .fileImporter(isPresented: $showingFileImporter,
                      allowedContentTypes: [.folder, .item],
                      allowsMultipleSelection: true) { res in
            if case let .success(urls) = res, let first = urls.first {
                pickedFolderURL = first
                showImportOptions = true
            }
        }
        .sheet(isPresented: $showImportOptions) {
            if let folder = pickedFolderURL {
                ImportOptionsSheet(folderURL: folder,
                                   settings: vm.settings) { confirmed, newSettings in
                    if confirmed {
                        vm.settings = newSettings
                        vm.importFolder(folder)
                    }
                    showImportOptions = false
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if vm.rootNode == nil {
                showingFileImporter = true
            }
        }
    }
}

struct FileTreeSidebar: View {
    @EnvironmentObject var vm: FileAggregator
    @State private var showingFileImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Add Folder button in header area - refined styling
            Button {
                showingFileImporter = true
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
            .background(Color.accentColor.opacity(0.06))
            .cornerRadius(4)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.bottom, 4)
            
            if let root = vm.rootNode {
                // Use List with sidebar style for automatic indentation and scrolling
                List {
                    // Wrap root in an array and use correct key path
                    OutlineGroup([root], children: \.children) { node in
                        FileRow(node: node)
                            // Note: EnvironmentObject is implicitly passed down,
                            // but explicitly adding it here for clarity doesn't hurt.
                            .environmentObject(vm)
                    }
                }
                .listStyle(.sidebar) // Apply sidebar styling
                // Removed .background and .padding(.horizontal, 8) as List handles this
            } else {
                VStack {
                    Spacer()
                    Text("No folder selected")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .fileImporter(isPresented: $showingFileImporter,
                      allowedContentTypes: [UTType.folder],
                      allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                vm.importFolder(url)
            }
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var vm: FileAggregator
    let node: FileNode
    
    // Compute child counts for display
    private var selectionCount: String {
        if node.isDirectory {
            let counts = vm.countForNode(node)
            return "(\(counts.selected)/\(counts.total))"
        }
        return ""
    }
    
    // Determine if the node is selected based on the ViewModel's Set
    private var isSelected: Bool {
        vm.selectedNodes.contains(node)
    }
    
    var body: some View {
        HStack(spacing: 6) { // Slightly increased spacing for better readability
            // File/Folder icon with proper coloring
            Group {
                if node.isDirectory {
                    Image(systemName: vm.expandedNodes.contains(node.id) ? "folder.fill" : "folder")
                        .foregroundColor(.blue)
                        .imageScale(.medium)
                } else {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                        .imageScale(.small)
                }
            }
            .frame(width: 20, alignment: .center)
            
            // Selection checkbox
            Button {
                if node.isDirectory {
                    vm.setSelectionRecursively(node: node, select: !isSelected)
                } else {
                    vm.toggleSelection(node)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : Color(white: 0.7))
                    .symbolRenderingMode(.hierarchical) // For better visual harmony
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .frame(width: 20, alignment: .center)
            .contentShape(Rectangle())
            
            // Filename + selection count for folders
            HStack(spacing: 4) {
                Text(node.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                
                if node.isDirectory {
                    Text(selectionCount)
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                        .padding(.leading, 2)
                }
            }
            
            Spacer(minLength: 8)
        }
        // Slightly rounder corners on the selection highlight for more polish
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
        .environmentObject(FileAggregator())
} 
