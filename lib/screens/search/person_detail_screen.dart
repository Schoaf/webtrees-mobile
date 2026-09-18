import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';

/// Full "review everything we know" view for one person — priority-2 in the
/// project plan. Every fact the API returns, in one scrollable list.
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.xref});

  final String xref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(webtreesClientProvider);
    final tree = ref.watch(treeNameProvider);

    return Scaffold(
      appBar: AppBar(title: Text(xref)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: client.individual(tree, xref),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          final person = data['person'] as Map<String, dynamic>;
          final facts = data['facts'] as List<dynamic>? ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(person['name'] as String? ?? '(no name)', style: Theme.of(context).textTheme.headlineSmall),
              Text(person['lifespan'] as String? ?? '', style: Theme.of(context).textTheme.bodyMedium),
              const Divider(height: 32),
              for (final fact in facts) _FactTile(fact: fact as Map<String, dynamic>),
            ],
          );
        },
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact});

  final Map<String, dynamic> fact;

  @override
  Widget build(BuildContext context) {
    final date = fact['date'] as Map<String, dynamic>?;
    final place = fact['place'] as Map<String, dynamic>?;
    final subtitleParts = [
      if (fact['value'] != null && (fact['value'] as String).isNotEmpty) fact['value'] as String,
      if (date != null) date['text'] as String,
      if (place != null) place['short'] as String,
    ];

    return ListTile(
      title: Text(fact['label'] as String? ?? fact['tag'] as String),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
    );
  }
}
