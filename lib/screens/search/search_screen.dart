import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/person_card.dart';
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
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
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
      if (!mounted) return;
      setState(() {
        _results = (response['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
        _searched = true;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Suche fehlgeschlagen: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(color: AppColors.surface, boxShadow: AppColors.cardShadow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Suche', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                const SizedBox(height: 14),
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 19, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          focusNode: _focusNode,
                          onChanged: _onChanged,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: 'Name eingeben…',
                          ),
                          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_searched) ...[
                  const SizedBox(height: 10),
                  Text('${_results.length} Treffer', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (!_searched) return const Center(child: Text('Suche nach einem Namen.', style: TextStyle(color: AppColors.textTertiary)));
    if (_results.isEmpty) return const Center(child: Text('Keine Treffer.', style: TextStyle(color: AppColors.textTertiary)));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final person = _results[index];
        return PersonCard(
          person: person,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: person['xref'] as String)),
          ),
        );
      },
    );
  }
}
