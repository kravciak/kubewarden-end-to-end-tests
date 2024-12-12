# - no parameter - last released
# - =devel | =version - last rc or specific version
# RANCHER=devel     # devel | version

# default
RANCHER=2.7.11
RANCHER=2.9.0-rc1
RANCHER=p2.9 -> prime
RANCHER=c2.9
RANCHER=head

search order?:
prime
primerc
primealpha
community

# Version shortcuts
# head|p2.9|c2.9|2.9|prime|p|c

# Exact version - search all repos
helm search repo rancher --version "2.9.0-rc0"

primerc:
    # no prime extensions
    # --set rancherImage=stgregistry.suse.com/rancher/rancher

head:
    # --set rancherImageTag=head

k3d cluster list == empty?

k3d cluster list --no-headers

if [ -v RANCHER ]; then
    # repository selection
    [[ "$RANCHER" == p[1-9]* ]] && RANCHER_REPO=rancher-prime     # RANCHER_VERSION="--devel"
    [[ "$RANCHER" == c[1-9]* ]] && RANCHER_REPO=rancher-community # RANCHER_VERSION="--version $RANCHER"
    # version selection
    [[ "$RANCHER" == [pc][1-9]* ]]
fi

info "ui: https://${IP_MASTERS[0]}.nip.io/"

REPO=rancher-primerc
helm repo add --force-update rancher-prime https://charts.rancher.com/server-charts/prime
helm repo add --force-update rancher-primerc https://charts.optimus.rancher.io/server-charts/latest
helm repo add --force-update rancher-primealpha https://charts.optimus.rancher.io/server-charts/alpha
helm repo add --force-update rancher-community https://releases.rancher.com/server-charts/latest
# helm repo add --force-update rancher-alpha  https://releases.rancher.com/server-charts/alpha

helm repo update $REPO

FQDN=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o custom-columns=INTERNAL-IP:.status.addresses[0].address --no-headers | tail -1).nip.io

# Use version sort because helm 2.7.2-rc10 < 2.7.2-rc1
# ranpsp=$(kubectl version -o json | jq -r '.serverVersion.minor <= "24"')
ranver=$(helm search repo $REPO -l ${RANCHER_VERSION:-} |\
            awk '{print $3}' | sed 's/-rc/~rc/' | sort --version-sort | sed 's/~rc/-rc/' | tail -1)

info "install rancher $ranver"
helm upgrade --install rancher $REPO/rancher --wait \
   --namespace cattle-system --create-namespace \
   --set hostname=$FQDN \
   --set bootstrapPassword=sa \
   --set replicas=1 \
   --set rancherImage=stgregistry.suse.com/rancher/rancher \
   --version=$ranver

# helm install rancher $REPO/rancher --devel --wait \
#    --namespace cattle-system --create-namespace \
#    --set hostname=${IP_MASTERS[0]}.nip.io \
#    --set bootstrapPassword=sa \
#    --set replicas=1 \
#    --set rancherImageTag=head

   # --set useBundledSystemChart=true
   # --set 'extraEnv[0].name=CATTLE_AGENT_IMAGE' \
   # --set 'extraEnv[0].value=stgregistry.suse.com/rancher/rancher-agent:v2.7.11-head' \

   # --set global.cattle.psp.enabled=$ranpsp \
   # --set rancherImageTag=v2.10-head
   # --set rancherImage="registry.rancher.com/rancher/rancher" \
   # --version=2.7.9 # $ranver

# helm install rancher rancher-latest/rancher --version 2.7.10 \
#  --namespace cattle-system \
#  --set hostname=${IP_MASTERS[0]}.nip.io \
#  --set global.cattle.psp.enabled=false \
#  --set ingress.tls.source=secret \
#  --set rancherImageTag=v2.7.11-head \
#  --set bootstrapPassword=sa \
#  --set rancherImage=stgregistry.suse.com/rancher/rancher \
#  --set 'extraEnv[0].name=CATTLE_AGENT_IMAGE' \
#  --set 'extraEnv[0].value=stgregistry.suse.com/rancher/rancher-agent:v2.7.11-head'

info 'wait rancher startup'
wait_pods -n cattle-system -l app=rancher-webhook
#wait_pods -n cattle-system
#wait_pods -n cattle-fleet-system

export RANCHER_URL=https://$FQDN

: