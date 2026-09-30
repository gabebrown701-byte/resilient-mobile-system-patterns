# Code Sketch: The Garage Cap Rule

*A companion to [When You Can't Serve Everyone at Once, Who Waits?](README.md). This is a simplified illustration written for this write-up. It is not production code, and it leaves out the data model, queries, configuration, and monitoring around the real thing.*

## Where it fits

The case study describes three garage states: Normal, Limited, and Paused. This sketch covers the Limited state, where a cap on active rides decides who gets served this round and who waits. Paused is handled earlier, when a booking is created, so it never reaches this check.

## The rule

```ts
type Mode = "normal" | "limited" | "paused";

interface Garage {
  mode: Mode;
  cap: number;         // most active rides allowed at the garage at once
  activeCount: number; // rides currently active to or from the garage
}

interface RideRequest {
  vehiclesAssigned: number; // 0 means brand new, more than 0 means partly served
}

// Decide whether the dispatcher may work on this request in this round.
// Returning false does not reject the request. It stays in the queue,
// keeps its place, and is looked at again next round.
function canDispatch(request: RideRequest, garage: Garage): boolean {
  // Normal needs no limits. Paused is enforced earlier, at booking time.
  if (garage.mode !== "limited") return true;

  // A party that already holds a slot must be allowed to finish. If the cap
  // blocked it, a large party could wait forever for its second vehicle
  // because its own first ride counts against the limit.
  const isPartlyServed = request.vehiclesAssigned > 0;
  if (isPartlyServed) return true;

  // Only brand new requests are held back once the cap is reached.
  return garage.activeCount < garage.cap;
}
```

## How it connects to the case study

- **"It just waits for the next round."** A `false` result never cancels anything. The request keeps its spot in line and gets reconsidered next round, which is what keeps this fair across a whole busy period and not only in one moment.
- **Parties that need more than one vehicle.** This is the part the case study does not spell out. Some parties are too big for one vehicle, so they are served in pieces. Once the first vehicle is assigned, that party is already counted against the cap. If the cap applied to it again, a party of twelve could sit at the limit forever, waiting for a second vehicle that its own first ride is blocking. So the cap only applies to brand new requests. Anything already in motion is allowed to finish.

## The test

```ts
const atCap: Garage = { mode: "limited", cap: 2, activeCount: 2 };

test("holds a new request when the garage is at its cap", () => {
  assert.equal(canDispatch({ vehiclesAssigned: 0 }, atCap), false);
});

test("lets a new request through while under the cap", () => {
  assert.equal(canDispatch({ vehiclesAssigned: 0 }, { ...atCap, activeCount: 1 }), true);
});

test("lets a partly served party get its next vehicle even at the cap", () => {
  assert.equal(canDispatch({ vehiclesAssigned: 1 }, atCap), true);
});

test("applies no limit in Normal mode", () => {
  assert.equal(canDispatch({ vehiclesAssigned: 0 }, { ...atCap, mode: "normal" }), true);
});
```

The third test is the one that matters. It protects the exact situation that would otherwise deadlock.

## A choice I made on purpose

The real check depends on counting how many rides are active at the garage. If that count ever fails, I let that one round run without the cap instead of holding up every guest. A briefly uncapped garage is a smaller problem than a stalled queue, so I chose to fail open.
