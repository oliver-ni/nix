"""Grab fresh discounted private-tracker releases onto the seedbox slot for ratio.

TRACKERS maps a qBittorrent category to the Prowlarr indexer that feeds it, one
per tracker so each site's hit-and-run obligations stay in their own category.
One run: delete torrents in those categories that have seeded long enough or
uploaded enough and are not among the last seeders, drop downloads that never
got going, then ask Prowlarr for each tracker's newest releases and add the
ones worth seeding. Each tracker and each grab is independent; a failure is
logged and the run moves on. Info hashes already handled are kept in
STATE_DIRECTORY so a deleted or skipped torrent is not considered again.
"""

import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

env = os.environ
GB = 1e9

PROWLARR_URL = env["PROWLARR_URL"]
QBITTORRENT_URL = env["QBITTORRENT_URL"]
QBITTORRENT_PREFERENCES = json.loads(env["QBITTORRENT_PREFERENCES"])
TRACKERS = json.loads(env["TRACKERS"])
DOWNLOADS = env["DOWNLOADS"]
SEED_TIME = timedelta(minutes=int(env["SEED_MINUTES"]))
DONE_RATIO = float(env["DONE_RATIO"])
MIN_OTHER_SEEDERS = int(env["MIN_OTHER_SEEDERS"])
MAX_AGE = timedelta(hours=float(env["MAX_AGE_HOURS"]))
MAX_SIZE = float(env["MAX_SIZE_GB"]) * GB
MAX_TOTAL = float(env["MAX_TOTAL_GB"]) * GB
MAX_DOWNLOAD_FACTOR = float(env["MAX_DOWNLOAD_FACTOR"])
STALL_TIME = timedelta(hours=float(env["STALL_HOURS"]))
CREDENTIALS = Path(env["CREDENTIALS_DIRECTORY"])
STATE = Path(env["STATE_DIRECTORY"]) / "grabbed.json"

# Prowlarr reports the tracker's discount as flags, not as a factor.
DOWNLOAD_FACTOR = {
    "freeleech": 0.0,
    "freeleech75": 0.25,
    "halfleech": 0.5,
    "freeleech25": 0.75,
}

qb = requests.Session()
qb.auth = tuple((CREDENTIALS / "qbittorrent-auth").read_text().strip().split(":", 1))
prowlarr = requests.Session()
prowlarr.headers["X-Api-Key"] = (CREDENTIALS / "prowlarr-api-key").read_text().strip()


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def qb_get(path, **params):
    r = qb.get(f"{QBITTORRENT_URL}/api/v2/{path}", params=params, timeout=60)
    r.raise_for_status()
    return r.json()


def qb_post(path, data=None, files=None, ok=()):
    r = qb.post(f"{QBITTORRENT_URL}/api/v2/{path}", data=data, files=files, timeout=300)
    if r.status_code not in ok:
        r.raise_for_status()
    return r


def ensure_preferences():
    current = qb_get("app/preferences")
    changed = {k: v for k, v in QBITTORRENT_PREFERENCES.items() if current.get(k) != v}
    if changed:
        log(f"setting preferences {changed}")
        qb_post("app/setPreferences", {"json": json.dumps(changed)})


def cleanup(torrents, now):
    """Delete finished torrents that have seeded long enough or uploaded
    enough, unless they are among the last seeders, and downloads that are
    still under 10% with no transfer for STALL_TIME (the trackers let those go
    without a hit-and-run). Returns the torrents that remain."""
    remaining = []
    for t in torrents:
        # num_complete is the tracker's seed count, including us.
        others = t["num_complete"] - 1
        done = t["seeding_time"] >= SEED_TIME.total_seconds() or t["ratio"] >= DONE_RATIO
        # last_activity is added_on until the first byte moves.
        idle = now.timestamp() - t["last_activity"]
        if t["progress"] < 0.1 and idle >= STALL_TIME.total_seconds():
            log(f"{t['category']}: stalled at {t['progress'] * 100:.1f}% for {idle / 3600:.1f}h: {t['name']}")
            qb_post("torrents/delete", {"hashes": t["hash"], "deleteFiles": "true"})
        elif t["progress"] < 1 or not done:
            remaining.append(t)
        elif others < MIN_OTHER_SEEDERS:
            log(f"{t['category']}: keeping, only {others} other seeders: {t['name']}")
            remaining.append(t)
        else:
            log(f"{t['category']}: done seeding {t['seeding_time'] / 86400:.1f}d, ratio {t['ratio']:.2f}: {t['name']}")
            qb_post("torrents/delete", {"hashes": t["hash"], "deleteFiles": "true"})
    return remaining


