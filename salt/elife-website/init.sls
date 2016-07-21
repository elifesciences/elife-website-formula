website-db:
    mysql_database.present:
        - name: {{ pillar.elife_website.db.name }}
        - connection_pass: {{ pillar.elife.db_root.password }}

website-db-test:
    mysql_database.present:
        - name: {{ pillar.elife_website.db_test.name }}
        - connection_pass: {{ pillar.elife.db_root.password }}

website-db-user:
    mysql_user.present:
        - name: website
        - password: website
        - connection_pass: {{ pillar.elife.db_root.password }} # do it as the root user
        - host: localhost
        - require:
            - service: mysql-server

website-db-access:
    mysql_grants.present:
        - user: website
        - database: {{ pillar.elife_website.db.name }}.*
        - grant: all privileges
        - connection_pass: {{ pillar.elife.db_root.password }} # do it as the root user
        - require:
            - mysql_user: website-db-user

website-db-access-test:
    mysql_grants.present:
        - user: website
        - database: {{ pillar.elife_website.db_test.name }}.*
        - grant: all privileges
        - connection_pass: {{ pillar.elife.db_root.password }} # do it as the root user
        - require:
            - mysql_user: website-db-user

website-log-file:
    file.managed:
        - name: {{ pillar.elife_website.logfile }}
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 660

website-dir:
    file.directory:
        - name: /srv/website
{% if pillar.elife.env != "dev" %}
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}
{% endif %}

website-repo:
    git.latest:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: git@github.com:elifesciences/elife-website.git
        - rev: {{ salt['elife.rev']() }}
        - branch: {{ salt['elife.branch']() }}
        - target: /srv/website/
        - force_fetch: True
        # fail if there are local changes
        #- force_checkout: True
        - force_reset: True
        - require:
            - file: website-dir

local-settings-file:
    file.managed:
        - name: /srv/website/local.settings.php
        - source: salt://elife-website/config/local.settings.php
        - template: jinja
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
{% if pillar.elife.env == "dev" %}
        - mode: 777
{% endif %}
        - require:
            - git: website-repo
            - file: website-log-file

website-deps:
    pkg.installed:
        - pkgs:
            - imagemagick

{% set platform_folder = '/home/' ~ pillar.elife.deploy_user.username ~ '/platform' %}

platform-known-host:
    ssh_known_hosts.present:
        - name: {{ pillar.elife_website.platform_env.host }}
        - user: {{ pillar.elife.deploy_user.username }}
        - fingerprint: {{ pillar.elife_website.platform_env.fingerprint }}
        - enc: ssh-rsa
        - require:
            - file: /home/{{ pillar.elife.deploy_user.username }}/.ssh/id_rsa

platform-folder:
    file.directory:
        - name: {{ platform_folder }}
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}
        - recurse:
            - user
            - group
        - require:
            - ssh_known_hosts: platform-known-host

platform-database:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: {{ platform_folder }}
        - name: |
            drush @website.platform sql-dump --gzip > site.sql.gz
            sed --in-place '/Warning: Permanently added the RSA host key for IP address/d' {{ platform_folder }}/site.sql.gz # Ugly hack as Drush redirects STDERR to STDOUT
            gunzip site.sql.gz
        - require:
            - file: platform-folder
            - file: drush-alias-file
        - unless:
            - test -f site.sql

platform-public-files:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: {{ platform_folder }}
        - name: drush --yes core-rsync @website.platform:sites/default/files {{ platform_folder }} --exclude-paths="css:ctools:js:styles:xmlsitemap"
        - require:
            - file: platform-folder
            - file: drush-alias-file
        - unless:
            - test -d files

platform-private-files:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: {{ platform_folder }}
        - name: drush --yes core-rsync @website.platform:../private {{ platform_folder }}
        - require:
            - file: platform-folder
            - file: drush-alias-file
        - unless:
            - test -d private

setup-drupal:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: /srv/website/
        - name: |
            set -e
{% if pillar.elife.env == "dev" %}
            ./setup.sh
{% else %}
            ./setup.sh --no-dev
{% endif %}
            drush @website.local sql-drop --yes
            drush @website.local sql-query --file="{{ platform_folder }}/site.sql"
            drush --yes core-rsync {{ platform_folder }}/files/ @website.local:sites/default/files/ --delete
            drush --yes core-rsync {{ platform_folder }}/private/ @website.local:../private/ --delete
            drush @website.local registry-rebuild
            ./update.sh
        - require:
            - pkg: website-deps
{% if pillar.elife.env != "dev" %}
            - git: website-repo
            #- cmd: update-drupal
{% endif %}
            - cmd: composer-global-paths
            - file: local-settings-file
            - file: drush-alias-file
            - cmd: platform-database
            - cmd: platform-public-files
            - cmd: platform-private-files
        - unless:
            - test -d /srv/website/web/

