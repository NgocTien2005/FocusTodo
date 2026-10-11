# FocusTodo

Flutter Android TODO assignment. Project name: `focus_todo`.

## Scope and interpretation

This Flutter Android app implements the assignment's six requirements: dated TODO creation, All/Today/Upcoming categories, category filtering, search, reminders ten minutes before due time, and completion removal from active lists. Each requirement has automated coverage; actual Android interaction and timed reminder delivery remain separate device checks recorded below.

The app supports descriptions and undated TODOs, validates blank titles and past due times, and stores records locally in SharedPreferences. Completed TODOs stay in storage, disappear from active results, and have their reminder canceled. No sample data is created. Deletion is supported for individual TODOs with confirmation; completed history, cloud sync, and undo are outside this assignment scope.

Reminders require notification permission and exact-alarm access, requested from **Enable reminders**. A scheduling failure keeps the saved TODO and can be retried with the same ID. A cancellation failure keeps completion persisted and displays a retryable Home warning. TODOs due in less than ten minutes are saved without a late/immediate alert.

## Search

Home filters immediately as you type in Search TODOs. It matches literal substrings in titles or optional descriptions, ignoring case and leading/trailing query whitespace. Characters such as `.*` or `[` are treated as text, not regular expressions. An empty or whitespace-only query restores all active items in the selected category.

Search combines with All/Today/Upcoming, continues excluding completed TODOs, and preserves the existing repository order. It only changes controller state: no stored TODOs are modified and no storage writes are triggered. The entered text and query remain when switching categories or returning from the create screen, including after saving. A newly saved item appears only if it matches both the category and query. Query state stays in memory and starts empty after an app restart.

The clear button is visible whenever the field contains text, including whitespace, and clears both the field and query. Rebuilds retain text, cursor position, and focus; dragging the TODO list dismisses the keyboard. Empty states distinguish `No active TODOs.`, `No TODOs in this category.`, and `No matching TODOs in this category.` Loading, errors, and Retry take precedence over list results.

## Local storage

One JSON document is stored under `focus_todo.document`, with `schemaVersion: 1`, `todos`, `nextTodoId`, and `nextNotificationId`. It reuses Todo's UTC serialization. Missing data on first launch is empty; malformed data, unsupported versions, allocator collisions, rejected writes (`false`) and platform failures surface as errors. Unreadable data is preserved and creation is blocked until a load succeeds; Retry does not erase it.

Repository creation writes each `todo-N` ID, nonnegative int32 notification ID, and both monotonic allocator counters together. Counters survive restart independently of the current list, and exhausted notification IDs produce an error. A shared queue serializes read-modify-write operations across repository instances in the app isolate. `saveTodos` upserts into the latest document so concurrent snapshots do not drop unrelated additions; deletion uses an explicit operation. Background-isolate writers are outside this feature's scope. Controller state changes only after a successful write.

## Domain rules for the feature task

- All: all incomplete TODOs, including overdue and undated items.
- Today: incomplete TODOs due today in the device's local timezone.
- Upcoming: incomplete TODOs due on a calendar date after today.
- Include midnight correctly. Compare local calendar components or use local calendar midnight boundaries; never assume a day is a fixed 24-hour duration.
- Search combines with the selected category and ignores case and surrounding whitespace.
- Completion hides a TODO from active lists and cancels its reminder after persistence.
- A TODO without a due time has no reminder.
Active TODOs can also be edited. The form trims titles and descriptions, allows clearing description and due time, and permits title/description edits to overdue TODOs when their due time is unchanged. Updates preserve stable IDs, creation/completion state, unrelated records, and allocator counters. Reminder changes follow persistence, reuse the same notification ID, and provide retry for failures using the latest saved record. Editing preserves the current category and search query. Active TODOs can be deleted individually from Home after a confirmation that names the TODO. Deletion persists before reminder cancellation; storage failures retain the TODO, and cancellation failures remain visible with a retry action even after the TODO is removed. Home uses compact overflow actions for Edit/Delete, an accessible completion control, and distinct undated and overdue due-time chips. Category selection hides the selected checkmark, uses selected colors, and adapts to a dropdown on narrow screens or when text is enlarged. Search, forms, cards, and primary buttons follow consistent Material 3 spacing, typography, and rounded corners.

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
  controllers/todo_controller.dart load/create state, validation, clock, categories, search
  repositories/todo_repository.dart persistence contract
  repositories/shared_preferences_todo_repository.dart JSON storage and ID allocation
  services/notification_service.dart notification contract
  screens/home_screen.dart        startup states, search/category list and resume refresh
  screens/create_todo_screen.dart validated, scrollable create form
  widgets/empty_state.dart        empty state