def download_factor(release):
    factors = [DOWNLOAD_FACTOR[f] for f in release.get("indexerFlags", []) if f in DOWNLOAD_FACTOR]
    return min(factors, default=1.0)


def describe(release, age, factor):
    return (
        f"{release['size'] / GB:.1f} GB, {age.total_seconds() / 3600:.1f}h old, "
        f"x{factor:g} download, S{release.get('seeders', '?')}/L{release.get('leechers', '?')}: "
        f"{release['title']}"
    )


def search(indexer_id):
    r = prowlarr.get(
        f"{PROWLARR_URL}/api/v1/search",
        params={"indexerIds": indexer_id, "type": "search", "limit": 50},
        timeout=120,
    )
    r.raise_for_status()
    return sorted(r.json(), key=lambda r: r["publishDate"], reverse=True)


def grab(release, category):
    # downloadUrl carries Prowlarr's API key; never log it.
    torrent = prowlarr.get(release["downloadUrl"], timeout=120)
    torrent.raise_for_status()
    r = qb_post(
        "torrents/add",
        {"category": category, "autoTMM": "true"},
        files={"torrents": ("release.torrent", torrent.content)},
    )
    # qBittorrent 5.2+ answers with JSON counts, older versions with "Ok."/"Fails."
    body = r.text.strip()
    added = body == "Ok." or (body.startswith("{") and r.json()["success_count"] > 0)
    if not added:
        raise RuntimeError(f"torrents/add returned {body!r}")


def save_state(seen):
    fd, tmp = tempfile.mkstemp(dir=STATE.parent, prefix=".grabbed-")
    with os.fdopen(fd, "w") as f:
        json.dump(sorted(seen), f)
    os.replace(tmp, STATE)


def main():
    seen = set(json.loads(STATE.read_text())) if STATE.exists() else set()

    ensure_preferences()
    # 409: already exists. AutoTMM puts each category under the slot's files/
    # tree beside the arr categories, which are the only ones the pull takes.
    for category in TRACKERS:
        qb_post("torrents/createCategory", {"category": category, "savePath": f"{DOWNLOADS}/{category}"}, ok=(409,))

    now = datetime.now(timezone.utc)
    torrents = qb_get("torrents/info")
    in_client = {t["hash"].lower() for t in torrents}
    ours = cleanup([t for t in torrents if t["category"] in TRACKERS], now)
    # MAX_TOTAL is shared: the categories compete for the same slot disk.
    total = sum(t["size"] for t in ours)

    failures = 0
    try:
        for category, indexer_id in TRACKERS.items():
            try:
                releases = search(indexer_id)
            except requests.RequestException as e:
                failures += 1
                log(f"{category}: search failed ({e})")
                continue

            for release in releases:
                info_hash = (release.get("infoHash") or "").lower()
                if not info_hash or info_hash in in_client or info_hash in seen:
                    continue
                age = now - datetime.fromisoformat(release["publishDate"].replace("Z", "+00:00"))
                factor = download_factor(release)
                size = release.get("size") or 0
                if factor > MAX_DOWNLOAD_FACTOR or age > MAX_AGE:
                    continue
                if size > MAX_SIZE:
                    log(f"{category}: skip, over size cap: {describe(release, age, factor)}")
                    seen.add(info_hash)
                    continue
                # Upload comes from swarms that are still one uploader and its
                # leechers; one that already has more seeders than leechers is
                # served and yields nothing.
                if (release.get("seeders") or 0) > max(1, release.get("leechers") or 0):
                    log(f"{category}: skip, already seeded: {describe(release, age, factor)}")
                    seen.add(info_hash)
                    continue
                if total + size > MAX_TOTAL:
                    log(f"{category}: skip, ratio categories at {total / GB:.0f} GB: {release['title']}")
                    continue

                try:
                    grab(release, category)
                except (requests.RequestException, RuntimeError) as e:
                    failures += 1
                    log(f"{category}: grab failed ({e}): {release['title']}")
                    continue
                seen.add(info_hash)
                total += size
                log(f"{category}: grabbed {describe(release, age, factor)}")
    finally:
        save_state(seen)

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
