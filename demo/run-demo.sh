#!/bin/bash

set -e
set -x
set -o pipefail

if ! test -d ./.home ; then
    mkdir .home
    cat > .home/prefs.db <<EOF
{
  "developer-dir": "${PWD}/devices"
}
EOF
fi

export THINGENGINE_HOME=./.home
export THINGENGINE_NLP_URL=http://127.0.0.1:8400
exec node --experimental_worker --max_old_space_size=14000 ./genie-server/dist/main.js
