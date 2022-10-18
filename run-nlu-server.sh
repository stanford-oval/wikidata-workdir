#!/bin/bash

set -e
set -o pipefail
set -x

exec node --experimental_worker ../genie-toolkit/dist/tool/genie.js server \
  --nlu-model "file://models/$1/" \
  --thingpedia "manifest.tt" 