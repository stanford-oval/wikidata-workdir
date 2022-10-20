#!/bin/bash

set -e
set -x
set -o pipefail

if ! test -d genie-server ; then
	git clone https://github.com/stanford-oval/genie-server.git
	pushd genie-server > /dev/null
	git checkout wip/qald
	npm ci
	popd
fi

if ! test -d devices/wd/node_modules ; then 
	pushd devices/wd > /dev/null
	npm ci
	popd 
fi