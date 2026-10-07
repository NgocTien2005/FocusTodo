import 'dart:async';

import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';

class MemoryDocumentStore implements TodoDocumentStore {
  String? document;
  bool failRead = false;
  bool rejectWrite = false;
  bool throwOnWrite = false;
  int writes = 0;
  Completer<void>? readGate;
  Completer<void>? writeGate;

  @override
  Future<String?> read() async {
    await readGate?.future;
    if (failRead) throw StateError('Platform read failed');
    return document;
  }

  @override
  Future<bool> write(String value) async {
    writes++;
    await writeGate?.future;
    if (throwOnWrite) throw StateError('Platform write failed');
    if (rejectWrite) return false;
    document = value;
    return true;
  }
}
