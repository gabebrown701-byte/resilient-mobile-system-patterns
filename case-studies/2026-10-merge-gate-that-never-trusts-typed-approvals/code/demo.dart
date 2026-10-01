// Run:  dart run demo.dart
import 'approval_gate.dart';
import 'scenarios.dart';

void main() {
  print('Deleting a test file needs a verified, quoted approval.\n');
  for (final s in scenarios) {
    final d = decide(s.pr, designated: designated);
    final mark = d.allowed ? 'ALLOWED' : 'BLOCKED';
    print('[$mark] ${s.name}');
    for (final p in d.problems) {
      print('          -> $p');
    }
  }
}
