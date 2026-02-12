#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${CONF_FILE:-$SCRIPT_DIR/snapshot-notifier.conf}"

if [[ ! -f "$CONF_FILE" ]]; then
    echo "Error: Config file not found: $CONF_FILE" >&2
    echo "Copy snapshot-notifier.conf.example to snapshot-notifier.conf and fill in your values." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"

: "${PROXMOX_HOST:?PROXMOX_HOST is required}"
: "${PROXMOX_TOKEN_ID:?PROXMOX_TOKEN_ID is required}"
: "${PROXMOX_TOKEN_SECRET:?PROXMOX_TOKEN_SECRET is required}"
: "${MATTERMOST_WEBHOOK_URL:?MATTERMOST_WEBHOOK_URL is required}"
SNAPSHOT_AGE_DAYS="${SNAPSHOT_AGE_DAYS:-5}"

CURL_OPTS=(--silent --show-error --insecure)
AUTH_HEADER="PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

api_get() {
    curl "${CURL_OPTS[@]}" -H "Authorization: $AUTH_HEADER" "${PROXMOX_HOST}/api2/json${1}"
}

now=$(date +%s)
threshold=$((now - SNAPSHOT_AGE_DAYS * 86400))

# Collect all old snapshots: node, vmid, type, snapshot name, age (days), description
results=()

nodes=$(api_get "/nodes" | jq -r '.data[].node')

for node in $nodes; do
    # Fetch QEMU VMs and LXC containers
    for vmtype in qemu lxc; do
        vmids=$(api_get "/nodes/${node}/${vmtype}" | jq -r '.data[].vmid // empty' 2>/dev/null)

        for vmid in $vmids; do
            vmname=$(api_get "/nodes/${node}/${vmtype}/${vmid}/status/current" \
                | jq -r '.data.name // "N/A"')

            snapshots=$(api_get "/nodes/${node}/${vmtype}/${vmid}/snapshot" \
                | jq -c '.data[] | select(.name != "current")')

            while IFS= read -r snap; do
                [[ -z "$snap" ]] && continue

                snap_name=$(echo "$snap" | jq -r '.name')
                snap_time=$(echo "$snap" | jq -r '.snaptime // 0')
                snap_desc=$(echo "$snap" | jq -r '.description // ""' | tr -d '\n')

                if [[ "$snap_time" -gt 0 && "$snap_time" -lt "$threshold" ]]; then
                    age_days=$(( (now - snap_time) / 86400 ))
                    snap_date=$(date -d "@${snap_time}" '+%Y-%m-%d %H:%M')
                    type_label=$([ "$vmtype" = "qemu" ] && echo "VM" || echo "CT")
                    results+=("${node}|${vmid}|${vmname}|${type_label}|${snap_name}|${snap_date}|${age_days}|${snap_desc}")
                fi
            done <<< "$snapshots"
        done
    done
done

# Build markdown table for Mattermost
if [[ ${#results[@]} -eq 0 ]]; then
    echo "No snapshots older than ${SNAPSHOT_AGE_DAYS} days found."
    exit 0
fi

table="#### :warning: Snapshots older than ${SNAPSHOT_AGE_DAYS} days (as of $(date '+%Y-%m-%d %H:%M'))\n\n"
table+="| Node | VMID | VM Name | Type | Snapshot | Created | Age (days) | Description |\n"
table+="| --- | --- | --- | --- | --- | --- | --- | --- |\n"

for row in "${results[@]}"; do
    IFS='|' read -r r_node r_vmid r_vmname r_type r_snap r_date r_age r_desc <<< "$row"
    table+="| ${r_node} | ${r_vmid} | ${r_vmname} | ${r_type} | ${r_snap} | ${r_date} | ${r_age} | ${r_desc} |\n"
done

table+="\n**Total: ${#results[@]} snapshot(s)**"

# Post to Mattermost via incoming webhook
payload=$(printf '%b' "$table" | jq -Rs '{text: .}')

http_code=$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$payload" \
    "$MATTERMOST_WEBHOOK_URL")

if [[ "$http_code" -eq 200 ]]; then
    echo "Posted snapshot report to Mattermost."
else
    echo "Error: Mattermost webhook returned HTTP ${http_code}" >&2
    exit 1
fi
