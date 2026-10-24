import 'package:flutter/material.dart';

import '../../widgets/start_person_builder.dart';
import 'person_detail_screen.dart';

/// The "Person" bottom-nav tab: the app's one person page, starting with
/// the start person (see startXrefProvider). Every person opened elsewhere
/// is shown here (openPerson).
class MyPersonScreen extends StatelessWidget {
  const MyPersonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StartPersonBuilder(builder: (xref) => PersonDetailScreen(xref: xref, isShowingOnlyWhenEmpty: true));
  }
}
