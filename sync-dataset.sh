#!/bin/bash

set -e
set -o pipefail

# args: s3-dir dataset-name
# eg.: ./sync-dataset.sh silei/dataset/qald/qald7/24/1664272755/ 24

bucket=https://nfs009a5d03c43b4e7e8ec2.blob.core.windows.net/pvc-a8853620-9ac7-4885-a30e-0ec357f17bb6
mkdir -p datasets/$2
azcopy sync --recursive ${bucket}/$1 datasets/$2/ --exclude-path "chunked"