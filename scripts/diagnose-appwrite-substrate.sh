#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

say "=== APPWRITE / DOCKER SUBSTRATE DIAGNOSTIC ==="
say
say "--- PLATFORM ---"
uname -a 2>/dev/null || true
getprop ro.product.model 2>/dev/null | sed 's/^/model: /' || true
getprop ro.build.version.release 2>/dev/null | sed 's/^/android: /' || true
say

say "--- USER / ROOT ---"
id 2>/dev/null || true
if have su; then
  if su -c id >/tmp/vantasm-su-id.$$ 2>/dev/null; then
    say "root_access: YES"
    cat /tmp/vantasm-su-id.$$
    ROOT_OK=1
  else
    say "root_access: NO"
    ROOT_OK=0
  fi
  rm -f /tmp/vantasm-su-id.$$ 2>/dev/null || true
else
  say "root_access: NO (su not found)"
  ROOT_OK=0
fi
say

say "--- DOCKER CLI / COMPOSE ---"
if have docker; then
  docker --version 2>&1 || true
  docker compose version 2>&1 || true
else
  say "docker: NOT INSTALLED"
fi
say

say "--- DOCKER DAEMON ---"
if have docker && docker info >/tmp/vantasm-docker-info.$$ 2>/tmp/vantasm-docker-err.$$; then
  say "docker_daemon: REACHABLE"
  head -n 30 /tmp/vantasm-docker-info.$$ 2>/dev/null || true
  DOCKER_OK=1
else
  say "docker_daemon: UNAVAILABLE"
  head -n 20 /tmp/vantasm-docker-err.$$ 2>/dev/null || true
  DOCKER_OK=0
fi
rm -f /tmp/vantasm-docker-info.$$ /tmp/vantasm-docker-err.$$ 2>/dev/null || true
say

say "--- KERNEL FEATURES ---"
for fs in overlay overlay2 fuse cgroup2; do
  if grep -qw "$fs" /proc/filesystems 2>/dev/null; then
    say "filesystem:$fs YES"
  else
    say "filesystem:$fs NO/UNKNOWN"
  fi
done

if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  say "cgroup_v2: YES"
  printf 'controllers: '
  cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true
else
  say "cgroup_v2: NO/UNKNOWN"
fi

for f in   /proc/sys/net/ipv4/ip_forward   /proc/sys/user/max_user_namespaces   /sys/module/overlay   /sys/fs/cgroup
do
  if [ -e "$f" ]; then say "present: $f"; else say "missing: $f"; fi
done
say

say "--- MEMORY / SWAP / SPACE ---"
free -h 2>/dev/null || true
cat /proc/swaps 2>/dev/null || true
df -h "$HOME" 2>/dev/null || true
say

say "--- APPWRITE SOURCE ---"
ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
if [ -d "$ROOT/src/appwrite/.git" ]; then
  say "appwrite_source: PRESENT"
  git -C "$ROOT/src/appwrite" rev-parse --short HEAD 2>/dev/null || true
else
  say "appwrite_source: MISSING"
fi
say

if [ "$DOCKER_OK" -eq 1 ]; then
  say "RESULT: DOCKER_SUBSTRATE_REACHABLE"
  exit 0
fi

if [ "$ROOT_OK" -eq 0 ]; then
  say "RESULT: HOLD_NO_ROOT_FOR_LOCAL_DOCKER_DAEMON"
  exit 4
fi

say "RESULT: HOLD_DOCKER_DAEMON_OR_KERNEL_FEATURES"
exit 4
