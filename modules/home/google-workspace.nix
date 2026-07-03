# Dendritic aspect: google-workspace (home-manager class).
#
# Wires the Google Workspace MCP server (@dguido/google-workspace-mcp) into pi,
# giving the agent access to Gmail, Google Drive, and Google Sheets.
#
# ── What this does ──────────────────────────────────────────────────────────
#  • Writes ~/.pi/agent/mcp.json so pi-mcp-adapter discovers the server.
#  • Writes ~/.config/google-workspace-mcp/credentials.json at activation
#    time, pulling the OAuth client-id and client-secret from sops secrets.
#  • Declares two sops secrets: google_oauth_client_id and
#    google_oauth_client_secret.  Their encrypted values must be added to
#    modules/home/sops/secrets/secrets.yaml (see "First-time setup" below).
#
# ── First-time setup (manual steps, done once) ──────────────────────────────
#  1. Create a Google Cloud project at https://console.cloud.google.com
#  2. Enable these APIs:
#       Gmail API, Google Drive API, Google Sheets API, Google Docs API,
#       Google Calendar API, Google People API
#  3. Configure the OAuth consent screen:
#       APIs & Services → OAuth consent screen → External (or Internal)
#       Add scopes:
#         https://www.googleapis.com/auth/gmail.modify
#         https://www.googleapis.com/auth/drive
#         https://www.googleapis.com/auth/spreadsheets
#         https://www.googleapis.com/auth/documents
#         https://www.googleapis.com/auth/calendar
#         https://www.googleapis.com/auth/contacts
#  4. Create an OAuth 2.0 Client ID:
#       APIs & Services → Credentials → Create → OAuth client ID
#       Application type: Desktop app
#       Download the JSON — you need client_id and client_secret from it.
#  5. Add the secrets to the sops-encrypted file:
#       cd modules/home/sops
#       sops secrets/secrets.yaml
#       # add keys:
#       #   google_oauth_client_id: <client_id from step 4>
#       #   google_oauth_client_secret: <client_secret from step 4>
#  6. After `home-manager switch`, run the auth flow once:
#       npx -y @dguido/google-workspace-mcp auth
#     This opens a browser, grants access, and writes
#     ~/.config/google-workspace-mcp/tokens.json.
#     Tokens auto-refresh — you only do this once unless you revoke access.
#
# ── Tools available to pi after setup ───────────────────────────────────────
#  Gmail (6 tools):    search_emails, get_email, send_email, create_draft,
#                      list_labels, modify_email_labels
#  Drive (5 tools):    search_files, get_file, list_files, create_file,
#                      download_file
#  Sheets (7 tools):   get_spreadsheet, get_values, update_values,
#                      batch_update_values, append_values, clear_values,
#                      create_spreadsheet
#  Docs (5 tools):     get_document, create_document, update_document,
#                      append_text, insert_text
#  Calendar (6 tools): list_calendars, list_events, get_event,
#                      create_event, update_event, delete_event
#  Contacts (3 tools): list_contacts, get_contact, search_contacts
#
{...}: {
  flake.modules.homeManager.google-workspace = {
    lib,
    config,
    pkgs,
    ...
  }: let
    # Services exposed to pi. Adjust to taste — adding "calendar" or "docs"
    # here requires the corresponding API to be enabled in GCP.
    workspaceServices = "drive,gmail,sheets,docs,calendar,contacts";

    # Path where @dguido/google-workspace-mcp stores its credentials.
    credentialsDir = "${config.home.homeDirectory}/.config/google-workspace-mcp";

    # Convenience: only wire up the secrets and activation if is_private.
    # This keeps the aspect safe to fold into a corporate config that provides
    # its own GCP project / credentials separately.
    isPrivate = config.my.is_private;
  in {
    # ── MCP server declaration ─────────────────────────────────────────────
    # pi-mcp-adapter reads ~/.pi/agent/mcp.json at startup.
    # This is a static file (no secrets) — credentials live in credentials.json.
    # NOTE: home.file creates a read-only symlink; pi-mcp-adapter only reads
    #       this file, it never writes to it, so read-only is fine.
    home.file.".pi/agent/mcp.json".text = builtins.toJSON {
      mcpServers = {
        google-workspace = {
          type = "stdio";
          command = "npx";
          args = ["-y" "@dguido/google-workspace-mcp"];
          env = {
            GOOGLE_WORKSPACE_SERVICES = workspaceServices;
            # credentials.json is picked up automatically from credentialsDir;
            # no GOOGLE_CLIENT_ID env var needed when the file is present.
          };
        };
      };
    };

    # ── Sops secrets (private env only) ────────────────────────────────────
    sops.secrets = lib.mkIf isPrivate {
      google_oauth_client_id = {};
      google_oauth_client_secret = {};
    };

    # ── Write credentials.json at activation time ───────────────────────────
    # home.activation runs after sops has decrypted secrets, so we can safely
    # read the secret paths here.  The file is written at 0600 so only the
    # owner can read it.
    home.activation.writeGoogleWorkspaceCreds = lib.mkIf isPrivate (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        _creds_dir="${credentialsDir}"
        _creds_file="$_creds_dir/credentials.json"

        if [ -f "${config.sops.secrets.google_oauth_client_id.path}" ] && \
           [ -f "${config.sops.secrets.google_oauth_client_secret.path}" ]; then

          $DRY_RUN_CMD mkdir -p "$_creds_dir"

          # Write as a temp file first, then atomically move into place.
          _tmp="$(mktemp "$_creds_dir/.credentials.XXXXXX")"
          chmod 600 "$_tmp"

          CLIENT_ID="$(cat "${config.sops.secrets.google_oauth_client_id.path}")"
          CLIENT_SECRET="$(cat "${config.sops.secrets.google_oauth_client_secret.path}")"

          printf '%s' "{\"installed\":{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\",\"redirect_uris\":[\"urn:ietf:wg:oauth:2.0:oob\",\"http://localhost\"],\"auth_uri\":\"https://accounts.google.com/o/oauth2/auth\",\"token_uri\":\"https://oauth2.googleapis.com/token\"}}" \
            > "$_tmp"
          mv "$_tmp" "$_creds_file"

          echo "google-workspace: wrote $PWD/$_creds_file" >&2
        else
          echo "google-workspace: sops secrets not yet decrypted, skipping credentials.json" >&2
        fi
      ''
    );
  };
}
