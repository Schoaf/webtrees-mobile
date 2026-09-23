import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/repositories/quick_note_store.dart';

// Only QuickNote's pure toMap()/fromMap() serialization is covered here -
// QuickNoteStore itself talks to a real sqflite database (via
// path_provider + sqflite platform channels), which would need a
// sqflite_common_ffi (or channel-mock) test harness this project doesn't
// have set up. Not worth adding just for this.
void main() {
  group('QuickNote.toMap', () {
    test('includes id when set', () {
      final note = QuickNote(
        id: 7,
        personGuess: 'Hans',
        xref: 'I1',
        text: 'Geburtstag ist 3. Mai',
        createdAt: DateTime(2024, 1, 2, 10, 30),
        synced: true,
      );

      expect(note.toMap(), {
        'id': 7,
        'person_guess': 'Hans',
        'xref': 'I1',
        'text': 'Geburtstag ist 3. Mai',
        'created_at': '2024-01-02T10:30:00.000',
        'synced': 1,
      });
    });

    test('omits id when null, and encodes synced=false as 0', () {
      final note = QuickNote(
        personGuess: 'Hans',
        text: 'note',
        createdAt: DateTime(2024, 1, 2),
      );

      final map = note.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['xref'], isNull);
      expect(map['synced'], 0);
    });
  });

  group('QuickNote.fromMap', () {
    test('round-trips through toMap/fromMap', () {
      final original = QuickNote(
        id: 3,
        personGuess: 'Anna',
        xref: 'I5',
        text: 'note text',
        createdAt: DateTime(2023, 6, 15, 8, 0),
        synced: true,
      );

      final restored = QuickNote.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.personGuess, original.personGuess);
      expect(restored.xref, original.xref);
      expect(restored.text, original.text);
      expect(restored.createdAt, original.createdAt);
      expect(restored.synced, original.synced);
    });

    test('decodes synced=0 as false and a missing xref as null', () {
      final restored = QuickNote.fromMap({
        'id': 1,
        'person_guess': 'Anna',
        'xref': null,
        'text': 'note text',
        'created_at': '2023-06-15T08:00:00.000',
        'synced': 0,
      });

      expect(restored.synced, isFalse);
      expect(restored.xref, isNull);
    });
  });
}
