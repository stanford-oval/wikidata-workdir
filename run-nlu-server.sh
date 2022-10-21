#!/bin/bash

set -e
set -o pipefail
set -x

export GENIENLP_DATABASE_DIR=./database/

exec node --experimental_worker ../genie-toolkit/dist/tool/genie.js server \
  --nlu-model "file://models/$1/" \
  --thingpedia "manifest.tt" \
  --no-contextual \
  --include-entity-value \
  --exclude-entity-display
