import SwiftUI
import AppKit
import os

@main
struct MacNoteApp: App {

    // MARK: - App-wide state

    @State private var appModel = AppModel()
    @State private var editorVMBox = EditorViewModelBox(EditorViewModel())
    @State private var findSession = FindSession()

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel, editorVMBox: editorVMBox, findSession: findSession)
                .onAppear {
                    appModel.startup()
                    // Wire storage dependencies into the editor view model
                    editorVMBox.vm.noteStore    = appModel.noteStore
                    editorVMBox.vm.indexService = appModel.indexService
                    // Give AppModel a weak handle so deleteNote can cancel pending saves.
                    appModel.editorViewModel = editorVMBox.vm
                    // Mirror editor content state into the @Observable AppModel so the
                    // toolbar Copy button's disabled state updates reactively.
                    editorVMBox.vm.onContentChanged = { [weak appModel] hasContent in
                        appModel?.editorHasContent = hasContent
                    }
                }
                .onDisappear {
                    Task {
                        await editorVMBox.vm.saveNow()
                        appModel.saveState()
                        appModel.fileWatcher.stop()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            FormatMenuCommands(appModel: AppModelBox(appModel))
            DeleteNoteCommands(appModel: AppModelBox(appModel))
            FindMenuCommands(findSession: FindSessionBox(findSession))
            ViewMenuCommands()
        }
    }
}

// MARK: - ContentView

/// Root layout: sidebar | detail.
struct ContentView: View {
    var appModel: AppModel
    @ObservedObject var editorVMBox: EditorViewModelBox
    var findSession: FindSession

    var body: some View {
        NavigationSplitView {
            SidebarView(appModel: appModel)
        } detail: {
            DetailView(appModel: appModel, editorVMBox: editorVMBox, findSession: findSession)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(appModel)
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    var appModel: AppModel
    @State private var showCategoryEditor = false
    @State private var pendingDeleteID: UUID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: Bindable(appModel).searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Category filter
            SidebarCategoryFilter()

            Divider()

            // Date-grouped note list
            SidebarNoteList()

            Divider()

            // Bottom toolbar
            HStack {
                Button {
                    appModel.startNewNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    showCategoryEditor = true
                } label: {
                    Label("Categories", systemImage: "tag")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.startNewNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .regular))
                        .imageScale(.medium)
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Note")
            }
        }
        .sheet(isPresented: $showCategoryEditor) {
            CategoryEditorSheet()
                .environment(appModel)
        }
        .alert("Delete this note?",
               isPresented: Binding(
                   get: { pendingDeleteID != nil },
                   set: { if !$0 { pendingDeleteID = nil } }
               )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { appModel.deleteNote(id: id) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("The note and its images will be moved to ~/.notes/.trash/.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestDeleteNote)) { note in
            if let id = note.object as? UUID { pendingDeleteID = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteSearch)) { _ in
            searchFocused = true
        }
    }
}

// MARK: - DeleteNoteCommands

struct DeleteNoteCommands: Commands {
    @ObservedObject var appModel: AppModelBox

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Delete Note\u{2026}") {
                if let id = appModel.model.selectedNoteID {
                    NotificationCenter.default.post(name: .requestDeleteNote, object: id)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(appModel.model.selectedNoteID == nil)
        }
    }
}

extension Notification.Name {
    static let requestDeleteNote = Notification.Name("MacNote.requestDeleteNote")
    /// Focuses the toolbar's in-note find field (⌘F).
    static let focusNoteFind = Notification.Name("MacNote.focusNoteFind")
    /// Focuses the sidebar's cross-note title search field (⌥⌘F).
    static let focusNoteSearch = Notification.Name("MacNote.focusNoteSearch")
}

// MARK: - DetailView

struct DetailView: View {
    var appModel: AppModel
    @ObservedObject var editorVMBox: EditorViewModelBox
    var findSession: FindSession

    @FocusState private var findFieldFocused: Bool
    @State private var showFontPopover = false

    var body: some View {
        Group {
            if let selectedID = appModel.selectedNoteID,
               let note = appModel.notes.first(where: { $0.id == selectedID }) {
                EditorPane(
                    note: note,
                    viewModel: editorVMBox,
                    findSession: findSession,
                    notesDirectory: appModel.noteStore.notesDirectory
                )
                .id(note.id)   // force view recreation on note switch
            } else {
                EmptyDetailView()
            }
        }
        .frame(minWidth: 400)
        .overlay(alignment: .top) {
            if appModel.isShowingCopyToast {
                CopyToastView()
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appModel.isShowingCopyToast)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.copyCurrentNote()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy note")
                .disabled(!appModel.canCopyCurrentNote)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFontPopover = true
                } label: {
                    Text("Aa")
                }
                .help("Font Size")
                .popover(isPresented: $showFontPopover) {
                    FontSizePopover()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NoteFindField(findSession: findSession, isFocused: $findFieldFocused)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteFind)) { _ in
            findFieldFocused = true
        }
    }
}

// MARK: - NoteFindField

/// Rounded, Apple-Notes-style find field in the detail toolbar. Highlights are
/// painted by `FindSession` directly onto the text view; this view only reads
/// `findSession`'s state to drive the query field, match counter, and
/// next/previous chevrons.
private struct NoteFindField: View {
    var findSession: FindSession
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Note", text: Bindable(findSession).query)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .frame(minWidth: 90, maxWidth: 160)
                .onExitCommand { findSession.clear() }
            if let countText = findSession.matchCountText {
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if !findSession.matches.isEmpty {
                Button(action: findSession.previous) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                Button(action: findSession.next) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
    }
}

// MARK: - FontSizePopover

private struct FontSizePopover: View {
    var body: some View {
        @Bindable var settings = EditorSettings.shared
        VStack(spacing: 12) {
            Text("\(Int(settings.fontSize)) pt")
                .font(.headline)
            HStack {
                Button {
                    settings.zoomOut()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.borderless)
                Slider(
                    value: Binding(
                        get: { Double(settings.fontSize) },
                        set: { settings.setFontSize(CGFloat($0)) }
                    ),
                    in: Double(EditorSettings.minSize)...Double(EditorSettings.maxSize),
                    step: 1
                )
                .frame(width: 140)
                Button {
                    settings.zoomIn()
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.borderless)
            }
            Button("Actual Size") {
                settings.resetZoom()
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 220)
    }
}

struct CopyToastView: View {
    var body: some View {
        Label("Note copied", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

// MARK: - EmptyDetailView

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select or create a note")
                .foregroundStyle(.secondary)
            Text("Command-N to create a new note")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
