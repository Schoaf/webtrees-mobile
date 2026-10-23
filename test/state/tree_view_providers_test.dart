import 'package:flutter/services.dart';
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
  'stepFamilies': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.usePrettyUrls).thenReturn(false);
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  // The app's one tree history: entering with I1 is what a tree view does when it opens.
  Future<TreeViewController> controllerFor(String xref) async {
    final notifier = container.read(treeViewControllerProvider.notifier);
    await notifier.enter(xref);
    return notifier;
  }

  test('starts empty; entering loads the person', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    expect(container.read(treeViewControllerProvider).activeXref, isNull);

    await controllerFor('I1');

    final state = container.read(treeViewControllerProvider);
    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.activeNeighborhood?.person.xref, 'I1');
  });

  test('entering with the person already in focus adds no undo step (#31)', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));

    final notifier = await controllerFor('I1');
    await notifier.enter('I1');
    expect(notifier.state.history, ['I1']);

    await notifier.enter('I2');
    await notifier.enter('I2');
    expect(notifier.state.history, ['I1', 'I2']);
  });

  test('a tree opened for another person is a step - undo leads back (#29, #31)', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));
    when(() => client.individual('Famtree', 'I3')).thenAnswer((_) async => _individualJson('I3'));

    final notifier = await controllerFor('I1');
    await notifier.selectPerson('I2'); // browsing in the tree
    await notifier.enter('I3'); // tree button on another person's page
    expect(notifier.state.activeXref, 'I3');
    await notifier.enter('I1'); // tree button on person A again: shows A, not B
    expect(notifier.state.activeXref, 'I1');
    notifier.undo();
    expect(notifier.state.activeXref, 'I3');
  });

  test('switching to another tree starts a fresh history', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    final notifier = await controllerFor('I1');
    expect(notifier.state.history, ['I1']);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    await container.read(treeNameProvider.notifier).set('Other');
    expect(container.read(treeViewControllerProvider).history, isEmpty);
  });

  test('selectPerson pushes history and fetches the new person once', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));

    final notifier = await controllerFor('I1');

    await notifier.selectPerson('I2');

    expect(notifier.state.history, ['I1', 'I2']);
    expect(notifier.state.activeXref, 'I2');
    verify(() => client.individual('Famtree', 'I2')).called(1);
  });

  test('undo/redo move through history without re-fetching', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _individualJson('I2'));

    final notifier = await controllerFor('I1');
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

    final notifier = await controllerFor('I1');
    await notifier.selectPerson('I2');
    notifier.undo();

    await notifier.selectPerson('I3');

    expect(notifier.state.history, ['I1', 'I3']);
    expect(notifier.state.canRedo, isFalse);
  });

  test('selectPartner updates selectedPartnerXref', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _individualJson('I1'));

    final notifier = await controllerFor('I1');

    notifier.selectPartner('I9');
    expect(notifier.state.selectedPartnerXref, 'I9');
  });

  test('a server error response is surfaced without crashing', () async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => {'ok': false, 'error': 'private'});

    await controllerFor('I1');

    final state = container.read(treeViewControllerProvider);
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
        'stepFamilies': <dynamic>[],
      },
    );

    await controllerFor('I1');

    final state = container.read(treeViewControllerProvider);
    expect(state.loading, isFalse);
    expect(state.error, isNotNull);
  });
}
