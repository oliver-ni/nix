"""Grab fresh discounted private-tracker releases onto the seedbox slot for ratio.

TRACKERS maps a qBittorrent category to the Prowlarr indexer that feeds it, one
per tracker so each site's hit-and-run obligations stay in their own category.
One run: delete torrents in those categories that have seeded long enough or
uploaded enough and are not among the last seeders, drop downloads that never
got going, then ask Prowlarr for each tracker's newest releases and add the
ones worth seeding. Each tracker and each grab is independent; a failure is
logged and the run moves on. Info hashes already handled are kept in
STATE_DIRECTORY so a deleted or skipped torrent is not considered again.

ARRS maps each arr's qBittorrent category to its URL. Their torrents are
deleted from the slot once qBittorrent has stopped them at the share limit the
arr set, the arr has imported them, and every file has been pulled home.
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
ARRS = json.loads(env["ARRS"])
DOWNLOADS = env["DOWNLOADS"]
LOCAL_DOWNLOADS = Path(env["LOCAL_DOWNLOADS"])
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


def arr_imported(url, api_key):
    """Info hashes of the torrents the arr has imported and is finished with.
    A download it is still working on (import pending, files it could not
    match) stays in its queue; one it never grabbed has no history."""
    arr = requests.Session()
    arr.headers["X-Api-Key"] = api_key
    queue = arr.get(f"{url}/api/v3/queue", params={"pageSize": 1000}, timeout=60)
    queue.raise_for_status()
    pending = {q["downloadId"].lower() for q in queue.json()["records"] if q.get("downloadId")}
    imported = set()
    page = 1
    while True:
        r = arr.get(
            f"{url}/api/v3/history",
            params={"eventType": 3, "pageSize": 500, "page": page},
            timeout=60,
        )
        r.raise_for_status()
        body = r.json()
        imported |= {h["downloadId"].lower() for h in body["records"] if h.get("downloadId")}
        if page * body["pageSize"] >= body["totalRecords"]:
            break
        page += 1
    return imported - pending


def at_share_limit(t):
    """qBittorrent stopped the torrent at a ratio or seeding-time limit set on
    it (the arrs set both from Prowlarr's seed criteria; -1 is unlimited and
    -2 the client default, neither of which is a goal)."""
    if t["state"] not in ("stoppedUP", "pausedUP"):
        return False
    return (0 <= t["ratio_limit"] <= t["ratio"]) or (
        0 <= t["seeding_time_limit"] <= t["seeding_time"] / 60
    )


def pulled_home(t):
    """Every file of the torrent is at home with its final size, which is the
    comparison the pull itself makes."""
    for f in qb_get("torrents/files", hash=t["hash"]):
        local = LOCAL_DOWNLOADS / t["category"] / f["name"]
        if not local.is_file() or local.stat().st_size != f["size"]:
            return False
    return True


def cleanup_arrs(torrents):
    """Delete the arrs' torrents that are done on every side: stopped at their
    share limit, imported by the arr, and pulled home. Deleting one makes the
    next pull drop its home copy, so each condition guards the others."""
    failures = 0
    for category, url in ARRS.items():
        try:
            imported = arr_imported(url, (CREDENTIALS / f"{category}-api-key").read_text().strip())
        except requests.RequestException as e:
            failures += 1
            log(f"{category}: could not read import state ({e})")
            continue
        for t in torrents:
            if t["category"] != category or not at_share_limit(t) or t["hash"].lower() not in imported:
                continue
            try:
                if not pulled_home(t):
                    log(f"{category}: imported, waiting for the pull: {t['name']}")
                    continue
                log(f"{category}: imported and pulled, ratio {t['ratio']:.2f}: {t['name']}")
                qb_post("torrents/delete", {"hashes": t["hash"], "deleteFiles": "true"})
            except (requests.RequestException, OSError) as e:
                failures += 1
                log(f"{category}: cleanup failed ({e}): {t['name']}")
    return failures


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

    failures = cleanup_arrs(torrents)
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
