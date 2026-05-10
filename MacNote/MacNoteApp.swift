import SwiftUI
import AppKit
import os

@main
struct MacNoteApp: App {

    // MARK: - App-wide state

    @State private var appModel = AppModel()
    @State private var editorVMBox = EditorViewModelBox(EditorViewModel())

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel, editorVMBox: editorVMBox)
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
        }
    }
}

// MARK: - ContentView

/// Root layout: sidebar | detail.
struct ContentView: View {
    var appModel: AppModel
    @ObservedObject var editorVMBox: EditorViewModelBox

    var body: some View {
        NavigationSplitView {
            SidebarView(appModel: appModel)
        } detail: {
            DetailView(appModel: appModel, editorVMBox: editorVMBox)
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

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: Bindable(appModel).searchText)
                    .textFieldStyle(.plain)
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
                .keyboardShortcut("n", modifiers: .command)
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
}

// MARK: - DetailView

struct DetailView: View {
    var appModel: AppModel
    @ObservedObject var editorVMBox: EditorViewModelBox

    var body: some View {
        Group {
            if let selectedID = appModel.selectedNoteID,
               let note = appModel.notes.first(where: { $0.id == selectedID }) {
                EditorPane(
                    note: note,
                    viewModel: editorVMBox,
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
        }
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
