{
  description = "claude-mac-chrome dev shell — pinned toolchain for reproducible test + release builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShells.default = pkgs.mkShell {
        name = "claude-mac-chrome-dev";
        buildInputs = with pkgs; [
          # Shell hygiene
          bash
          bats
          shellcheck
          shfmt

          # Parsing / JSON
          jq

          # Reproducible release
          gnutar
          coreutils
          diffoscope

          # Supply chain
          cosign
          syft # CycloneDX SBOM generator

          # Test harness (happy-dom + fuzzers)
          nodejs_20
          radamsa
        ];

        shellHook = ''
          echo "claude-mac-chrome dev shell"
          echo "  bash:       $(bash --version | head -n1)"
          echo "  bats:       $(bats --version 2>/dev/null || echo missing)"
          echo "  shellcheck: $(shellcheck --version | sed -n 's/^version: //p')"
          echo "  shfmt:      $(shfmt --version)"
          echo "  jq:         $(jq --version)"
          echo "  node:       $(node --version)"
        '';
      };

      checks.default = pkgs.runCommand "claude-mac-chrome-lint" {
        buildInputs = with pkgs; [bash shellcheck shfmt bats jq];
      } ''
        cd ${./.}
        bash scripts/lint.sh
        touch $out
      '';
    });
}
