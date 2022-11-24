{ lib, config, pkgs, ... }:
let cfg = config.services.startpage;
in {
  options = with lib; {
    services.startpage = {
      enable = lib.mkEnableOption "Enable startpage";

      port = mkOption {
        type = types.int;
        default = 3000;
        description = ''
          Port to listen on
        '';
      };

      user = mkOption {
        type = with types; oneOf [ str int ];
        default = "startpage";
        description = ''
          The user the service will use.
        '';
      };

      group = mkOption {
        type = with types; oneOf [ str int ];
        default = "startpage";
        description = ''
          The group the service will use.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.startpage;
        defaultText = literalExpression "pkgs.startpage";
        description = "The package to use for startpage";
      };
    };
  };

  config = lib.mkIf (cfg.enable) {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      description = "startpage service user";
      isSystemUser = true;
      home = "/var/lib/startpage";
      createHome = true;
      group = "${cfg.group}";
    };

    systemd.services.startpage = {
      enable = true;
      description = "startpage server";
      wantedBy = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = { HOME = "/var/lib/startpage"; };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;

        ExecStart =
          "${cfg.startpage}/bin/startpage.pl -m production -l http://127.0.0.1:${
            toString cfg.port
          }";
      };
    };
  };
}
