#!/bin/bash

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output)
      OUTPUT_PATH="$2"
      shift # past argument
      shift # past value
      ;;
    --default)
      DEFAULT=YES
      shift # past argument
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

[ -d $OUTPUT_PATH ] || mkdir $OUTPUT_PATH

files=`ls ./converted/*.qald.json`
for f in $files
do
    iName="$(basename $f .json)"
    oName="$iName.tsv"
    echo "$iName -> $oName"
    node qald/dist/lib/converter/index.js \
        -i ${f} \
        -o "$OUTPUT_PATH/$oName" \
        --manifest manifest.tt \
        --domains parameter-datasets/domain.json \
        --cache qald/wikidata_cache.sqlite \
        --bootleg-db qald/bootleg.sqlite \
        --include-entity-value \
        --exclude-entity-display
done

# ./convert-to-thingtalk.sh -o ./thingtalk-data 2>&1 | tee log.txt