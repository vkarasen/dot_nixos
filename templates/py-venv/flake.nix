{
  description = "Python/Snakemake development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";

    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs;
        [
          snakemake
          python312
        ]
        ++ (with pkgs.python312Packages; [
          numpy
          pandas
          matplotlib
        ]);
      shellHook =
        #bash
        ''
          python -m venv .venv
          . .venv/bin/activate
        '';
    };
  };
}
