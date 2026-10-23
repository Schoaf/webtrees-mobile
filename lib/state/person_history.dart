import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';

/// The app's one person-page history (#31): every person page shows the
/// active person of this history, and undo/redo step through the persons
/// viewed before - however the page was reached. Browser-style: a new step
/// after undo discards the redo entries, and the same person twice in a row
/// is never a step.
class PersonHistory {
  const PersonHistory({required this.history, required this.pos});

  final List<String> history;
  final int pos;

  /// Null until a person page has been opened.
  String? get activeXref => history.isEmpty ? null : history[pos];
  bool get canUndo => pos > 0;
  bool get canRedo => pos < history.length - 1;
}

class PersonHistoryController extends Notifier<PersonHistory> {
  @override
  PersonHistory build() {
    // Another tree or server: start fresh.
    ref.watch(treeNameProvider);
    ref.watch(serverUrlProvider);
    return const PersonHistory(history: [], pos: 0);
  }

  /// [xref] comes into view - a new step unless it already is the active one.
  void show(String xref) {
    if (xref == state.activeXref) return;
    final history = state.history.isEmpty ? [xref] : (state.history.sublist(0, state.pos + 1)..add(xref));
    state = PersonHistory(history: history, pos: history.length - 1);
  }

  void undo() {
    if (state.canUndo) state = PersonHistory(history: state.history, pos: state.pos - 1);
  }

  void redo() {
    if (state.canRedo) state = PersonHistory(history: state.history, pos: state.pos + 1);
  }
}

final personHistoryProvider = NotifierProvider<PersonHistoryController, PersonHistory>(PersonHistoryController.new);
