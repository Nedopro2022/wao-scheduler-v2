#!/usr/bin/env bash

# scripts must be run from project root
. hack/1-bin.sh || exit 1

# consts

CERT_MANAGER_YAML=${CERT_MANAGER_YAML:-"https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml"}
METRICS_SERVER_YAML=${METRICS_SERVER_YAML:-"https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.6.1/components.yaml"}
METRICS_SERVER_PATCH=${METRICS_SERVER_PATCH:-'''[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'''}

# libs

# Usage: lib::create-cluster <name> <kind_image>
function lib::create-cluster {
    local kind_name=$1
    local name=kind-$1
    local kind_image=$2

    test -s "$KIND"
    test -s "$KUBECTL"

    "$KIND" delete cluster --name "$kind_name"

    "$KIND" create cluster --name "$kind_name" --image="$kind_image" --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

    "$KUBECTL" apply -f "$CERT_MANAGER_YAML"
    "$KUBECTL" apply -f "$METRICS_SERVER_YAML"
    "$KUBECTL" patch -n kube-system deployment metrics-server --type=json -p "$METRICS_SERVER_PATCH"
}

# Usage: lib::start-docker
function lib::start-docker {

    set +o nounset
    if [ "$CI" == "true" ]; then return 0; fi
    set -o nounset

    sudo systemctl start docker || sudo service docker start || true
    sleep 1

    # https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
    sudo sysctl fs.inotify.max_user_watches=524288 || true
    sudo sysctl fs.inotify.max_user_instances=512 || true
}

# Usage: lib::retry <max_attempts> <cmd>...
# Example: lib::retry 5 ls foo
#          lib::retry 5 timeout 3 curl 8.8.8.8
# Ref.: https://stackoverflow.com/questions/12321469/retry-a-bash-command-with-timeout
function lib::retry {
    local -r -i max_attempts="$1"; shift
    local -r cmd=$*
    local -i attempt_num=1

    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            echo "attempt $attempt_num/$max_attempts failed, exit(1)"
            return 1
        else
            echo "attempt $attempt_num/$max_attempts failed, trying again in $attempt_num seconds..."
            sleep $(( attempt_num++ ))
        fi
    done
}
