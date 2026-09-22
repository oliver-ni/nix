"""Print the Twitch URL of the best live LoL Esports match, or nothing."""

import json
import sys
import urllib.request

API = "https://esports-api.lolesports.com/persisted/gw/getLive?hl=en-US"
# Public key embedded in lolesports.com's frontend.
API_KEY = "0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z"

# Lower is better. Unlisted leagues rank after these.
LEAGUE_RANK = {
    "worlds": 0,
    "msi": 1,
    "first_stand": 2,
    "lck": 10,
    "lpl": 11,
    "lec": 12,
    "lta_n": 13,
    "lta_s": 14,
    "lcp": 15,
}
LOCALE_RANK = {"en-US": 0, "en-GB": 1, "en-AU": 2}


def main():
    req = urllib.request.Request(API, headers={"x-api-key": API_KEY})
    with urllib.request.urlopen(req, timeout=15) as r:
        events = json.load(r)["data"]["schedule"]["events"]

    candidates = []
    for e in events:
        if e.get("type") != "match" or e.get("state") != "inProgress":
            continue
        streams = [s for s in e.get("streams", []) if s.get("provider") == "twitch"]
        if not streams:
            continue
        streams.sort(key=lambda s: LOCALE_RANK.get(s.get("locale", ""), 50))
        league = e.get("league", {}).get("slug", "")
        candidates.append((LEAGUE_RANK.get(league, 100), e, streams[0]))

    if not candidates:
        return 1
    candidates.sort(key=lambda c: c[0])
    _, event, stream = candidates[0]
    teams = " vs ".join(t.get("code", "?") for t in event.get("match", {}).get("teams", []))
    print(f"https://www.twitch.tv/{stream['parameter']}")
    print(f"{event['league']['name']} | {event.get('blockName', '')} | {teams} | {stream.get('locale')}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
