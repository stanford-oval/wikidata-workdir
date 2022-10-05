#!/usr/bin/env bash

set -e
set -x
set -o pipefail

if ! test -d qald ; then
	git clone https://github.com/rayslxu/qald
	chown genie-toolkit:genie-toolkit qald

	pushd qald > /dev/null
	git checkout $1
	su genie-toolkit -c 'npm ci'
	popd
fi
