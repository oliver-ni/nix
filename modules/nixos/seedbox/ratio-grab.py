"""Grab fresh discounted AvistaZ releases onto the seedbox slot for ratio.

One run: find new releases through Prowlarr, add the ones worth seeding to
qBittorrent under the ratio category, and delete torrents that have seeded
long enough and are not the last seeders left. Nothing in the category is
ever pulled home.

Each grab is independent: a failure is logged and the run moves on. The set
of info hashes already handled is kept in STATE_DIRECTORY so a torrent that
was deleted, or skipped for size, is not considered again.
"""

import json
import os
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

GB = 1e9

# Prowlarr reports the tracker's discount as flags, not as a factor.
DOWNLOAD_FACTOR = {
    "freeleech": 0.0,
    "freeleech75": 0.25,
    "halfleech": 0.5,
    "freeleech25": 0.75,
}


@dataclass(frozen=True)
class Config:
    prowlarr_url: str
    prowlarr_indexer_id: str
    qbittorrent_url: str
    category: str
    save_path: str
    seed_time: timedelta
    min_other_seeders: int
    max_age: timedelta
    max_size: float
    max_total: float
    max_download_factor: float
    upload_slots: int
    upload_slots_per_torrent: int
    credentials: Path
    state: Path

    @classmethod
    def from_env(cls, env=os.environ):
        return cls(
            prowlarr_url=env["PROWLARR_URL"],
            prowlarr_indexer_id=env["PROWLARR_INDEXER_ID"],
            qbittorrent_url=env["QBITTORRENT_URL"],
            category=env["CATEGORY"],
            save_path=env["SAVE_PATH"],
            seed_time=timedelta(minutes=int(env["SEED_MINUTES"])),
            min_other_seeders=int(env["MIN_OTHER_SEEDERS"]),
            max_age=timedelta(hours=float(env["MAX_AGE_HOURS"])),
            max_size=float(env["MAX_SIZE_GB"]) * GB,
            max_total=float(env["MAX_TOTAL_GB"]) * GB,
            max_download_factor=float(env["MAX_DOWNLOAD_FACTOR"]),
            upload_slots=int(env["UPLOAD_SLOTS"]),
            upload_slots_per_torrent=int(env["UPLOAD_SLOTS_PER_TORRENT"]),
            credentials=Path(env["CREDENTIALS_DIRECTORY"]),
            state=Path(env["STATE_DIRECTORY"]) / "grabbed.json",
        )


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def session(retries=3):
    s = requests.Session()
    retry = Retry(
        total=retries,
        backoff_factor=1,
        status_forcelist=(502, 503, 504),
        allowed_methods=("GET", "POST"),
    )
    s.mount("http://", HTTPAdapter(max_retries=retry))
    s.mount("https://", HTTPAdapter(max_retries=retry))
    return s


class QBittorrent:
    def __init__(self, url, auth):
        self.url = url
        self.session = session()
        self.session.auth = auth

    def get(self, path, **params):
        r = self.session.get(f"{self.url}/api/v2/{path}", params=params, timeout=60)
        r.raise_for_status()
        return r.json()

    def post(self, path, data=None, files=None, ok=()):
        r = self.session.post(
            f"{self.url}/api/v2/{path}", data=data, files=files, timeout=300
        )
        if r.status_code not in ok:
            r.raise_for_status()
        return r

    def ensure_preferences(self, wanted):
        current = self.get("app/preferences")
        changed = {k: v for k, v in wanted.items() if current.get(k) != v}
        if changed:
            log(f"setting preferences {changed}")
            self.post("app/setPreferences", {"json": json.dumps(changed)})

    def ensure_category(self, name, save_path):
        # 409: already exists.
        self.post(
            "torrents/createCategory",
            {"category": name, "savePath": save_path},
            ok=(409,),
        )

    def torrents(self):
        return self.get("torrents/info")

    def add(self, category, torrent_file):
        r = self.post(
            "torrents/add",
            {"category": category, "autoTMM": "true"},
            files={"torrents": ("release.torrent", torrent_file)},
        )
        if r.text.strip() != "Ok.":
            raise RuntimeError(f"torrents/add returned {r.text.strip()!r}")

    def delete(self, info_hash):
        self.post("torrents/delete", {"hashes": info_hash, "deleteFiles": "true"})


