# VisitPath — iOS app (teacher-friendly theme update)

A native **SwiftUI + MapKit + CoreLocation** iPhone application for work-based learning teachers, branded as **VisitPath**. This is the complete source project based on the user's existing WBL-app repository, not an already-signed IPA. It preserves the supplied `project.yml`, `builder.json`, and `.github/workflows` layout for XcodeGen / GitHub IPA builds.

## What's new in this release

- **All-time visit tracking:** Visits are no longer reset on a monthly boundary. The old destructive "Start new month" action is gone. All records stay until the user explicitly selects **Data → Delete all app data** (or deletes the app from the phone without preserving the data).
- **Visit count on each student:** Student rows show the number of recorded visits/contacts rather than a visited/not-visited icon.
- **Student visit timeline:** Tap any student to see every recorded visit, with full date/time and its kind. You can also manually log a contact and export just that student's visits to CSV.
- **Visit kinds:** Choose **In person**, **Zoom**, **Phone call**, or **Message** for *each selected student* when planning a session. Completing that stop records the kind and exact completion timestamp. The manual visit form can backdate a contact.
- **Only in-person stops on map:** Route optimization and the Google Maps / Apple Maps navigation links include only In person stops. Remote contacts remain on the active-session checklist, but are never route waypoints. For remote-only sessions, the app does not require GPS or create mileage.
- **More student sorting:** Last name, first name, employer, grade, graduation year, most visits, fewest visits, or most recently visited. You can filter to unvisited or previously visited students.
- **Date-range exports:** **Data → Export individual reports** provides independent mileage, visit, and student CSV exports. Toggle **Choose a date range** to select arbitrary inclusive start and end dates (spanning any number of months/years). Mileage is filtered by *planned trip date*; visits are filtered by the *actual logged timestamp*. Date filters do not affect student-roster export.
- **Complete export:** A ZIP backup still includes all students, every visit, notes, trips, individual trip stops, mileage CSV, and the full JSON snapshot without a date restriction.

## Screens

| Screen | What it does |
|---|---|
| Home | Shows active trip/session; mark students visited/contacted and save actual mileage for any in-person stops |
| Students | Import roster, view visit counts, search, sort, filter; tap student for full visit timeline and notes |
| Plan | Select students, set a visit type for each, pick a date, optionally optimize the in-person route and start session |
| Mileage | Review completed travel and remote contact sessions; correct reimbursement miles after driving |
| Data | Export mileage, visits, roster for selected dates; full ZIP backup; optional permanent full reset |

## Import spreadsheets

Students → Import accepts actual `.xlsx` workbooks, `.csv`, `.tsv` files and CSV pasted text. Google Sheets files should first be downloaded as Microsoft Excel (`.xlsx`) or CSV. Spreadsheet columns:

```
First Name,Last Name,Graduation Year,Grade,Employer Name,Employer Address,Phone Number
Jamie,Lee,2028,11,Example Workshop,"100 Main St, Columbus, GA",555-0100
```

First worksheet is used for `.xlsx`; `.xls` and direct Google Sheets URL imports are not supported. Review the preview and student count before accepting an import. **Replacing a roster** is still destructive to roster records; export your data first.

## Existing-data compatibility

Saved data is read from the same `wbl-visits.json` document in the app's local Documents directory. The new app decodes legacy `Student.visits: [Date]` entries and converts them into typed visit history **without changing their original timestamps**. Because the old version did not record a visit kind, migrated visits are marked **In person**. Preexisting trips with no explicit stop type also default to In person.

**Important:** Visits/trips that were already cleared using the older monthly reset cannot be recovered by this new build. The new version simply prevents future monthly wipes. Updating with the *same bundle identifier* generally preserves existing app data; uninstalling or using a new bundle identifier may not.

## IPA build

1. Extract the ZIP and upload the *contents* of `WBL-app-main/` to the root of your existing GitHub WBL repository.
2. In `builder.json`, confirm that `github.owner` and `github.repo` match your account/repository, if your builder uses those fields.
3. Run the existing iOS workflow with scheme **WBLTracker**. The XcodeGen project uses iOS 17.2+ and Swift 5.
4. The GitHub Actions workflow can produce an **unsigned IPA**. For installation on a real iPhone, use appropriate Apple signing and provisioning with the permitted device.
5. On a Mac with Xcode, run `xcodegen generate`, then build/open `WBLTracker.xcodeproj`.

The app uses `ZIPFoundation` from Swift Package Manager for spreadsheets/export. A network connection is needed when Apple MapKit geocodes or estimates driving routes; remote-only sessions work without route requests.

## Limitations and privacy

- Mileage is **estimated using MapKit road distances**, not tracked by GPS. Enter/edit actual reimbursement miles after a trip.
- Optimization uses a geographical nearest-neighbor / 2-opt heuristic rather than live-traffic global optimization.
- Google Maps can open a multi-stop route, subject to its waypoint limits. Apple Maps' URL opens the **first** in-person leg, not a multi-stop tour.
- Student notes, phone numbers, employer locations and visit histories are stored locally on the iPhone. There is no cloud sync, login, or server-side access control. Store exports securely and use only with school/district approval and appropriate student-data privacy safeguards.
- Full reset is irreversible without an external backup. Export archives before reinstalling or switching devices.
- Source checks were run with the Linux Swift frontend and a data-model migration test. A full native Xcode/iOS SDK build and device runtime test **have not** been performed in this environment.

## VisitPath app icon and branding

- The supplied logo is included as `WBLTracker/Assets.xcassets/VisitPathLogo.imageset`.
- The app's home-screen icon is a 1024 × 1024 opaque PNG in `WBLTracker/Assets.xcassets/AppIcon.appiconset`.
- The XcodeGen project explicitly specifies `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
- The iPhone display name is **VisitPath**. The existing build target/scheme remains **WBLTracker** for GitHub builder compatibility.
- The bundle identifier remains **com.buildertest.wbltracker**, matching the old app so an update is more likely to retain locally stored student data. Do not change this without considering data migration and signing.
- Color themes are selectable in **Settings**. Your choice is saved on the device.

### Build troubleshooting

Run `xcodegen generate` to regenerate `VisitPath.xcodeproj`, then build the **WBLTracker** scheme.
The warning about `ZIPFoundation.Archive.init` being deprecated is not a build-blocking error.
