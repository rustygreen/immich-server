#!/usr/bin/env bash

echo "DNS:"
nslookup photos.example.com

echo "Containers:"
docker ps

echo "Mount:"
df -h | grep photos
