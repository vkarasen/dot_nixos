# Helper (underscore-prefixed ⇒ ignored by import-tree): the derivation for a
# single-file Bun executable of pi. Consumed by reference from the overlay in
# parts.nix (so `pkgs.pi-bun` exists in every pkgs instance this flake builds,
# including the home-manager configs, which share the perSystem pkgs) and
# surfaced as `packages.pi-bun` by the sibling pi-bun.nix.
#
# It reuses nixpkgs' `pi-coding-agent` output instead of re-running the npm
# workspace build: that output already contains the built `dist/` (including
# `dist/bun/cli.js`, the Bun entrypoint) plus the runtime `node_modules`. Only
# the two extra entrypoints and the static assets come from the source tree,
# because buildNpmPackage does not ship `packages/coding-agent/src/`.
#
# Upstream's own `build:binary` is reproduced here, minus:
#   * the per-workspace `npm --prefix ../<pkg> run build` steps — nixpkgs
#     already ran them;
#   * `--bytecode` — bun 1.4.2 and 1.3.13 cannot generate bytecode for this
#     bundle. Minimal repro: any ESM entry using top-level await fails with
#     `"await" can only be used inside an "async" function` (bun's bytecode
#     path parses the entry as non-async), while the full bundle either panics
#     (`index out of bounds`, exit 134) or silently emits a binary that dies
#     with `SyntaxError: import.meta is only valid inside modules`. Without the
#     flag the binary builds, boots, loads .ts extensions and finds its assets.
{
  pkgs,
  lib,
  ...
}: let
  pi = pkgs.pi-coding-agent;
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "pi-bun";
    inherit (pi) version;

    dontUnpack = true;
    dontConfigure = true;
    # A Bun single-file executable embeds its runtime and bundled payload after
    # the ELF; stripping or patchelf-ing it corrupts the executable.
    dontPatchELF = true;
    dontStrip = true;
    strictDeps = true;

    nativeBuildInputs = [
      pkgs.bun
      pkgs.makeWrapper
    ];

    buildPhase = ''
      runHook preBuild

      mkdir -p work
      cp -r ${pi}/lib/node_modules/pi-monorepo/. work/
      cp -r ${pi.src}/packages/coding-agent/src work/
      chmod -R u+w work
      cd work

      # Bun wants a writable HOME; the sandbox HOME is read-only. Nothing here
      # touches the network.
      export HOME="$TMPDIR"

      bun build --compile \
        --no-compile-autoload-bunfig \
        ./dist/bun/cli.js \
        ./src/utils/image-resize-worker.ts \
        ./src/extensions/codemode/worker.ts \
        --outfile dist/pi

      # `npm run copy-binary-assets` inlined: it shells out to shx, a pruned
      # devDependency, so the npm script cannot run in this derivation.
      cp package.json README.md CHANGELOG.md dist/
      mkdir -p dist/theme dist/assets dist/export-html/vendor
      cp src/modes/interactive/theme/*.json dist/theme/
      cp src/modes/interactive/assets/*.png dist/assets/
      cp src/core/export-html/template.html dist/export-html/
      cp src/core/export-html/vendor/*.js dist/export-html/vendor/
      cp -r docs examples dist/
      cp node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm dist/

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # `getPackageDir()` is `dirname(process.execPath)` for a Bun binary, and
      # process.execPath resolves symlinks — so the executable has to live IN
      # the asset directory. `bin/pi` is created below as a symlink to it; the
      # wrapProgram in postFixup then replaces that symlink with a wrapper
      # script that execs the same absolute path (the symlink survives as
      # `bin/.pi-wrapped`), so getPackageDir() still lands on
      # $out/libexec/pi-dist either way. The layout below is exactly what
      # `copy-binary-assets` produces; `dist/` itself is embedded in the
      # executable and is not needed on disk.
      mkdir -p $out/libexec/pi-dist
      install -m755 dist/pi $out/libexec/pi-dist/pi
      cp package.json README.md CHANGELOG.md $out/libexec/pi-dist/
      cp -r \
        dist/theme dist/assets dist/export-html dist/docs dist/examples \
        dist/photon_rs_bg.wasm \
        $out/libexec/pi-dist/
      mkdir -p $out/bin
      ln -s $out/libexec/pi-dist/pi $out/bin/pi

      runHook postInstall
    '';

    postFixup = ''
      # The same wrapper nixpkgs puts around the Node build: grep/find tools on
      # PATH, plus the version-check/telemetry defaults that keep pi hermetic.
      wrapProgram $out/bin/pi \
        --prefix PATH : ${lib.makeBinPath [pkgs.ripgrep pkgs.fd]} \
        --set-default PI_SKIP_VERSION_CHECK 1 \
        --set-default PI_TELEMETRY 0
    '';

    meta = {
      description = "pi coding agent built as a single-file Bun executable";
      inherit (pi.meta) license platforms;
      mainProgram = "pi";
    };
  }
