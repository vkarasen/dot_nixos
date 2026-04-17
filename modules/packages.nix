# Standalone nixvim package built from the merged nixvim aspect modules
{ inputs, self, ... }: {
  perSystem = { pkgs, system, ... }: {
    packages.nvim = inputs.nixvim.legacyPackages.${system}.makeNixvimWithModule {
      inherit pkgs;
      module = {
        imports = [ self.modules.nixvim.standalone ];
      };
    };
  };
}

