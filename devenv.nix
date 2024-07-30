{ pkgs, lib, config, ... }:
let
  DOMAIN = "magento2.local";
  MAGENTO_DIR = "magento2";
in
{
  dotenv.disableHint = true;

  packages = [ pkgs.git pkgs.gnupatch pkgs.n98-magerun2 ];

  languages.php.enable = true;
  languages.php.package = pkgs.php82.buildEnv {
    extensions = { all, enabled }: with all; enabled ++ [ xdebug xsl redis ];
    extraConfig = ''
      memory_limit = 2G
      realpath_cache_ttl = 3600
      session.gc_probability = 0
      ${lib.optionalString config.services.redis.enable ''
      session.save_handler = redis
      session.save_path = "tcp://127.0.0.1:${toString config.services.redis.port}/0"
      ''}
      display_errors = On
      error_reporting = E_ALL
      assert.active = 0
      opcache.memory_consumption = 256M
      opcache.interned_strings_buffer = 20
      zend.assertions = 0
      short_open_tag = 0
      zend.detect_unicode = 0
      post_max_size = 32M
      upload_max_filesize = 32M

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
      "pm.max_children" = 10;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 1;
      "pm.max_spare_servers" = 10;
    };
  };

  services.opensearch.enable = true;
  services.opensearch.package = pkgs.opensearch;

  services.mailhog.enable = true;
  services.redis.enable = true;
  services.redis.port = 6379;

  # Auto generete cert SSL for domain
  certificates = [ DOMAIN ];

  # Add domain to /etc/hosts
  hosts."${DOMAIN}" = "127.0.0.1";

  services.caddy.enable = true;
  services.caddy.virtualHosts."${DOMAIN}" = {
    extraConfig = ''
      encode zstd gzip
      root * ${MAGENTO_DIR}/pub
      php_fastcgi unix/${config.languages.php.fpm.pools.web.socket}
      file_server
      encode

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

      encode zstd gzip
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
    cronjob.exec = ''while true; do php ${MAGENTO_DIR}/bin/magento cron:run && sleep 60; done'';
  };
}