{% if pillar.elife.env != "dev" %}

update-drupal:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: /srv/website/
        - name: ./update.sh
        - require:
            - cmd: setup-drupal
        - unless:
            - test -d /srv/website/web/

website-public-files:
    file.directory:
        - name: /srv/website/web/sites/default/files
        - file_mode: 664
        - dir_mode: 755
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - recurse:
            - user
            - group
            - mode
        - require:
            - cmd: setup-drupal

website-private-files:
    file.directory:
        - name: /srv/website/private
        - file_mode: 660
        - dir_mode: 750
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - recurse:
            - user
            - group
            - mode
        - require:
            - cmd: setup-drupal

website-cache-files:
    file.directory:
        - name: /srv/website/cache
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - recurse:
            - user
            - group
        - require:
            - cmd: setup-drupal

{% endif %}



drush-alias-file:
    file.managed:
        - name: /etc/drush/website.aliases.drushrc.php
        - source: salt://elife-website/config/website.aliases.drushrc.php
        - template: jinja
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - require:
            - cmd: drush-aliases-folder

add-default-drush-alias-to-bashrc:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: echo 'drush site-set @website.local' >> ~/.bashrc
        - unless:
            - cat ~/.bashrc | grep "drush site-set @website.local"
        - require:
            - file: drush-alias-file




behat-settings-file:
    file.managed:
        - name: /srv/website/tests/behat/behat.yml
        - source: salt://elife-website/config/behat.yml
        - template: jinja

start-selenium:
    service.running:
        - name: selenium
        - require:
            - cmd: get-selenium
            - file: get-selenium
            - pkg: firefox

solr-core:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: |
            mkdir -p /opt/solr/example/solr/drupal
            echo "name=drupal" > /opt/solr/example/solr/drupal/core.properties
            cp -r /srv/website/src/elife_profile/modules/contrib/search_api_solr/solr-conf/4.x /opt/solr/example/solr/drupal
            mv /opt/solr/example/solr/drupal/4.x /opt/solr/example/solr/drupal/conf
        - unless:
            - test -d /opt/solr/example/solr/drupal
        - require:
            - cmd: setup-drupal
            - file: solr4-install
        - listen_in:
            - service: solr4

solr-core-clear:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: |
            set -e
            curl "http://localhost:8983/solr/drupal/update?stream.body=<delete><query>*:*</query></delete>&commit=true"
            drush @website.local search-api-clear
        - requires:
            - cmd: solr-core
        - onchanges:
            - cmd: setup-drupal

solr-core-test:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: |
            mkdir -p /opt/solr/example/solr/drupal_test
            echo "name=drupal_test" > /opt/solr/example/solr/drupal_test/core.properties
            cp -r /srv/website/src/elife_profile/modules/contrib/search_api_solr/solr-conf/4.x /opt/solr/example/solr/drupal_test
            mv /opt/solr/example/solr/drupal_test/4.x /opt/solr/example/solr/drupal_test/conf
            sed -i -e "s?solr.autoSoftCommit.MaxTime=[0-9]\+?solr.autoSoftCommit.MaxTime=500?g" /opt/solr/example/solr/drupal_test/conf/solrcore.properties
        - unless:
            - test -d /opt/solr/example/solr/drupal_test
        - require:
            - cmd: setup-drupal
            - file: solr4-install
        - listen_in:
            - service: solr4

drupal-cron: # Every 20 minutes
    cron.present:
        - user: {{ pillar.elife.deploy_user.username }}
        - identifier: drupal-cron
        - name: /srv/website/run-cron.sh
        - minute: '*/20'

drupal-user:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: /srv/website/web
        - name: drush user-create "{{ pillar.elife_website.drupal_user.username }}" --password "{{ pillar.elife_website.drupal_user.password }}"
        - require:
            - cmd: setup-drupal
        - unless:
            - drush user-information "{{ pillar.elife_website.drupal_user.username }}"

drush-user-details:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: /srv/website/web
        - name: |
            drush user-password "{{ pillar.elife_website.drupal_user.username }}" --password="{{ pillar.elife_website.drupal_user.password }}"
            drush user-add-role "eLife Article Publisher" "{{ pillar.elife_website.drupal_user.username }}"
        - require:
            - cmd: drupal-user

