# Dendritic aspect: lock (NixOS class) — lock screen (hyprlock), idle daemon
# (hypridle), and the login greeter (greetd + ReGreet).
#
# Lock policy:
#   - never auto-lock on idle — hypridle's idle listener (suspend on battery)
#     lives in modules/home/laptop.nix; locking happens via before_sleep_cmd
#     right before suspend, not on idle
#   - lock right before suspend/hibernate (before_sleep_cmd = hyprlock), so the
#     machine always wakes to the lock screen (laptop only — a desktop PC never
#     auto-suspends, so it never auto-locks)
#   - manual lock via SUPER+ESC (desktop concern; see modules/home/desktop.nix)
#   - this aspect (greetd + hyprlock PAM) is a GUI/login concern, kept for every
#     GUI host even though only laptops auto-lock
{...}: {
  flake.modules.nixos.lock = {
    config,
    lib,
    ...
  }: {
    # hyprlock — enables the package and its PAM service (needed to unlock).
    programs.hyprlock.enable = true;

    # programs.hyprlock drags in services.hypridle as a dependency, but hypridle
    # is only meaningful where its config exists: ~/.config/hypr/hypridle.conf
    # is written by the home laptop aspect (modules/home/laptop.nix, selected only
    # on laptop hosts). Unconfigured, it exits, hits the start-limit and leaves a
    # failed unit on every desktop boot. So track the NixOS-side laptop flag:
    # true on laptops (nixos.laptop sets my.laptop.enable, which only laptop
    # hosts import) and false on desktops, which lock manually (see the header).
    services.hypridle.enable = lib.mkForce config.my.laptop.enable;

    # Unlock the user's gnome-keyring with the login password, so nm-applet
    # can read stored wifi PSKs without a separate keyring-unlock prompt.
    # greetd's PAM stack just substacks/includes `login`, so the module must
    # be wired here for it to run during greetd auth/session.
    security.pam.services.login.enableGnomeKeyring = true;

    # Login screen: greetd + ReGreet (GTK). Replaces the TTY auto-start.
    services.displayManager.regreet = {
      enable = true;
      # Single user + single session: skip the user/session selection UI.
      settings.skip_selection = true;
    };
  };
}
