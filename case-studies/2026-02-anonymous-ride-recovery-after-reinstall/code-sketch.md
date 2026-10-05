# Code Sketch: Recovering an Existing Ride

This sketch is deliberately smaller than the production implementation.

~~~text
Does this guest have an active ride we can safely reconnect?

          ┌──────────────────────────┐
          │ Current temporary user   │
          └────────────┬─────────────┘
                       │
                       ▼
             ┌───────────────────┐
             │ 6-digit code      │
             │ + venue           │
             └─────────┬─────────┘
                       │
                       ▼
             ┌───────────────────┐
             │ Server checks     │
             │ active ride       │
             └─────────┬─────────┘
                       │
              ┌────────┴────────┐
              │                 │
             No                Yes
              │                 │
              ▼                 ▼
       Generic failure      Transaction
                              │
                              ▼
                       Reconnect owner
                              │
                              ▼
                         Resume ride
~~~

## Why the transaction matters

A transaction makes the ownership change conditional on the booking still being in the state we expected when we checked it.

That matters when another operation is happening at the same time.

## The important invariants

1. **Recovery never creates a second ride.**
2. **Only active rides are eligible.**
3. **The venue must match.**
4. **The caller must be authenticated.**
5. **Repeated attempts are limited.**
6. **A recovery attempt cannot reveal partial information about another ride.**
7. **Two devices cannot both successfully take ownership of the same recovered ride.**
8. **Unrelated booking fields are left alone.**

## What the tests prove

The production backend test suite exercises the real handler against the Firestore emulator and reads the database after each operation.

| Scenario | Expected behavior |
|---|---|
| Correct code | Existing booking is rebound to the caller |
| Wrong code | Generic NOT_FOUND; booking unchanged |
| Code belongs to another venue | Generic NOT_FOUND; no cross-venue details |
| Caller already has another active ride | Recovery blocked; target booking unchanged |
| Sixth attempt inside the rate-limit window | RATE_LIMITED; target booking unchanged |
| Same caller retries after successful recovery | Idempotent success; no second mutation |
| Completed/cancelled ride | Not recoverable |

The last point is particularly important: product intent and implementation should not drift silently. If terminal-state behavior changes later, the tests should change with it.

## A small implementation detail worth preserving

The client stores only a boolean-like signal that it previously had an active ride.

It does **not** store:

- the booking ID
- the ride's destination
- the driver's information
- the user's old authentication ID
- the ride's full record

That keeps local persistence intentionally weak.

The server remains the source of truth.