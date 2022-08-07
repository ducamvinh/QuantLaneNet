#!/bin/bash

# Create signing key
echo -e "\n[FIX] Creating signing key..."
cd /lib/modules/$(uname -r)/build/certs

tee x509.genkey > /dev/null << 'EOF'
[ req ]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts
[ req_distinguished_name ]
CN = Modules
[ myexts ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF

openssl req -new -nodes -utf8 -sha512 -days 36500 -batch -x509 -config x509.genkey -outform DER -out signing_key.x509 -keyout signing_key.pem

# Create links
echo -e "\n[FIX] Creating symlinks..."
ln -vfs /sys/kernel/btf/vmlinux /usr/lib/modules/$(uname -r)/build/vmlinux
ln -vfs /boot/System.map-$(uname -r) /usr/lib/modules/$(uname -r)/build/System.map

