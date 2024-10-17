#!/usr/bin/env bash
set -aeEuo pipefail
# trap 'echo "Error on ${BASH_SOURCE/$PWD/.}:${LINENO} $(sed -n "${LINENO} s/^\s*//p" $PWD/${BASH_SOURCE/$PWD})"' ERR

. "$(dirname "$0")/../helpers/kubelib.sh"

# Optional variables
K3S=${K3S:-$(k3d version -o json | jq -r '.k3s')}
CLUSTER_NAME=${CLUSTER_NAME:-k3s-default}
MASTER_COUNT=${MASTER_COUNT:-1}
WORKER_COUNT=${WORKER_COUNT:-1}

# Complete partial K3S version from dockerhub
if [[ ! $K3S =~ ^v[0-9.]+-k3s[0-9]$ ]]; then
    K3S=$(curl -L -s "https://registry.hub.docker.com/v2/repositories/rancher/k3s/tags?page_size=20&name=$K3S" | jq -re 'first(.results[].name | select(test("^v[0-9.]+-k3s[0-9]$")))')
    echo "K3S version: $K3S"
fi

# Create new cluster
if [ "${1:-}" == 'create' ]; then
    # /dev/mapper: https://k3d.io/v5.7.4/faq/faq/#issues-with-btrfs
    k3d cluster create $CLUSTER_NAME --wait \
        --image rancher/k3s:$K3S \
        -s $MASTER_COUNT -a $WORKER_COUNT \
        --registry-create k3d-$CLUSTER_NAME-registry \
        -v /dev/mapper:/dev/mapper
    wait_pods -n kube-system
fi

# Delete existing cluster
if [ "${1:-}" == 'delete' ]; then
    k3d cluster delete $CLUSTER_NAME
fi

# Return 0 if cluster exists otherwise non 0
if [ "${1:-}" == 'status' ]; then
    k3d cluster list $CLUSTER_NAME &>/dev/null
fi

: