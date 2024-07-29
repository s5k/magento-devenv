{ pkgs, lib, config, ... }:
{
  dotenv.enable = true;
  packages = [ pkgs.git pkgs.gnupatch pkgs.n98-magerun2 ];

  languages.php.enable = true;
  languages.php.package = pkgs.php82.buildEnv {
    extensions = { all, enabled }: with all; enabled ++ [ xdebug xsl redis ];
    extraConfig = ''
      memory_limit = 512m
      opcache.memory_consumption = 256M
      opcache.interned_strings_buffer = 20
      xdebug.mode = "debug"
      xdebug.start_with_request = "trigger"
      xdebug.discover_client_host = 1
      xdebug.var_display_max_depth = -1
      xdebug.var_display_max_data = -1
      xdebug.var_display_max_children = -1

    '';
  };
  languages.php.fpm.pools.web = {
    settings = {
      "clear_env" = "no";
      "pm" = "dynamic";
      "pm.max_children" = 5;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 1;
      "pm.max_spare_servers" = 5;
    };
  };

  services.opensearch.enable = true;
  services.opensearch.package = pkgs.opensearch;

  services.mailhog.enable = true;
  services.redis.enable = true;
  services.redis.port = 6379;

  services.caddy.enable = true;
  services.caddy.virtualHosts."http://${config.env.DEV_DOMAIN}:80" = {
    extraConfig = ''
      root * magenos2/pub
      php_fastcgi unix/${config.languages.php.fpm.pools.web.socket}
      file_server

      @blocked {
        path /media/customer/* /media/downloadable/* /media/import/* /media/custom_options/* /errors/*
      }
      respond @blocked 403

      @notfound {
        path_regexp reg_notfound \/\..*$|\/errors\/.*\.xml$|theme_customization\/.*\.xml
      }
      respond @notfound 404

      @staticPath path_regexp reg_static ^/static/(version\d*/)?(.*)$
      handle @staticPath {
        @static file /static/{re.reg_static.2}
        rewrite @static /static/{re.reg_static.2}
        @dynamic not file /static/{re.reg_static.2}
        rewrite @dynamic /static.php?resource={re.reg_static.2}
      }

      @mediaPath path_regexp reg_media ^/media/(.*)$
      handle @mediaPath {
        @static file /media/{re.reg_media.1}
        rewrite @static /media/{re.reg_media.1}
        @dynamic not file /media/{re.reg_media.1}
        rewrite @dynamic /get.php?resource={re.reg_media.1}
      }
    '';
  };

  services.mysql.enable = true;
  services.mysql.package = pkgs.mysql80;
  services.mysql.settings.mysqld.port = 3306;
  services.mysql.initialDatabases = [{ name = "magento2"; }];
  services.mysql.ensureUsers = [
    {
      name = "magento2";
      password = "magento2";
      ensurePermissions = { "*.*" = "ALL PRIVILEGES"; };
    }
  ];

  processes = {
    cronjob.exec = ''while true; do php ${config.env.MAGENTO_DIR}/bin/magento cron:run && sleep 60; done'';
  };
}
