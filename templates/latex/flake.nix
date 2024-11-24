{
  description = "Flake for latex dev";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    with flake-utils.lib;
      eachSystem allSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};

        buildInputs = with pkgs;
          [
            coreutils
            snakemake
            python312
            texlive.combined.scheme-full
            bash
          ]
          ++ (with pkgs.python312Packages; [
            numpy
            matplotlib
            pygments
          ]);
      in rec {
        devShells.default = pkgs.mkShell {
          inherit buildInputs;
        };
        packages = {
          document = pkgs.stdenvNoCC.mkDerivation rec {
            inherit buildInputs;
            name = "latex flake template";
            src = self;
            phases = ["unpackPhase" "buildPhase" "installPhase"];
            buildPhase = ''
              export PATH="${pkgs.lib.makeBinPath buildInputs}"
			  export HOME=.
              env SOURCE_DATE_EPOCH=${toString self.lastModified} \
              snakemake -c 1
            '';
            installPhase = ''
              mkdir -p $out
              cp KarasenkoPhD.pdf outline.pdf $out/
            '';
          };
        };
        defaultPackage = packages.document;
      });
}
