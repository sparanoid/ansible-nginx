#!/bin/bash
#
# See https://github.com/xdtianyu/scripts/tree/master/lets-encrypt for update
# Usage: /etc/nginx/letsencrypt/letsencrypt-ct-submit.sh /etc/nginx/letsencrypt/domain.tld.conf
#
# Requirement:
#   - git (yum install git)
#   - go (yum install golang)

CONFIG=$1

if [ -f "$CONFIG" ];then
    . "$CONFIG"
    DIRNAME=$(dirname "$CONFIG")
    cd "$DIRNAME"
else
    echo "Missing config"
    exit 1
fi

KEY_PREFIX="${DOMAIN_KEY%.*}"
DOMAIN_CHAINED_CRT="$KEY_PREFIX.chained.crt"

# Generate CT
CT_SUBMIT_DIR="/tmp/ct-submit"
if [ -d "$CT_SUBMIT_DIR" ]; then
  echo "Old ct-submit detected, removing..."
  rm -rf $CT_SUBMIT_DIR
fi

cd /tmp/
git clone https://github.com/grahamedgecombe/ct-submit.git
cd ct-submit
go build

CT_CWD="$DIRNAME/sct/$KEY_PREFIX"
echo "Submitting Certificates Transparency..."
mkdir -p "$CT_CWD"
$CT_SUBMIT_DIR/ct-submit ct.googleapis.com/aviator   <$DIRNAME/$DOMAIN_CHAINED_CRT >$CT_CWD/aviator.sct
$CT_SUBMIT_DIR/ct-submit ct.googleapis.com/pilot     <$DIRNAME/$DOMAIN_CHAINED_CRT >$CT_CWD/pilot.sct
echo -e "\e[01;32mDone: $DOMAIN_CHAINED_CRT CTs have been submitted\e[0m"
