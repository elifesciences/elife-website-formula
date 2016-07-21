website-vhost:
    file.managed:
        - name: /etc/nginx/sites-enabled/website.conf
        - source: salt://elife-website/config/etc-nginx-sites-enabled-website.conf
        - listen_in:
            - service: nginx-server-service
            - service: php-fpm
