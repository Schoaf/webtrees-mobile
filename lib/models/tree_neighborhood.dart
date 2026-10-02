/// Typed models for the family-tree view, parsed from the (enriched)
/// `Individual` API response. Deliberately typed rather than the raw
/// `Map<String,dynamic>` convention used elsewhere in the app: the
/// suppression rules, undo/redo history and partner-switching logic here
/// touch these fields at enough call sites that typed access is worth the
/// deviation.
library;

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

enum MaritalStatus { married, partnership, divorced, ended, widowed, unknown }

/// api4webtrees 1.8.0 dropped the server-side `maritalStatus` field
/// deliberately ("that's more an interpretation and belongs in the app") -
/// this ports the exact logic our own fork used to compute it server-side
/// (webtreesand-api commit 87c97de), now client-side instead. `facts` is
/// a family's own `facts[]` (GEDCOM tags like MARR/DIV), `husbandDead`/
/// `wifeDead` its husband/wife `isDead` flags - both already present on
/// every family in the Individual response (parentFamilies, spouseFamilies,
/// stepFamilies all share the same shape).
MaritalStatus _maritalStatusFromFamilyJson(Map<String, dynamic> json) {
  final facts = (json['facts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final tags = facts.map((f) => f['tag'] as String?).toSet();
  final hasMarriage = tags.contains('MARR');
  // Gedcom::DIVORCE_EVENTS (webtrees core, app/Gedcom.php).
  final hasDivorce = tags.contains('DIV') || tags.contains('ANUL') || tags.contains('_SEPR');

  if (hasDivorce) {
    return hasMarriage ? MaritalStatus.divorced : MaritalStatus.ended;
  }

  final husband = json['husband'] as Map<String, dynamic>?;
  final wife = json['wife'] as Map<String, dynamic>?;
  final partnerDead = (husband?['isDead'] as bool? ?? false) || (wife?['isDead'] as bool? ?? false);

  if (partnerDead) return MaritalStatus.widowed;
  if (hasMarriage) return MaritalStatus.married;
  if (husband != null && wife != null) return MaritalStatus.partnership;
  return MaritalStatus.unknown;
}

int? _yearFromEvent(Map<String, dynamic>? event) {
  final date = event?['date'] as Map<String, dynamic>?;
  return date?['year'] as int?;
}

/// First word of the given-name portion of webtrees' `sortName`
/// (`"Surname,Given Middle"`) — more reliable than splitting the display
/// `name`, which has no fixed separator between given and surname.
String _firstNameFrom({required String name, required String sortName}) {
  final comma = sortName.indexOf(',');
  final given = comma == -1 ? name : sortName.substring(comma + 1);
  final firstWord = given.trim().split(RegExp(r'\s+')).firstOrNull;
  return (firstWord == null || firstWord.isEmpty) ? name : firstWord;
}

/// One person as shown on a tree-view card — parent, sibling, partner or
/// child. `hasParents`/`partnersCount`/`childrenCount` are only present
/// when the server was asked for them (`personSummary(..., withCounts:
/// true)`), which the enriched `Individual` response always does.
class TreeNode {
  const TreeNode({
    required this.xref,
    required this.firstName,
    required this.sex,
    required this.isDead,
    required this.birthYear,
    required this.thumb,
    required this.private,
    this.hasParents,
    this.partnersCount,
    this.childrenCount,
  });

  factory TreeNode.fromJson(Map<String, dynamic> json) {
    return TreeNode(
      xref: json['xref'] as String,
      firstName: _firstNameFrom(
        name: json['name'] as String? ?? '',
        sortName: json['sortName'] as String? ?? '',
      ),
      sex: json['sex'] as String? ?? 'U',
      isDead: json['isDead'] as bool? ?? false,
      birthYear: _yearFromEvent(json['birth'] as Map<String, dynamic>?),
      thumb: json['thumb'] as String?,
      private: json['private'] as bool? ?? false,
      hasParents: json['hasParents'] as bool?,
      partnersCount: json['partnersCount'] as int?,
      childrenCount: json['childrenCount'] as int?,
    );
  }

  final String xref;
  final String firstName;
  final String sex;
  final bool isDead;
  final int? birthYear;
  final String? thumb;
  final bool private;
  final bool? hasParents;
  final int? partnersCount;
  final int? childrenCount;
}

/// Extra detail shown only on the current/active person's (expanded)
/// card — everyone else's card is name/year/badges only.
class TreePersonDetail {
  const TreePersonDetail({required this.birthDateText, required this.birthPlace, required this.occupation});

  factory TreePersonDetail.fromIndividualJson(Map<String, dynamic> json) {
    // The Individual response has no top-level "birth" field of its own -
    // that only exists on a nested personSummary() (e.g. json['person'],
    // or a parent/spouse/child entry), which is what TreeNode.fromJson
    // reads for its own birthYear. The full BIRT fact (with its display
    // text and place) lives in the flat facts[] list here instead, same
    // as everywhere else in the app that reads a fact off this endpoint.
    final facts = (json['facts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final birtFact = facts.where((f) => f['tag'] == 'BIRT').firstOrNull;
    final occuFact = facts.where((f) => f['tag'] == 'OCCU').firstOrNull;

    return TreePersonDetail(
      birthDateText: (birtFact?['date'] as Map<String, dynamic>?)?['text'] as String? ?? '',
      birthPlace: (birtFact?['place'] as Map<String, dynamic>?)?['short'] as String? ?? '',
      occupation: occuFact?['value'] as String? ?? '',
    );
  }

  final String birthDateText;
  final String birthPlace;
  final String occupation;
}

/// One of the current person's partner families — `partner` is `null` for
/// an unknown/unrecorded other parent (rendered as the dashed placeholder
/// card).
class TreePartnerFamily {
  const TreePartnerFamily({
    required this.familyXref,
    required this.partner,
    required this.maritalStatus,
    required this.marriageYear,
    required this.children,
  });

  factory TreePartnerFamily.fromFamilyJson(Map<String, dynamic> json) {
    final spouseJson = json['spouse'] as Map<String, dynamic>?;
    final childrenJson = (json['children'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return TreePartnerFamily(
      familyXref: json['xref'] as String,
      partner: spouseJson == null ? null : TreeNode.fromJson(spouseJson),
      maritalStatus: _maritalStatusFromFamilyJson(json),
      marriageYear: _yearFromEvent(json['marriage'] as Map<String, dynamic>?),
      children: _sortedByBirthThenName(childrenJson.map(TreeNode.fromJson).toList()),
    );
  }

  final String familyXref;
  final TreeNode? partner;
  final MaritalStatus maritalStatus;
  final int? marriageYear;
  final List<TreeNode> children;

  bool get isOngoing => maritalStatus == MaritalStatus.married || maritalStatus == MaritalStatus.partnership;
}

List<TreeNode> _sortedByBirthThenName(List<TreeNode> nodes) {
  final sorted = [...nodes];
  sorted.sort((a, b) {
    final yearCompare = (a.birthYear ?? 9999).compareTo(b.birthYear ?? 9999);
    return yearCompare != 0 ? yearCompare : a.firstName.compareTo(b.firstName);
  });
  return sorted;
}

/// The whole neighborhood around one person: parents, full siblings, every
/// partner (with that partner's own children), parsed from a single
/// `Individual` API response.
class TreeNeighborhood {
  const TreeNeighborhood({
    required this.person,
    required this.personDetail,
    required this.father,
    required this.mother,
    required this.extraChildrenFather,
    required this.extraChildrenMother,
    required this.siblings,
    required this.partners,
  });

  factory TreeNeighborhood.fromJson(Map<String, dynamic> json) {
    final person = TreeNode.fromJson(json['person'] as Map<String, dynamic>);
    final parentFamilies = (json['parentFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final primaryParents = parentFamilies.firstOrNull;
    final fatherJson = primaryParents?['husband'] as Map<String, dynamic>?;
    final motherJson = primaryParents?['wife'] as Map<String, dynamic>?;
    final fatherXref = fatherJson?['xref'] as String?;
    final motherXref = motherJson?['xref'] as String?;

    // api4webtrees never sent a dedicated "siblings" field - it's just the
    // primary parent family's own children, minus the person themself (the
    // maintainer's own words: "its the children of parentFamilies without
    // the person itself").
    final siblingsJson = (primaryParents?['children'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((c) => c['xref'] != person.xref);

    final spouseFamilies = (json['spouseFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    // 1.8.0 replaced extraChildrenByParent (a plain {father,mother} count)
    // with stepFamilies: full family objects (same shape as parentFamilies)
    // for every OTHER partner either parent has, each carrying which parent
    // it belongs to via "parent". Sum each side's children back down to the
    // two counts this screen actually shows (a "+N" hint, not the families
    // themselves - showing those is a nice future upgrade, not this one).
    final stepFamilies = (json['stepFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    var extraChildrenFather = 0;
    var extraChildrenMother = 0;
    for (final family in stepFamilies) {
      final parentXref = family['parent'] as String?;
      final childCount = (family['children'] as List<dynamic>? ?? []).length;
      if (parentXref != null && parentXref == fatherXref) extraChildrenFather += childCount;
      if (parentXref != null && parentXref == motherXref) extraChildrenMother += childCount;
    }

    return TreeNeighborhood(
      person: person,
      personDetail: TreePersonDetail.fromIndividualJson(json),
      father: fatherJson == null ? null : TreeNode.fromJson(fatherJson),
      mother: motherJson == null ? null : TreeNode.fromJson(motherJson),
      extraChildrenFather: extraChildrenFather,
      extraChildrenMother: extraChildrenMother,
      siblings: _sortedByBirthThenName(siblingsJson.map(TreeNode.fromJson).toList()),
      partners: spouseFamilies.map(TreePartnerFamily.fromFamilyJson).toList(),
    );
  }

  final TreeNode person;
  final TreePersonDetail personDetail;
  final TreeNode? father;
  final TreeNode? mother;
  final int extraChildrenFather;
  final int extraChildrenMother;
  final List<TreeNode> siblings;
  final List<TreePartnerFamily> partners;

  /// The partner shown by default when this person becomes the active
  /// person: the most recently married/partnered ongoing relationship, or
  /// (if none is ongoing) the most recent relationship overall. webtrees
  /// has no "primary family" flag to read instead, so this is a heuristic —
  /// tapping a different partner chip always overrides it.
  TreePartnerFamily? get defaultPartner {
    if (partners.isEmpty) return null;
    final ongoing = partners.where((p) => p.isOngoing).toList();
    final pool = ongoing.isNotEmpty ? ongoing : partners;
    return pool.reduce((best, p) => (p.marriageYear ?? -1) > (best.marriageYear ?? -1) ? p : best);
  }
}
