#!/bin/bash

set -e
set -o pipefail

# args: s3-dir model-name
# eg.: ./sync-model.sh silei/models/qald/qald7/24/1664272755/ 24

bucket=https://nfs009a5d03c43b4e7e8ec2.blob.core.windows.net/pvc-a8853620-9ac7-4885-a30e-0ec357f17bb6
mkdir -p models/$2
azcopy sync --recursive ${bucket}/$1 models/$2/ --exclude-pattern "*00*;best_optim.pth"