# Code sketches: making reports more actionable

These examples illustrate the implementation decisions described in the case study. They are simplified for readability and are not complete, drop-in production code.

## 1. Read the route after navigation resolves

The first version listened for a change to the raw route information and immediately read the router's current configuration. That notification could arrive before the new route had finished resolving.

**Risky timing:**

```dart
// The route-information notification can fire before resolution finishes.
router.routeInformationProvider.addListener(() {
  final path = router.routerDelegate.currentConfiguration.uri.path;
  reportScreen(path); // May still be empty or the previous route.
});
```

**Use the resolved navigation state instead:**

```dart
router.routerDelegate.addListener(() {
  final path = router.routerDelegate.currentConfiguration.uri.path;
  reportScreen(path);
});
```

In the actual implementation, this change made the diagnostic listener read the route after the router updated its current configuration. A test of the real listener path reproduced the stale-value problem and verified the corrected behavior.

## 2. Test the value that is recorded, not only that the method runs

A setter can complete without throwing while still recording the wrong value. The test seam makes it possible to verify the actual key and value sent by the diagnostic service.

```dart
final captured = <String, Object>{};

service.debugKeySink = (key, value) {
  captured[key] = value;
};

service.setRideStatus(RideStatus.awaitingDriver);

expect(captured['ride_status'], 'awaiting-driver');
```

This matters because the application uses a backend status string with a hyphen, rather than the Dart enum's camel-case name. The assertion checks the contract that a report actually needs.

## 3. Do not let reporting failures interrupt the user flow

Diagnostic reporting should be best-effort. The app should not fail because a logging SDK could not accept a value.

```dart
void safelyReport(void Function() record) {
  try {
    record();
  } catch (_) {
    // A reporting failure must not interrupt the user flow.
  }
}
```

The production service follows this pattern around Crashlytics custom-key updates and selected non-fatal reporting calls. Error handling for fatal framework reports preserves the existing fatal-reporting behavior.

## What these examples do not prove

The snippets explain the timing, testing, and safety principles. They do not replace the full app wiring, and they do not demonstrate a measured reduction in crash rates or incident-resolution time.
