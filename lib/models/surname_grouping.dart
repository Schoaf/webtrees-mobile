/// Which surnames share a colour in the tree (#43) - set in the profile.
enum SurnameGrouping {
  /// The surname as webtrees files it (SURN): spellings share a colour
  /// only where SURN says so.
  exact,

  /// Also spellings that differ only slightly: Hummer and Humer, Schmidt
  /// and Schmitt, Mayer and Meier.
  spelling,

  /// Also names that sound alike (Kölner Phonetik) - coarse: Meier and
  /// Mohr sound alike too.
  sound,
}

/// The key the surnames of one colour share.
String surnameGroupKey(String surname, SurnameGrouping grouping) {
  return switch (grouping) {
    SurnameGrouping.exact => surname,
    SurnameGrouping.spelling => _simplifiedSpelling(surname),
    SurnameGrouping.sound => _soundCode(surname),
  };
}

/// The surname in a plain spelling: umlauts written out, letters that sound
/// alike made the same, doubled letters single.
String _simplifiedSpelling(String surname) {
  var s = surname.toLowerCase().trim();
  if (s.isEmpty) return '';
  s = s.replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');
  s = s
      .replaceAll('th', 't')
      .replaceAll('ph', 'f')
      .replaceAll('ck', 'k')
      .replaceAll('tz', 'z')
      .replaceAll('dt', 't')
      .replaceAll(RegExp('ey|ay|ai'), 'ei')
      .replaceAll('y', 'i');
  s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  return s.endsWith('d') ? '${s.substring(0, s.length - 1)}t' : s;
}

/// The Kölner Phonetik code of the surname - or the surname itself when it
/// has no code (no letters it knows).
String _soundCode(String surname) {
  final s = surname
      .toLowerCase()
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 's')
      .replaceAll(RegExp('[^a-z]'), '');
  final digits = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final prev = i > 0 ? s[i - 1] : '';
    final next = i + 1 < s.length ? s[i + 1] : '';
    digits.write(switch (s[i]) {
      'a' || 'e' || 'i' || 'j' || 'o' || 'u' || 'y' => '0',
      'h' => '',
      'b' => '1',
      'p' => next == 'h' ? '3' : '1',
      'd' || 't' => 'csz'.contains(next) && next.isNotEmpty ? '8' : '2',
      'f' || 'v' || 'w' => '3',
      'g' || 'k' || 'q' => '4',
      'c' when i == 0 => 'ahkloqrux'.contains(next) && next.isNotEmpty ? '4' : '8',
      'c' => 'sz'.contains(prev) && prev.isNotEmpty
          ? '8'
          : 'ahkoqux'.contains(next) && next.isNotEmpty
          ? '4'
          : '8',
      'x' => 'ckq'.contains(prev) && prev.isNotEmpty ? '8' : '48',
      'l' => '5',
      'm' || 'n' => '6',
      'r' => '7',
      _ => '8', // s, z
    });
  }
  // Repeated digits once; vowels only at the start.
  final code = digits.toString().replaceAllMapped(RegExp(r'(\d)\1+'), (m) => m[1]!);
  final result = code.isEmpty ? '' : code[0] + code.substring(1).replaceAll('0', '');
  return result.isEmpty ? surname.toLowerCase() : result;
}
