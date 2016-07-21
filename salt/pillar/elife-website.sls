elife_website:
    logfile: /var/log/website.log

    db:
        name: website
        username: drupal
        password: drupal-pass

    db_test:
        name: website_test
        username: drupal
        password: drupal-test-pass

    drupal_user:
        username: drupal
        password: drupal-user-pass

    platform_env:
        root: /app/web
        db_file: /tmp/site.sql
        uri: foo.example.org
        host: bar.example.org
        fingerprint: aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa
        user: username
