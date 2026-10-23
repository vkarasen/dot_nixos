{
  flake.templates = {
    py-venv = {
      path = ../../templates/py-venv;
      description = "Python/Snakemake development environment";
    };
    latex = {
      path = ../../templates/latex;
      description = "latex development template";
    };
    rust = {
      path = ../../templates/rust;
      description = "Rust workspace template — flake-parts + crane + fenix (checks, static musl, devshell)";
    };
    jekyll = {
      path = ../../templates/jekyll;
      description = "Jekyll template";
    };
  };
}
