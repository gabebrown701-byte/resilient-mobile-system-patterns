# Code Sketch: The Approval Check

*A companion to [A Merge Gate That Never Trusts a Sentence Someone Typed](README.md). This is a simplified illustration written for this write-up. It is not production code, and it leaves out the file classification, the test selection, the pull request template, and the CI workflow around the real thing.*

## Where it fits

The case study describes a gate that decides which expensive tests a change needs and whether it needs a human sign-off. This sketch covers only the sign-off. It answers one question: when the author's description says a specific person approved something, can I believe it?

## The rule

A sentence the author typed is a claim. It counts only if a designated reviewer really approved the latest commit, and their own review text quotes that exact sentence. The decision for one risky action, deleting a test file, then looks like this:

```dart
Decision decide(PullRequest pr, {required List<String> designated}) {
  final problems = <String>[];
  final deleted = ({...pr.deletedTestFiles}.toList())..sort();
  if (deleted.isEmpty) return Decision(true, problems);

  final claimed = findLine(pr.description, removalLabel);
  if (claimed == null) {
    problems.add('deleted tests $deleted but there is no approval line');
    return Decision(false, problems);
  }

  final approvers = verifiedApprovers(
    reviews: pr.reviews, designated: designated, headSha: pr.headSha);
  final reviewText = approvers[loginOf(claimed)];

  // 1. A real reviewer, on THIS commit, quoting the exact line.
  if (reviewText == null ||
      !_norm(reviewText).contains(_norm('$removalLabel: $claimed'))) {
    problems.add('the line is only a claim');
  }
  // 2. It names EXACTLY the deleted files (whole paths) and gives a reason.
  final listed = filesOf(claimed);
  if (listed == null ||
      listed.length != deleted.length ||
      !listed.containsAll(deleted)) {
    problems.add('the approval must list exactly the deleted files $deleted');
  }
  if (!hasReason(claimed)) problems.add('the approval needs a reason');
  return Decision(problems.isEmpty, problems);
}
```

## How it connects to the case study

- **"A sentence in the description is only a claim."** The author's text is never evidence. The only evidence is a review written by someone else.
- **"The reviewer's own text quotes the exact line."** This is what stops a generic "looks good" from being reused for a sentence the reviewer never saw.
- **"New commits start over."** An approval of an older commit doesn't count, so a reviewer who approved version one has not approved version two.
- **"Whole paths that must equal the deleted set."** Matching by "contains" let `old_test.dart.bak` satisfy a deletion of `old_test.dart`. Parsing the list into whole paths and comparing sets closes that.

## The test

Eleven scenarios, one per attack and defense. `dart run demo.dart` prints them:

```
[ALLOWED] Nothing deleted
[BLOCKED] Deletes a test, says nothing
[BLOCKED] FORGED: author types the approval, nobody reviewed
[BLOCKED] REPLAY: reviewer said "looks good", author added the line afterwards
[BLOCKED] STALE: reviewer approved an older commit
[BLOCKED] WRONG PERSON: a non-designated account approved
[BLOCKED] REVOKED: approved, then requested changes
[BLOCKED] SUBSTRING TRICK: approval names old_test.dart.bak
[BLOCKED] MENTION TRICK: the real path only appears in the reason
[BLOCKED] EXTRA FILE: approval lists a file that was not deleted
[ALLOWED] REAL APPROVAL: designated reviewer, latest commit, quoted the exact line
```

`dart run self_test.dart` runs 16 checks and exits non-zero on any failure.

A passing test only means something if it can fail, so I proved that. I put two of the real bugs back into a temporary copy and ran the self-test:

- Matching paths by "contains" again: **3 checks failed** (substring, mention and extra-file).
- Removing the "reviewer must quote the line" check: **5 checks failed** (forged, replay, stale, wrong person, revoked).

Restoring the original made all 16 pass again.

## A choice I made on purpose

Anything the gate can't read or verify ends in **blocked**, never allowed. That has a cost. A transient failure, such as a reviews lookup that times out, blocks a merge until someone re-runs the check. I chose that because the two mistakes aren't equal: a wrongly blocked change costs a retry, and a wrongly allowed one is silent. A gate that fails open stops being a gate on the exact day it's needed.

## Run it yourself

Needs only the Dart SDK.

```
cd code
dart run demo.dart
dart run self_test.dart
```

The files: [`approval_gate.dart`](code/approval_gate.dart) (the check), [`scenarios.dart`](code/scenarios.dart) (the 11 situations), [`demo.dart`](code/demo.dart) and [`self_test.dart`](code/self_test.dart).
