import 'package:flutter/foundation.dart';

enum TodoCategory { all, today, upcoming }

/// Starter state only. CRUD, persistence, filtering, and search are coming next.
class TodoController extends ChangeNotifier {
  TodoCategory _category = TodoCategory.all;
  TodoCategory get category => _category;

  void selectCategory(TodoCategory category) {
    if (_category == category) return;
    _category = category;
    notifyListeners();
  }
}
