"""Grab fresh discounted AvistaZ releases onto the seedbox slot for ratio.

One run: find new releases through Prowlarr, add the ones worth seeding to
qBittorrent under the ratio category with a per-torrent seeding-time limit,
and delete torrents that have reached it. Nothing in the category is ever
pulled home.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

PROWLARR_URL = os.environ["PROWLARR_URL"]
PROWLARR_INDEXER_ID = os.environ["PROWLARR_INDEXER_ID"]
QBITTORRENT_URL = os.environ["QBITTORRENT_URL"]
CATEGORY = os.environ["CATEGORY"]
SAVE_PATH = os.environ["SAVE_PATH"]
SEED_MINUTES = int(os.environ["SEED_MINUTES"])
MAX_AGE_HOURS = float(os.environ["MAX_AGE_HOURS"])
MAX_SIZE_GB = float(os.environ["MAX_SIZE_GB"])
MAX_TOTAL_GB = float(os.environ["MAX_TOTAL_GB"])
MAX_DOWNLOAD_FACTOR = float(os.environ["MAX_DOWNLOAD_FACTOR"])
UPLOAD_SLOTS = int(os.environ["UPLOAD_SLOTS"])
UPLOAD_SLOTS_PER_TORRENT = int(os.environ["UPLOAD_SLOTS_PER_TORRENT"])

CREDENTIALS = Path(os.environ["CREDENTIALS_DIRECTORY"])
STATE = Path(os.environ["STATE_DIRECTORY"]) / "grabbed.json"

GB = 1e9

# Prowlarr reports the tracker's discount as flags, not as a factor.
DOWNLOAD_FACTOR = {
    "freeleech": 0.0,
    "freeleech75": 0.25,
    "halfleech": 0.5,
    "freeleech25": 0.75,
}

qb = requests.Session()
qb.auth = tuple(
    (CREDENTIALS / "qbittorrent-auth").read_text().strip().split(":", 1)
)

prowlarr = requests.Session()
prowlarr.headers["X-Api-Key"] = (
    (CREDENTIALS / "prowlarr-api-key").read_text().strip()
)


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def qb_get(path, **params):
    r = qb.get(f"{QBITTORRENT_URL}/api/v2/{path}", params=params, timeout=60)
    r.raise_for_status()
    return r


def qb_post(path, data=None, files=None, ok=()):
    r = qb.post(
        f"{QBITTORRENT_URL}/api/v2/{path}", data=data, files=files, timeout=300
    )
    if r.status_code not in ok:
        r.raise_for_status()
    return r


def download_factor(release):
    factors = [DOWNLOAD_FACTOR.get(f) for f in release.get("indexerFlags", [])]
    factors = [f for f in factors if f is not None]
    return min(factors) if factors else 1.0


def cleanup(torrents):
    for t in torrents:
        if t["state"] not in ("stoppedUP", "pausedUP"):
            continue
        if t["seeding_time"] < SEED_MINUTES * 60:
            continue
        log(f"done seeding {t['seeding_time'] // 86400}d, ratio {t['ratio']:.2f}: {t['name']}")
        qb_post("torrents/delete", {"hashes": t["hash"], "deleteFiles": "true"})


def ensure_preferences():
    wanted = {
        "max_uploads": UPLOAD_SLOTS,
        "max_uploads_per_torrent": UPLOAD_SLOTS_PER_TORRENT,
    }
    current = qb_get("app/preferences").json()
    changed = {k: v for k, v in wanted.items() if current.get(k) != v}
    if changed:
        log(f"setting preferences {changed}")
        qb_post("app/setPreferences", {"json": json.dumps(changed)})


def main():
    seen = set(json.loads(STATE.read_text())) if STATE.exists() else set()

    ensure_preferences()

    # AutoTMM puts the category under the slot's files/ tree, beside the arr
    # categories; the pull only includes those two.
    qb_post(
        "torrents/createCategory",
        {"category": CATEGORY, "savePath": SAVE_PATH},
        ok=(409,),
    )

    all_torrents = qb_get("torrents/info").json()
    in_client = {t["hash"].lower() for t in all_torrents}
    ours = [t for t in all_torrents if t["category"] == CATEGORY]
    cleanup(ours)
    total = sum(t["size"] for t in ours if t["state"] not in ("stoppedUP", "pausedUP"))

    r = prowlarr.get(
        f"{PROWLARR_URL}/api/v1/search",
        params={"indexerIds": PROWLARR_INDEXER_ID, "type": "search", "limit": 50},
        timeout=120,
    )
    r.raise_for_status()
    releases = sorted(r.json(), key=lambda x: x["publishDate"], reverse=True)

    now = datetime.now(timezone.utc)
    for release in releases:
        info_hash = (release.get("infoHash") or "").lower()
        published = datetime.fromisoformat(release["publishDate"].replace("Z", "+00:00"))
        age_hours = (now - published).total_seconds() / 3600
        factor = download_factor(release)
        title = release["title"]

        if not info_hash or info_hash in in_client or info_hash in seen:
            continue
        if factor > MAX_DOWNLOAD_FACTOR or age_hours > MAX_AGE_HOURS:
            continue
        if release["size"] > MAX_SIZE_GB * GB:
            log(f"skip {release['size'] / GB:.0f} GB: {title}")
            seen.add(info_hash)
            continue
        if total + release["size"] > MAX_TOTAL_GB * GB:
            log(f"skip, category at {total / GB:.0f} GB: {title}")
            continue

        torrent = prowlarr.get(release["downloadUrl"], timeout=120)
        torrent.raise_for_status()
        qb_post(
            "torrents/add",
            {"category": CATEGORY, "autoTMM": "true"},
            files={"torrents": (f"{info_hash}.torrent", torrent.content)},
        )
        qb_post(
            "torrents/setShareLimits",
            {
                "hashes": info_hash,
                "ratioLimit": -1,
                "seedingTimeLimit": SEED_MINUTES,
                "inactiveSeedingTimeLimit": -1,
                "shareLimitAction": "Stop",
            },
        )
        seen.add(info_hash)
        total += release["size"]
        log(
            f"grabbed {release['size'] / GB:.1f} GB, {age_hours:.1f}h old, "
            f"x{factor:g} download, S{release['seeders']}/L{release['leechers']}: {title}"
        )

    STATE.write_text(json.dumps(sorted(seen)))


if __name__ == "__main__":
    main()
