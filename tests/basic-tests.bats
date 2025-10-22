#!/usr/bin/env bats

setup() {
    setup_helper
}
teardown_file() {
    teardown_helper
}

# Get versions from hauler_manifest
# Usage: haul_get section selector
haul_get() {
    local n="$1" # name of the hauler_manifest section
    local q="$2" # name of the image or chart to query
    local y      # yaml from section $n

    y=$(n=$n yq -e 'select(.metadata.name == env(n)).spec | .images + .charts' "$CHARTS_LOCATION/hauler_manifest.yaml")
    case "$n" in
        *not-signed-images|*container-images|*policies)
            q=$q yq -e '.[].name | select(contains(env(q)+":")) | split(":")[1]' <<<"$y";;
        *helm-charts)
            q=$q yq -e '.[] | select(.name == env(q)).version' <<<"$y";;
        *)
            echo "Unknown hauler section: $n" >&2; return 1;;
    esac
}

# Get versions from helm charts
# Usage: helm_get chart-name [yq-query]
helm_get() {
    local chart=$CHARTS_LOCATION/$1
    yq -e "${2:-.}" <(helm show values "$chart"; helm show chart "$chart")
}

@test "$(tfile) Version checks" {
    # Helm app version is consistent
    helm list -n "$NAMESPACE" -o json | jq 'map(.app_version) | unique | length == 1'

    # Hauler manifest versions for PRs
    if [[ "$CHARTS_LOCATION" == */* ]]; then
        # Helm Charts
        for chart in kubewarden-crds kubewarden-controller kubewarden-defaults; do
            test "$(haul_get kubewarden-helm-charts $chart)" = "$(helm_get $chart '.version')"
        done
        test "$(haul_get kubewarden-helm-charts policy-reporter)" = "$(helm_get kubewarden-controller '.dependencies[].version')"
        # Signed images
        test "$(haul_get kubewarden-container-images kubewarden-controller)" = "$(helm_get kubewarden-controller '.image.tag')"
        test "$(haul_get kubewarden-container-images audit-scanner)" = "$(helm_get kubewarden-controller '.auditScanner.image.tag')"
        test "$(haul_get kubewarden-container-images policy-server)" = "$(helm_get kubewarden-defaults '.policyServer.image.tag')"
        # Unsigned images
        test "$(haul_get kubewarden-not-signed-images policy-reporter)" = "$(helm_get kubewarden-controller '.policy-reporter.image.tag')"
        test "$(haul_get kubewarden-not-signed-images policy-reporter-ui)" = "$(helm_get kubewarden-controller '.policy-reporter.ui.image.tag')"
        test "$(haul_get kubewarden-not-signed-images kuberlr-kubectl)" = "$(helm_get kubewarden-controller '.preDeleteJob.image.tag')"
        # Policies
        for policy in allow-privilege-escalation-psp capabilities-psp host-namespaces-psp hostpaths-psp pod-privileged user-group-psp; do
            test "$(haul_get kubewarden-policies $policy)" \
                = "$(helm_get kubewarden-defaults | p=$policy yq '.recommendedPolicies[].module? | select(.repository == "*"+env(p)).tag')"
        done
    fi
}

# Create pod-privileged policy to block CREATE & UPDATE of privileged pods
@test "$(tfile) Apply pod-privileged policy that blocks CREATE & UPDATE" {
    apply_policy privileged-pod-policy.yaml

    # Launch unprivileged pod
    kubectl run nginx-unprivileged --image=nginx:alpine
    wait_for pod nginx-unprivileged

    # Launch privileged pod (should fail)
    kubefail_privileged run pod-privileged --image=rancher/pause:3.2 --privileged
}

# Update pod-privileged policy to block only UPDATE of privileged pods
@test "$(tfile) Patch policy to block only UPDATE operation" {
    yq '.spec.rules[0].operations = ["UPDATE"]' "$RESOURCES_DIR/policies/privileged-pod-policy.yaml" | kubectl apply -f -

    # I can create privileged pods now
    kubectl run nginx-privileged --image=nginx:alpine --privileged

    # I can not update privileged pods
    kubefail_privileged label pod nginx-privileged x=y
}

@test "$(tfile) Delete ClusterAdmissionPolicy" {
    delete_policy privileged-pod-policy.yaml

    # I can update privileged pods now
    kubectl label pod nginx-privileged x=y
}

@test "$(tfile) Apply mutating psp-user-group AdmissionPolicy" {
    apply_policy psp-user-group-policy.yaml

    # Policy should mutate pods
    kubectl run pause-user-group --image rancher/pause:3.2
    wait_for pod pause-user-group
    kubectl get pods pause-user-group -o json | jq -e ".spec.containers[].securityContext.runAsUser==1000"

    delete_policy psp-user-group-policy.yaml
}

@test "$(tfile) Launch & scale second policy server" {
    create_policyserver e2e-tests
    wait_for policyserver e2e-tests --for=condition=ServiceReconciled

    kubectl patch policyserver e2e-tests --type=merge -p '{"spec": {"replicas": 2}}'
    wait_policyserver e2e-tests

    kubectl delete ps e2e-tests
}

@test "$(tfile) Cosign" {
    # Images
    # policy-server kubewarden-controller audit-scanner

    cosign verify ghcr.io/kubewarden/policy-server:v1.29.0 \
          --certificate-identity-regexp 'https://github.com/kubewarden/*' \
          --certificate-oidc-issuer https://token.actions.githubusercontent.com
    slsactl verify ghcr.io/kubewarden/policy-server:v1.29.0

    # Helm charts
    cosign verify ghcr.io/kubewarden/charts/kubewarden-defaults:1.5.4 \
        --certificate-identity-regexp 'https://github.com/kubewarden/*' \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com

    # kwctl
    gh attestation verify kwctl-linux-x86_64 --repo kubewarden/kwctl

    # Policies
    cosign verify ghcr.io/kubewarden/policies/verify-image-signatures:v0.2.5 \
        --certificate-identity-regexp 'https://github.com/kubewarden/*' \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com
}
