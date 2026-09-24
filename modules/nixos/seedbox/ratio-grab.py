"""Grab fresh discounted AvistaZ releases onto the seedbox slot for ratio.

One run: delete torrents in the ratio category that have seeded long enough
and are not among the last seeders, then ask Prowlarr for the newest
releases and add the ones worth seeding. Each grab is independent; a failure
is logged and the run moves on. Info hashes already handled are kept in
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
PROWLARR_INDEXER_ID = env["PROWLARR_INDEXER_ID"]
QBITTORRENT_URL = env["QBITTORRENT_URL"]
QBITTORRENT_PREFERENCES = json.loads(env["QBITTORRENT_PREFERENCES"])
CATEGORY = env["CATEGORY"]
SAVE_PATH = env["SAVE_PATH"]
SEED_TIME = timedelta(minutes=int(env["SEED_MINUTES"]))
MIN_OTHER_SEEDERS = int(env["MIN_OTHER_SEEDERS"])
MAX_AGE = timedelta(hours=float(env["MAX_AGE_HOURS"]))
MAX_SIZE = float(env["MAX_SIZE_GB"]) * GB
MAX_TOTAL = float(env["MAX_TOTAL_GB"]) * GB
MAX_DOWNLOAD_FACTOR = float(env["MAX_DOWNLOAD_FACTOR"])
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


def cleanup(torrents):
    """Delete finished torrents that have seeded long enough, unless they are
    among the last seeders. Returns the torrents that remain."""
    remaining = []
    for t in torrents:
        # num_complete is the tracker's seed count, including us.
        others = t["num_complete"] - 1
        if t["progress"] < 1 or t["seeding_time"] < SEED_TIME.total_seconds():
            remaining.append(t)
        elif others < MIN_OTHER_SEEDERS:
            log(f"keeping, only {others} other seeders: {t['name']}")
            remaining.append(t)
        else:
            log(f"done seeding {t['seeding_time'] // 86400}d, ratio {t['ratio']:.2f}: {t['name']}")
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


def grab(release):
    # downloadUrl carries Prowlarr's API key; never log it.
    torrent = prowlarr.get(release["downloadUrl"], timeout=120)
    torrent.raise_for_status()
    r = qb_post(
        "torrents/add",
        {"category": CATEGORY, "autoTMM": "true"},
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
    # 409: already exists. AutoTMM puts the category under the slot's files/
    # tree beside the arr categories, which are the only ones the pull takes.
    qb_post("torrents/createCategory", {"category": CATEGORY, "savePath": SAVE_PATH}, ok=(409,))

    torrents = qb_get("torrents/info")
    in_client = {t["hash"].lower() for t in torrents}
    ours = cleanup([t for t in torrents if t["category"] == CATEGORY])
    total = sum(t["size"] for t in ours)

    r = prowlarr.get(
        f"{PROWLARR_URL}/api/v1/search",
        params={"indexerIds": PROWLARR_INDEXER_ID, "type": "search", "limit": 50},
        timeout=120,
    )
    r.raise_for_status()
    releases = sorted(r.json(), key=lambda r: r["publishDate"], reverse=True)

    now = datetime.now(timezone.utc)
    failures = 0
    try:
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
                log(f"skip, over size cap: {describe(release, age, factor)}")
                seen.add(info_hash)
                continue
            if total + size > MAX_TOTAL:
                log(f"skip, category at {total / GB:.0f} GB: {release['title']}")
                continue

            try:
                grab(release)
            except (requests.RequestException, RuntimeError) as e:
                failures += 1
                log(f"grab failed ({e}): {release['title']}")
                continue
            seen.add(info_hash)
            total += size
            log(f"grabbed {describe(release, age, factor)}")
    finally:
        save_state(seen)

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
