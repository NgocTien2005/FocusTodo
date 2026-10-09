# FocusTodo submission checklist

## Six requirements and evidence

| Requirement | Implementation | Automated evidence | Android device evidence |
| --- | --- | --- | --- |
| Dated TODO creation | `lib/screens/create_todo_screen.dart`, `lib/controllers/todo_controller.dart`, `lib/repositories/shared_preferences_todo_repository.dart` | `test/widget_test.dart`, `test/todo_repository_test.dart` validate dates, persistence, blank title, incomplete/past time | Pending. Create dated and undated records; verify validation and restart persistence. |
| All/Today/Upcoming categories | `lib/controllers/todo_controller.dart` uses local calendar dates | `test/todo_controller_test.dart`, `test/widget_test.dart` cover membership and date rollover | Pending. Compare same-day and future-day records in each category. |
| Category filtering | `lib/controllers/todo_controller.dart` | Controller/widget tests cover category selection and category plus query | Pending. Switch categories with and without a query. |
| Search | `lib/controllers/todo_controller.dart`, `lib/screens/home_screen.dart` | Controller/widget tests cover title/description, casing, whitespace, literal text, empty states and retained query | Pending. Search title and description on Android and combine with categories. |
| Reminder ten minutes before due | `lib/services/local_notification_service.dart`, `lib/services/notification_service.dart`, `lib/controllers/todo_controller.dart`; Android manifest and drawable icon | `test/notification_service_test.dart`, `test/todo_controller_test.dart`, `test/widget_test.dart` cover UTC instant, eligibility, permissions, retries, reconciliation and races | **Unverified.** Actual scheduled delivery must be observed on Android; a fake, pending row, or APK is not delivery evidence. |
| Completion removes active TODO | `lib/controllers/todo_controller.dart`, Home completion control | Repository/controller/widget tests cover durable completion, filters, cancellation and retry | Pending. Complete a TODO in each relevant result context and verify it stays completed after restart. |

Automated verification on 9 October 2026: formatting succeeded, `flutter analyze` reported no issues, all **78 tests passed**, and `flutter build apk --debug` succeeded. These results do not establish Android UI or notification delivery behavior.

## Demo sequence

1. Start the app with existing app data intact. Create `VERIFY-UNDATED`, `VERIFY-TODAY`, and `VERIFY-UPCOMING`; verify the dated form rejects a blank title and past time.
2. Check All/Today/Upcoming. Search a title substring and a description substring, then combine each query with category filters.
3. Close and reopen the app normally. Verify all three TODOs remain. Complete a visible TODO and confirm it disappears while the other records remain.
4. Tap **Enable reminders** and grant notification and exact-alarm permissions through Android's normal prompts/settings flow.
5. Create `VERIFY-DELIVERY` due about 12 minutes from the current time. Record timezone, due time, persisted notification ID, expected trigger (`dueAt - 10 minutes`) and actual displayed notification time. Background or dismiss from Recents; do not Force stop.
6. Create `VERIFY-CANCEL` with an eligible reminder, complete it before its trigger, confirm it is no longer pending, and observe that no alert appears at its former trigger time.
7. If possible, deny each reminder permission once, restore it in Settings, return to the app, and verify status/reconciliation. If feasible, restart the device and verify plugin reboot restoration.
8. Record the exact test titles left in local storage. This app has no delete operation; do not clear app data just to clean the demo.

## Device evidence and blockers

On 9 October 2026, Flutter detected phone model **2406APNFAG**, Android **16 / API 36**, serial `GERW7DMFTGW4FATC`. Its foreground was a Messenger `InCallActivity`, so the app was not opened or interacted with. The Pixel_9 AVD was `emulator-5554 offline`. A non-destructive cold boot attempt failed because an emulator already held the same AVD. No app data was cleared or emulator wiped. No device UI, permission, restart, reboot, reminder delivery, or cancellation observation has been recorded.

Before claiming full verification, use the phone only after its current user has made it available without an active call. The Android SDK currently lacks command-line tools and has unknown license status (`flutter doctor -v`); resolve these setup items if needed. The APK output is `build/app/outputs/flutter-apk/app-debug.apk`.

## Evidence and history

Inspect repository history with:

```powershell
git log --oneline --decorate --graph -20
git log --oneline -- README.md docs/submission-checklist.md
git status --short --branch
```

Include the **real agent-session history/transcript** required by the submission process. Obtain it from the actual session export or platform history; do not fabricate, reconstruct, or present this checklist as a transcript.
