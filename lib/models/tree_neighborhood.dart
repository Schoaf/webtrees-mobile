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

MaritalStatus _maritalStatusFromJson(String? value) => switch (value) {
  'married' => MaritalStatus.married,
  'partnership' => MaritalStatus.partnership,
  'divorced' => MaritalStatus.divorced,
  'ended' => MaritalStatus.ended,
  'widowed' => MaritalStatus.widowed,
  _ => MaritalStatus.unknown,
};

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
    final birth = json['birth'] as Map<String, dynamic>?;
    final facts = (json['facts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final occuFact = facts.where((f) => f['tag'] == 'OCCU').firstOrNull;

    return TreePersonDetail(
      birthDateText: (birth?['date'] as Map<String, dynamic>?)?['text'] as String? ?? '',
      birthPlace: (birth?['place'] as Map<String, dynamic>?)?['short'] as String? ?? '',
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
      maritalStatus: _maritalStatusFromJson(json['maritalStatus'] as String?),
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
    final parentFamilies = (json['parentFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final primaryParents = parentFamilies.firstOrNull;
    final fatherJson = primaryParents?['husband'] as Map<String, dynamic>?;
    final motherJson = primaryParents?['wife'] as Map<String, dynamic>?;

    final spouseFamilies = (json['spouseFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final siblingsJson = (json['siblings'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final extra = json['extraChildrenByParent'] as Map<String, dynamic>? ?? const {};

    return TreeNeighborhood(
      person: TreeNode.fromJson(json['person'] as Map<String, dynamic>),
      personDetail: TreePersonDetail.fromIndividualJson(json),
      father: fatherJson == null ? null : TreeNode.fromJson(fatherJson),
      mother: motherJson == null ? null : TreeNode.fromJson(motherJson),
      extraChildrenFather: extra['father'] as int? ?? 0,
      extraChildrenMother: extra['mother'] as int? ?? 0,
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
