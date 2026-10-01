// A simplified, generic extract of the idea behind a merge gate I built.
// It is NOT the production file (that one is far larger and stays private).
// No dependencies: runs with just the Dart SDK.
//
// The rule it enforces:
//   A sentence typed into a pull request description is only a CLAIM.
//   It counts as an approval only if a designated reviewer really approved
//   the latest commit AND their own review text quotes that exact sentence.
//   Anything unreadable, missing, or ambiguous means "blocked", never "allowed".

/// One review as a code host returns it, oldest first.
class Review {
  Review(this.user, this.state, this.commitId, {this.body = ''});
  final String user; // who reviewed
  final String state; // APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED
  final String commitId; // the commit they reviewed
  final String body; // the reviewer's own text
}

/// A pull request, reduced to what the gate needs.
class PullRequest {
  PullRequest({
    required this.headSha,
    required this.description,
    required this.reviews,
    this.deletedTestFiles = const [],
  });
  final String headSha;
  final String description; // written by the AUTHOR: never trusted
  final List<Review> reviews; // written by REVIEWERS: the evidence
  final List<String> deletedTestFiles;
}

class Decision {
  Decision(this.allowed, this.problems);
  final bool allowed;
  final List<String> problems;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Designated reviewers whose LATEST decisive review is APPROVED, was made on
/// the current head commit, and (value) what that review said.
///
///  * a COMMENTED review changes nothing;
///  * CHANGES_REQUESTED or DISMISSED after an approval revokes it;
///  * an approval of an older commit does not count: new commits start over.
Map<String, String> verifiedApprovers({
  required List<Review> reviews,
  required List<String> designated,
  required String headSha,
}) {
  final allowed = designated.map((d) => d.toLowerCase()).toSet();
  final latest = <String, Review>{};
  for (final r in reviews) {
    final s = r.state.toUpperCase();
    if (s == 'APPROVED' || s == 'CHANGES_REQUESTED' || s == 'DISMISSED') {
      latest[r.user.toLowerCase()] = r;
    }
  }
  return {
    for (final e in latest.entries)
      if (allowed.contains(e.key) &&
          e.value.state.toUpperCase() == 'APPROVED' &&
          e.value.commitId == headSha)
        e.key: e.value.body,
  };
}

/// Reads a line like `Label: @login, rest...` out of free text.
String? findLine(String text, String label) {
  final m = RegExp(
    '^\\s*${RegExp.escape(label)}\\s*:\\s*(\\S.*)\$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(text);
  return m?.group(1)?.trim();
}

String? loginOf(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^@([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)')
      .firstMatch(value.trim());
  return m?.group(1)?.toLowerCase();
}

/// The exact paths listed after `files:` (up to `reason:`), as WHOLE tokens.
/// `a_test.dart.bak` never satisfies `a_test.dart`, and a path that is merely
/// mentioned in the reason does not count.
Set<String>? filesOf(String? value) {
  if (value == null) return null;
  final m = RegExp(r'files\s*:\s*(.*?)(?:,?\s*reason\s*:|$)', caseSensitive: false)
      .firstMatch(value);
  if (m == null) return null;
  return {
    for (final t in m.group(1)!.split(RegExp(r'[\s,]+')))
      if (t.isNotEmpty) t.startsWith('./') ? t.substring(2) : t,
  };
}

bool hasReason(String? value) {
  final m = value == null
      ? null
      : RegExp(r'reason\s*:\s*(.+)$', caseSensitive: false).firstMatch(value);
  return m != null && m.group(1)!.trim().length >= 10;
}

const removalLabel = 'Test removal approved by';

/// The decision. Deleting a test file is the cheapest way to weaken a safety
/// net, so it needs a human: a quoted line, from a real reviewer, naming every
/// deleted file exactly, with a reason.
Decision decide(PullRequest pr, {required List<String> designated}) {
  final problems = <String>[];
  final deleted = ({...pr.deletedTestFiles}.toList())..sort();
  if (deleted.isEmpty) return Decision(true, problems);

  final claimed = findLine(pr.description, removalLabel);
  if (claimed == null) {
    problems.add('deleted tests $deleted but the description has no '
        '"$removalLabel" line');
    return Decision(false, problems);
  }

  final approvers = verifiedApprovers(
    reviews: pr.reviews,
    designated: designated,
    headSha: pr.headSha,
  );
  final login = loginOf(claimed);
  final reviewText = login == null ? null : approvers[login];

  // 1. The reviewer must have really approved THIS commit, in their own words
  //    quoting the exact line the author wrote.
  if (reviewText == null ||
      !_norm(reviewText).contains(_norm('$removalLabel: $claimed'))) {
    problems.add('the line is only a claim: no designated reviewer approved '
        'the latest commit and quoted it');
  }
  // 2. It must name EXACTLY the deleted files, and give a reason.
  final listed = filesOf(claimed);
  if (listed == null ||
      listed.length != deleted.length ||
      !listed.containsAll(deleted)) {
    problems.add('the approval must list exactly the deleted files $deleted');
  }
  if (!hasReason(claimed)) {
    problems.add('the approval needs a reason of at least 10 characters');
  }
  return Decision(problems.isEmpty, problems);
}
