# When Your Ride Survives, But Your Login Doesn't

*A product and systems design problem from a ride-dispatch app that lets guests book without creating an account.*


## The problem

I wanted the first ride to feel almost effortless.

A guest can open the app and request a golf cart without creating an account, choosing a password, or giving an email address. Behind the scenes, the app uses a temporary identity so the booking can still belong to someone.

That makes the first experience much easier.

It also creates a tradeoff:

**What happens if that temporary identity disappears while the ride is still active?**

That can happen after an app reinstall or when the app's local authentication state is cleared. The ride still exists on the server. The guest simply comes back as a different temporary user.

From the guest's point of view:

~~~text
"I already asked for a ride."
          ↓
The app starts again
          ↓
The app can't find that ride
          ↓
The guest looks like a brand-new user
~~~

Without a recovery path, the easiest thing for the guest to do is request another ride.

That creates two problems at once:

- **The guest may lose visibility into a ride that is already on the way.**
- **The system may end up with two active ride requests for one person.**

The second problem matters beyond the guest. A duplicate request can take another place in the queue, consume driver capacity, and make dispatch less predictable for everyone else.

## Why I chose anonymous booking anyway

The answer was not to make every guest create an account.

That would solve the technical problem by adding friction to the product's most important moment: getting someone from "I need a ride" to "my ride is requested." I wanted people to use the product quickly and with as little hassle as possible so I could learn from real usage and improve the experience.

I made a deliberate tradeoff:

> **Keep booking nearly frictionless, then give the guest a small, deliberate way to recover an active ride if their temporary identity changes.**

The recovery mechanism needed to be:

- easy enough that a guest could use it without support
- strong enough that someone nearby could not simply guess their ride
- limited to rides that are still active
- handled by the server rather than trusted to the phone
- careful not to expose whether a ride exists unless the full recovery information is provided

## The experience

The recovery experience starts only when two things are true:

1. The app cannot find an active ride for the current temporary identity.
2. The device remembers that it previously had an active ride.

The second signal is only a **hint**. It is not proof that a ride still exists.

~~~text
Phone remembers:
"I had a ride."

              ↓

Server decides:
"Does an active ride matching this code actually exist?"
~~~

If the local hint is present, the guest sees:

### Looking for your ride?

> If you already requested a ride, we can help you find it.

**Find My Ride**

*You'll just need your 6-digit backup code.*

Or, if they intentionally want to start over:

**Request New Ride**

There is no scary warning about authentication, user IDs, reinstalling, or "orphaned" bookings. Those are implementation details, not the guest's problem.

~~~mermaid
flowchart TD
    A[App opens] --> B[Create or restore temporary identity]
    B --> C{Active ride found?}
    C -->|Yes| D[Resume ride]
    C -->|No| E{Device remembers a previous active ride?}
    E -->|No| F[Start a new ride]
    E -->|Yes| G[Looking for your ride?]
    G --> H[Enter 6-digit backup code]
    H --> I[Server checks code + venue + active status]
    I -->|Valid| J[Reconnect booking to new identity]
    J --> K[Resume existing ride]
    I -->|Not valid| L[Generic failure message]
    L --> H
    G -->|Request New Ride| F
~~~

## Why a backup code instead of the ticket number?

The app already gives the guest a 6-digit backup code with their ride.

I deliberately used that existing artifact instead of making the guest enter the visible ticket number.

The ticket number is designed for queueing. It is sequential and therefore predictable.

The backup code is a separate, randomly generated 6-digit value. It is a better recovery credential because it is not simply the next number in a public sequence.

But a 6-digit code is not treated as magically secure.

The design adds additional guardrails:

- only active rides can be recovered
- recovery is scoped to the selected venue
- recovery requires the complete code
- attempts are rate-limited
- partial matches are never revealed
- a failed lookup returns a generic response
- recovery is performed by the backend
- the booking is changed inside a transaction
- a second device cannot silently take ownership of the same recovered ride

The goal was not "make the code impossible to guess."

The goal was **make a small recovery credential useful without turning it into an unrestricted lookup mechanism.**

## What happens when recovery succeeds?

The server changes the booking's owner from the old temporary identity to the guest's new temporary identity.

Nothing else about the ride needs to be recreated.

That means the guest keeps the same:

- ride request
- place in the queue
- destination
- assigned driver, if one already exists
- current ride status

~~~text
Old booking
    │
    ├── NOT cancelled
    ├── NOT recreated
    ├── NOT removed from the queue
    └── NOT copied into a second booking

              ↓

        Existing booking
              │
              ↓
       New temporary identity
~~~

## The security decision that mattered most

The recovery lookup happens on the backend.

The phone does **not** get to directly search the database for a matching code and then decide which ride it belongs to.

That keeps the important decisions in one place:

~~~text
Guest's phone
     │
     │ venue + 6-digit code
     ↓
Backend
     │
     ├── Is the request authenticated?
     ├── Is the input valid?
     ├── Has this caller used up its attempt budget?
     ├── Does the code match this venue?
     ├── Is the ride still active?
     ├── Does this guest already have another active ride?
     ├── Has another device already recovered it?
     │
     ↓
Atomic update
     │
     └── Reconnect booking to the new identity
~~~

That separation is what lets the UI stay simple without making the backend simple-minded.

## The concurrency problem

Imagine the guest reinstalls the app on two phones and both phones try the same recovery code at nearly the same time.

Without protection:

~~~text
Phone A ──┐
          ├──> same booking <──┐
Phone B ──┘                    │
                               │
                    last write wins
