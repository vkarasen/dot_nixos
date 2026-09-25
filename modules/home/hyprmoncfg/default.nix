# Dendritic aspect: hyprmoncfg (home-manager class).
# Dynamic monitor profile manager for Hyprland: auto-switches layouts by
# connected hardware set and re-applies saved arrangements, including
# clamshell (lid) and undock realignment. Replaces nwg-displays.
#
# Built from upstream crmne/hyprmoncfg @ v1.19.1 because nixpkgs ships a stale
# 1.9.1. v1.19.1 handles lid/clamshell natively: the closed-lid policy no longer
# loops remove/add on troy's eDP panel, which stays DRM-connected while shut.
# Drop the derivation below once nixpkgs catches up.
{inputs, ...}: {
  flake.modules.homeManager.hyprmoncfg = {
    pkgs,
    lib,
    ...
  }: let
    hyprmoncfg = pkgs.buildGoModule {
      pname = "hyprmoncfg";
      version = "0-unstable";
      src = inputs.hyprmoncfg;
      subPackages = ["cmd/hyprmoncfg" "cmd/hyprmoncfgd"];
      proxyVendor = true;
      vendorHash = "sha256-97z4+U/SumG5sidy62SW43E+Bi6FpvJKCI6wqwXts2g=";
      # buildGoModule already injects CGO_ENABLED into `env`; the derivation-arg
      # form conflicts, so override it in `env` instead.
      env.CGO_ENABLED = "0";
      nativeBuildInputs = [pkgs.makeWrapper];
      postInstall = ''
        wrapProgram $out/bin/hyprmoncfg --prefix PATH : ${lib.makeBinPath [pkgs.hyprland]}
        wrapProgram $out/bin/hyprmoncfgd --prefix PATH : ${lib.makeBinPath [pkgs.hyprland]}
      '';
    };
  in {
    home.packages = [hyprmoncfg];

    # Mirrors upstream packaging/systemd/hyprmoncfgd.service.
    systemd.user.services.hyprmoncfgd = {
      Unit = {
        Description = "Hyprland monitor profile daemon (hyprmoncfgd)";
        After = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${hyprmoncfg}/bin/hyprmoncfgd";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install = {WantedBy = ["default.target"];};
    };

    # hyprmoncfg writes ~/.config/hypr/hyprmoncfg-monitors.lua and appends a
    # guarded dofile(...) line to the Hyprland root config. home-manager owns
    # that config (regenerated on switch), so we declare the include here; the
    # daemon's EnsureIncluded recognises this exact line and leaves it alone.
    # The guard means a not-yet-generated file is not a fatal load error.
    wayland.windowManager.hyprland.extraConfig = ''
      -- Added by hyprmoncfg: its generated monitor rules load last
      do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
    '';
  };
}
