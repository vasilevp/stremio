{
  description = "Stremio - Freedom to Stream";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [rust-overlay.overlays.default];
          config.allowUnfree = true;
        };
        rustToolchain = pkgs.rust-bin.nightly.latest.default;

        runtimeLibs = with pkgs; [
          alsa-lib
          atk
          cairo
          cups
          dbus
          expat
          gtk3
          libappindicator-gtk3
          libgbm
          libglvnd
          libxkbcommon
          nspr
          nss
          systemdMinimal
          xorg.libX11
          xorg.libxcb
          xorg.libXcomposite
          xorg.libXdamage
          xorg.libXext
          xorg.libXfixes
          xorg.libXrandr
          nodejs
        ];
      in {
        packages = {
          cef = pkgs.stdenv.mkDerivation {
            pname = "cef-minimal";
            version = "138.0.21";

            src = pkgs.fetchurl {
              url = "https://cef-builds.spotifycdn.com/cef_binary_138.0.21%2Bg54811fe%2Bchromium-138.0.7204.101_linux64_minimal.tar.bz2";
              sha256 = "sha256-Kob/5lPdZc9JIPxzqiJXNSMaxLuAvNQKdd/AZDiXvNI=";
            };

            nativeBuildInputs = [pkgs.autoPatchelfHook];
            buildInputs = runtimeLibs;

            installPhase = ''
              mkdir -p $out
              cp -r Release/* $out/
              cp -r Resources/* $out/
            '';
          };

          default = pkgs.rustPlatform.buildRustPackage {
            pname = "stremio-linux-shell";
            version = "1.0.0-beta.13";

            src = pkgs.fetchFromGitHub {
              owner = "Stremio";
              repo = "stremio-linux-shell";
              rev = "v1.0.0-beta.13";
              sha256 = "sha256-1f9IBNo5gxpSqTSIf8QuQOlf+sfRhohOmQTLRbX/OU8=";
            };

            cargoHash = "sha256-wx5oF4uF9UMtKzfGxZKsy6mVjYaRD40dLuvaRtz8yE4=";

            nativeBuildInputs = with pkgs; [
              rustToolchain
              pkg-config
              makeWrapper
            ];

            buildInputs = with pkgs;
              [
                gtk3
                mpv
                openssl
              ]
              ++ runtimeLibs;

            preBuild = ''
              export CEF_PATH="${self.packages.${system}.cef}"
            '';

            buildFeatures = ["offline-build"];

            postInstall = ''
              # Copy CEF vendor directory
              mkdir -p $out/lib
              cp -r vendor/cef $out/lib/ || true

              # Install server.js
              install -Dm644 data/server.js $out/bin/server.js

              # Install desktop file and substitute paths
              install -Dm644 data/com.stremio.Stremio.desktop $out/share/applications/com.stremio.Stremio.desktop
              substituteInPlace $out/share/applications/com.stremio.Stremio.desktop \
                --replace "Exec=stremio" "Exec=$out/bin/stremio-linux-shell"

              # Install icons
              for size in 16 22 24 32 48 64 128 256; do
                if [ -f data/icons/hicolor/''${size}x''${size}/apps/com.stremio.Stremio.png ]; then
                  install -Dm644 data/icons/hicolor/''${size}x''${size}/apps/com.stremio.Stremio.png \
                    $out/share/icons/hicolor/''${size}x''${size}/apps/com.stremio.Stremio.png
                fi
              done

              # Install metainfo
              if [ -f data/com.stremio.Stremio.metainfo.xml ]; then
                install -Dm644 data/com.stremio.Stremio.metainfo.xml \
                  $out/share/metainfo/com.stremio.Stremio.metainfo.xml
              fi

              # Wrap binary with proper library path
              wrapProgram $out/bin/stremio-linux-shell \
                --prefix PATH : "${pkgs.nodejs}/bin" \
                --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}" \
                --prefix LD_LIBRARY_PATH : "$out/lib/cef" \
                --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib"
            '';

            meta = with pkgs.lib; {
              description = "Stremio - Freedom to Stream";
              homepage = "https://www.stremio.com/";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              maintainers = [];
            };
          };
        };
      }
    );
}
