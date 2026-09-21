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
#   - manual lock via SUPER+L (desktop concern; see modules/home/desktop.nix)
#   - this aspect (greetd + hyprlock PAM) is a GUI/login concern, kept for every
#     GUI host even though only laptops auto-lock
{...}: {
  flake.modules.nixos.lock = {...}: {
    # hyprlock — enables the package and its PAM service (needed to unlock).
    programs.hyprlock.enable = true;

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
