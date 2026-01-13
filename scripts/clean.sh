#!/usr/bin/env bash

set -eou pipefail

echo "This will delete all your data."
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

docker compose down -v
rm -f ./certs/* ./secrets/* .env

