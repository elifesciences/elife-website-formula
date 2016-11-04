{% set elife = pillar.elife %}
{% set app = pillar.elife_website %}

website-deps:
    pkg.installed:
        - pkgs:
            - imagemagick

website-db:
    mysql_database.present:
        - name: {{ app.db.name }}
        - connection_pass: {{ elife.db_root.password }}

website-db-test:
    mysql_database.present:
        - name: {{ app.db_test.name }}
        - connection_pass: {{ elife.db_root.password }}

website-db-user:
    mysql_user.present:
        - name: website
        - password: website
        - connection_pass: {{ elife.db_root.password }} # do it as the root user
        - host: localhost
        - require:
            - service: mysql-server

website-db-access:
    mysql_grants.present:
        - user: website
        - database: {{ app.db.name }}.*
        - grant: all privileges
        - connection_pass: {{ elife.db_root.password }} # do it as the root user
        - require:
            - mysql_user: website-db-user

website-db-access-test:
    mysql_grants.present:
        - user: website
        - database: {{ app.db_test.name }}.*
        - grant: all privileges
        - connection_pass: {{ elife.db_root.password }} # do it as the root user
        - require:
            - mysql_user: website-db-user

website-log-file:
    file.managed:
        - name: {{ app.logfile }}
        - user: {{ elife.webserver.username }}
        - group: {{ elife.webserver.username }}
        - mode: 660

#
#
#

website-dir:
    file.directory:
        - name: /srv/website

website-repo:
    builder.git_latest:
        - name: git@github.com:elifesciences/elife-website.git
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        - rev: {{ salt['elife.rev']() }}
        - branch: {{ salt['elife.branch']() }}
        - target: /srv/website/
        - force_fetch: True
        # fail if there are local changes
        #- force_checkout: True
        - force_reset: True
        - require:
            - file: website-dir

    file.directory:
        - user: {{ elife.deploy_user.username }}
        - name: /srv/website/
        - recurse:
            - user
        - require:
            - builder: website-repo

local-settings-file:
    file.managed:
        - name: /srv/website/local.settings.php
        - source: salt://elife-website/config/local.settings.php
        - template: jinja
        - user: {{ elife.webserver.username }}
        - group: {{ elife.webserver.username }}
        - require:
            - website-repo
            - file: website-log-file

setup-drupal:
    cmd.run:
        - user: {{ elife.deploy_user.username }}
        - cwd: /srv/website/
        {% if pillar.elife.env == "dev" %}
        - name: ./create.sh
        {% else %}
        - name: ./create.sh --no-dev
        {% endif %}
        - require:
            - pkg: website-deps
            - website-repo
            - composer
            - drush
            - nodejs
            - file: local-settings-file
            - file: drush-alias-file            
        - unless:
            - test -d /srv/website/web/

update-drupal:
    cmd.run:
        - user: {{ elife.deploy_user.username }}
        - cwd: /srv/website/
        - name: ./update.sh
        - require:
            - cmd: setup-drupal
            - drush-registry-rebuild
        - unless:
            - test -d /srv/website/web/

website-public-files:
    file.directory:
        - name: /srv/website/web/sites/default/files
        - file_mode: 664
        - dir_mode: 755
        - user: {{ elife.webserver.username }}
        - group: {{ elife.webserver.username }}
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
        - user: {{ elife.webserver.username }}
        - group: {{ elife.webserver.username }}
        - recurse:
            - user
            - group
            - mode
        - require:
            - cmd: setup-drupal

website-cache-files:
    file.directory:
        - name: /srv/website/cache
        - user: {{ elife.webserver.username }}
        - group: {{ elife.webserver.username }}
        - dir_mode: 775
        - file_mode: 664
        - recurse:
            - user
            - group
            - mode
        - require:
            - cmd: setup-drupal

drush-alias-file:
    file.managed:
        - name: /etc/drush/website.aliases.drushrc.php
        - source: salt://elife-website/config/website.aliases.drushrc.php
        - template: jinja
        - user: {{ elife.webserver.username }}
        - group: {{ elife.webserver.username }}
        - require:
            - cmd: drush-aliases-folder

add-default-drush-alias-to-bashrc:
    cmd.run:
        - user: {{ elife.deploy_user.username }}
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

solr-core:
    cmd.run:
        - user: {{ elife.deploy_user.username }}
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
        - user: {{ elife.deploy_user.username }}
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
        - user: {{ elife.deploy_user.username }}
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
        - user: {{ elife.deploy_user.username }}
        - identifier: drupal-cron
        - name: /srv/website/run-cron.sh
        - minute: '*/20'


{% for name, user in app.drupal_users.items() %}
drupal-user-{{ name }}:
    cmd.run:
        - user: {{ elife.deploy_user.username }}
        - cwd: /srv/website/web
        - name: drush user-create "{{ user.username }}" --password "{{ user.password }}"
        - require:
            - cmd: setup-drupal
        - unless:
            - drush user-information "{{ user.username }}"

drupal-user-{{ name }}-details:
    cmd.run:
        - user: {{ elife.deploy_user.username }}
        - cwd: /srv/website/web
        - name: |
            drush user-password "{{ user.username }}" \
                --password="{{ user.password }}"
            drush user-add-role "eLife Article Publisher" "{{ user.username }}"
        - require:
            - cmd: drupal-user-{{ name }}
{% endfor %}
