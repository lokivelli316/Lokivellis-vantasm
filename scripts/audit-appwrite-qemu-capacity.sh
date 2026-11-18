#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

MIN_FREE_KB="${APPWRITE_VM_MIN_FREE_KB:-12582912}"
MIN_MEM_KB="${APPWRITE_VM_MIN_MEM_KB:-5242880}"

FREE_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
MEM_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"

echo "=== APPWRITE QEMU CAPACITY AUDIT ==="
echo "disk_free_kib=${FREE_KB:-UNKNOWN}"
echo "disk_required_kib=$MIN_FREE_KB"
if [ -n "${FREE_KB:-}" ]; then
  if [ "$FREE_KB" -ge "$MIN_FREE_KB" ]; then
    echo "disk_gate=PASS"
  else
    echo "disk_gate=HOLD short_kib=$((MIN_FREE_KB-FREE_KB))"
  fi
fi

echo "mem_available_kib=${MEM_KB:-UNKNOWN}"
echo "mem_required_kib=$MIN_MEM_KB"
if [ -n "${MEM_KB:-}" ]; then
  if [ "$MEM_KB" -ge "$MIN_MEM_KB" ]; then
    echo "memory_gate=PASS"
  else
    echo "memory_gate=HOLD short_kib=$((MIN_MEM_KB-MEM_KB))"
  fi
fi

echo
echo "=== LARGEST HOME DIRECTORIES ==="
du -x -h --max-depth=1 "$HOME" 2>/dev/null | sort -h | tail -n 25

echo
echo "=== REBUILDABLE / REDOWNLOADABLE CANDIDATES ONLY ==="
for p in   "$HOME/.cache"   "$HOME/.npm"   "$HOME/.cargo/registry"   "$HOME/forge-tools/cargo/registry"   "$HOME/forge-tools/src/lemmeknow/target"   "$HOME/forge-tools/src/rust-anything/target"   "$HOME/forge-tools/playwright-cli/node_modules"
do
  [ -e "$p" ] && du -sh "$p" 2>/dev/null || true
done

echo
echo "No files were deleted or moved."
