# FocusTodo

Flutter Android TODO assignment. Project name: `focus_todo`.

Deadline: **11 October 2026**.

## Scope and interpretation

The assignment says “console-based” but requires Flutter local notifications. We assume a simple Flutter Android mobile application. **Ask the instructor to clarify this assumption before implementing further features.** No terminal-style UI or separate CLI is planned.

The six requirements are dated/timed TODO creation, All/Today/Upcoming categories, category filtering, search, notifications ten minutes before due time, and completion removal from active lists. This feature adds TODO creation and local persistence to the reviewed foundation.

Implemented: validated TODO creation with an optional description and local date/time pickers; clearing the due time; SharedPreferences persistence and startup loading/retry; stable TODO/notification IDs; All/Today/Upcoming filtering; local due-time display; completed-item exclusion; and loading/error/empty/list states. The scrollable form rejects blank titles, incomplete date/time selections and past due times, disables Save during a write, retains input on storage failure, and closes only after persistence succeeds. Categories refresh when the app resumes.

Pending: search, edit/delete/completion actions, notification permissions, scheduling/cancellation, and scheduling timezone initialization. Search and reminders are explicitly marked as coming next. NotificationService remains an abstract contract and is never invoked by this feature. No sample data is created by the app.

## Local storage

One JSON document is stored under `focus_todo.document`, with `schemaVersion: 1`, `todos`, `nextTodoId`, and `nextNotificationId`. It reuses Todo's UTC serialization. Missing data on first launch is empty; malformed data, unsupported versions, allocator collisions, rejected writes (`false`) and platform failures surface as errors. Unreadable data is preserved and creation is blocked until a load succeeds; Retry does not erase it.

Repository creation writes each `todo-N` ID, nonnegative int32 notification ID, and both monotonic allocator counters together. Counters survive restart independently of the current list, and exhausted notification IDs produce an error. A shared queue serializes read-modify-write operations across repository instances in the app isolate. `saveTodos` upserts into the latest document so concurrent snapshots do not drop unrelated additions; future deletion requires an explicit operation. Background-isolate writers are outside this feature's scope. Controller state changes only after a successful write.

## Domain rules for the feature task

- All: all incomplete TODOs, including overdue and undated items.
- Today: incomplete TODOs due today in the device's local timezone.
- Upcoming: incomplete TODOs due on a calendar date after today.
- Include midnight correctly. Compare local calendar components or use local calendar midnight boundaries; never assume a day is a fixed 24-hour duration.
- Search combines with the selected category and ignores case and surrounding whitespace.
- Completion hides a TODO from active lists and cancels its reminder.
- A TODO without a due time has no reminder.
- Reminder time is `dueAt` minus ten minutes. If it has already passed, disclose that a full ten-minute advance reminder is unavailable; never schedule into the past.
- Editing or deleting a TODO must update or cancel its reminder.
- Persist each nonnegative int32 `notificationId`, keep it stable, and allocate IDs without collisions, including after restart. Do not use `String.hashCode` as an allocator.
- Obtain the device timezone with `flutter_timezone`; do not hardcode `Asia/Ho_Chi_Minh`. Initialize `timezone` before scheduling.
- JSON stores date/time instants in UTC. Convert to local time for category boundaries and display. Revisit timezone changes and daylight saving transitions during device testing.

## Structure

```text
lib/
  main.dart                       entry point
  app.dart                        theme and Provider wiring
  models/todo.dart                immutable model and JSON
  controllers/todo_controller.dart load/create state, validation, clock, categories
  repositories/todo_repository.dart persistence contract
  repositories/shared_preferences_todo_repository.dart JSON storage and ID allocation
  services/notification_service.dart notification contract
  screens/home_screen.dart        startup states, category list and resume refresh
  screens/create_todo_screen.dart validated, scrollable create form
  widgets/empty_state.dart        empty state
test/
  widget_test.dart                creation, pickers, errors, keyboard and resume
  todo_test.dart                  serialization and copyWith
  todo_repository_test.dart       persistence, corruption, IDs, concurrent writes
  todo_controller_test.dart       state, validation, retry and calendar boundaries
  support/memory_document_store.dart controllable storage failures for tests
```

## Windows PowerShell workflow

From this workspace, after Flutter is installed and available on PATH:

```powershell
# Reopen PowerShell after the PATH update, or use this in the current session:
$env:Path = 'C:\src\flutter\bin;' + $env:Path
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter emulators --launch Pixel_9
flutter run -d emulator-5554
```

`Pixel_9` is the currently configured AVD. Wait for it to boot and confirm its ID with `flutter devices`; substitute that ID if it differs from `emulator-5554`. Do not select a Windows/browser target for this assignment. To connect a phone, enable Developer options and USB debugging, connect USB, approve the phone's debugging prompt, and install the OEM USB driver if needed.

## Manual feature checks on Android

1. Tap Add TODO, enter a title and optional description, leave date/time empty, and save. Verify the item appears under All with "No due date or time", but not Today or Upcoming.
2. Create a second TODO with today's date and a time still in the future. Verify it appears under All and Today, but not Upcoming. Choose tomorrow's date/time for a third TODO; it should appear under All and Upcoming.
3. On the create form, try a blank title, a date without a time, and a past time today. Each must remain on the form with an error. Clear due time to save the item as undated.
4. Close the app and launch it again (do not uninstall or clear app data). Verify the titles, descriptions and due times remain, and check all three categories again. A same-day overdue item remains in Today and All; a previous-day item remains in All only.
5. Leave the app in the background across local midnight, then resume it. Verify Today/Upcoming use the new calendar date. Rotate or use a small screen with the keyboard open; scroll to Save and verify the form remains usable.

