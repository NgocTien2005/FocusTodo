# FocusTodo guidance

- Follow the six assignment requirements: dated TODO creation, All/Today/Upcoming categories, category filtering, search, reminders 10 minutes before due time, and completion removal from active lists.
- Keep changes scoped to the requested task. This foundation does not implement the full app.
- Separate UI, state, persistence, and notification responsibilities.
- Use asynchronous operations and surface errors to the user.
- Never use Timer as the mechanism for background TODO reminders.
- Verify local calendar date boundaries, serialization, stable notification IDs, and cancellation on completion/edit/delete.
- Run dart format, flutter analyze, and relevant flutter tests.
- Never claim a device test passed unless it actually ran.
