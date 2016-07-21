install-load-tester:
    file.managed:
        - name: /opt/load-tester/load-tester.sh
        - source: salt://elife-website/load-tester.sh
        - template: jinja
        - makedirs: True
        - mode: 755
        - require:
            - cmd: drupal-user
            
    cmd.run:
        - name: |
            chown -R {{ pillar.elife.deploy_user.username }}:{{ pillar.elife.deploy_user.username }} /opt/load-tester/
        - require:
            - file: install-load-tester