Storage-failure retention and corrupted-data recovery are covered by automated tests. No destructive clear-data recovery action is built into the app. Clearing app data or uninstalling removes local preferences. Reminder delivery, editing, deletion and completion are not available yet.

## Notifications and platform limitations

Runtime permission requests and reminder scheduling are deferred to the feature task. Android 13+ requires notification permission; exact alarms require checking special access and asking the user where applicable. Use `SCHEDULE_EXACT_ALARM`, never `USE_EXACT_ALARM`, full-screen intents, or foreground services for this assignment. Denied permission must be surfaced. Reboot restoration needs the plugin receivers and `RECEIVE_BOOT_COMPLETED`.

Android OEM battery restrictions, force-stop behavior, permission revocation, and alarm limits can affect delivery. Test scheduling, reboot recovery, editing, deleting, and completion cancellation on an actual Android device. A debug APK or widget test alone does not establish notification delivery.

Official references: [Flutter Windows installation](https://docs.flutter.dev/install/manual), [Android setup](https://docs.flutter.dev/platform-integration/android/setup), and [notification plugin setup](https://pub.dev/packages/flutter_local_notifications).

## Environment and verification

Installed Flutter **3.47.6 stable** at `C:\src\flutter`, with **Dart 3.13.5**. The official Windows bundle SHA-256 was verified before extraction. Flutter was added to the user PATH without removing existing entries. The project was created **in this workspace** using:

```powershell
flutter create --platforms=android --project-name focus_todo .
flutter pub add provider shared_preferences flutter_local_notifications timezone flutter_timezone intl
flutter config --jdk-dir 'C:\Program Files\Android\Android Studio\jbr'
```

Git **2.52.0.windows.1**, Android Studio **2025.2.3**, its OpenJDK **21.0.8**, SDK platforms **35/36**, build-tools **34.0.0/35.0.0/36.0.0/36.1.0**, and emulator **37.2.12.0** were detected. The default PATH Java remains **1.8.0_481**; Flutter uses Android Studio's JBR instead. Windows desktop and web toolchains are available but unrelated to this Android assignment; Xcode is unnecessary.

| Package | Resolved version |
| --- | --- |
| provider | 6.1.5+1 |
| shared_preferences | 2.5.6 |
| flutter_local_notifications | 22.3.1 |
| timezone | 0.11.1 |
| flutter_timezone | 5.1.1 |
| intl | 0.20.3 |
| flutter_lints | 6.0.0 |
| flutter_test | Flutter SDK 3.47.6 |

`pubspec.lock` is included for reproducibility. Transitive newer-version notices from pub do not represent resolution failures. No backend, authentication, or code-generation dependencies were added.

Android uses the stable Flutter template: **AGP 9.1.0**, **Gradle 9.3.1**, **Kotlin 2.4.0**, Java/Kotlin target **17**, compile/target SDK **36**, minimum SDK **24**, and NDK **28.2.13676358**. The generated AGP compatibility flags are preserved. Desugaring **2.1.4**, multidex, scheduled/reboot receivers, and the three app permissions above were configured after reading the resolved plugin's official README. The plugin also supplies its standard vibration permission.

The foundation previously passed six tests. For this feature, `dart format lib test`, `flutter analyze --no-pub`, and `flutter test --no-pub` succeeded: **no analysis issues and all 33 tests passed**. Coverage includes dated/undated round trips, a fresh repository/controller loading saved data, malformed/unsupported data preservation, write/read failures, allocator persistence/exhaustion and historical ID reuse prevention, concurrent writes, validation, repeated submission, UTC-to-local calendar boundaries (midnight and overdue), creation on Home, input retention on failure, loading/retry, keyboard layout and resume refresh.

**`flutter build apk --debug --no-pub` passed** and produced `build/app/outputs/flutter-apk/app-debug.apk` (final incremental build: 10.1 seconds). The pinned NDK **28.2.13676358** and Gradle distribution are now installed. Rechecked `flutter doctor -v` still reports missing Android command-line tools and unknown license status; these warnings did not block the verified APK build with the currently installed SDK.

**Device verification remains pending.** An Android 17/API 37 emulator was visible at the initial check, but the subsequent APK installation attempt failed with `device 'emulator-5554' not found`. The final device check lists Windows/Chrome/Edge only; `flutter emulators` lists the configured **Pixel_9** AVD. No successful Android launch or manual persistence test is claimed.

Manual setup:

1. Android Studio → Tools → SDK Manager → SDK Tools: install **Android SDK Command-line Tools (latest)** so doctor can inspect licenses. The required NDK is already present. Review any installation/license prompts yourself.
2. Reopen PowerShell and run `flutter doctor --android-licenses`; read each license and decide whether to accept it. **This setup did not accept SDK licenses.** Then run `flutter doctor -v`.
3. Start **Pixel_9** with `flutter emulators --launch Pixel_9` or Device Manager, or connect/authorize a USB-debugging Android phone. Check `flutter devices`.
4. Run `flutter build apk --debug`, then `flutter run` from this workspace once one Android device is available.

The project uses the existing Git repository. Track `pubspec.lock` alongside application source.
