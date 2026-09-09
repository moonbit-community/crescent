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

server_log="$(mktemp -t crescent-e2e-server.XXXXXX)"

# Redirect the server's output to a file rather than letting it inherit this
# script's stdout/stderr. A CI step is considered finished only once every
# process holding those pipes has exited, and the server outlives `moon`.
moon run e2e/server --target "$target" --diagnostic-limit 0 >"$server_log" 2>&1 &
server_pid=$!

cleanup() {
  status=$?
  # Surface the server's output when something went wrong; it is otherwise
  # invisible because it no longer shares this script's stdout.
  if [ "$status" -ne 0 ] && [ -s "$server_log" ]; then
    echo "--- e2e server output ($target) ---" >&2
    cat "$server_log" >&2
  fi
  # `moon run` spawns the actual server (server.exe) as a child, so killing
  # only $server_pid leaves that grandchild running. Kill moon's children
  # first, then moon itself.
  pkill -P "$server_pid" 2>/dev/null || true
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  rm -f "$server_log"
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
