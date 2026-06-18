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
      description = "rust template using naersk";
    };
    jekyll = {
      path = ../../templates/jekyll;
      description = "Jekyll template";
    };
  };
}
