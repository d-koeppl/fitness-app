# ADR-039 — The zones' max heart rate is the highest one recorded

**Status:** Accepted · **Date:** 2026-09-28
**Amends:** ADR-020 in fitness-dashboard (where max HR comes from)

## Context

The zone boundaries are Karvonen bands from a resting and a maximum heart
rate. Resting HR is measured every night. Max HR had to be configured
(`HEALTH_MAX_HR_BPM`, or `HEALTH_BIRTH_YEAR` for 220 − age), and in
production neither was set, so no session chart had zones.

The stored traces already hold the answer. The highest reading across all
of them on 2026-09-27 was 191 bpm, in the match on 2026-09-20, held over
several readings. A heart that reached 191 has a maximum of at least 191.

## Decision

- The sync records the highest heart rate any trace reached in
  `meta/max_hr` (`bpm`, the session it came from, when it was raised). It
  only ever goes up, and it is raised in a transaction so two syncs
  storing traces at once cannot lower it.
- A trace's peak is the highest bpm it **held for two consecutive
  readings** (`analysis/heart_rate.py::sustained_peak`). A single spike is
  what an optical sensor does when a strap slips. Counting it would move
  every zone boundary up for good, with nothing to bring it back down.
- The first sync with nothing on record seeds it from every trace ever
  stored, so the history counts without a migration step.
- The zones use the higher of the recorded max and the configured one
  (`services/heart_rate.py::max_heart_rate`). A recorded peak is a lower
  bound, so a configured number below it is out of date. A configured
  number above it, such as a ramp test, still wins.

## Consequences

- Zones appear on every chart as soon as one workout with readings is
  synced, and they shift when a workout goes higher, with no setting to
  edit.
- A spike held for two readings still counts. If one ever does, set
  `meta/max_hr.bpm` back by hand; later syncs only raise it from there.
  Deleting the document would not help, because the re-seed would find
  the same spike.
- A training peak is usually a few beats under a true lab maximum, so the
  bands sit slightly low until a hard enough session raises them. That is
  the same error an unmeasured setting had, and it corrects itself.
