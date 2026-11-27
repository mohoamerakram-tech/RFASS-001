#!/bin/bash
set -euo pipefail

SUBNET="172.28.0.0/24"
iptables -L DOCKER-USER -n >/dev/null 2>&1 || exit 0

# Make idempotent by removing any existing rules for this subnet first
while iptables -D DOCKER-USER -s "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; do :; done
while iptables -D DOCKER-USER -s "$SUBNET" -d "$SUBNET" -j ACCEPT 2>/dev/null; do :; done
while iptables -D DOCKER-USER -s "$SUBNET" -d 192.168.0.0/16 -j DROP 2>/dev/null; do :; done
while iptables -D DOCKER-USER -s "$SUBNET" -d 10.0.0.0/8 -j DROP 2>/dev/null; do :; done
while iptables -D DOCKER-USER -s "$SUBNET" -d 172.16.0.0/12 -j DROP 2>/dev/null; do :; done
while iptables -D DOCKER-USER -s "$SUBNET" -d 100.64.0.0/10 -j DROP 2>/dev/null; do :; done

# Final rule order in DOCKER-USER:
# 1. Allow return traffic for established connections (e.g. localhost:8642)
# 2. Allow intra-AI-lab container communication inside 172.28.0.0/24
# 3. Block new outbound connections from AI lab containers to LAN & Tailnet
iptables -I DOCKER-USER 1 -s "$SUBNET" -d 100.64.0.0/10 -j DROP
iptables -I DOCKER-USER 1 -s "$SUBNET" -d 172.16.0.0/12 -j DROP
iptables -I DOCKER-USER 1 -s "$SUBNET" -d 10.0.0.0/8 -j DROP
iptables -I DOCKER-USER 1 -s "$SUBNET" -d 192.168.0.0/16 -j DROP
iptables -I DOCKER-USER 1 -s "$SUBNET" -d "$SUBNET" -j ACCEPT
iptables -I DOCKER-USER 1 -s "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