class Prowlarr:
    def __init__(self, url, api_key):
        self.url = url
        self.session = session()
        self.session.headers["X-Api-Key"] = api_key

    def latest(self, indexer_id, limit=50):
        r = self.session.get(
            f"{self.url}/api/v1/search",
            params={"indexerIds": indexer_id, "type": "search", "limit": limit},
            timeout=120,
        )
        r.raise_for_status()
        return r.json()

    def download(self, release):
        # The URL carries the API key; never log it.
        r = self.session.get(release["downloadUrl"], timeout=120)
        r.raise_for_status()
        return r.content


class State:
    def __init__(self, path):
        self.path = path
        self.seen = set(json.loads(path.read_text())) if path.exists() else set()

    def save(self):
        fd, tmp = tempfile.mkstemp(dir=self.path.parent, prefix=".grabbed-")
        with os.fdopen(fd, "w") as f:
            json.dump(sorted(self.seen), f)
        os.replace(tmp, self.path)


def download_factor(release):
    factors = [DOWNLOAD_FACTOR.get(f) for f in release.get("indexerFlags", [])]
    factors = [f for f in factors if f is not None]
    return min(factors) if factors else 1.0


def describe(release, age, factor):
    return (
        f"{release['size'] / GB:.1f} GB, {age.total_seconds() / 3600:.1f}h old, "
        f"x{factor:g} download, S{release.get('seeders', '?')}/L{release.get('leechers', '?')}: "
        f"{release['title']}"
    )


def cleanup(qb, cfg, torrents):
    """Delete finished torrents that have seeded long enough and are not
    among the last seeders. The tracker's seed count includes us."""
    for t in torrents:
        if t["progress"] < 1 or t["seeding_time"] < cfg.seed_time.total_seconds():
            continue
        others = t["num_complete"] - 1
        if others < cfg.min_other_seeders:
            log(f"keeping, only {others} other seeders: {t['name']}")
            continue
        try:
            qb.delete(t["hash"])
        except requests.RequestException as e:
            log(f"delete failed ({e}): {t['name']}")
            continue
        log(f"done seeding {t['seeding_time'] // 86400}d, ratio {t['ratio']:.2f}: {t['name']}")


def choose(cfg, releases, in_client, seen, total, now):
    """Yield (release, age, factor) worth grabbing, newest first, keeping a
    running total so the category stays under max_total."""
    releases = sorted(releases, key=lambda r: r["publishDate"], reverse=True)
    for release in releases:
        info_hash = (release.get("infoHash") or "").lower()
        if not info_hash or info_hash in in_client or info_hash in seen:
            continue

        published = datetime.fromisoformat(release["publishDate"].replace("Z", "+00:00"))
        age = now - published
        factor = download_factor(release)
        size = release.get("size") or 0
        if factor > cfg.max_download_factor or age > cfg.max_age:
            continue
        if size > cfg.max_size:
            log(f"skip, over size cap: {describe(release, age, factor)}")
            seen.add(info_hash)
            continue
        if total + size > cfg.max_total:
            log(f"skip, category at {total / GB:.0f} GB: {release['title']}")
            continue

        total += size
        yield info_hash, release, age, factor


def main():
    cfg = Config.from_env()
    qb = QBittorrent(
        cfg.qbittorrent_url,
        tuple((cfg.credentials / "qbittorrent-auth").read_text().strip().split(":", 1)),
    )
    prowlarr = Prowlarr(
        cfg.prowlarr_url, (cfg.credentials / "prowlarr-api-key").read_text().strip()
    )
    state = State(cfg.state)

    qb.ensure_preferences(
        {
            "max_uploads": cfg.upload_slots,
            "max_uploads_per_torrent": cfg.upload_slots_per_torrent,
        }
    )
    # AutoTMM puts the category under the slot's files/ tree, beside the arr
    # categories; the pull only includes those two.
    qb.ensure_category(cfg.category, cfg.save_path)

    all_torrents = qb.torrents()
    in_client = {t["hash"].lower() for t in all_torrents}
    ours = [t for t in all_torrents if t["category"] == cfg.category]
    cleanup(qb, cfg, ours)
    total = sum(t["size"] for t in ours)

    releases = prowlarr.latest(cfg.prowlarr_indexer_id)
    now = datetime.now(timezone.utc)
    failures = 0
    try:
        for info_hash, release, age, factor in choose(
            cfg, releases, in_client, state.seen, total, now
        ):
            try:
                qb.add(cfg.category, prowlarr.download(release))
            except (requests.RequestException, RuntimeError) as e:
                failures += 1
                log(f"grab failed ({e}): {release['title']}")
                continue
            state.seen.add(info_hash)
            log(f"grabbed {describe(release, age, factor)}")
    finally:
        state.save()

    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
