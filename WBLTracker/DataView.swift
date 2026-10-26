import SwiftUI
import UniformTypeIdentifiers

struct DataView: View {
    @EnvironmentObject var store: VisitStore
    @State private var files: [URL] = []
    @State private var exportPresented = false
    @State private var fullConfirmation = false
    @State private var report: ReportKind = .mileage
    @State private var filterDates = false
    @State private var startDate = Calendar.current.date(byAdding:.day,value:-30,to:Date()) ?? .now
    @State private var endDate = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section("Export individual reports") {
                    Picker("Report",selection:$report) {
                        ForEach(ReportKind.allCases) { type in Text(type.rawValue).tag(type) }
                    }.pickerStyle(.menu)
                    Toggle("Choose a date range",isOn:$filterDates)
                    if filterDates {
                        DatePicker("From (inclusive)",selection:$startDate,displayedComponents:.date)
                        DatePicker("Through (inclusive)",selection:$endDate,displayedComponents:.date)
                    }
                    Text("Mileage reports use scheduled trip dates. Visit reports use the actual recorded visit dates and times. You can export any range, including across multiple months or years.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Export \(report.rawValue) CSV",systemImage:"square.and.arrow.up") {
                        let start: Date? = filterDates ? startDate : nil
                        let end: Date? = filterDates ? endDate : nil
                        if let file = store.exportCSV(report,start:start,end:end) {
                            files = [file]
                            exportPresented = true
                        }
                    }
                }
                Section("Complete backup • all dates") {
                    Text("Exports every student, all visit records (including visit types), employers, notes, completed and active trips, route stops and mileage. Includes a JSON snapshot. No date filter is applied to backups.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Export everything as ZIP",systemImage:"archivebox") {
                        files = store.exportFiles()
                        exportPresented = !files.isEmpty
                    }
                }
                Section("History stays saved") {
                    Label("Visits and mileage never reset when the month changes.",systemImage:"calendar.badge.checkmark")
                    Text("For a monthly report, choose the first and last day above. You don't need to delete or reset data to start a new month.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Full reset — permanent") {
                    Text("Deletes all students, notes, visits, trips and mileage stored on this device. This is the only reset; export a backup before using it.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Delete all app data",role:.destructive) { fullConfirmation = true }
                }
            }
            .navigationTitle("Data & Exports")
            .sheet(isPresented:$exportPresented) { ExportSheet(files:files) }
            .confirmationDialog("Delete every student and record?",isPresented:$fullConfirmation,titleVisibility:.visible) {
                Button("Permanently delete everything",role:.destructive) { store.fullReset() }
                Button("Cancel",role:.cancel) {}
            } message: { Text("This clears all local WBL records. Export a backup first.") }
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
                    Text("Save the files securely to Files or your school's approved storage. Exports can contain student contact information.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Export files") {
                    ForEach(files,id:\.path) { url in
                        ShareLink(item:url) { Label(url.lastPathComponent,systemImage:"square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Share export")
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
