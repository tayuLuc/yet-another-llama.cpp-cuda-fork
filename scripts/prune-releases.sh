#!/usr/bin/env bash
# Keep only the newest N releases per fork and mode; delete the rest.
#
# Usage: prune-releases.sh [--apply] [N_STABLE [N_NIGHTLY]]
#   default: dry run. Nothing is deleted without --apply.
#   default N_STABLE=1, N_NIGHTLY=3.
#
# stable is kept at 1 because that is what the image serves and the fetcher
# always resolves the newest release by published_at - an older stable release
# can never be selected, so keeping it only makes the list unreadable.
# nightly is kept at 3: the nightly image is a diagnostic lane and a small
# window is what makes a broken nightly build recoverable without a rebuild.
#
# Deleting a release is not undoable: gh release delete removes the tag too, and
# the release notes and asset history are gone even if the tag is recreated.
# Releases without assets are left alone - they are not what a fetcher can use,
# and they are usually shells from an interrupted build.
set -euo pipefail

APPLY=0
if [ "${1:-}" = "--apply" ]; then APPLY=1; shift; fi
N_STABLE="${1:-1}"
N_NIGHTLY="${2:-3}"
KEEP_NIGHTLY_FORKS="${3:-vanilla turboquant prism atomic}"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$TOKEN" ] || { echo "!! need GH_TOKEN/GITHUB_TOKEN" >&2; exit 1; }
AUTH=(-H "Authorization: token $TOKEN")
REPO="${SRC_REPO:-tayuLuc/yet-another-llama.cpp-cuda-fork}"

# Same window problem the fetcher had: page 1 alone misses nightlies and the
# atomic fork entirely, so walk pages until a short page ends the list.
alls=()
for page in 1 2 3 4 5 6 7 8 9 10; do
  chunk=$(curl -s "${AUTH[@]}" \
    "https://api.github.com/repos/${REPO}/releases?per_page=100&page=${page}")
  echo "$chunk" | jq -e 'type == "array"' >/dev/null 2>&1 || {
    echo "!! page ${page}: GitHub did not return an array (rate limit?)" >&2
    exit 1
  }
  n=$(echo "$chunk" | jq 'length')
  [ "$n" -eq 0 ] && break
  alls+=("$chunk")
  [ "$n" -lt 100 ] && break
done
rels=$(printf '%s\n' "${alls[@]}" | jq -s 'add')

echo "==> loaded $(echo "$rels" | jq 'length') releases from ${REPO}"
echo "==> policy: keep ${N_STABLE} stable + ${N_NIGHTLY} nightly per fork"

total=0
for fork in $KEEP_NIGHTLY_FORKS; do
  for mode in stable nightly; do
    if [ "$mode" = "stable" ]; then keep="$N_STABLE"; else keep="$N_NIGHTLY"; fi
    # mapfile is bash 4+; this script also runs under the macOS bash 3.2.
    tags=""
    ntags=0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      tags="${tags}${t}
"
      ntags=$((ntags + 1))
    done < <(echo "$rels" | jq -r --arg f "$fork" --arg m "$mode" '
      if $m == "nightly" then
        [ .[] | select(.tag_name | test("^"+$f+"-nightly-[0-9a-f]+$")) ]
      else
        [ .[] | select(.tag_name | test("^"+$f+"-")) | select(.tag_name | test("nightly") | not) ]
      end
      | sort_by(.published_at) | reverse | .[] | .tag_name')
    [ "$ntags" -eq 0 ] && continue
    drop=$(( ntags > keep ? ntags - keep : 0 ))
    [ "$drop" -eq 0 ] && { echo "  ${fork}/${mode}: ${ntags} всего, ничего не трогаем"; continue; }
    echo "  ${fork}/${mode}: ${ntags} всего, оставляем ${keep}, удаляем ${drop}"
    i=0
    # Strip the trailing newline from $tags so the loop sees no phantom row.
    echo "$tags" | while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      i=$((i + 1))
      [ "$i" -le "$keep" ] && continue
      has_asset=$(echo "$rels" | jq -r --arg t "$tag" \
        '.[] | select(.tag_name==$t) | if (.assets | length) > 0 then "yes" else "no" end' | head -1)
      if [ "$has_asset" != "yes" ]; then
        echo "      - $tag  (SKIP: без ассетов)"
        continue
      fi
      if [ "$APPLY" -eq 1 ]; then
        echo "      - $tag  удаляю"
        gh release delete "$tag" --repo "$REPO" --yes >/dev/null 2>&1
        gh api -X DELETE "/repos/${REPO}/git/refs/tags/${tag}" >/dev/null 2>&1 || true
        total=$((total + 1))
      else
        echo "      - $tag  (был бы удалён)"
        total=$((total + 1))
      fi
    done
  done
done

if [ "$APPLY" -eq 0 ]; then
  echo "==> СУХОЙ ПРОГОН: ничего не удалено. Повторить с --apply, чтобы выполнить."
else
  echo "==> удалено релизов: $total"
fi