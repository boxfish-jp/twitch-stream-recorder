{
  description = "Twitch Stream Recorder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem = nixpkgs.lib.genAttrs supportedSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          formatter = pkgs.nixfmt-tree;
          packages.default = pkgs.stdenv.mkDerivation {
            pname = "twitch-stream-recorder";
            version = "0.1.0";
            src = ./.;
            dontBuild = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase = ''
              runHook preInstall

              mkdir -p $out/lib/twitch-stream-recorder
              cp twitch-recorder.py $out/lib/twitch-stream-recorder/twitch-recorder.py

              pythonEnv=${pkgs.python3.withPackages (ps: [ ps.requests ])}
              makeWrapper "$pythonEnv/bin/python" $out/bin/twitch-stream-recorder \
                --add-flags "$out/lib/twitch-stream-recorder/twitch-recorder.py" \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.streamlink
                    pkgs.ffmpeg
                  ]
                }

              runHook postInstall
            '';
          };
        }
      );
      collect = name: nixpkgs.lib.mapAttrs (_: system: system.${name}) perSystem;
    in
    {
      formatter = collect "formatter";
      packages = collect "packages";

      homeModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.twitch-recorder;
        in
        {
          options.services.twitch-recorder = {
            enable = lib.mkEnableOption "Twitch Stream Recorder";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The twitch-stream-recorder package to use.";
            };

            username = lib.mkOption {
              type = lib.types.str;
              description = "Twitch username to record by default.";
            };

            quality = lib.mkOption {
              type = lib.types.str;
              default = "best";
              description = "Stream quality to record.";
            };

            rootPath = lib.mkOption {
              type = lib.types.str;
              default = "${config.home.homeDirectory}/Videos/twitch";
              description = "Root directory where recordings are stored.";
            };

            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                File containing TWITCH_CLIENT_ID and TWITCH_CLIENT_SECRET.
              '';
            };

            extraEnvironment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional environment variables for the service.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.user.services.twitch-recorder = {
              Unit = {
                Description = "Twitch Stream Recorder";
                After = [
                  "graphical-session.target"
                  "network.target"
                ];
                Wants = [
                  "graphical-session.target"
                  "network-online.target"
                ];
              };

              Service = {
                Type = "simple";
                ExecStart =
                  "${cfg.package}/bin/twitch-stream-recorder"
                  + " --username ${cfg.username}"
                  + " --quality ${cfg.quality}";
                Environment = [
                  "TWITCH_ROOT_PATH=${cfg.rootPath}"
                ]
                ++ (lib.mapAttrsToList (name: value: "${name}=${value}") cfg.extraEnvironment);
                EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
                Restart = "on-failure";
                RestartSec = 30;
              };

              Install.WantedBy = [ "graphical-session.target" ];
            };
          };
        };
    };
}
