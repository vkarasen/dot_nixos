# Dendritic aspect: tickrs (home-manager class).
{...}: {
  flake.modules.homeManager.tickrs = {pkgs, ...}: let
    tickrsConfig = {
      symbols = [
        "CDNS"
        "SNPS"
        "INTC"
        "QCOM"
        "ARM"
        "NVDA"
        "AMD"
        "AAPL"
        "MSFT"
        "GOOG"
        "META"
        "SPY"
        "GC=F"
      ];
      show_x_labels = true;
      show_volumes = true;
      summary = true;
      update_interval = 10;
    };
    yaml = pkgs.formats.yaml {};
  in {
    home.packages = [pkgs.tickrs];

    xdg.configFile."tickrs/config.yml" = {
      source = yaml.generate "tickrs-config.yml" tickrsConfig;
      force = true;
    };
  };
}
