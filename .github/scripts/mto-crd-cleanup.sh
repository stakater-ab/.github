#!/bin/bash
# Timeout duration
TIMEOUT_DURATION=15

# List of CRDs to delete
declare -a CRDS=("extensions.tenantoperator.stakater.com"
  "integrationconfigs.tenantoperator.stakater.com"
  "resourcesupervisors.tenantoperator.stakater.com"
  "templategroupinstances.tenantoperator.stakater.com"
  "templateinstances.tenantoperator.stakater.com"
  "templates.tenantoperator.stakater.com"
  "tenants.tenantoperator.stakater.com"
  "quotas.tenantoperator.stakater.com")

for crd in "${CRDS[@]}"; do
  echo "Processing CRD: $crd"

  # Identify and delete all associated CRs across all namespaces
  CR_NAMESPACES=$(oc get $crd --all-namespaces -o jsonpath='{.items[*].metadata.namespace}' >/dev/null 2>&1)

  # If the CRD is cluster-scoped, delete all CRs in the cluster
  if [ -z "$CR_NAMESPACES" ]; then
    CRs=$(oc get $crd -o jsonpath='{.items[*].metadata.name}' >/dev/null 2>&1)
    for cr in $CRs; do
        echo "Deleting cluster-scoped CR: $cr"
        if ! timeout $TIMEOUT_DURATION oc delete $crd $cr >/dev/null 2>&1; then
            echo "Timeout reached when deleting CRs, removing finalizers and trying again"
            oc patch $crd $cr --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1
            exists=$(oc get $crd $cr >/dev/null 2>&1)
            if [ -n "$exists" ]; then
              oc delete $crd $cr --grace-period=0 --force >/dev/null 2>&1
            fi
            echo "Deleted CR: $cr"
        fi
    done
  fi

  # If the CRD is namespace-scoped, delete all CRs in each namespace
  for ns in $CR_NAMESPACES; do
    echo "Deleting CRs in namespace: $ns"
    if ! timeout $TIMEOUT_DURATION oc delete $crd --all -n $ns >/dev/null 2>&1; then
      echo "Timeout reached when deleting CRs, removing finalizers and trying again"

      # If deletion of a CR is blocked or takes longer than $TIMEOUT_DURATION seconds, remove the finalizer and attempt deletion again
      CRs=$(oc get $crd -n $ns -o jsonpath='{.items[*].metadata.name}' >/dev/null 2>&1)
      for cr in $CRs; do
        oc patch $crd $cr -n $ns --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1
        exists=$(oc get $crd $cr -n $ns >/dev/null 2>&1)
        if [ -n "$exists" ]; then
          oc delete $crd $cr -n $ns --grace-period=0 --force >/dev/null 2>&1
        fi
        echo "Deleted CR: $cr in namespace: $ns"
      done
    fi
  done

  # Delete the CRD itself
  echo "Deleting CRD: $crd"
  if ! timeout $TIMEOUT_DURATION oc delete crd $crd >/dev/null 2>&1; then
    echo "Timeout reached when deleting CRD, removing finalizers and trying again"

    # If deletion of the CRD is blocked or takes longer than $TIMEOUT_DURATION seconds, remove the finalizer and attempt deletion again
    oc patch crd $crd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1
    exists=$(oc get crd $crd >/dev/null 2>&1)
    if [ -n "$exists" ]; then
      oc delete crd $crd --grace-period=0 --force >/dev/null 2>&1
    fi
  fi
  echo "Deleted CRD: $crd"
done

# Cleanup orphaned MTO namespaces
kubectl get namespaces -l stakater.com/tenant -o=jsonpath='{.items[*].metadata.name}' | \
xargs -n 1 -I % sh -c 'kubectl patch namespace % -p "{\"metadata\":{\"finalizers\":null}}" --type=merge && kubectl delete namespace %'