~~~

That is not a good recovery model.

The backend instead performs the ownership change inside a database transaction and records that the booking has already been recovered.

The desired invariant is:

> **One active booking can only be recovered once.**

The losing request receives the same generic failure style rather than being told that another device has already recovered the booking. That matters for privacy as well as correctness.

## The double-booking guard

I also considered a less obvious sequence:

~~~text
Reinstall
   ↓
New temporary identity
   ↓
Guest requests another ride
   ↓
Guest later tries to recover the original ride
~~~

The safe answer is not to silently cancel either ride.

If the new identity already has another active ride, recovery is blocked and the guest is told to deal with the existing ride first.

That preserves user agency and avoids a backend decision that could accidentally delete a legitimate booking.

## Observability

A recovery flow is not finished just because it works.

I added structured events for the important outcomes, including:

- recovery eligibility shown
- recovery attempted
- recovery succeeded
- invalid recovery code
- recovery failed
- recovery rate-limited
- recovery blocked because another active ride already exists
- recovery latency
- venue mismatch

This gives the product a way to answer a question that otherwise would be impossible:

> **Are guests actually getting stranded, or is the recovery path simply never being needed?**

It also makes a future regression visible. If recovery attempts suddenly increase after an authentication change, that is a signal that something upstream may have changed.

## A small UX decision with a big purpose

I also added an optional **Save Pass** action to the ride confirmation experience.

It saves a simple digital pass containing the ride's QR code and backup code.

This was intentionally positioned as a convenience, not as a warning:

**Save Pass**

rather than:

**Save this in case the app breaks.**

No scary message. No mandatory step. No interruption.

The recovery system remains the safety net; saving the pass simply makes the recovery artifact easier to keep.

## What I actually built

The feature crossed the frontend and backend rather than living in a single screen.

### Frontend

The app:

- remembers only a small "previously had an active ride" signal locally
- checks the current temporary identity for an active booking
- routes eligible guests into recovery
- provides a dedicated 6-digit entry experience
- handles loading, success, invalid code, rate-limit, existing-ride, and terminal states
- restores the ride into the normal confirmation experience after success
- keeps the interface free of backend terminology

### Backend

The server:

- authenticates the recovery request
- validates the venue and code
- limits repeated attempts
- searches only eligible active rides
- prevents cross-venue matches
- prevents conflicting active bookings
- rechecks the booking inside a transaction
- reconnects the existing booking to the new temporary identity
- records recovery outcomes for later analysis

### Testing

The backend behavior was tested against the Firestore emulator rather than only checking that the function returned the expected object.

The test suite verifies, among other things:

- successful ownership recovery
- wrong-code behavior
- cross-venue isolation
- rate limiting
- existing active-booking protection
- idempotent recovery when the current owner retries
- terminal-state behavior
- preservation of unrelated booking fields

The dangerous bugs here are not "does the button work?" They are:

> **Did we accidentally change the wrong booking?**

> **Did we leak information about another guest's ride?**

> **Can two devices take the same ride?**

> **Did recovery accidentally create a second booking?**

## By the numbers

- **1** existing ride is recovered rather than recreated.
- **6** digits are used for the recovery code.
- **5 attempts** are allowed within the recovery window before rate limiting.
- **2 layers** decide whether recovery should even be offered: a local hint and a server-authoritative check.
- **0** booking records need to be duplicated to restore the ride.

The most important number, though, is **one**:

> **One active booking should remain one active booking, even when the guest's temporary identity changes.**

## What I learned

The interesting part of this feature was not generating a 6-digit code or building a six-box input.

It was deciding **where trust belongs**.

The phone can remember a hint.

The guest can provide a recovery code.

But only the server can decide whether an active ride exists, whether it can be recovered, and whether the ownership change is safe.

That let me keep the front door of the product simple — no account creation just to request a ride — without pretending that convenience removes the need for recovery, privacy, or concurrency controls.

## Code Sketch

<details>
<summary><b>Show the recovery decision in simplified code</b></summary>

<br>

*This is a simplified illustration for this case study, not a copy of the production function.*

~~~ts
const ACTIVE_STATUSES = [
  "pending",
  "awaiting-driver",
  "assigned",
  "in-progress",
  "scan-failed",
];

async function recoverRide(callerUid, venueId, backupCode) {
  if (!/^\d{6}$/.test(backupCode)) {
    return { success: false, reason: "NOT_FOUND" };
  }

  if (await rateLimitExceeded(callerUid)) {
    return { success: false, reason: "RATE_LIMITED" };
  }

  const candidate = await findActiveRide(venueId, backupCode);
  if (!candidate) {
    return { success: false, reason: "NOT_FOUND" };
  }

  return firestore.runTransaction(async (tx) => {
    const booking = await tx.get(candidate.ref);

    if (!booking.exists || alreadyRecovered(booking)) {
      return { success: false, reason: "NOT_FOUND" };
    }

    if (await callerAlreadyHasAnotherActiveRide(tx, callerUid)) {
      return { success: false, reason: "ALREADY_HAS_ACTIVE_BOOKING" };
    }

    tx.update(candidate.ref, {
      userID: callerUid,
      updatedAt: serverTimestamp(),
    });

    return {
      success: true,
      bookingID: candidate.id,
      rideStatus: booking.data()?.rideStatus,
    };
  });
}
~~~

The code is intentionally boring.

That is a good thing.

The interesting product work was deciding **what the function is allowed to do**, what it must never reveal, and which parts of the ride must remain untouched.

</details>
