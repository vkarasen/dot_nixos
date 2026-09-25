# Fires on every herdr workspace.closed event (see herdr-plugin.toml).
# Only acts when the closed workspace was a linked worktree sub-workspace
# AND Worktrunk itself independently confirms that specific worktree is
# already identical to or merged into the repo's default branch. Any
# ambiguity — unparseable event JSON, an already-gone checkout, a worktree
# not on Worktrunk's own safe list — is a silent no-op by design: closing
# is the *trigger* to check, never the authority to remove. This is the
# primary cleanup path; the systemd worktrunk-autoprune timer (1-week
# min-age, modules/home/worktrunk.nix) is the backstop for anything this
# misses (herdr not running, the plugin failing, herdr quitting uncleanly).
#
# No --min-age guard here, unlike the timer: closing the workspace IS the
# deliberate "I'm done" signal, so there is nothing to wait out.
set -uo pipefail

json="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -n "$json" ] || exit 0

checkout_path="$(echo "$json" | jq -r '.data.workspace.worktree.checkout_path // empty' 2>/dev/null)"
is_linked="$(echo "$json" | jq -r '.data.workspace.worktree.is_linked_worktree // empty' 2>/dev/null)"
repo_root="$(echo "$json" | jq -r '.data.workspace.worktree.repo_root // empty' 2>/dev/null)"

[ -n "$checkout_path" ] && [ "$is_linked" = "true" ] && [ -n "$repo_root" ] || exit 0
[ -d "$checkout_path" ] || exit 0

candidates="$(wt step prune --dry-run --min-age=0s --format=json -C "$repo_root" 2>/dev/null)" || exit 0
branch="$(echo "$candidates" | jq -r --arg p "$checkout_path" '.[] | select(.path == $p) | .branch' 2>/dev/null | head -n1)"
[ -n "$branch" ] || exit 0

wt remove "$branch" -C "$repo_root" --format=json >/dev/null 2>&1