test/
  widget_test.dart                search, creation, pickers, errors, keyboard and resume
  todo_test.dart                  serialization and copyWith
  todo_repository_test.dart       persistence, corruption, IDs, concurrent writes
  todo_controller_test.dart       search, state, validation, retry and calendar boundaries
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
flutter emulators
flutter run -d <online-android-device-id>
```

`Pixel_9` is the configured AVD. Confirm that it is online in `flutter devices` before using it. To connect a phone, enable Developer options and USB debugging, connect USB, and approve the phone's debugging prompt. On this machine `adb` is at `C:\Users\LENOVO\AppData\Local\Android\sdk\platform-tools\adb.exe` and is not on PATH. Flutter currently reports missing Android command-line tools and unknown Android license status; install those tools and review/accept licenses through Android Studio before relying on a local Android toolchain setup.

## Manual feature checks on Android

1. Tap Add TODO, enter a title and optional description, leave date/time empty, and save. Verify the item appears under All with an "Undated" status, but not Today or Upcoming.
2. Create a second TODO with today's date and a time still in the future. Verify it appears under All and Today, but not Upcoming. Choose tomorrow's date/time for a third TODO; it should appear under All and Upcoming.
3. On the create form, try a blank title, a date without a time, and a past time today. Each must remain on the form with an error. Clear due time to save the item as undated.
4. Close the app and launch it again (do not uninstall or clear app data). Verify the titles, descriptions and due times remain, and check all three categories again. A same-day overdue item remains in Today and All; a previous-day item remains in All only.
5. Leave the app in the background across local midnight, then resume it. Verify Today/Upcoming use the new calendar date. Rotate or use a small screen with the keyboard open; scroll to Save and verify the form remains usable.
6. Search using part of a title, then part of a description. Try mixed case and surrounding spaces; confirm the same results. Use a missing phrase to check the no-matching message. Try literal punctuation such as `.*` in a title/query.
7. With a query entered, switch All/Today/Upcoming. Confirm the text stays and each list satisfies both filters. Tap Clear search; confirm the field empties and only the selected category's items return. A whitespace-only query must also show the full category list.
8. Enter a query, open Add TODO and return without saving; confirm the text and category remain. Create a matching TODO and a nonmatching TODO; only the matching item should appear (if also in the category). Clear search to see both in All.
9. Focus search and drag a long TODO list; confirm the keyboard closes. Restart the app; confirm query text resets while saved TODOs remain.
10. Complete a TODO from All, Today, or Upcoming, then repeat with a search query active. Confirm it disappears after the save succeeds, category/query remain selected, the confirmation appears, and the correct empty state is shown when the last visible result is completed. Reject a write to confirm the item stays visible and retry works. Restart and confirm the completed record remains saved but hidden and its reminder is absent.
11. Enable reminders from Home. On Android 13+, allow notifications; when asked, grant Alarms & reminders exact-alarm access in Settings. Return to the app and verify the enabled status and that pending eligible TODOs are reconciled. Deny each permission separately, then retry after enabling it in system settings.
12. Create a TODO due 11–12 minutes from now. Verify the pending entry uses the persisted notification ID and TODO ID payload and is scheduled exactly at `dueAt - 10 minutes`. Background or dismiss the app from Recents (do not force-stop it) and observe delivery at that time. Create another eligible TODO, complete it before its reminder, and verify the reminder is canceled. Restart and verify persistence; if feasible, test reboot restoration. Do not shorten the production reminder interval.
13. On a normal-width phone, verify All/Today/Upcoming stay on one line and the selected segment is clear without a checkmark. On a narrow phone or with enlarged text, verify the adaptive category dropdown remains usable. Open a TODO action menu and check the compact Edit/Delete actions and distinct undated/overdue styling.

Storage-failure retention and corrupted-data recovery are covered by automated tests. Completion checks: complete one TODO in All, Today, and Upcoming and confirm it disappears; search for it and confirm the result disappears; complete the last visible result and confirm the appropriate empty state; reject a completion write and confirm the TODO remains and can be retried; tap the checkbox repeatedly while pending and confirm there is one write; restart the app and confirm the completed TODO remains stored and hidden. Verify that descriptions, due times, IDs, unrelated TODOs, and allocator counters remain unchanged. No destructive clear-data recovery action is built into the app. Clearing app data or uninstalling removes local preferences. Reminder delivery remains subject to device verification.

## Six-requirement status

| Requirement | Implemented | Automated evidence | Device verified |
| --- | --- | --- |
| Dated TODO creation | Yes; date/time validation and persistence | Widget, repository and validation tests | Not yet |
| All/Today/Upcoming categories | Yes; local calendar boundaries | Controller and lifecycle/widget tests | Not yet |
| Category filtering | Yes | Controller/widget tests, including combined search | Not yet |
| Search | Yes; combines with categories | Controller/widget tests | Not yet |
| Reminder ten minutes before due | Yes; exact Android alarm path, permissions and reconciliation | Service/controller/widget tests; does not prove OS delivery | Not yet |
| Completion removes active TODO | Yes; persists completion and cancels reminder with retry warning | Repository/controller/widget tests | Not yet |

## UI verification

On 10 October 2026, `dart format lib test`, `flutter analyze`, `flutter test` (102 tests), and `flutter build apk --debug` passed for the UI polish branch. Widget layout checks passed at 320 px width and enlarged text. The debug APK installed and launched on the **Pixel_9 emulator (Android 17 / API 37, sdk gphone16k x86_64)**. The Home screen screenshot at [docs/screenshots/ui-polish-pixel9.png](docs/screenshots/ui-polish-pixel9.png) shows All/Today/Upcoming on one line with a clearly selected segment and no checkmark. No TODO test data was created, and no physical-device verification was performed.

## Notifications and platform limitations

`LocalNotificationService` initializes the timezone database and uses the IANA device timezone from `flutter_timezone`; it preserves the stored UTC instant when converting to `TZDateTime`. It schedules one exact, idle-allowed Android alarm at `dueAt - 10 minutes`, using the TODO's stable `notificationId` and TODO ID payload. Completed and undated TODOs are not scheduled; reminders whose trigger time is now or past are skipped. The dedicated `focus_todo_reminders` channel uses high importance, the default notification sound and a drawable status icon.

Home offers **Enable reminders**. Android 13+ notification permission and Android exact-alarm special access are requested from that explicit action. The app uses `SCHEDULE_EXACT_ALARM`; it never falls back to approximate scheduling or claims success without exact-alarm permission. Permission status is rechecked when returning from Settings and on app resume. Denied permissions do not block TODO creation/completion. Startup and resume reconciliation remove stale pending reminders and schedule missing eligible reminders; a storage load failure never triggers an empty-list reconciliation. Scheduling after a successful save can fail independently and is retryable using the same ID. Completion is persisted before cancellation; a failed cancellation remains visible on Home with a retry action. The manifest declares the scheduled and boot receivers, `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, and `SCHEDULE_EXACT_ALARM`; Gradle uses desugaring 2.1.4 and SDK compatibility for the resolved plugin.

