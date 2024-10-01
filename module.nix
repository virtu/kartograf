flake: { config, pkgs, lib, ... }:

with lib;

let
  inherit (flake.packages.${pkgs.stdenv.hostPlatform.system}) kartograf;
  cfg = config.services.kartograf;
  postScript = pkgs.writeScriptBin "post-script" /* bash */ ''
    #!/${pkgs.bash}/bin/bash
    timestamp=$(${pkgs.findutils}/bin/find out -mindepth 1 -maxdepth 1 -type d | ${pkgs.coreutils}/bin/cut -d/ -f2)
    mv out/$timestamp/final_result.txt ${cfg.resultPath}/asmap-$timestamp.txt
    echo "Copied result from /out/$timestamp/final_result.txt to ${cfg.resultPath}/asmap-$timestamp.txt"
    rm -rf data out
    echo "Cleaned up temporary directories."
  '';
in
{
  options.services.kartograf = {
    enable = mkEnableOption "kartograf";
    clean = mkEnableOption "cleaning up of temporary artifacts after processing." // { default = true; };
    silent = mkEnableOption "silencing output (suppresses pandarallel's progress_bar)." // { default = true; };
    useIRR = mkEnableOption "using Internet Routing Registry (IRR) data" // { default = true; };
    useRV = mkEnableOption "using RouteViews (RV) data" // { default = true; };
    workers = mkOption {
      type = types.int;
      default = 0;
      example = 4;
      description = mdDoc "Number of workers to use for pandarallel (0 = use all available cores).";
    };
    schedule = mkOption {
      type = types.str;
      default = "*-*-01 00:00:00 UTC";
      example = "monthly";
      description = mdDoc "Systemd OnCalendar setting for kartograf.";
    };
    resultPath = mkOption {
      type = types.path;
      default = "/home/kartograf/";
      example = "/scratch/results/kartograf/";
      description = mdDoc "Directory for results.";
    };
  };

  config = mkIf cfg.enable {
    users = {
      users.kartograf = {
        isSystemUser = true;
        group = "kartograf";
        home = "/home/kartograf";
        createHome = true;
        homeMode = "755";
      };
      groups.kartograf = { };
    };

    systemd.timers.kartograf = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Unit = [ "kartograf.service" ];
      };
    };

    systemd.services.kartograf = {
      description = "kartograf";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Environment = "PYTHONUNBUFFERED=1";
        ExecStopPost = "${postScript}/bin/post-script";
        ExecStart = ''${kartograf}/bin/kartograf map \
          ${optionalString cfg.clean "--cleanup" } \
          ${optionalString cfg.silent "--silent" } \
          ${optionalString cfg.useIRR "--irr" } \
          ${optionalString cfg.useRV "--routeviews" } \
          ${optionalString (cfg.workers != 0) "--workers=${toString cfg.workers}" } \
        '';
        MemoryDenyWriteExecute = true;
        WorkingDirectory = cfg.resultPath;
        ReadWriteDirectories = cfg.resultPath;
        User = "kartograf";
        Group = "kartograf";
      };
    };
  };
}
