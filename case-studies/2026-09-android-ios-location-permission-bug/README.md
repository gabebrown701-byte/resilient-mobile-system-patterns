# Android and iOS Lie About Permission State, Just in Opposite Directions

*Found and fixed pre-launch, while building a ride-dispatch app for iOS and Android.*

## The problem

Picture a guest who opens the app, gets asked for location access, and taps "Don't Allow." Fair enough. They close the app, come back a week later, and get asked again. And again the week after that. Forever.

That's not a made-up edge case. That's exactly what testing turned up before this app ever reached a real user: any guest who permanently denied location access would hit that same prompt on every single relaunch, with the app having no way to know it should stop asking. No real guest had hit the dead end yet, since nothing had shipped, but it was fully reproducible, and it would have hit every one of them, every single time. From the guest's side it would have looked broken: why does this app keep interrupting me for something I already said no to?

The intended behavior was simple. If someone permanently denies location, skip the prompt on every future launch and send them straight to picking their destination manually. That's a two-line product decision. Getting it to actually hold turned out to require understanding something neither platform tells you directly: Android and iOS answer the question "what did the user decide?" in two genuinely different, and in one case actively unreliable, ways.

## The investigation

The permission library this app uses (like most Flutter and native apps use some version of this pattern) exposes one read-only check you can call before ever showing your own prompt, so you don't interrupt someone who's already granted or already permanently refused. The idea is you check first, then decide whether to bother the user at all.

The first fix I wrote extended a warning banner ("Location is off, but you can still pick a venue manually") to cover more of that read-only check's possible results. It passed my own tests. It did not survive adversarial review, which caught that the banner was now showing up for people who had never been asked at all, telling them their location was "off" when nothing had ever been turned off in the first place. A real false positive, and a fair one to catch.

Chasing that down meant going past the Flutter-level API and into the actual native plugin source, since the plugin is open source and the answer had to be sitting in there somewhere.

iOS turned out to be well-behaved. A real "Don't Allow" tap reports back as a distinct, permanent status, separate from "never asked." You can trust it.

```objc
// From geolocator_apple's native status mapper
switch (authorizationStatus) {
    case kCLAuthorizationStatusNotDetermined:
    case kCLAuthorizationStatusRestricted:
        return @0;  // -> LocationPermission.denied
    case kCLAuthorizationStatusDenied:
        return @1;  // -> LocationPermission.deniedForever
    ...
}
```

Android is not well-behaved. Its read-only check collapses three genuinely different states, "never asked," "denied, can ask again," and "permanently denied," into the exact same value. There is no way to tell them apart from that call alone. The only way Android will ever tell you a denial is permanent is through the result of an actual, live permission request, the kind that puts a real dialog in front of the user.

```java
// From geolocator_android's permission check
if (permissionStatus == PackageManager.PERMISSION_DENIED) {
    return LocationPermission.denied;  // never/denied/permanent all land here
}
```

That's the actual bug. Not a typo, not a missed null check. Two platforms answering the same question with different amounts of honesty, and code that assumed they'd agree.

My first attempt at fixing this stored a single true/false flag: "has this user's denial ever been confirmed by a real prompt." That was still wrong, just in a smaller way. A flag can tell you a denial happened. It can't tell you which kind. So a user who had permanently denied would get that fact correctly remembered, and then incorrectly summarized back down to "denied, might ask again," which put them right back in the same loop the whole fix was supposed to end.

## The fix

The real fix was to stop compressing the answer. Persist and restore the actual confirmed status, not a boolean summary of it, and only trust that restored status for routing once it's confirmed by a real request, never by the ambiguous read-only check alone.

```dart
// Only a live permission request is trustworthy on Android.
// The read-only check can't tell "never asked" from "denied forever."
final restoredStatus = await getConfirmedDeniedStatus(userId) ?? rawStatus;

if (restoredStatus == PermissionStatus.deniedForever) {
  // Skip the prompt entirely. Go straight to manual selection.
  return fallbackToManualSelection();
}
```

One more piece mattered here that's easy to miss: a user who was never asked at all still deserves an honest interface. You can't show them "location is off" (nothing is off) but you also can't silently hide the fact that they don't have location access either. The final version shows a neutral, accurate message for that ambiguous case, and reserves the stronger "you turned this off" language for the cases that are actually confirmed. Small distinction, but it's the difference between an interface that's honest with the user and one that's just guessing and hoping it reads fine either way.

## By the numbers

This single piece of permission-routing logic, well under 50 lines, went through 3 separate rounds of Codex's adversarial review before it was correct, and each round caught a genuinely different failure mode, not the same issue restated:

1. A false positive shown to users who'd never been asked
2. A real permanent denial silently erased when the user picked "choose manually" instead of retrying
3. A real permanent denial correctly remembered, then incorrectly flattened back into "might ask again" by a boolean that couldn't hold the distinction

Three rounds, three non-overlapping defects, zero of them caught by a standard test suite, because the actual bug lived in what the platform itself was willing to admit, not in anything the app's own code could unit test its way into finding.

## The Why

The lesson isn't really about location permissions. It's that "the platform will tell me the truth if I just check" is an assumption, not a guarantee, and the only way to know whether it holds is to go read the actual native source and stop trusting the abstraction. The library authors weren't wrong to unify the API. iOS and Android genuinely don't expose the same information, and something has to paper over that gap. The mistake is assuming the paper is thick enough to build product behavior on top of without checking first.
