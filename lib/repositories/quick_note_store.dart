import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// A fact the user jotted down fast (e.g. "X's birthday is 3 May") when
/// posting it straight to webtrees wasn't possible or fast enough. Kept
/// entirely on-device until the user reconciles it into a real fact.
class QuickNote {
  QuickNote({
    this.id,
    required this.personGuess,
    this.xref,
    required this.text,
    required this.createdAt,
    this.synced = false,
  });

  final int? id;
  final String personGuess;

  /// The person's xref, when the note was taken from a known person's page
  /// (e.g. a fact that failed to post) — lets the app jump straight back to
  /// them instead of re-searching by name.
  final String? xref;
  final String text;
  final DateTime createdAt;
  final bool synced;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'person_guess': personGuess,
        'xref': xref,
        'text': text,
        'created_at': createdAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  static QuickNote fromMap(Map<String, Object?> map) => QuickNote(
        id: map['id'] as int?,
        personGuess: map['person_guess'] as String,
        xref: map['xref'] as String?,
        text: map['text'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        synced: (map['synced'] as int) == 1,
      );
}

class QuickNoteStore {
  static Database? _db;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      p.join(dir.path, 'quick_notes.db'),
      version: 2,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE quick_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          person_guess TEXT NOT NULL,
          xref TEXT,
          text TEXT NOT NULL,
          created_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE quick_notes ADD COLUMN xref TEXT');
        }
      },
    );
    _db = db;
    return db;
  }

  Future<int> add(QuickNote note) async {
    final db = await _database();
    return db.insert('quick_notes', note.toMap());
  }

  Future<List<QuickNote>> unsynced() async {
    final db = await _database();
    final rows = await db.query('quick_notes', where: 'synced = 0', orderBy: 'created_at DESC');
    return rows.map(QuickNote.fromMap).toList();
  }

  Future<void> markSynced(int id) async {
    final db = await _database();
    await db.update('quick_notes', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }
}
