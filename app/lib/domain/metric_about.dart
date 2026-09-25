// What each metric means, in the user's own terms — the copy behind the
// "What this is" panel in every detail sheet. Generated verbatim from
// fitness-dashboard's web/lib/metric-about.ts, whose header explains the
// three questions and why `source` is the one that goes stale: when the
// calculation in api/analysis/training_load.py or the field read in
// api/integrations/google_health.py changes, this text changes with it.
//
// A switch over MetricKey rather than a map, so a new metric does not
// compile until someone has written its explanation.

import 'key_metrics.dart';

class MetricAbout {
  const MetricAbout({required this.what, required this.read, required this.source});

  /// What the number is a measurement of.
  final String what;

  /// How to read a value, and what a change in it is worth.
  final String read;

  /// Which device or calculation produced it, and against what.
  final String source;
}

MetricAbout metricAbout(MetricKey key) => switch (key) {
  MetricKey.restingHr => const MetricAbout(
    what: 'Your lowest sustained heart rate, measured by the watch overnight while you were asleep and still — one value per night.',
    read: 'Read it against your own normal rather than anyone else\'s. A slow drift downwards over weeks is aerobic fitness improving. A jump of three to five beats above your usual — especially with HRV down on the same night — is the familiar sign of a hard day not yet absorbed, a short night, alcohol, or something coming on.',
    source: 'Taken straight from the watch through the Google Health API (daily resting heart rate) and stored as reported; nothing here recalculates it. It also carries 30% of the weight in Readiness and Recovery.',
  ),
  MetricKey.hrvMs => const MetricAbout(
    what: 'The average variation in the gap between heartbeats overnight, in milliseconds. It tracks which half of your nervous system had the upper hand while you slept — more variation means the resting side did.',
    read: 'The absolute number means nothing between people and not much on its own: yours has ranged from roughly 29 to 113 ms on ordinary nights. Only the comparison against your own recent baseline says anything. Above baseline means the load landed well; several nights clearly below it means you are still paying for it. One night is noise, a week is a signal.',
    source: 'Measured by the watch overnight and read through the Google Health API (daily heart rate variability, averaged over the night). It is the biggest single input to Readiness and Recovery, at 50% of the weight.',
  ),
  MetricKey.steps => const MetricAbout(
    what: 'Every step the watch counted between midnight and midnight.',
    read: 'This is how much you moved, not how hard — a 12,000-step day of walking around and a brutal hour on the pitch are worlds apart in training terms, and steps cannot tell them apart. The goal line is 10,000 a day. It is most useful for catching easy days that quietly turned into sedentary ones.',
    source: 'Google Health\'s own pre-aggregated daily total, one number per day. Deliberately not part of the training load: that runs on Active Zone Minutes instead, so that intensity counts for something.',
  ),
  MetricKey.sleepMinutes => const MetricAbout(
    what: 'Time actually asleep, not time in bed — the awake stretches inside the night are subtracted, so this reads lower than the hours you spent lying down.',
    read: 'Everything here scores sleep against an eight-hour target. One short night mostly shows up as tomorrow\'s Readiness; a run of them starts bending HRV and resting heart rate too. Switch to the weekly view before drawing conclusions, since a single late match night drags one day a long way.',
    source: 'The watch\'s sleep session through the Google Health API, summing the light, deep and REM stages and dropping AWAKE. A night is filed under the day you woke up, converted to local time, so it lines up with what the Google Health app shows you. Worth 20% of Readiness and Recovery.',
  ),
  MetricKey.weightKg => const MetricAbout(
    what: 'Body weight in kilograms, as your scale reported it — the average of that day\'s readings when there was more than one.',
    read: 'A kilo of movement between two days is water, food and timing, not fat. Switch the range to monthly and read that line instead: over four weeks the direction is real, over two days it is not.',
    source: 'Google Health\'s daily weight roll-up, which arrives in grams and is divided by a thousand here. Whichever scale or app writes weight into Google Health is the actual source. Nothing smooths it. The days you did not weigh yourself stay empty in the chart and the list below, but anywhere a current weight is shown — the Today tile, the Health card, the daily report and the coach — it is your last reading, labelled with the day it was taken.',
  ),
  MetricKey.vo2max => const MetricAbout(
    what: 'The watch\'s estimate of your maximum oxygen uptake, in millilitres of oxygen per kilogram per minute. It is the standard one-number summary of aerobic capacity.',
    read: 'An estimate, not a lab test, and it moves in weeks rather than days — a change of less than a point is noise. Rising through a block of training means the engine is getting bigger. A drop usually follows a lay-off, an illness, or a stretch of nothing but short sessions.',
    source: 'Calculated by Fitbit/Google from heart rate against pace on your tracked runs, and read through the Google Health API (daily VO2 max). Shown exactly as reported — this dashboard never estimates it itself. It only lands on the days the watch re-estimates, so, like weight, the tile and the card show your last reading with the day it came from while the chart leaves the gap.',
  ),
  MetricKey.readiness => const MetricAbout(
    what: 'A 0–100 answer to one question: how well did you recover last night? It looks at last night only, which is what makes it react to the day you have just had.',
    read: 'It is graded against your own previous 28 days, so around 50 means “a normal night for you” rather than “average for a person”. High says the hard session landed and today can be hard too. Low for two or three days running is the moment to ease off. It is the same idea as Google Health\'s Tagesform index and usually lands close to it.',
    source: 'Computed here, not read from the watch: a weighted blend of your own numbers against a 28-day baseline that excludes the night being scored. HRV counts 50% (40% above your baseline scores 100, 40% below scores 0), resting heart rate 30% (10% below baseline scores 100, 10% above scores 0), and sleep 20%, as a share of the eight-hour target. Anything missing drops out and the rest are re-weighted. Needs about 14 days of history before it means anything.',
  ),
  MetricKey.recovery => const MetricAbout(
    what: 'The same 0–100 recovery index as Readiness, but built from the last three nights instead of one — the slower, steadier read on how well your body is absorbing training.',
    read: 'Use it for the shape of the week, not for today\'s session. It is deliberately hard to move, so one bad night barely dents it and a real dip means something. The flip side is that it lags: one unusually good night keeps it propped up for two more days, which is exactly why Readiness exists alongside it. The training status reads it directly too — below 40 it calls you strained no matter what the load says.',
    source: 'The same calculation as Readiness — HRV 50%, resting heart rate 30%, sleep 20%, each against your own 28-day baseline. The only difference is what counts as “now”: three nights here, one there.',
  ),
  MetricKey.fitness => const MetricAbout(
    what: 'Your long-run training load, in Active Zone Minutes per day — what your body has come to expect from an average day over the last several weeks.',
    read: 'This is the number that represents actual aerobic base, and it only moves with consistency: a single huge session barely nudges it, and two weeks off visibly drains it. Rising slowly is what a good block looks like. For scale, holding it near 21 is roughly the WHO\'s 150 moderate minutes a week.',
    source: 'An exponentially weighted average of daily load with a 42-day time constant — Banister\'s impulse-response model, the same maths behind Garmin\'s version. Usually called a “42-day average”, but the weighting decays smoothly rather than cutting off, so a hard session fades instead of dropping out of a window overnight. Computed here over your whole history, never over just the stretch on screen.',
  ),
  MetricKey.fatigue => const MetricAbout(
    what: 'The same daily load, averaged over a much shorter horizon — roughly what the last week has done to you.',
    read: 'It moves fast in both directions: a heavy weekend spikes it, and a few easy days bring it straight back down. On its own it is neither good nor bad. It only means something next to Fitness, which is what Form measures — Fatigue above Fitness is the normal price of building.',
    source: 'The same exponentially weighted average as Fitness, with a 7-day time constant instead of 42. Same input, same maths, shorter memory.',
  ),
  MetricKey.form => const MetricAbout(
    what: 'Fitness minus Fatigue, in the same Active Zone Minutes per day. Negative means the recent week has been heavier than your baseline; positive means you are carrying less fatigue than fitness.',
    read: 'Read it on the standard bands: below −30 is overreaching, −10 to −30 is a productive block, −10 to +10 is holding steady, and above +10 you are fresh, with above +25 properly tapered. Deeply negative is not a failure — it is what building looks like — but it is not where you want to be on a match day.',
    source: 'Derived here from the two averages, one day at a time. The API reports Form only as today\'s headline number, so the chart recomputes the gap for each day rather than inventing a series the backend does not send. The bands above are absolute, not a share of Fitness: measured on this user\'s own history, a 42-day mean load around 55 sits in the range those bands were written for.',
  ),
};

