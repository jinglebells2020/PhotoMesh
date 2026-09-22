#!/usr/bin/env python3
"""Analytics report from the collector's event files (no database needed).

Reads <raw>/installs/*/events/*.jsonl and <raw>/installs/*/samples/*.json.
"""
import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


def load_events(raw: Path, since: datetime):
    for path in raw.glob("installs/*/events/*.jsonl"):
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = event.get("timestamp") or event.get("receivedAt") or ""
            try:
                when = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            except ValueError:
                continue
            if when >= since:
                event["_when"] = when
                yield event


def table(title, rows, headers):
    print(f"\n{title}")
    widths = [max(len(str(h)), *(len(str(r[i])) for r in rows)) if rows else len(str(h)) for i, h in enumerate(headers)]
    print("  " + "  ".join(str(h).ljust(w) for h, w in zip(headers, widths)))
    for r in rows:
        print("  " + "  ".join(str(v).ljust(w) for v, w in zip(r, widths)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", default="data/raw")
    parser.add_argument("--days", type=int, default=30)
    args = parser.parse_args()
    raw = Path(args.raw)
    since = datetime.now(timezone.utc) - timedelta(days=args.days)

    events = list(load_events(raw, since))
    installs = {e.get("installId") for e in events}
    by_name = Counter(e.get("name") for e in events)
    per_day = defaultdict(Counter)
    recognition = defaultdict(list)
    feedback = []
    survey = []
    credits = Counter()
    credit_awards = Counter()
    sessions = []
    funnel = Counter()
    for e in events:
        p = e.get("properties") or {}
        day = e["_when"].date().isoformat()
        name = e.get("name")
        per_day[day][name] += 1
        per_day[day]["_installs"] = 0
        if name == "recognition":
            recognition[(p.get("model"), p.get("tier"), p.get("outcome"))].append(p.get("ms") or 0)
        elif name == "feedback":
            feedback.append(p)
        elif name == "survey":
            survey.append(p)
        elif name == "credits_earned":
            credits[p.get("reason")] += p.get("credits") or 0
            credit_awards[p.get("reason")] += 1
        elif name == "app_background" and p.get("active_seconds") is not None:
            sessions.append(p["active_seconds"])
        elif name in ("plus_gate", "paywall_shown", "purchase_started", "purchase_completed", "purchase_failed", "purchase_restored"):
            funnel[name] += 1
    day_installs = defaultdict(set)
    for e in events:
        day_installs[e["_when"].date().isoformat()].add(e.get("installId"))

    print(f"Photocircuits report: last {args.days} days, {len(events)} events from {len(installs)} installs")
    table("Events by name", [(n, c) for n, c in by_name.most_common()], ["event", "count"])
    table("Per day", [(d, len(day_installs[d]), c.get("app_open", 0), c.get("recognition", 0), c.get("solve", 0), c.get("solve_failed", 0), c.get("feedback", 0))
                      for d, c in sorted(per_day.items())], ["day", "installs", "opens", "recognitions", "solves", "failed", "feedback"])
    table("Recognition", [(m or "?", t or "?", o or "?", len(ms), round(statistics.mean(ms)) if ms else 0)
                          for (m, t, o), ms in sorted(recognition.items(), key=lambda kv: -len(kv[1]))], ["model", "tier", "outcome", "n", "avg ms"])

    samples = []
    for path in raw.glob("installs/*/samples/*.json"):
        try:
            s = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
        samples.append(s)
    corrected = [s for s in samples if s.get("corrected")]
    dominant = Counter((s.get("diff") or {}).get("dominant", "unknown") for s in corrected)
    print(f"\nScans shared: {len(samples)} total, {sum(1 for s in samples if s.get('accepted'))} accepted, {len(corrected)} corrected")
    table("What corrections change", [(k, n) for k, n in dominant.most_common()], ["dominant change", "count"])

    helpful = sum(1 for f in feedback if f.get("helpful") is True)
    print(f"\nFeedback: {len(feedback)} ratings, {helpful} helpful ({100 * helpful / max(1, len(feedback)):.0f}%)")
    reasons = Counter()
    for f in feedback:
        if f.get("helpful") is False:
            for r in str(f.get("reasons") or "").split("|"):
                if r:
                    reasons[(r, f.get("method"))] += 1
    table("Why it did not help", [(r, m, n) for (r, m), n in reasons.most_common(12)], ["reason", "method", "count"])
    comments = [(f.get("method"), f.get("comment")) for f in feedback if f.get("comment")]
    if comments:
        print("\nLatest comments")
        for method, comment in comments[-10:]:
            print(f"  [{method}] {comment}")

    if survey:
        roles = Counter(s.get("role") for s in survey)
        nps_values = [s.get("nps") for s in survey if isinstance(s.get("nps"), (int, float))]
        promoters = sum(1 for n in nps_values if n >= 9)
        detractors = sum(1 for n in nps_values if n <= 6)
        nps = 100 * (promoters - detractors) / max(1, len(nps_values))
        print(f"\nSurvey: {len(survey)} answers, NPS {nps:.0f} (avg {statistics.mean(nps_values):.1f})" if nps_values else f"\nSurvey: {len(survey)} answers")
        table("Who answers", [(r, n) for r, n in roles.most_common()], ["role", "count"])
        uses = Counter(u for s in survey for u in str(s.get("uses") or "").split("|") if u)
        table("What they use it for", [(u, n) for u, n in uses.most_common()], ["use", "count"])
        wishes = [s.get("wish") for s in survey if s.get("wish")]
        if wishes:
            print("\nWishes")
            for w in wishes[-10:]:
                print(f"  - {w}")

    table("Bonus scans", [(r, credit_awards[r], credits[r]) for r in credits], ["reason", "awards", "credits"])
    if funnel:
        table("Plus funnel", [(k, funnel[k]) for k in ("plus_gate", "paywall_shown", "purchase_started", "purchase_completed", "purchase_failed", "purchase_restored") if funnel[k]], ["step", "count"])
    if sessions:
        print(f"\nSessions: {len(sessions)}, median {statistics.median(sessions):.0f} s active, mean {statistics.mean(sessions):.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
