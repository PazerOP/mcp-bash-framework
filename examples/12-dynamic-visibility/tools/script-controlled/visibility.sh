#!/usr/bin/env bash
# Visibility script: returns 0 (visible) during business hours, 1 (hidden) otherwise
# This is an example - you can implement any logic here

hour=$(date +%H)
hour=${hour#0}  # Remove leading zero

if [ "$hour" -ge 9 ] && [ "$hour" -lt 17 ]; then
    # Visible during business hours (9 AM - 5 PM)
    exit 0
else
    # Hidden outside business hours
    exit 1
fi
