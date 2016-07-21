#!/bin/bash

# @description: this script should be run as root so services can be started. 
# actual tests are run as the deploy user (elife)

set -e # all statements must return successfully

# configure and run selenium
export DISPLAY=:99.0
sh -e /etc/init.d/xvfb start

# run the tests 
su elife -c 'sh /srv/website/run-tests.sh'
