#!/bin/bash

# POSTs JSON derived from elife article XML to the elife-website project.
# use ctrl-c to quit.

# @author: Luke Skibinski <l.skibinski@elifesciences.org>

install_article_json() {
    # clone the eif-article-json repo, update if it already exists
    if [ ! -d eif-article-json ]; then
        git clone https://github.com/elifesciences/eif-article-json
    else
	    git -C eif-article-json reset --hard
    fi
}

basic_import() {
    for file in `ls eif-article-json/article-json/*.json | sort --numeric-sort --reverse`; do
        echo "POST'ing $file ..."
        time curl -v -X POST -d @$file http://localhost/api/article.json --header "Authorization: Basic {{ salt['elife.b64encode'](pillar.elife_website.drupal_users.builder.username + ':' + pillar.elife_website.drupal_users.builder.password) }}" --header "Content-Type:application/json" 2>&1 | grep 'HTTP/1.1 '
        printf "\n\n"
    done
}

control_c() {
    echo "interrupt caught, exiting. this script can be run multiple times ..."
    exit $?
}

trap control_c SIGINT

install_article_json
time basic_import
