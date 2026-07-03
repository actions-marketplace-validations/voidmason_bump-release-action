#!/usr/bin/env bash
# Version math for bump-release-action: routes the requested action to
# cargo set-version and reports the resulting version.
#
# Usage: bump-version.sh <patch|minor|major|beta|beta-minor|beta-major|finalize>
# Runs at the workspace root; writes next=<version> to $GITHUB_OUTPUT.
set -euo pipefail

ACTION="${1:?usage: bump-version.sh <patch|minor|major|beta|beta-minor|beta-major|finalize>}"

ver() { cargo read-manifest | jq -r .version; }
PREV=$(ver)
# Version math is delegated to cargo set-version; bash only routes the action.
# `beta` covers both starting a patch pre-release and incrementing an existing
# one - set-version picks by current state, and updates Cargo.lock as it goes.
# --workspace also covers a lone package (a one-member workspace).
case "$ACTION" in
  patch|minor|major) cargo set-version --workspace --bump "$ACTION" ;;
  beta)              cargo set-version --workspace --bump beta ;;
  beta-minor|beta-major)
    # `--bump beta` always patches the base, so it cannot start a minor/major
    # pre-release. set-version also refuses downgrades (0.2.0 -> 0.2.0-beta.1),
    # ruling out "bump then suffix". Bump the target base ourselves and set the
    # pre-release in one shot - always an upgrade from the current version.
    base=${PREV%%-*}; IFS=. read -r maj min _ <<< "$base"
    case "$ACTION" in
      beta-minor) target="$maj.$((min+1)).0" ;;
      beta-major) target="$((maj+1)).0.0" ;;
    esac
    cargo set-version --workspace "$target-beta.1" ;;
  finalize)          cargo set-version --workspace --bump release ;;
  *) echo "::error::unknown action: $ACTION"; exit 1 ;;
esac
NEXT=$(ver)
# `finalize` with no active pre-release is a no-op; an unchanged version would
# produce an empty commit in the action. Fail loud instead of releasing nothing.
if [ "$NEXT" = "$PREV" ]; then
  echo "::error::version unchanged ($PREV): '$ACTION' is a no-op here"
  exit 1
fi
echo "next=$NEXT" >> "$GITHUB_OUTPUT"
