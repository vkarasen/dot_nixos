# Dendritic aspect: gnome-keyring (NixOS class) — PAM auto-unlock for the
# login keyring (nm-applet / Secret Service wifi PSKs). The user-side daemon
# is modules/home/desktop.nix (services.gnome-keyring); this enables the
# system side, which wires pam_gnome_keyring into the `login` PAM service so
# the login keyring unlocks with the login password at login. It also installs
# a setuid wrapper granting gnome-keyring-daemon cap_ipc_lock (mlock secrets).
{...}: {
  flake.modules.nixos.gnome-keyring = {config, ...}: {
    services.gnome.gnome-keyring.enable = true;
  };
}
