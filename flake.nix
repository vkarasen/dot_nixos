{
  description = "I am a very special flake";

  # Inputs are managed by tack (.tack/pins.toml + .tack/pins.lock.json). This
  # flake deliberately declares no `inputs`: use `tack update` / `tack freeze` /
  # `tack add` / `tack rm` instead of `nix flake lock --update-input`.
  #
  # flake-parts defaults `self` to `inputs.self`, and perSystem derives
  # `inputs'`/`pkgs` from `self.inputs` — so we thread `self` through mkFlake
  # and rebind `self.inputs` to the tack input set (mirrors flake-parts'
  # extras/partitions.nix).

  outputs = { self, ... }@args:
    let
      tack = (import ./.tack) { overrides = args.tackOverrides or { }; };
      inputs = tack // { self = self'; };
      self' = self // { inherit inputs; };
    in
      tack.flake-parts.lib.mkFlake {
        inherit inputs;
        self = self';
      } (tack.import-tree ./modules);
}
