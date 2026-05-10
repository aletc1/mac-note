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
    }
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
                    draftText: .constant(""),
                    isDraft: false,
                    viewModel: editorVMBox
                )
                .id(note.id)   // force view recreation on note switch
            } else if appModel.draftBuffer.isActive {
                EditorPane(
                    note: nil,
                    draftText: Bindable(appModel.draftBuffer).text,
                    isDraft: true,
                    viewModel: editorVMBox
                )
            } else {
                EmptyDetailView()
            }
        }
        .frame(minWidth: 400)
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
