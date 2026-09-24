import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/state/tree_view_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

Map<String, dynamic> _individualJson(String xref, {String name = 'Test Person'}) => {
  'ok': true,
  'person': {'xref': xref, 'name': name, 'sortName': 'Person,$name'},
  'facts': <dynamic>[],
  'parentFamilies': <dynamic>[],
  'spouseFamilies': <dynamic>[],
  'siblings': <dynamic>[],
  'extraChildrenByParent': {'father': 0, 'mother': 0},
};

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  // treeViewControllerProvider is autoDispose (screen-scoped by design) - a
  // bare container.read() has no listener, so the real app's ref.watch
  // (which keeps it alive for as long as the screen is mounted) has to be
  // simulated here with an explicit no-op listener, or the provider gets
  // disposed before the deferred _load() microtask runs.
  TreeViewController controllerFor(String xref) {
    container.listen(treeViewControllerProvider(xref), (_, _) {});
    return container.read(treeViewControllerProvider(xref).notifier);
  }

  test('build() starts loading and fetches the start person', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));

    final notifier = controllerFor('I1');
    expect(container.read(treeViewControllerProvider('I1')).loading, isTrue);
    expect(notifier.state.activeXref, 'I1');

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(treeViewControllerProvider('I1'));
    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.activeNeighborhood?.person.xref, 'I1');
  });

  test('selectPerson pushes history and fetches the new person once', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));

    final notifier = controllerFor('I1');
    await Future<void>.delayed(Duration.zero);

    await notifier.selectPerson('I2');

    expect(notifier.state.history, ['I1', 'I2']);
    expect(notifier.state.activeXref, 'I2');
    verify(() => client.individual('Famtree', 'I2')).called(1);
  });

  test('undo/redo move through history without re-fetching', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));

    final notifier = controllerFor('I1');
    await Future<void>.delayed(Duration.zero);
    await notifier.selectPerson('I2');

    notifier.undo();
    expect(notifier.state.activeXref, 'I1');
    expect(notifier.state.canUndo, isFalse);
    expect(notifier.state.canRedo, isTrue);

    notifier.redo();
    expect(notifier.state.activeXref, 'I2');

    // Only the two original fetches - undo/redo must not have re-fetched.
    verify(() => client.individual('Famtree', 'I1')).called(1);
    verify(() => client.individual('Famtree', 'I2')).called(1);
  });

  test('selecting a person after undo discards the redo entries', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));
    when(() => client.individual('Famtree', 'I3')).thenAnswer((_) async => _individualJson('I3'));

    final notifier = controllerFor('I1');
    await Future<void>.delayed(Duration.zero);
    await notifier.selectPerson('I2');
    notifier.undo();

    await notifier.selectPerson('I3');

    expect(notifier.state.history, ['I1', 'I3']);
    expect(notifier.state.canRedo, isFalse);
  });

  test('selectPartner updates selectedPartnerXref', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));

    final notifier = controllerFor('I1');
    await Future<void>.delayed(Duration.zero);

    notifier.selectPartner('I9');
    expect(notifier.state.selectedPartnerXref, 'I9');
  });

  test('a server error response is surfaced without crashing', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => {'ok': false, 'error': 'private'});

    controllerFor('I1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(treeViewControllerProvider('I1'));
    expect(state.loading, isFalse);
    expect(state.error, 'private');
  });

  test('a malformed response (TypeError during parsing) surfaces as an error, not an eternal spinner', () async {
    // person.xref missing -> TreeNode.fromJson's `json['xref'] as String`
    // throws a TypeError, not an Exception - regression test for a real
    // device bug where this hung on the loading spinner forever because
    // `on Exception` alone doesn't catch Error subtypes like TypeError.
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'ok': true,
        'person': {'name': 'No Xref'},
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': <dynamic>[],
        'siblings': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
      },
    );

    controllerFor('I1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(treeViewControllerProvider('I1'));
    expect(state.loading, isFalse);
    expect(state.error, isNotNull);
  });
}
