// Run:  dart run self_test.dart     (exits non-zero if any check fails)
import 'dart:io';
import 'approval_gate.dart';
import 'scenarios.dart';

var failures = 0;
var checks = 0;

void check(bool ok, String what) {
  checks++;
  if (!ok) {
    failures++;
    stderr.writeln('FAIL: $what');
  }
}

void main() {
  // 1. Every scenario decides the way it should.
  for (final s in scenarios) {
    final d = decide(s.pr, designated: designated);
    check(d.allowed == s.expectAllowed, s.name);
  }

  // 2. Whole-token path matching, in isolation.
  check(
    filesOf('@a, files: x/a.dart y/b.dart, reason: long enough reason')!
            .difference({'x/a.dart', 'y/b.dart'}).isEmpty,
    'filesOf reads whole paths',
  );
  check(filesOf('@a, reason: mentions x/a.dart') == null,
      'a path in the reason is not a files: entry');
  check(filesOf('@a, files: ./x/a.dart')!.contains('x/a.dart'),
      './ prefix is normalised');

  // 3. A reviewer's COMMENT never revokes or grants anything.
  final onlyComment = verifiedApprovers(
    reviews: [Review('reviewer-one', 'COMMENTED', head, body: line)],
    designated: designated,
    headSha: head,
  );
  check(onlyComment.isEmpty, 'a comment is not an approval');

  // 4. Garbage in means blocked, not allowed.
  final garbage = decide(
    PullRequest(
      headSha: head,
      description: '\u0000\u0000 not a real description',
      reviews: [Review('', '', '')],
      deletedTestFiles: const ['test/x_test.dart'],
    ),
    designated: designated,
  );
  check(!garbage.allowed, 'unreadable input fails closed');

  print('$checks checks, $failures failed');
  exit(failures == 0 ? 0 : 1);
}