/// The training-load sheet charts three series at once, so it is not a
/// MetricKey, but it wears the same panel.
const trainingLoadAbout = MetricAbout(
  what: 'Three numbers in one unit, Active Zone Minutes. Load is what a day cost you, Fitness is your long-run average of it, Fatigue is your short-run average of it, and the gap between those two is Form.',
  read: 'Fitness climbs slowly and fades slowly; Fatigue does both quickly. While Fatigue sits above Fitness you are building — productive, and tired with it. When Fitness pulls more than about 10 ahead you are fresh, and past 25 you are properly tapered. For scale, holding Fitness near 21 is roughly the WHO\'s 150 moderate minutes a week.',
  source: 'Load is the day\'s Active Zone Minutes from the watch: one point per minute in the moderate heart-rate zone, two in vigorous or peak, added up across every session it tracked. A match or training the watch missed is added on top as an estimate — your logged ÖFB minutes or a 90-minute training block, priced at the Active Zone Minutes per minute your own recent matches and sessions actually averaged. It only counts as recorded, and so stops being estimated, if a tracked session started with it: from half an hour before to two hours after. Fitness and Fatigue are exponentially weighted averages of Load with 42-day and 7-day time constants — Banister\'s impulse-response model, the same maths behind Garmin\'s version — run over your entire history.',
);

