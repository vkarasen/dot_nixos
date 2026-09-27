# Dendritic aspect: keepass (home-manager class) — KeePassXC password vault.
# Selected by core.nix (the universal bundle), so it is evaluated on every host
# and gates itself internally:
#   * CLI access (keepassxc-cli, kpcli, keepass-diff) on any private host,
#     including headless machines that can reach the vault over Nextcloud.
#   * GUI app + browser integration on private GUI hosts only.
#
# The vault file is /home/vkarasen/sync/private/bishoppasswords.kdbx (inside the
# Nextcloud-synced ~/sync folder, NOT the rclone FUSE mounts /mnt/gdrive and
# /mnt/nextcloud). programs.keepassxc.enable auto-installs KeePassXC's
# native-messaging manifest, which lets the KeePassXC-Browser extension (declared
# below) talk to the running, unlocked app.
#
# programs.keepassxc.settings makes home-manager own keepassxc.ini (a read-only
# store symlink), so GUI settings changes no longer persist — edit them here.
# Browser.UpdateBinaryPath = false is the home-manager #8257 workaround that
# stops KeePassXC trying to rewrite the read-only ini on startup.
{inputs, ...}: {
  flake.modules.homeManager.keepass = {
    pkgs,
    config,
    lib,
    ...
  }: {
    # CLI access on any private host (GUI or headless): keepassxc provides
    # keepassxc-cli (scriptable reads/export), kpcli is interactive, keepass-diff
    # diffs .kdbx files. keepassxc itself is only listed for headless hosts —
    # on GUI hosts programs.keepassxc.enable already installs it.
    home.packages = lib.mkIf config.my.is_private (with pkgs;
      [
        keepass-diff
        kpcli
      ]
      ++ lib.optional (!config.my.gui.enable) keepassxc);

    # GUI app + browser integration, only on private GUI hosts.
    programs.keepassxc = lib.mkIf (config.my.is_private && config.my.gui.enable) {
      enable = true;
      settings = {
        General = {ConfigVersion = 2;};
        Browser = {
          Enabled = true;
          # home-manager #8257: stop KeePassXC rewriting the read-only ini to
          # fix up the native-messaging manifest path.
          UpdateBinaryPath = false;
        };
        GUI = {
          ApplicationTheme = "classic"; # follow the Kvantum/catppuccin theme
          MinimizeOnClose = true; # close hides to tray instead of quitting
          MinimizeToTray = true;
          ShowTrayIcon = true;
          TrayIconAppearance = "colorful";
        };
        PasswordGenerator = {
          AdditionalChars = "";
          ExcludedChars = "";
        };
        Security = {
          LockDatabaseIdle = false;
          LockDatabaseScreenLock = false;
        };
      };
    };

    # The KeePassXC-Browser Firefox extension, attached to the vkarasen profile
    # (declared in modules/home/browser.nix). Kept here — not in browser.nix — so
    # the whole KeePass concern (app + service + extension) lives in one aspect
    # that can be ripped out as a unit. Inert unless Firefox is enabled.
    programs.firefox.profiles."vkarasen".extensions.packages = lib.mkIf (config.my.is_private && config.my.gui.enable) [
      inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.keepassxc-browser
    ];

    # Home-manager refuses to clobber a pre-existing writable keepassxc.ini (the
    # one this repo used to leave in place). We own the file now, and the old
    # copy held the KeeShare private key we are deliberately dropping, so
    # overwrite it without keeping a backup of the secret.
    xdg.configFile."keepassxc/keepassxc.ini".force = true;

    # Start minimized to the system tray (vault stays locked until first unlock
    # via the browser extension). Repo idiom for login-time GUI apps: a systemd
    # user service After graphical-session.target (see modules/home/hyprmoncfg).
    systemd.user.services.keepassxc = lib.mkIf (config.my.is_private && config.my.gui.enable) {
      Unit = {
        Description = "KeePassXC password manager";
        After = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.keepassxc}/bin/keepassxc --minimized";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install = {WantedBy = ["default.target"];};
    };
  };
}
