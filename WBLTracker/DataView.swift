import SwiftUI
import UniformTypeIdentifiers

struct DataView: View {
    @EnvironmentObject var store: VisitStore
    @State private var files: [URL] = []
    @State private var exportPresented = false
    @State private var monthlyConfirmation = false
    @State private var fullConfirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Export all data") {
                    Text("Exports students, employers, addresses, visit status and timestamps, notes, trips, mileage and individual trip stops. Includes a complete JSON backup.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Prepare complete export", systemImage:"square.and.arrow.up") {
                        files = store.exportFiles()
                        exportPresented = !files.isEmpty
                    }
                }
                Section("New month") {
                    Text("Keeps every student and their workplace details and notes. Clears visit flags, visit history, planned trips and mileage totals. Export your records before resetting.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Start new month", role:.destructive) { monthlyConfirmation = true }
                }
                Section("Full reset") {
                    Text("Permanently deletes all students, notes, visits, trips and mileage saved on this device. Export first if you need a record.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Delete all app data", role:.destructive) { fullConfirmation = true }
                }
            }
            .navigationTitle("Data & Reset")
            .sheet(isPresented:$exportPresented) { ExportSheet(files:files) }
            .confirmationDialog("Start a new month?", isPresented:$monthlyConfirmation, titleVisibility:.visible) {
                Button("Clear monthly visits and trips", role:.destructive) { store.startNewMonth() }
                Button("Cancel", role:.cancel) {}
            } message: { Text("Students and their notes will stay. Visit history and mileage will be cleared. This can't be undone.") }
            .confirmationDialog("Delete every student and record?", isPresented:$fullConfirmation, titleVisibility:.visible) {
                Button("Permanently delete everything", role:.destructive) { store.fullReset() }
                Button("Cancel", role:.cancel) {}
            } message: { Text("All local WBL data will be deleted. Export a backup first.") }
        }
    }
}

struct ExportSheet: View {
    let files: [URL]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Share the complete ZIP backup to Files, Drive, email or another app before resetting.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Export files") {
                    ForEach(files, id:\.path) { url in
                        ShareLink(item:url) { Label(url.lastPathComponent, systemImage:"square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Full export")
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") {dismiss()} } }
        }
    }
}