/// Beers are the one number here a person types in rather than a device
/// recording it. Same panel, same three questions.
const beerAbout = MetricAbout(
  what: 'Half-litre beers, one per tap of the counter on the Today tab, counted per day. Inside the record a day with nothing on it is a day with no beers — unlike every other chart here, where an empty day means the watch had nothing to say. The chart starts at the first beer ever logged, because a day before that is one nobody could have logged a beer on, and it is drawn as the gap it is.',
  read: 'One 0.5 L beer is about 20 g of alcohol, so the litres under the count are the useful half of it. The daily view is what you actually drank; the weekly and monthly views are beers per day, averaged, which is the number that says whether a habit is drifting. Read it beside resting heart rate, HRV and sleep on the same nights — that is the whole reason it is recorded.',
  source: 'Entirely self-reported: nothing measures this. A beer lands on the day it was tapped in, or on the day you chose if you filled it in afterwards — any day back, however old, while today\'s beers belong to the counter on the Today tab. The day boundary is local midnight — so a beer at half past midnight belongs to the new day, the same as every other daily number here. The daily report reads the last fortnight of it and the coach can ask for more. A forgotten round is invisible until someone fills that day in, and a day entered a week late is a memory rather than an observation: treat a low count as the weaker evidence.',
);

/// A single tracked session is not a metric with a series, but the
/// questions it has to answer are the same three.
const exerciseAbout = MetricAbout(
  what: 'One workout the watch tracked, on its own: when it started, how long it ran, and the numbers it recorded while it did. These are the sessions that add up to a day\'s training load.',
  read: 'Active Zone Minutes is the one to read first — it is the load unit, so it says what this session cost you rather than how long it lasted. One point per minute in the moderate heart-rate zone, two in vigorous or peak, which is why a short hard session can outscore a long easy one. Average heart rate is the sanity check on it, and the trace under it is the shape behind both — a steady hour and a session of hard intervals can average the same 149 bpm.',
  source: 'Recorded by the watch and read through the Google Health API\'s per-session exercise data. The session is filed under the day it started in local time — the same day its Active Zone Minutes were counted into. Beyond duration, Active Zone Minutes and average heart rate, whatever else Google recorded for the session is shown as-is under its own name, because which fields a session carries depends on the activity. The heart rate trace is fetched per session, a few at a time and newest first, so a session opened right after a sync may not have one yet. Its zone colours are the one thing here that was not measured: the API reports the minutes spent in each zone but not the beats they start at, so the boundaries are worked out from your resting heart rate and your maximum — with no maximum configured the trace is drawn plain rather than coloured against a guess. A session marked “not tracked” is one the watch missed: it comes from your match log or your calendar, and its load is estimated from its minutes at the rate your recent tracked sessions of that kind ran at. It only counts as recorded if a tracked session started with it — from half an hour before to two hours after — so a morning walk does not cancel the estimate for an evening training, and the day is worth both. Mark one skipped and it stops counting.',
);