The plugin's reboot receiver restores scheduled alarms after device reboot. Dismissing the app task from Recents is different from using Android **Force stop** in App info/Settings or `adb shell am force-stop`: the manual delivery check should background/dismiss the task but must not force-stop the app. OEM battery policies and exact-alarm permission revocation can still affect delivery. A mock, pending-notification row, or APK build does not establish actual delivery.

Official references: [flutter_local_notifications 22.3.1 documentation](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1), [flutter_timezone API](https://pub.dev/documentation/flutter_timezone/latest/flutter_timezone/FlutterTimezone-class.html), [Android exact-alarm guidance](https://developer.android.com/develop/background-work/services/alarms), [Flutter Windows installation](https://docs.flutter.dev/install/manual), and [Android setup](https://docs.flutter.dev/platform-integration/android/setup).

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

Search verification on **8 October 2026**, on `feature/todo-search`: `dart format lib test` succeeded (15 files, 4 formatted); `flutter analyze` succeeded with **no issues**; `flutter test` succeeded with **all 52 tests passed**. Search tests cover title/nullable-description matching, case, surrounding whitespace, empty reset, no matches, literal punctuation, all categories, completed exclusion, retained query/order, unchanged storage, restart reset, field focus/cursor retention, clear, empty messages, create navigation, matching/nonmatching creation, and keyboard dismissal on list drag. Existing creation, persistence, validation, error/retry, serialization, stable ID, local calendar boundary, and lifecycle assertions remain covered.

**`flutter build apk --debug` passed** and produced `build/app/outputs/flutter-apk/app-debug.apk` (`assembleDebug`: 36.8 seconds). The pinned NDK **28.2.13676358** and Gradle distribution are installed. PR #1's `flutter doctor -v` reported missing Android command-line tools and unknown license status; doctor/license checks were not rerun for search. SDK lock/cache access outside the workspace required running Flutter/Dart verification outside the restricted filesystem sandbox.

**Android search verification was blocked.** The Pixel_9 AVD reported `emulator-5554 offline`; it was not wiped. A later Android launch attempt and the current device limitation are recorded below.

Completion verification on **9 October 2026**, on `feature/todo-completion`: `dart format lib test` succeeded; `flutter analyze` succeeded with **no issues**; `flutter test` succeeded with **all 59 tests passed**. Added coverage verifies persistent/idempotent completion, preservation of fields, unrelated records and allocator counters, unknown IDs, rejected writes, controller recreation, duplicate completion, concurrent create/completion, retry after failure, filtering through All/Today/Upcoming and search, pending UI, last-item empty state and success/error feedback. **`flutter build apk --debug` passed** and produced `build/app/outputs/flutter-apk/app-debug.apk` (`assembleDebug`: 40.1 seconds). Android launch was attempted by starting `Pixel_9`; `adb` then reported `emulator-5554 offline`, and Flutter continued to list only Windows/Chrome/Edge. No device launch or device test is claimed. The project shell did not have `adb` on PATH; direct invocation from the configured SDK confirmed the offline status.

Reminder verification on **9 October 2026**, on `feature/todo-reminders`: `dart format lib test` succeeded; `flutter analyze` completed with **no issues**; `flutter test` passed **all 72 tests**; `flutter build apk --debug` succeeded and produced `build/app/outputs/flutter-apk/app-debug.apk`. Tests cover the reminder instant/UTC conversion, eligibility, permissions and initialization errors, partial scheduling and retry, stable IDs, completion cancellation/retry, reconciliation, load failures and scheduling/completion races. These automated checks do not verify Android alarm delivery.

**Android reminder delivery remains unverified.** On **9 October 2026**, `flutter doctor -v` and `flutter devices` identified phone model **2406APNFAG**, Android **16 / API 36**, serial `GERW7DMFTGW4FATC`, as online. The foreground was `com.facebook.orca`'s `InCallActivity` (Messenger call); no app install, launch, UI interaction, or notification test was done during that call. Pixel_9 appeared as `emulator-5554 offline`. A normal launch failed because an emulator process already held the AVD; a direct non-destructive cold boot with `-no-snapshot-load` also failed with “Running multiple emulators with the same AVD”. The emulator was not wiped or terminated. No app data was cleared. No permission flow, six-requirement device check, 11–12 minute delivery, cancellation alert observation, restart persistence, or reboot restoration is claimed. Dismissing from Recents is not Force stop; do not force-stop when observing delivery.

Final verification on `fix/android-final-verification`, **9 October 2026**: `dart format lib test` succeeded; `flutter analyze` found no issues; `flutter test` passed **78 tests** after targeted regressions were added; `flutter build apk --debug` succeeded at `build/app/outputs/flutter-apk/app-debug.apk`. Confirmed fixes recheck reminder eligibility immediately before platform scheduling, cancel stale alarms when the controller receives `noAdvanceNotice`, prevent reconciliation until storage has loaded successfully, and clear cancellation warnings once reconciliation confirms an alarm is absent. Tests also cover initialization errors separately from storage load errors and permission reconciliation on resume. The exact expected/observed reminder times are **not available** because no eligible TODO was created on a device and no OS notification was observed.

Manual setup:

1. Android Studio → Tools → SDK Manager → SDK Tools: install **Android SDK Command-line Tools (latest)** so doctor can inspect licenses. The required NDK is already present. Review any installation/license prompts yourself.
2. Reopen PowerShell and run `flutter doctor --android-licenses`; read each license and decide whether to accept it. **This setup did not accept SDK licenses.** Then run `flutter doctor -v`.
3. Start **Pixel_9** with `flutter emulators --launch Pixel_9` or Device Manager, or connect/authorize a USB-debugging Android phone. Check `flutter devices`.
4. Run `flutter build apk --debug`, then `flutter run` from this workspace once one Android device is available.

For the remaining device checks, first make the Android 16 phone available without an active call. Install the APK with `adb install -r` (no `pm clear`, uninstall, or data reset), launch FocusTodo, and use uniquely named TODOs such as `VERIFY-UNDATED`, `VERIFY-TODAY`, `VERIFY-UPCOMING`, and `VERIFY-CANCEL`. Follow the 12-step checklist above. Record the phone's displayed timezone, TODO due time, persisted notification ID, expected `dueAt - 10 minutes` trigger, and observed notification time. Remove test TODOs only through the app if a supported removal operation becomes available; this version has no delete flow, so test records may remain in app storage. Record exactly which titles remain.

The project uses the existing Git repository. Track `pubspec.lock` alongside application source.
