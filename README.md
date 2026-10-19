# WBL Visits — native iPhone app

Built with **SwiftUI + MapKit + CoreLocation**, XcodeGen, and the same `builder.json` / GitHub IPA build workflow style as the supplied Chessphone app. All student, notes, and trip data is stored locally in the phone's Documents directory as `wbl-visits.json`. No login, cloud database, analytics, or external student-data transmission is implemented. Route locations/addresses are provided to Apple Maps for directions and to Google Maps when the teacher chooses its external route link.

## Screens
- **Home:** active trip automatically shown on app launch; `I Have Visited` immediately stamps date and time and updates student status.
- **Students:** full list, visited status, search, add/edit, CSV import by file or pasted text, visit history, dated editable notes.
- **Plan:** date, student selection, GPS or manual origin, round-trip toggle, optimized stop order (nearest neighbor plus 2-opt) and Apple MapKit road-distance calculation.
- **Mileage:** completed trips, estimated and editable actual reimbursement miles, total, shareable CSV.

## Import CSV
Header row (headerless files in this order also work):
```
First Name,Last Name,Graduation Year,Grade,Employer Name,Employer Address,Phone Number
Jamie,Lee,2028,11,Example Workshop,"100 Main St, Columbus, GA",555-0100
```
For text input, paste comma-separated CSV rows. Quoted commas and escaped double-quotes are handled.

## IPA creation
1. Create a **new GitHub repository**, upload the contents of this ZIP to its root, and ensure the default branch is `main`. Avoid overwriting the chess app repository.
2. If your third-party builder expects a repository identity, edit `builder.json` `github.owner` and `github.repo` to point to the new repo.
3. Run your builder's iOS build exactly as for Chessphone, with scheme **WBLTracker**. Alternatively, on GitHub: Actions → Build iOS IPA → Run workflow.
4. The GitHub workflow produces an **unsigned IPA** under the `WBLTracker-unsigned-ipa` artifact. For a device-installable IPA, configure your builder or Xcode with an Apple signing certificate and provisioning profile (and permitted device ID for development/ad hoc builds).
5. On a Mac with Xcode, `brew install xcodegen`, `xcodegen generate`, then open `WBLTracker.xcodeproj` to run on device or simulator.

## Important behavior and limitations
- **Mileage:** MapKit computes driving distance for each leg of the planned route at planning time. This is an estimate, not actual GPS odometer mileage. Teacher can enter or correct actual total miles on completion; mileage export uses saved miles.
- **Optimization:** geographic nearest-neighbor with 2-opt improvement; not guaranteed globally optimal or traffic-aware. Calculation requires network connectivity.
- **External maps:** Google Maps URL supports the full ordered route and return-to-origin; waypoint limits may vary by Google Maps platform and browser. Apple Maps public URL opens the **first leg**, not the multi-stop route.
- **GPS:** on-demand when planning; no background tracking. Denial can be bypassed by entering an origin address.
- **Data privacy:** this prototype has no authentication, encryption-at-rest beyond device protections, remote sync, or school-managed access controls. Only import real student information on an appropriately managed device and after school/district approval. Back up/export data before deleting the app: uninstalling may erase its data.
- **Build verification:** generated on a Linux runner where iOS SDK/Xcode is unavailable; run an Xcode build on macOS to validate before deployment.

## Updated: spreadsheet import, complete export, and resets

- **Students → Import**: Select an actual `.xlsx` workbook (including a Google Sheets export), `.csv`, `.tsv`, or `.txt` file in the iOS Files picker. The first worksheet of an Excel workbook is used. Review the first 15 students and total count before tapping Import. Headers should be: First Name, Last Name, Graduation Year, Grade, Employer Name, Employer Address, Phone Number. You can also paste CSV text.
- **Data → Prepare complete export**: Creates a single shareable ZIP containing `students.csv`, `visits.csv`, `notes.csv`, `trips.csv`, `trip_stops.csv`, and `full_backup.json`. CSV files can be opened in spreadsheet programs; JSON is a complete archival snapshot. The export can be saved to iCloud Drive or shared using the iOS share sheet.
- **Data → Start new month**: Keeps students, employers, addresses, phones and student notes, but clears visit flags/history, all trips and mileage. **Export first** to preserve prior months.
- **Data → Delete all app data**: Deletes all local student, visit, notes and trip data after a confirmation prompt. **Export first**.
- `ZIPFoundation` is an SPM dependency and will be fetched automatically by XcodeGen/Xcode on your cloud Mac build. The `.xlsx` importer handles Excel OpenXML shared strings, inline strings, and the first worksheet; legacy `.xls` is unsupported. Export to `.xlsx` or `.csv` from Google Sheets instead of providing a Google Sheets web link.

Privacy: Student information and notes are stored locally in the app's Documents directory. Do not put real student data in public GitHub repositories. Store exported archives securely and comply with school student-record policies.
