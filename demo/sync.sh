#!/bin/bash

set -e
set -o pipefail

curl -O https://almond-static.stanford.edu/research/qald/wikidata_cache.sqlite
curl -O https://almond-static.stanford.edu/research/qald/bootleg.sqlite
curl -O https://almond-static.stanford.edu/research/qald/manifest.tt
curl -O https://almond-static.stanford.edu/research/qald/domain.json