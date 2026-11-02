import SwiftUI

struct ThemePalette {
    let name: String
    let tint: Color
    let softTint: Color
    let cardBackground: Color
}

enum AppTheme: String, CaseIterable, Identifiable {
    case skyBlue = "Light Blue"
    case forestGreen = "Forest Green"
    case plum = "Soft Plum"
    case sunrise = "Sunrise"

    var id: String { rawValue }

    var palette: ThemePalette {
        switch self {
        case .skyBlue:
            let blue = Color(red: 0.11, green: 0.43, blue: 0.74)
            return ThemePalette(name: rawValue, tint: blue,
                                softTint: Color(red: 0.87, green: 0.94, blue: 1.0),
                                cardBackground: Color(red: 0.93, green: 0.97, blue: 1.0))
        case .forestGreen:
            return ThemePalette(name: rawValue, tint: Color(red: 0.14, green: 0.42, blue: 0.33),
                                softTint: Color.green.opacity(0.13), cardBackground: Color.green.opacity(0.07))
        case .plum:
            return ThemePalette(name: rawValue, tint: Color(red: 0.44, green: 0.26, blue: 0.63),
                                softTint: Color.purple.opacity(0.13), cardBackground: Color.purple.opacity(0.07))
        case .sunrise:
            return ThemePalette(name: rawValue, tint: Color(red: 0.66, green: 0.35, blue: 0.09),
                                softTint: Color.orange.opacity(0.14), cardBackground: Color.orange.opacity(0.08))
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case system = "Match iPhone"
    case dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .system: return nil
        case .dark: return .dark
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var current: AppTheme {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "timestamp.theme") }
    }
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "timestamp.appearance") }
    }

    init() {
        let defaults = UserDefaults.standard
        let oldTheme = defaults.string(forKey: "visitpath.theme")
        let chosenTheme = defaults.string(forKey: "timestamp.theme") ?? oldTheme ?? ""
        current = (chosenTheme == "Calm Blue") ? .skyBlue : (AppTheme(rawValue: chosenTheme) ?? .skyBlue)
        appearance = AppAppearance(rawValue: defaults.string(forKey: "timestamp.appearance") ?? "") ?? .light
    }
}

struct BrandHeaderView: View {
    @EnvironmentObject var theme: ThemeManager
    var subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image("VisitPathLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .padding(10)
                .background(theme.current.palette.softTint, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Timestamp").font(.title2.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var store: VisitStore
    @State private var confirmDisableDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandHeaderView(subtitle: "Workplace visits made simple")
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section("Colors & appearance") {
                    Picker("Color theme", selection: $theme.current) {
                        ForEach(AppTheme.allCases) { choice in Text(choice.rawValue).tag(choice) }
                    }
                    Picker("Screen appearance", selection: $theme.appearance) {
                        ForEach(AppAppearance.allCases) { choice in Text(choice.rawValue).tag(choice) }
                    }
                    Text("Light Blue with white backgrounds is the default. Your selections are saved automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Student data retention") {
                    Toggle("Delete records after graduation", isOn: Binding(
                        get: { store.automaticDeletionEnabled },
                        set: { enabled in
                            if enabled { store.automaticDeletionEnabled = true }
                            else { confirmDisableDeletion = true }
                        }
                    ))
                    Label("Example: graduation year 2028 → deletion on July 1, 2029.", systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                    Text("When enabled, Timestamp checks at launch, when you return to the app, and after importing or editing students. It removes expired students, their notes and visits, and trips that include them. It does not erase exports, cloud/device backups, or copies shared elsewhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.missingGraduationYearCount > 0 {
                        Label("\(store.missingGraduationYearCount) students have missing/invalid graduation years and cannot be automatically deleted. Correct those records.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let notice = store.lastCleanupNotice {
                        Label(notice, systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Your responsibility") {
                    Label("Student information is sensitive", systemImage: "lock.shield")
                        .font(.headline)
                    Text("You are responsible for following your school's retention policy. Before a record expires, securely transfer required student records to your school's approved system, or keep automatic deletion enabled when permitted by school policy. Turning off auto-delete means you must manage deletion yourself.")
                    Text("Student information is stored on this device. Exported files and backups must be protected and deleted separately. Automatic deletion does not guarantee legal compliance or remove copies outside this app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Turn off automatic deletion?", isPresented: $confirmDisableDeletion) {
                Button("Keep on", role: .cancel) { }
                Button("Turn off") { store.automaticDeletionEnabled = false }
            } message: {
                Text("You will be responsible for manually transferring and deleting student data under your school's policy. Existing records will remain until you delete them.")
            }
        }
    }
}

struct PrivacyNoticeView: View {
    let acknowledge: () -> Void
    let reviewBeforeDeleting: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Protect student information", systemImage: "lock.shield.fill")
                        .font(.title2.bold()).foregroundStyle(Color(red: 0.11, green: 0.43, blue: 0.74))
                    Text("Timestamp may contain private student records, workplace addresses, phone numbers, and teacher notes.")
                    Text("You are responsible for securely transferring records the school must retain to an approved system, or using automatic deletion when school policy permits it.")
                    Text("Automatic deletion is ON by default. For graduation year 2028, records are due for deletion July 1, 2029. The app checks when it opens or becomes active, not while closed.")
                    Text("If you are updating an older version, enabling deletion now may immediately remove records past their cutoff, including associated trips. Transfer any school-required data first.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Exports, device backups, and shared copies are not deleted automatically. Confirm your school's retention requirements before using real student information.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("I understand — enable deletion") { acknowledge() }
                        .font(.headline)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    Button("Review or export older records first") { reviewBeforeDeleting() }
                        .frame(maxWidth: .infinity)
                    Text("The review option temporarily turns automatic deletion off. Re-enable it in Settings after securely transferring required records.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Student privacy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
