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

# The closed workspace is not proof that nothing is still inside the
# checkout: a pane (shell or agent) in some *other* workspace can have its
# cwd there. `herdr pane list` with no --workspace returns every
# workspace's panes, each carrying the pane's cwd, so that is the liveness
# source. Fail-safe: if the query fails or the envelope does not parse we
# cannot tell what is live, so do nothing. Panes of the closing workspace
# itself are excluded — that workspace is going away, and its closure is
# the trigger, not a reason to keep the worktree.
#
# Plugin commands get Herdr's own binary path in HERDR_BIN_PATH (Herdr
# injects it, and ./herdr-plugin.toml's command runs via a
# writeShellApplication wrapper that deliberately does NOT put herdr on
# PATH), so call back through that, falling back to PATH resolution.
herdr_bin="${HERDR_BIN_PATH:-herdr}"
if ! pane_json="$("$herdr_bin" pane list 2>&1)" || ! jq -e '.result.panes | type == "array"' <<<"$pane_json" >/dev/null 2>&1; then
  echo "worktrunk-close-prune: cannot read live herdr panes, leaving $checkout_path alone" >&2
  exit 0
fi
closing_ws="$(echo "$json" | jq -r '.data.workspace.workspace_id // .data.workspace_id // empty' 2>/dev/null)"
live_cwds="$(echo "$pane_json" | jq -r --arg ws "$closing_ws" '.result.panes[]? | select($ws == "" or .workspace_id != $ws) | .cwd // empty, .foreground_cwd // empty' 2>/dev/null)" || exit 0

# Prefix-safe, matching modules/home/worktrunk.nix's guard: exact match, or
# the live cwd is a descendant of the checkout (compare against
# "$probe_path" + "/", so /a/b matches inside /a but /ab does not).
probe_path="${checkout_path%/}"
while IFS= read -r live_cwd; do
  [ -n "$live_cwd" ] || continue
  if [ "$live_cwd" = "$probe_path" ] || [ "${live_cwd#"$probe_path"/}" != "$live_cwd" ]; then
    echo "worktrunk-close-prune: live herdr pane in $live_cwd, leaving $checkout_path alone" >&2
    exit 0
  fi
done <<<"$live_cwds"

candidates="$(wt step prune --dry-run --min-age=0s --format=json -C "$repo_root" 2>/dev/null)" || exit 0
branch="$(echo "$candidates" | jq -r --arg p "$checkout_path" '.[] | select(.path == $p) | .branch' 2>/dev/null | head -n1)"
[ -n "$branch" ] || exit 0

wt remove "$branch" -C "$repo_root" --format=json >/dev/null 2>&1
