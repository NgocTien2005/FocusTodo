# FocusTodo

Flutter Android TODO assignment. Project name: `focus_todo`.

Deadline: **11 October 2026**.

## Scope and interpretation

The assignment says “console-based” but requires Flutter local notifications. We assume a simple Flutter Android mobile application. **Ask the instructor to clarify this assumption before implementing further features.** No terminal-style UI or separate CLI is planned.

The six requirements are dated/timed TODO creation, All/Today/Upcoming categories, category filtering, search, notifications ten minutes before due time, and completion removal from active lists. This task provides only the project foundation.

Implemented: immutable JSON-serializable model (including stable integer notification IDs and explicit nullable clearing), category selection state, Material 3 starter screen, honest Coming next messages, persistence and notification contracts, and starter/model tests. Remaining: TODO CRUD, actual category filtering/search, SharedPreferences persistence, permissions, timezone initialization, reminder scheduling/cancellation, and completion workflow. No sample data is persisted. Abstract service methods are intentionally unimplemented.

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
  controllers/todo_controller.dart category selection foundation
  repositories/todo_repository.dart persistence contract
  services/notification_service.dart notification contract
  screens/home_screen.dart        starter controls
  widgets/empty_state.dart        empty state
test/
  widget_test.dart                starter controls and disclosures
  todo_test.dart                  serialization and copyWith
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
flutter run -d <android-device-id>
```

Use `flutter devices` to substitute a real Android ID; do not select a Windows/browser target for this assignment. To connect a phone, enable Developer options and USB debugging, connect USB, approve the phone's debugging prompt, and install the OEM USB driver if needed. Alternatively create/start an Android emulator in Android Studio Device Manager.

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

Git **2.52.0.windows.1**, Android Studio **2025.2.3**, its OpenJDK **21.0.8**, SDK platforms **35/36**, build-tools **34.0.0/35.0.0/36.0.0/36.1.0**, and emulator **36.3.10.0** were detected. The default PATH Java remains **1.8.0_481**; Flutter uses Android Studio's JBR instead. Windows desktop and web toolchains are available but unrelated to this Android assignment; Xcode is unnecessary.

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

Checks actually run: `flutter --version`, `dart --version`, `flutter doctor -v`, `flutter devices`, `flutter emulators`, `flutter pub get`, `dart format lib test`, `flutter analyze`, and `flutter test`. Formatting succeeded, analysis found **no issues**, and **all six tests passed**. The tests exercise JSON round trips (including null dueAt/description), explicit nullable clearing, copyWith preservation, notification ID bounds, category selection, and unfinished-action disclosures.

**Android build and launch are pending; no APK build or device test has passed.** Doctor reports missing command-line tools and unknown license status. The pinned NDK is also absent. Devices lists Windows/Chrome/Edge only, and no usable AVD is configured.

Manual setup:

1. Android Studio → Tools → SDK Manager → SDK Tools: install **Android SDK Command-line Tools (latest)**. Under **NDK (Side by side)**, enable Show Package Details and select **28.2.13676358**. Review any installation/license prompts yourself.
2. Reopen PowerShell and run `flutter doctor --android-licenses`; read each license and decide whether to accept it. **This setup did not accept SDK licenses.** Then run `flutter doctor -v`.
3. Create/start an emulator in Device Manager, or connect/authorize a USB-debugging Android phone. Check `flutter devices`.
4. Run `flutter build apk --debug`, then `flutter run` from this workspace once one Android device is available.

The project uses the existing Git repository. Track `pubspec.lock` alongside application source.
