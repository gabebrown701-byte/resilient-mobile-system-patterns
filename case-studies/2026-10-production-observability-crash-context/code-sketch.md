# Sanitized sketch: making reports more actionable

This is a conceptual example written for this case study, **not copied production code**. Values are illustrative and identifiers are redacted.

## 1. Describe the experience with a small context object

```dart
final reportContext = <String, Object>{
  'platform': 'ios',
  'flavor': 'driver',
  'presentation_variant': 'native',
  'theme_mode': 'dark',
  'language': 'en',
  'accessibility_mode': 'large_text,reduce_motion',
  'text_scale': 1.5,
  'screen': 'active_ride',
  'journey': 'driver_active_ride',
  'ride_status': 'assigned',
  'venue_id': '<redacted-venue-id>',
};
```

The object is an illustration of the shape of the context, not a live report. Real values must come from the application's current sources of truth. Do not put names, emails, booking IDs, ticket numbers, recovery codes, tokens, or free-text user content into this context.

## 2. Update navigation context only after the route is resolved

```dart
// Conceptual sequence, not the production listener implementation.
void onResolvedNavigation(String screen, String journey) {
  diagnostics.setScreen(screen);
  diagnostics.setJourney(journey);
}
```

The timing matters. Reading navigation state before the router finishes resolving a destination can record the previous screen—or no screen at all. The test should exercise the actual router-to-diagnostics connection, not only test how a path is classified.

## 3. Keep diagnostic collection from becoming a new failure

```dart
void safelyRecord(void Function() record) {
  try {
    record();
  } catch (_) {
    // Reporting failure must not crash the user-facing app.
  }
}
```

This is the basic safety boundary: telemetry is best-effort, and the application should remain usable if the reporting SDK cannot accept a value.

## 4. Treat UX events as signals for investigation

Examples of structured event names used by the instrumentation:

- `rage_tap`
- `backtrack`
- `dead_end_guard_triggered`
- `appearance_preference_changed`
- `dark_mode_session_active`
- `reduce_motion_detected`

Their meaning depends on the context and surrounding behavior. For example, a backtrack can be a sign of confusion—or a deliberate choice. These events help identify patterns; they do not prove user frustration or establish business impact on their own.
