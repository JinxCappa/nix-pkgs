{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.remotepc-host;
  optDir = "/opt/remotepc-host";
  package = cfg.package;
  appDir = "${package}/opt/remotepc-host";
  electron = "${appDir}/remotepc-host";
  appAsar = "${appDir}/resources/app.asar";

  servicePath = [
    pkgs.bashNonInteractive
    pkgs.coreutils
    pkgs.dbus
    pkgs.dmidecode
    pkgs.ethtool
    pkgs.findutils
    pkgs.gawk
    pkgs.getent
    pkgs.gnugrep
    pkgs.gnused
    pkgs.hwinfo
    pkgs.libnotify
    pkgs.procps
    pkgs.sudo
    pkgs.systemd
    pkgs.util-linux
    pkgs.xdotool
    pkgs.xinput
    pkgs.xrandr
    pkgs.xsel
  ];
  servicePathText = "/run/wrappers/bin:${lib.makeBinPath servicePath}";
  compatSh = pkgs.writeShellScript "remotepc-host-compat-sh" ''
    keep_env=("PATH=${servicePathText}")
    for name in \
      APP \
      DBUS_SESSION_BUS_ADDRESS \
      DESKTOP_SESSION \
      DISPLAY \
      DISPLAY_VARIABLE \
      ELECTRON_RUN_AS_NODE \
      HOME \
      LD_LIBRARY_PATH \
      LOCALE_ARCHIVE \
      LOG_LEVEL \
      LOGNAME \
      MESA_NO_WARNINGS \
      NODE_NO_WARNINGS \
      SESSION_TYPE \
      TZDIR \
      UID \
      USER \
      VIEWER_MACHINE_ID \
      WAYLAND_DISPLAY \
      XAUTHORITY \
      XAUTH_VARIABLE \
      XDG_CURRENT_DESKTOP \
      XDG_RUNTIME_DIR \
      XDG_SESSION_TYPE
    do
      if [ "''${!name+x}" = x ]; then
        keep_env+=("$name=''${!name}")
      fi
    done
    exec ${pkgs.coreutils}/bin/env -i "''${keep_env[@]}" ${pkgs.bashNonInteractive}/bin/sh "$@"
  '';

  commonEnvironment = {
    NODE_NO_WARNINGS = "1";
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      pkgs.libglvnd
      pkgs.mesa
    ];
    PATH = lib.mkForce servicePathText;
  };

  nodeService = entry: {
    path = servicePath;
    environment = commonEnvironment // {
      ELECTRON_RUN_AS_NODE = "1";
      APP = "remotepc-host";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${electron} ${appAsar}/${entry}";
    };
  };
