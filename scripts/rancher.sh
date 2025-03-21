#!/usr/bin/env bash
set -aeEuo pipefail
# trap 'echo "Error on ${BASH_SOURCE/$PWD/.}:${LINENO} $(sed -n "${LINENO} s/^\s*//p" $PWD/${BASH_SOURCE/$PWD})"' ERR

. "$(dirname "$0")/../helpers/kubelib.sh"


# RANCHER=2.11.2-rc1
# RANCHER=2.11
# RANCHER=p2.11-0
# RANCHER=c2.11-0
# RANCHER=2.11-0
# RANCHER=2.11-0
# RANCHER=p
# RANCHER=c*-0

RANCHER=${RANCHER:-}


if [[ $RANCHER =~ ^(c|community|p|prime)(.+)$ ]]; then
    PREFIX="${BASH_REMATCH[1]}"
    REST="${BASH_REMATCH[2]}"
else
    PREFIX=""
    REST="$RANCHER"
fi

# Remove leading "v" if present
RANCHER="${RANCHER#v}"
# RANCHERREPO="${RANCHERREPO:-}"

# REPO=rancher-community
# helm repo add --force-update rancher-prime https://charts.rancher.com/server-charts/prime
# helm repo add --force-update rancher-primerc https://charts.optimus.rancher.io/server-charts/latest
# helm repo add --force-update rancher-primealpha https://charts.optimus.rancher.io/server-charts/alpha
# helm repo add --force-update rancher-community https://releases.rancher.com/server-charts/latest
# helm repo add --force-update rancher-communityalpha https://releases.rancher.com/server-charts/alpha

# ==================================================================================================
# Preferences

helm search repo /rancher --devel | tail -n +2 | semsort -k2 | tail -1


exit 0

# No params: Latest stable version
# Repo param: c|p (*)
# Version param: find in repo (v)

c > p >

# no version
2.10-0

# Defaults
community
rc


# Limit repositories based on prefix community|prime
rancher-prime
rancher-primerc
rancher-primealpha

# Find repos with highest version based on constraints ~2.9-0
rancher-prime
rancher-primerc


# Priority: prime > community > primerc > primealpha > communityalpha
rancher-prime


# by default stable (*)
# by default prime (p)
# by default latest




RANCHER="c2.11-0"

PREFIX=""
REST=""

if [[ $RANCHER =~ ^([cp])(.+)$ ]]; then
    PREFIX="${BASH_REMATCH[1]}"
    REST="${BASH_REMATCH[2]}"
else
    PREFIX=""
    REST="$RANCHER"
fi

echo "Prefix: $PREFIX"
echo "Rest: $REST"


        # =====================================================================================================================
        # Limit k8s version - Rancher 2.7 chart supports < 1.28.0
        [[ "$RANCHER" == *2.7* ]] && K3S_VERSION="v1.27"
        [[ "$RANCHER" == *2.8* ]] && K3S_VERSION="v1.28"
        [[ "$RANCHER" == *2.9* ]] && K3S_VERSION="v1.30"
        [[ "$RANCHER" == *2.10* ]] && K3S_VERSION="v1.31"


        # =====================================================================================================================
        # Complete partial K3S version from dockerhub v1.30 -> v1.30.5-k3s1
        # if [[ ! $K3S =~ ^v[0-9.]+-k3s[0-9]$ ]]; then
            # K3S=$(curl -L -s "https://registry.hub.docker.com/v2/repositories/rancher/k3s/tags?page_size=20&name=$K3S" | jq -re 'first(.results[].name | select(test("^v[0-9.]+-k3s[0-9]$")))')
            # echo "K3S version: $K3S"
        # fi


        # =====================================================================================================================
        RANCHER_FQDN=$(k3d cluster list ${{ env.K3D_CLUSTER_NAME }} -o json | jq -r '[.[].nodes[] | select(.role == "server").IP.IP] | first').nip.io

        # Install cert-manager
        helm repo add jetstack https://charts.jetstack.io --force-update
        helm upgrade -i --wait cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true

        # Install Rancher
        helm search repo $REPO/rancher ${RANCHER:+--version "$RANCHER"}
        helm upgrade --install rancher $REPO/rancher --wait \
            --namespace cattle-system --create-namespace \
            --set hostname=$RANCHER_FQDN \
            --set bootstrapPassword=sa \
            --set replicas=1 \
            ${RANCHER:+--version "$RANCHER"}

        # Wait for Rancher
        for i in {1..20}; do
            output=$(kubectl get pods --no-headers -o wide -n cattle-system -l app=rancher-webhook | grep -vw Completed || echo 'Wait: cattle-system')$'\n'
            output+=$(kubectl get pods --no-headers -o wide -n cattle-system | grep -vw Completed || echo 'Wait: cattle-system')$'\n'
            output+=$(kubectl get pods --no-headers -o wide -n cattle-fleet-system | grep -vw Completed || echo 'Wait: cattle-fleet-system')$'\n'
            grep -vE '([0-9]+)/\1 +Running|^$' <<< $output || break
            [ $i -ne 20 ] && sleep 30 || { echo "Godot: pods not running"; exit 1; }
        done

        echo "RANCHER_FQDN=$RANCHER_FQDN" | tee -a $GITHUB_ENV



# Optional variables
K3S=${K3S:-$(k3d version -o json | jq -r '.k3s')}
CLUSTER_NAME=${CLUSTER_NAME:-k3s-default}
MASTER_COUNT=${MASTER_COUNT:-1}
WORKER_COUNT=${WORKER_COUNT:-1}
MTLS=${MTLS:-}

# Complete partial K3S version from dockerhub
if [[ ! $K3S =~ ^v[0-9.]+-k3s[0-9]$ ]]; then
    K3S=$(curl -L -s "https://registry.hub.docker.com/v2/repositories/rancher/k3s/tags?page_size=20&name=$K3S" | jq -re 'first(.results[].name | select(test("^v[0-9.]+-k3s[0-9]$")))')
    echo "K3S version: $K3S"
fi

# Create new cluster
if [ "${1:-}" == 'create' ]; then
    # Generate certificates
    if [ -n "${MTLS:-}" ]; then
        MTLS_DIR=$(dirname $(realpath -s $0))/../resources/mtls/
        generate_certs "$MTLS_DIR" mtls.kubewarden.io
    fi

    # /dev/mapper: https://k3d.io/v5.7.4/faq/faq/#issues-with-btrfs
    # registry-config: https://k3d.io/v5.8.3/faq/faq/#dockerhub-pull-rate-limit
    k3d cluster create $CLUSTER_NAME --wait \
        --image rancher/k3s:$K3S \
        -s $MASTER_COUNT -a $WORKER_COUNT \
        --registry-create k3d-$CLUSTER_NAME-registry \
        --registry-config <(echo "${K3D_REGISTRY_CONFIG:-}") \
        -v /dev/mapper:/dev/mapper \
        ${MTLS:+--k3s-arg '--kube-apiserver-arg=admission-control-config-file=/etc/mtls/admission.yaml@server:*'} \
        ${MTLS:+--volume "$MTLS_DIR:/etc/mtls@server:*"}

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
