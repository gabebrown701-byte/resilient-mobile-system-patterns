# When the App Breaks, Can You Tell What the User Was Experiencing?

*Building useful crash context and UX-friction signals into a two-sided mobile product.*

## The problem

A crash report can tell you **that** something failed. It does not always tell you what the person was doing when it happened.

Imagine receiving a report that says a layout operation failed. Was the person using the Guest app or the Driver app? Which screen were they on? Was the app displaying a different language, a larger text size, or a different presentation style? Was a ride active?

Those details can change where an investigation should start. Without them, the team may have to reproduce the problem, guess at the conditions, or ask questions the report could have answered automatically.

The product has two distinct experiences—one for people requesting rides and another for the drivers fulfilling them—running across iOS and Android. I wanted incident reports to carry enough **relevant context to narrow the investigation**, without creating a second source of truth for application state.

## The product decision

I treated diagnostics as part of the product's operational experience, not just a logging task.

The design had three rules:

1. **Capture context that helps explain a failure.** Record the platform, app experience, presentation and theme, language, accessibility settings, screen, journey, ride status, and venue context.
2. **Take each value from the place that already owns it.** For example, screen information comes from resolved navigation state, while ride and venue information comes from the app's existing state transitions. Diagnostics should describe the product, not invent a parallel version of it.
3. **Keep telemetry out of the user's way.** Recording diagnostic context is best-effort. A failure in the reporting layer must not become a new reason for the app itself to fail.

## What a more useful report can tell us

The implementation adds **11 structured Crashlytics context keys**. They are deliberately small pieces of state rather than a dump of whatever happens to be in memory.

| Context | Questions it helps investigate |
|---|---|
| Platform and app experience | Is the report associated with iOS or Android, and with the Guest or Driver experience? |
| Presentation, theme, and language | Was the app rendering under a particular display configuration? |
| Accessibility mode and text scale | Was a screen-reader setting, reduced motion, high contrast, bold text, or larger text active? |
| Screen and journey | Which part of the experience was open, and which broader task did it belong to? |
| Ride status and venue context | Was a ride active, and which venue context had the app resolved? |

These values do not diagnose a root cause by themselves. They help an engineer ask a better first question and compare reports that share the same conditions.

~~~text
A report without context
  "A framework error occurred."
              |
              v
A report with context
  "A framework error occurred while the Driver experience
   was on the active-ride screen, with large text enabled."
~~~

*Illustration only—not a real crash report or a claim about a specific production incident.*

## The wiring mattered more than the key names

Adding fields to a logging service would have been the easy part. The harder part was ensuring the fields reflected the state the person was actually seeing.

I built a shared diagnostic boundary for both app experiences and connected it to existing sources of truth:

- **At startup:** record the platform and which app experience is running.
- **When navigation resolves:** update the current screen and classify it into a named journey.
- **When presentation or accessibility state changes:** update the relevant context rather than leaving startup values in place.
- **When ride or venue state changes:** update or clear those values using the existing state transitions.
- **When a supported framework layout exception is detected:** classify it separately from an ordinary fatal report and attach the already-recorded text-scale context.

The shared service extends the existing diagnostics approach rather than introducing a second analytics or state-management framework. Context-setting is also guarded so that a telemetry SDK problem does not take the app down with it.

## A test uncovered a real reporting bug

One of the most important results came from testing the *connection* between navigation and diagnostics—not from testing the screen classifier in isolation.

The first implementation listened to a route-information notification that arrived **before navigation had finished resolving the new route**. That meant diagnostics could read an empty route at startup or the route the person had just left, instead of the route they had just reached.

A unit test for the route-to-journey mapping would not catch that. I added a test that exercised the actual navigation-listener path, reproduced the stale value, and changed the listener to observe the resolved navigation state instead.

~~~mermaid
flowchart TD
    A[Person navigates to a screen] --> B[Router resolves the new location]
    B --> C[Diagnostics reads resolved navigation state]
    C --> D[Screen and journey context are updated]
    D --> E[Future report has more useful context]
    F[Earlier approach: listen before resolution] --> G[Empty or previous screen can be recorded]
    G --> H[Test exposes the mismatch]
~~~

This is the principle I wanted to enforce: **test that the signal is accurate at the real integration point, not merely that a helper function works on its own.**

## Looking beyond crashes: measure UX friction too

Crash reporting only reveals part of the experience. A person can struggle with the interface without causing a crash.

Alongside diagnostic context, I added a small set of structured product events intended to surface moments worth investigating:

- **Rage taps:** repeated taps on a control while it is known to be unresponsive.
- **Backtracking:** moving back to an earlier step within the defined booking flow.
- **Dead-end guard triggers:** a navigation attempt that reaches a guard designed to protect an active task.
- **Appearance preference changes:** an actual change in the person's selected theme, not a repeated tap on the same option.
- **Dark-mode session and reduced-motion signals:** whether those states were actually active, with session-level deduplication where appropriate.

These signals are not a verdict that the interface is bad. A backtrack may be intentional, and a blocked navigation may be the correct safety behavior. They make useful questions measurable so the team can investigate patterns rather than relying only on anecdotes.

I kept this work scoped to the new UX and accessibility signals. It was not a replacement for the separate business-funnel measurement work needed to understand booking conversion, booking failures, or ride completion.

## Accessibility: useful signal, not a promise to catch every visual defect

The diagnostic context includes the active accessibility configuration and numeric text scale. Certain reported framework layout exceptions can also be classified as non-fatal errors, with the text-scale context attached.

There is an important limit: **this does not catch every visual overflow or clipping problem in a release build**. Some classic pixel-overflow diagnostics are development-time assertions and may not produce a report in production. Automated widget tests at large text sizes remain an important safety net for visual defects that do not throw an exception.

That distinction matters. A monitoring mechanism should state what it can observe, not imply it can see every failure.

## Validation

The final validation recorded for this phase reported:

- **11** structured Crashlytics context keys
- **2** app experiences: Guest and Driver
- **2** mobile platforms: iOS and Android
- **27** new or extended tests across analytics, navigation, Crashlytics classification, and rage-tap behavior
- **207/207** Flutter tests passing in the final phase validation
- **0** reported Flutter analyzer issues
- Successful Guest and Driver builds for Android and iOS

Those results establish that the implementation was tested and buildable at that point. They do **not** establish a measured reduction in production incident-resolution time, a lower crash rate, or improved conversion. That would require production data and a follow-up measurement plan.

## Privacy and scope

The public example is intentionally sanitized. It contains no real venue identifier, user or booking identifiers, recovery codes, Firebase project identifiers, credentials, production logs, or internal repository paths. Any example values are illustrative.

The diagnostic keys described here focus on bounded operational context. The goal is to make a report easier to investigate—not to collect a passenger's identity or arbitrary free-text content.

## What this says about how I build

The work was not simply “add monitoring.” It required product judgment about **which facts would change an investigation**, architecture judgment about **where those facts should come from**, and testing discipline to verify that the facts were correct when real navigation and state changes occurred.

I also made the limits explicit: diagnostic context can guide an investigation, but it is not proof of a root cause; UX events are signals to inspect, not automatic judgments about users; and a non-fatal classifier is not a substitute for visual accessibility tests.

That is the kind of observability I want in a product: enough signal to learn from failures and friction, without creating new failure modes or claiming outcomes that have not been measured.
