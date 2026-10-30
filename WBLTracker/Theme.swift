import SwiftUI

struct ThemePalette {
    let name: String
    let tint: Color
    let softTint: Color
    let cardBackground: Color
}

enum AppTheme: String, CaseIterable, Identifiable {
    case calmBlue = "Calm Blue"
    case forestGreen = "Forest Green"
    case plum = "Soft Plum"
    case sunrise = "Sunrise"

    var id: String { rawValue }

    var palette: ThemePalette {
        switch self {
        case .calmBlue:
            return ThemePalette(name: rawValue, tint: .blue, softTint: Color.blue.opacity(0.12), cardBackground: Color.blue.opacity(0.07))
        case .forestGreen:
            return ThemePalette(name: rawValue, tint: .green, softTint: Color.green.opacity(0.12), cardBackground: Color.green.opacity(0.07))
        case .plum:
            return ThemePalette(name: rawValue, tint: .purple, softTint: Color.purple.opacity(0.12), cardBackground: Color.purple.opacity(0.07))
        case .sunrise:
            return ThemePalette(name: rawValue, tint: .orange, softTint: Color.orange.opacity(0.12), cardBackground: Color.orange.opacity(0.07))
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var current: AppTheme {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: storageKey) }
    }

    private let storageKey = "visitpath.theme"

    init() {
        let saved = UserDefaults.standard.string(forKey: storageKey)
        self.current = AppTheme(rawValue: saved ?? "") ?? .calmBlue
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
            VStack(alignment: .leading, spacing: 4) {
                Text("VisitPath")
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        BrandHeaderView(subtitle: "Simple workplace visit tracking for teachers")
                        Text("Choose a color theme that feels comfortable and easy to read. The app keeps the layout simple so teachers can quickly find students, plan visits, and export records.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section("Appearance") {
                    Picker("Color theme", selection: $theme.current) {
                        ForEach(AppTheme.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    ForEach(AppTheme.allCases) { option in
                        Button {
                            theme.current = option
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(option.palette.tint)
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.rawValue)
                                        .foregroundStyle(.primary)
                                    Text(option == .calmBlue ? "Best default for most teachers" : "Easy-reading alternate theme")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if theme.current == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(option.palette.tint)
                                }
                            }
                        }
                    }
                }

                Section("Designed to be simple") {
                    Label("Home shows the current trip first", systemImage: "house")
                    Label("Students can be sorted and searched", systemImage: "person.2")
                    Label("Plan only adds in-person visits to the map", systemImage: "map")
                    Label("Exports and full reset stay in one place", systemImage: "square.and.arrow.up")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
