// The scenarios shared by demo.dart (prints them) and self_test.dart (asserts
// them). Each is a pull request that deletes a test file, plus what a hostile
// or careless author might try.
import 'approval_gate.dart';

const designated = ['reviewer-one'];
const head = 'c0ffee2'; // the commit under review
const line =
    'Test removal approved by: @reviewer-one, files: test/old_test.dart, reason: replaced by a better test';

class Scenario {
  Scenario(this.name, this.pr, {required this.expectAllowed});
  final String name;
  final PullRequest pr;
  final bool expectAllowed;
}

PullRequest pr({
  String description = 'Cleaning up tests.',
  List<Review> reviews = const [],
  List<String> deleted = const ['test/old_test.dart'],
}) =>
    PullRequest(
      headSha: head,
      description: description,
      reviews: reviews,
      deletedTestFiles: deleted,
    );

final scenarios = <Scenario>[
  Scenario('Nothing deleted', pr(deleted: const []), expectAllowed: true),
  Scenario('Deletes a test, says nothing', pr(), expectAllowed: false),
  Scenario(
    'FORGED: author types the approval, nobody reviewed',
    pr(description: line),
    expectAllowed: false,
  ),
  Scenario(
    'REPLAY: reviewer said "looks good", author added the line afterwards',
    pr(
      description: line,
      reviews: [Review('reviewer-one', 'APPROVED', head, body: 'Looks good.')],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'STALE: reviewer approved an older commit',
    pr(
      description: line,
      reviews: [Review('reviewer-one', 'APPROVED', 'oldsha1', body: line)],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'WRONG PERSON: a non-designated account approved',
    pr(
      description: line,
      reviews: [Review('random-user', 'APPROVED', head, body: line)],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'REVOKED: approved, then requested changes',
    pr(
      description: line,
      reviews: [
        Review('reviewer-one', 'APPROVED', head, body: line),
        Review('reviewer-one', 'CHANGES_REQUESTED', head),
      ],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'SUBSTRING TRICK: approval names old_test.dart.bak',
    pr(
      description: line.replaceFirst('old_test.dart,', 'old_test.dart.bak,'),
      reviews: [
        Review(
          'reviewer-one',
          'APPROVED',
          head,
          body: line.replaceFirst('old_test.dart,', 'old_test.dart.bak,'),
        ),
      ],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'MENTION TRICK: the real path only appears in the reason',
    pr(
      description:
          'Test removal approved by: @reviewer-one, files: test/other_test.dart, reason: unlike test/old_test.dart this is obsolete',
      reviews: [
        Review(
          'reviewer-one',
          'APPROVED',
          head,
          body:
              'Test removal approved by: @reviewer-one, files: test/other_test.dart, reason: unlike test/old_test.dart this is obsolete',
        ),
      ],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'EXTRA FILE: approval lists a file that was not deleted',
    pr(
      description: line.replaceFirst(
        'files: test/old_test.dart,',
        'files: test/old_test.dart test/keep_test.dart,',
      ),
      reviews: [
        Review(
          'reviewer-one',
          'APPROVED',
          head,
          body: line.replaceFirst(
            'files: test/old_test.dart,',
            'files: test/old_test.dart test/keep_test.dart,',
          ),
        ),
      ],
    ),
    expectAllowed: false,
  ),
  Scenario(
    'REAL APPROVAL: designated reviewer, latest commit, quoted the exact line',
    pr(
      description: line,
      reviews: [
        Review('reviewer-one', 'APPROVED', head,
            body: 'Checked the replacement.\n\n$line'),
      ],
    ),
    expectAllowed: true,
  ),
];
