#!/bin/bash
#
# See https://github.com/xdtianyu/scripts/tree/master/lets-encrypt for update
# Usage: /etc/nginx/letsencrypt/letsencrypt.sh /etc/nginx/letsencrypt/domain.tld.conf
#
# Requirement:
#   - git (yum install git)
#   - go (yum install golang)

CONFIG=$1
ACME_TINY="/tmp/acme_tiny.py"

if [ -f "$CONFIG" ];then
    . "$CONFIG"
    DIRNAME=$(dirname "$CONFIG")
    cd "$DIRNAME"
else
    echo "ERROR CONFIG."
    exit 1
fi

KEY_PREFIX="${DOMAIN_KEY%.*}"
DOMAIN_CRT="$KEY_PREFIX.crt"
DOMAIN_CSR="$KEY_PREFIX.csr"
DOMAIN_CHAINED_CRT="$KEY_PREFIX.chained.crt"

if [ ! -f "$ACCOUNT_KEY" ];then
    echo "Generate account key..."
    openssl genrsa 4096 > "$ACCOUNT_KEY"
fi

if [ ! -f "$DOMAIN_KEY" ];then
    echo "Generate domain key..."
    if [ "$ECC" = "TRUE" ];then
        openssl ecparam -genkey -name secp384r1 -out "$DOMAIN_KEY"
    else
        openssl genrsa 2048 > "$DOMAIN_KEY"
    fi
fi

echo "Generate CSR...$DOAMIN_CSR"

OPENSSL_CONF="/etc/ssl/openssl.cnf"

if [ ! -f "$OPENSSL_CONF" ];then
    OPENSSL_CONF="/etc/pki/tls/openssl.cnf"
    if [ ! -f "$OPENSSL_CONF" ];then
        echo "Error, file openssl.cnf not found."
        exit 1
    fi
fi

openssl req -new -sha256 -key "$DOMAIN_KEY" -subj "/" -reqexts SAN -config <(cat $OPENSSL_CONF <(printf "[SAN]\nsubjectAltName=%s" "$DOMAINS")) > "$DOMAIN_CSR"

wget https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py -O $ACME_TINY -o /dev/null

if [ -f "$DOMAIN_CRT" ];then
    mv "$DOMAIN_CRT" "$DOMAIN_CRT-OLD-$(date +%y%m%d-%H%M%S)"
fi

DOMAIN_DIR="$DOMAIN_DIR/.well-known/acme-challenge/"
mkdir -p "$DOMAIN_DIR"

python $ACME_TINY --account-key "$ACCOUNT_KEY" --csr "$DOMAIN_CSR" --acme-dir "$DOMAIN_DIR" > "$DOMAIN_CRT"

if [ "$?" != 0 ];then
    exit 1
fi

if [ ! -f "lets-encrypt-x3-cross-signed.pem" ];then
    wget https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem -o /dev/null
fi

cat "$DOMAIN_CRT" lets-encrypt-x3-cross-signed.pem > "$DOMAIN_CHAINED_CRT"


echo -e "\e[01;32mNew cert: $DOMAIN_CHAINED_CRT has been generated\e[0m"

# Copied from le-ct-submit.sh
# Why copied? this should be run every time when a new certificate issued, so
# we also need to generate new CT for the new certs, the eaiset way to do this
# is to run ct-submit right after acme-tiny.
#
# Note: when acme-tiny fails to generate certs (rate limit for example), the
# following code won't run, you can run it mannally via Ansible:
#
# $ ansible-playbook prepare.yml --limit hostname --tags "ct_submit"
#
# Generate CT
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

#service nginx reload
