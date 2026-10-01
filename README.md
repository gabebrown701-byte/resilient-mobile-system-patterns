# Resilient Mobile System Patterns

Real product and engineering problems from building a production-grade mobile app ahead of launch, written up as case studies. Each one covers the actual problem, how it was worked through, what changed, and a number that backs up the claim rather than just asserting it. Some include small, runnable code extracts you can try yourself.

## Process & Tooling
- **[A Merge Gate That Never Trusts a Sentence Someone Typed](case-studies/2026-10-merge-gate-that-never-trusts-typed-approvals/)**. A risky change needs a human to approve it, but "approved by me" is just text anyone (or any AI working as me) can type. The fix: an approval only counts if a named reviewer really approved the latest version and their own review quotes the exact line. Includes runnable code. About 2,400 lines of gate code backed by about 2,800 lines of tests, 176 tests in all, and roughly two dozen distinct defects found by independent review rounds.
- **[The Safety Check That Refused a Healthy Machine](case-studies/2026-10-measure-before-you-fix-simulator-load/)**. My own pre-flight check kept blocking test runs on a machine that was fine, because it was reading numbers that lag or go stale. Measured instead of guessed: a simulator boot pegs the CPU at 0% idle for about 35 seconds, while the "load" reading stayed high for minutes after the CPU was already 88 to 94% idle. Includes a runnable demo of the check failing open versus failing closed.
- **[A Code Review Process That Can Block Me From Stopping Until It's Satisfied](case-studies/2026-09-codex-adversarial-code-review-process/)**. A governed AI code review gate that checks implementations against actual product intent, not just syntax. 15 distinct, confirmed defects caught in a single day of focused work, none of them a repeat of the same issue.

## Platform & Native Integration
- **[Android and iOS Lie About Permission State, Just in Opposite Directions](case-studies/2026-09-android-ios-location-permission-bug/)**. A permission bug that required reading the native plugin's own source to diagnose, caught pre-launch through 3 independent rounds of adversarial review, each one catching a genuinely different failure mode.

## Systems & Concurrency
- **[Making Sure "Stop" Actually Means Stop](case-studies/2026-09-crash-safe-locking-for-ios-android-test-automation/)**. A shared-resource safeguard for automated tests, and the gap where stopping the supervisor didn't actually stop the real work underneath it. Proven by deliberately causing the failure, not just reading the code. 7 distinct defects caught and fixed, plus the load-average-96 incident that started the investigation, fully resolved.

## Product Design & Fairness
- **[When You Can't Serve Everyone at Once, Who Waits?](case-studies/2026-03-fair-ride-dispatch-under-capacity-limits/)**. Designing a congestion-governance system where "fair" had to be explicitly defined before it could be built. 4 distinct ways to define fairness were worked through on purpose, and 6 tricky situations were resolved with a written answer before any implementation began.
