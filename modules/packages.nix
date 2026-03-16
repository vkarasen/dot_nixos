# Standalone nixvim package
{ inputs, ... }: {
  perSystem = { pkgs, system, ... }: {
    packages.nvim = inputs.nixvim.legacyPackages.${system}.makeNixvimWithModule {
      inherit pkgs;
      module = import ./_nixvim/standalone.nix;
    };
  };
}

