import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/person_history.dart';
import '../../widgets/start_person_builder.dart';
import 'person_detail_screen.dart';

/// The "Person" bottom-nav tab: the app's one person page, starting with
/// the start person (see startXrefProvider). Every person opened elsewhere
/// is shown here (openPerson) - also when there is no start person.
class MyPersonScreen extends ConsumerWidget {
  const MyPersonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(personHistoryProvider.select((history) => history.activeXref));
    if (active != null) return PersonDetailScreen(xref: active, isShowingOnlyWhenEmpty: true);
    return StartPersonBuilder(builder: (xref) => PersonDetailScreen(xref: xref, isShowingOnlyWhenEmpty: true));
  }
}
