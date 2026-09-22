#!/usr/bin/env bash
# Runs inside cage. Plays the best live LoL Esports match; idles otherwise.
# mpv's options live in $MPV_HOME/mpv.conf so streamlink and the idle player
# share them.
set -u

PICK="${PICK_STREAM:?}"
IDLE="${IDLE_IMAGE:?}"
POLL=60
current=""
player=""

trap '[ -n "$player" ] && kill "$player" 2>/dev/null; exit 0' TERM INT

play() {
  [ -n "$player" ] && kill "$player" 2>/dev/null && wait "$player" 2>/dev/null
  if [ -n "$1" ]; then
    streamlink --twitch-disable-ads --twitch-low-latency --player mpv \
      --player-args '--profile=low-latency' "$1" best &
  else
    mpv --loop-file=inf --image-display-duration=inf "$IDLE" &
  fi
  player=$!
}

while :; do
  url=$("$PICK" 2>/dev/null) || url=""
  if [ "$url" != "$current" ] || ! kill -0 "$player" 2>/dev/null; then
    current="$url"
    play "$url"
  fi
  sleep "$POLL" &
  wait $!
done
