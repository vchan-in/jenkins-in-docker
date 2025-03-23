#!/bin/sh
set -e

# Replace HOST_IP in the Nginx config
envsubst '$host_ip' < /etc/nginx/nginx.template > /etc/nginx/nginx.conf

# Execute the default Docker command
exec "$@"