in
{
  options.services.remotepc-host = {
    enable = lib.mkEnableOption "RemotePC Host daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default =
        pkgs.remotepc-host or
          (throw "services.remotepc-host.package must be set to the remotepc-host package");
      defaultText = lib.literalExpression "pkgs.remotepc-host";
      description = "RemotePC Host package to run.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package ];

    system.activationScripts.remotepcHostOpt = lib.stringAfter [ "usrbinenv" ] ''
      mkdir -p ${optDir} ${optDir}/resources /var/log/remotepc-host

      for path in ${appDir}/* ${appDir}/.[!.]*; do
        name="$(basename "$path")"
        case "$name" in
          .|..|resources) continue ;;
        esac
        ln -sfn "$path" "${optDir}/$name"
      done

      for path in ${appDir}/resources/*; do
        name="$(basename "$path")"
        case "$name" in
          setupComplete) continue ;;
        esac
        ln -sfn "$path" "${optDir}/resources/$name"
      done

      touch ${optDir}/resources/setupComplete
    '';

    systemd.services.remotepc-host = {
      description = "RemotePC Enterprise Host remote control daemon";
      after = [
        "network.target"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = servicePath;
      environment = commonEnvironment // {
        ELECTRON_RUN_AS_NODE = "1";
        APP = "remotepc-host";
        MESA_NO_WARNINGS = "1";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${package}/bin/.remotepc-host-daemon";
        BindReadOnlyPaths = [ "${compatSh}:/bin/sh" ];
        Restart = "on-failure";
        StartLimitIntervalSec = 60;
        StartLimitBurst = 10;
      };
    };

    systemd.services.remotepc-host-installer =
      nodeService "node_modules/daemon/starter/installer.js";

    systemd.services.remotepc-host-uninstaller =
      nodeService "node_modules/daemon/starter/uninstaller.js";

    systemd.services."remotepc-host-nativelisteners@" =
      nodeService "node_modules/daemon/starter/nativeEventListeners.js"
      // {
        environment = commonEnvironment // {
          ELECTRON_RUN_AS_NODE = "1";
          APP = "remotepc-host";
          LOG_LEVEL = "%i";
        };
        serviceConfig = {
          Type = "simple";
          ExecStart = "${electron} ${appAsar}/node_modules/daemon/starter/nativeEventListeners.js";
          TimeoutStopSec = "2s";
        };
      };

    systemd.services."remotepc-host-ftHost@" = {
      description = "RemotePC Desktop FT";
      path = servicePath;
      environment = commonEnvironment // {
        ELECTRON_RUN_AS_NODE = "1";
        APP = "remotepc-host";
        VIEWER_MACHINE_ID = "%i";
      };
      serviceConfig = {
        Type = "simple";
        EnvironmentFile = "-/var/log/remotepc-host/.env";
        ExecStart = "${electron} ${appAsar}/node_modules/daemon/starter/FTHostMain.js";
        TimeoutStopSec = "2s";
      };
    };

    systemd.services."remotepc-host-desktop@" = {
      description = "RemotePC Desktop";
      path = servicePath;
      environment = commonEnvironment // {
        ELECTRON_RUN_AS_NODE = "1";
        APP = "remotepc-host";
        VIEWER_MACHINE_ID = "%i";
      };
      serviceConfig = {
        Type = "simple";
        EnvironmentFile = "-/var/log/remotepc-host/.env";
        ExecStart = "${electron} ${appAsar}/node_modules/host";
        TimeoutStopSec = "2s";
      };
    };

    systemd.user.services."remotepc-host-nativelisteners@" = {
      description = "RemotePC Native Listeners";
      path = servicePath;
      environment = commonEnvironment // {
        ELECTRON_RUN_AS_NODE = "1";
        APP = "remotepc-host";
        LOG_LEVEL = "%i";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${electron} ${appAsar}/node_modules/daemon/starter/nativeEventListeners.js";
        TimeoutStopSec = "2s";
      };
    };

    systemd.user.services."remotepc-host-ftHost@" = {
      description = "RemotePC Desktop FT";
      path = servicePath;
      environment = commonEnvironment // {
        ELECTRON_RUN_AS_NODE = "1";
        APP = "remotepc-host";
        VIEWER_MACHINE_ID = "%i";
      };
      serviceConfig = {
        Type = "simple";
        EnvironmentFile = "-/var/log/remotepc-host/.env";
        ExecStart = "${electron} ${appAsar}/node_modules/daemon/starter/FTHostMain.js";
        TimeoutStopSec = "2s";
      };
    };

    systemd.user.services."remotepc-host-desktop@" = {
      description = "RemotePC Desktop";
      path = servicePath;
      environment = commonEnvironment // {
        ELECTRON_RUN_AS_NODE = "1";
        APP = "remotepc-host";
        VIEWER_MACHINE_ID = "%i";
      };
      serviceConfig = {
        Type = "simple";
        EnvironmentFile = "-/var/log/remotepc-host/.env";
        ExecStart = "${electron} ${appAsar}/node_modules/host";
        TimeoutStopSec = "2s";
      };
    };

    systemd.user.services.remotepc-host-appUI = {
      description = "RemotePC Configuration";
      path = servicePath;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${appDir}/bin/writeConfig";
      };
    };
  };
}
