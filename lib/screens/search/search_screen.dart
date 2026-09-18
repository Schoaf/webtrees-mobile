import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import 'person_detail_screen.dart';

/// Priority-2 screen: find a person and review everything stored about
/// them. Charts are deliberately out of scope for v1 (hard to use on a
/// small screen) — this is a plain searchable list.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ref.read(webtreesClientProvider);
      final tree = ref.read(treeNameProvider);
      final response = await client.individuals(tree, query: query);
      setState(() {
        _results = response['data'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _error = 'Search failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryController,
          decoration: const InputDecoration(
            hintText: 'Search people…',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(_queryController.text),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) return const Center(child: Text('Search for a name above.'));

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final person = _results[index] as Map<String, dynamic>;
        return ListTile(
          title: Text(person['name'] as String? ?? '(no name)'),
          subtitle: Text(person['lifespan'] as String? ?? ''),
          onTap: () {
            final xref = person['xref'] as String;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: xref)),
            );
          },
        );
      },
    );
  }
}
