#!/usr/bin/env bash
# Runs requester against stand-ins: a pkexec that only waits (no dialog) and a
# notify-send that does nothing, started the way agent-root and a bare pkexec
# call would start them. Prints each case and fails on the first mismatch.
#
# Usage: test/requester_test.sh    (agent-root on PATH for its cases)
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
requester=$here/requester
fake=$(mktemp -d)
pids=()
cleanup() {
  [ "${#pids[@]}" -eq 0 ] || kill "${pids[@]}" 2>/dev/null
  rm -rf "$fake"
}
trap cleanup EXIT

printf '#include <unistd.h>\nint main(void) { pause(); return 0; }\n' >"$fake/p.c"
gcc -o "$fake/pkexec" "$fake/p.c" || exit 1
printf '#!/bin/sh\necho 1\n' >"$fake/notify-send"
chmod +x "$fake/notify-send"

failures=0
check() {
  local name=$1 message=$2 filter=$3 out
  out=$("$requester" "$message" "$name")
  if jq -e --arg tag "$name" ".tag == \$tag and ($filter)" <<<"$out" >/dev/null; then
    echo "ok   $name: $out"
  else
    echo "FAIL $name: $out (wanted $filter)"
    failures=$((failures + 1))
  fi
}

# Start a stand-in in the background and wait, at most two seconds, until its
# pkexec is up next to the ones already started.
started=0
start() {
  local i
  "$@" </dev/null >/dev/null 2>&1 &
  pids+=($!)
  started=$((started + 1))
  for ((i = 0; i < 200; i++)); do
    [ "$(pgrep -cx pkexec -U "$(id -u)")" -ge "$started" ] && return 0
    sleep 0.01
  done
  echo "FAIL: the stand-in pkexec did not start" >&2
  exit 1
}

msg() { printf 'Authentication is needed to run `%s'"'"' as the super user' "$1"; }

if command -v agent-root >/dev/null; then
  start env PATH="$fake:$PATH" agent-root "Install Valkey (Redis) for Sidekiq" pacman -S --noconfirm valkey
  check agent-root "$(msg "/usr/bin/pacman -S --noconfirm valkey")" \
    '.via == "agent-root" and .reason == "Install Valkey (Redis) for Sidekiq"'

  # yay and paru: the reason comes from the environment.
  start env AGENT_ROOT_REASON="Build and install from the AUR" PATH="$fake:$PATH" agent-root pacman -U --noconfirm /tmp/x.pkg.tar.zst
  check aur-helper "$(msg "/usr/bin/pacman -U --noconfirm /tmp/x.pkg.tar.zst")" \
    '.via == "agent-root" and .reason == "Build and install from the AUR"'

  long_args=(-S --noconfirm valkey redis-tools postgresql postgresql-libs nginx certbot python-certbot-nginx)
  start env PATH="$fake:$PATH" agent-root "Set up the web stack" pacman "${long_args[@]}"
  long="/usr/bin/pacman ${long_args[*]}"
  check long-command "$(msg "${long:0:38} ... ${long: -38}")" '.reason == "Set up the web stack"'
else
  echo "skip agent-root cases: agent-root is not on PATH"
fi

# A bare pkexec with a program name, which pkexec looks up in the caller's PATH.
# shellcheck disable=SC2016 # $0 is the inner shell's
start bash -c 'exec -a pkexec "$0" whoami' "$fake/pkexec"
check bare-pkexec "$(msg /usr/bin/whoami)" '.via == "pkexec" and .reason == ""'

# Two requests that look the same: no answer rather than a guess.
# shellcheck disable=SC2016
start bash -c 'exec -a pkexec "$0" whoami' "$fake/pkexec"
check ambiguous "$(msg /usr/bin/whoami)" 'has("via") | not'

check no-match "$(msg /usr/bin/ls)" 'has("via") | not'
check other-action "Authentication is required to mount a disk" 'has("via") | not'

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo "all passed"
