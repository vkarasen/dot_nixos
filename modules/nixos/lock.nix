# Dendritic aspect: lock (NixOS class) — lock screen (hyprlock), idle daemon
# (hypridle), and the login greeter (greetd + ReGreet).
#
# Lock policy (see modules/home/desktop.nix for the user-level config):
#   - never auto-lock on idle (hypridle has no idle listeners)
#   - lock right before suspend/hibernate (before_sleep_cmd = hyprlock), so the
#     machine always wakes to the lock screen
#   - manual lock via SUPER+L
{...}: {
  flake.modules.nixos.lock = {...}: {
    # hyprlock — enables the package and its PAM service (needed to unlock).
    programs.hyprlock.enable = true;

    # Login screen: greetd + ReGreet (GTK). Replaces the TTY auto-start.
    services.displayManager.regreet.enable = true;
  };
}
