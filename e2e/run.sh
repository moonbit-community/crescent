#!/bin/sh

set -eu

target="${1:-native}"
case "$target" in
  native|wasm) ;;
  *)
    echo "usage: $0 [native|wasm]" >&2
    exit 2
    ;;
esac

moon run e2e/server --target "$target" --diagnostic-limit 0 &
server_pid=$!

cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Retry only the stateless health exchange while Moon builds and starts the
# server. Retrying the full suite would carry cookies across attempts.
hurl \
  --retry 50 \
  --retry-interval 200 \
  --to-entry 1 \
  --variable host=http://127.0.0.1:4010 \
  e2e/hurl/crescent.hurl >/dev/null

hurl \
  --test \
  --variable host=http://127.0.0.1:4010 \
  e2e/hurl/*.hurl
