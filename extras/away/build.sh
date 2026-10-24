#!/bin/bash
# Rebuild the idle watcher. Generated protocol glue goes in build/ (regenerable).
set -e
cd "$(dirname "$0")"; mkdir -p build
wayland-scanner client-header ext-idle-notify-v1.xml build/ext-idle-notify-v1-client.h
wayland-scanner private-code  ext-idle-notify-v1.xml build/ext-idle-notify-v1-protocol.c
gcc -O2 -Wall -Ibuild -o build/midnight-idle midnight-idle.c build/ext-idle-notify-v1-protocol.c $(pkg-config --cflags --libs wayland-client)
echo built build/midnight-idle
