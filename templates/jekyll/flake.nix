{
  description = "Pablo's Cooking Website";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      gems = pkgs.bundlerEnv {
        name = "gems";
        ruby = pkgs.ruby;
        gemdir = "./.";
      };
    in
      with pkgs; {
        devShells.default = mkShell {
          buildInputs = [gems bundix];
          BUNDLE_FORCE_RUBY_PLATFORM = "true";
        };
        packages.default = stdenv.mkDerivation {
          name = "Cooking";
          src = self;
          buildInputs = [gems];
          buildPhase =
            #bash
            ''
              ${gems}/bin/jekyll build
            '';
          installPhase =
            #bash
            ''
              mkdir -p $out
              cp -r _site $out/_site
            '';
        };
      });
}
