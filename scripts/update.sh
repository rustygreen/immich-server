#!/usr/bin/env bash
cd ~/immich-homelab
docker compose pull
docker compose up -d
docker image prune -f
