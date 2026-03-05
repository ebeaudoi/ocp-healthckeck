#!/bin/bash

# OpenShift Cluster Health Check - Extended Version
# Includes node CPU/memory usage monitoring and additional tests

# Global variables
CLRGRN=$'\033[32m'
CLRRED=$'\033[31m'
CLRYLW=$'\033[33m'
CLRRESET=$'\033[0m'

# Thresholds for CPU and memory usage (percentage)
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=80

# Troubleshooting file (created when any check fails)
TROUBLESHOOT_FILE="ocp4hc-troubleshoot-$(date +%Y%m%d-%H%M%S).txt"
TROUBLESHOOT_CREATED=0

# Write troubleshooting commands to file (creates file on first failure)
write_troubleshoot() {
    local section_title="$1"
    shift
    local commands=("$@")
    if [ $TROUBLESHOOT_CREATED -eq 0 ]; then
        {
            echo "=============================================="
            echo "OpenShift Health Check - Troubleshooting Guide"
            echo "Generated: $(date)"
            echo "Cluster: $(oc whoami --show-server 2>/dev/null || echo 'N/A')"
            echo "=============================================="
            echo ""
        } > "$TROUBLESHOOT_FILE"
        TROUBLESHOOT_CREATED=1
    fi
    {
        echo "### $section_title"
        echo ""
        for cmd in "${commands[@]}"; do
            echo "$cmd"
        done
        echo ""
    } >> "$TROUBLESHOOT_FILE"
}

# Write troubleshooting with failure description (for etcd and similar)
write_troubleshoot_with_desc() {
    local section_title="$1"
    local description="$2"
    shift 2
    local commands=("$@")
    if [ $TROUBLESHOOT_CREATED -eq 0 ]; then
        {
            echo "=============================================="
            echo "OpenShift Health Check - Troubleshooting Guide"
            echo "Generated: $(date)"
            echo "Cluster: $(oc whoami --show-server 2>/dev/null || echo 'N/A')"
            echo "=============================================="
            echo ""
        } > "$TROUBLESHOOT_FILE"
        TROUBLESHOOT_CREATED=1
    fi
    {
        echo "### $section_title"
        echo ""
        echo "FAILURE DESCRIPTION:"
        echo "$description" | sed 's/^/  /'
        echo ""
        echo "INVESTIGATION COMMANDS:"
        for cmd in "${commands[@]}"; do
            echo "  $cmd"
        done
        echo ""
    } >> "$TROUBLESHOOT_FILE"
}

# Verify the oc command is installed
if ! command -v oc &> /dev/null; then
    echo "The oc command could not be found"
    echo "Please make sure the Openshift client tool is installed"
    exit 1
fi

# Verify jq is installed
if ! command -v jq &> /dev/null; then
    echo "The jq command could not be found"
    echo "Please install jq for JSON parsing"
    exit 1
fi

# OCP cluster info
OCPVER=$(oc get clusterversion -o=jsonpath={.items[*].status.desired.version} 2>/dev/null)
OCPCLUSTERID=$(oc get clusterversion -o=jsonpath={.items[*].spec.clusterID} 2>/dev/null)
printf "\n-- Cluster info --\n"
printf "OCP version   :  ${OCPVER}\n"
printf "OCP cluster ID:  ${OCPCLUSTERID}\n"

# Node information
printf "\n-- Node details --\n"
printf "\nMaster nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; oc get nodes | grep master | awk '{print $1" "$3}' | while read node role; do echo "$(oc get node $node -o json 2>/dev/null | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done) | column -s"|" -t
oc get nodes -l node-role.kubernetes.io/master= -o json 2>/dev/null | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'
printf "\nWorker nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; oc get nodes | grep worker | grep -v infra | awk '{print $1" "$3}' | while read node role; do echo "$(oc get node $node -o json 2>/dev/null | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done) | column -s"|" -t
oc get nodes -l node-role.kubernetes.io/worker= -o json 2>/dev/null | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'
printf "\nInfra nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; oc get nodes | grep infra | awk '{print $1" "$3}' | while read node role; do echo "$(oc get node $node -o json 2>/dev/null | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done) | column -s"|" -t
oc get nodes -l node-role.kubernetes.io/infra= -o json 2>/dev/null | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'

# Node CPU and Memory Usage (requires metrics-server)
printf "\n-- Node CPU and Memory Usage --\n"
if oc adm top nodes 2>/dev/null | head -1 | grep -q "CPU"; then
    printf "Current resource utilization:\n\n"
    oc adm top nodes
    printf "\n"
    # Check for nodes exceeding thresholds (columns: NAME CPU(cores) CPU% MEMORY MEMORY%)
    USAGE_ISSUES=0
    while read -r line; do
        [ -z "$line" ] && continue
        CPU_PCT=$(echo "$line" | awk '{print $(NF-2)}' | tr -d '%')
        MEM_PCT=$(echo "$line" | awk '{print $NF}' | tr -d '%')
        NODE_NAME=$(echo "$line" | awk '{print $1}')
        if [[ "$CPU_PCT" =~ ^[0-9]+$ ]] && [[ "$CPU_PCT" -ge "$CPU_WARN_THRESHOLD" ]] 2>/dev/null; then
            printf "  $CLRYLW WARNING: Node $NODE_NAME CPU usage is ${CPU_PCT}%% (threshold: ${CPU_WARN_THRESHOLD}%%) $CLRRESET\n"
            USAGE_ISSUES=1
        fi
        if [[ "$MEM_PCT" =~ ^[0-9]+$ ]] && [[ "$MEM_PCT" -ge "$MEM_WARN_THRESHOLD" ]] 2>/dev/null; then
            printf "  $CLRYLW WARNING: Node $NODE_NAME Memory usage is ${MEM_PCT}%% (threshold: ${MEM_WARN_THRESHOLD}%%) $CLRRESET\n"
            USAGE_ISSUES=1
        fi
    done < <(oc adm top nodes --no-headers 2>/dev/null)
    if [ "$USAGE_ISSUES" -eq 0 ]; then
        printf "Node resource usage within thresholds (CPU/Memory < ${CPU_WARN_THRESHOLD}%%) -- $CLRGRN PASSED $CLRRESET\n"
    else
        HIGH_USAGE_NODES=()
        while read -r line; do
            [ -z "$line" ] && continue
            cpu_pct=$(echo "$line" | awk '{print $(NF-2)}' | tr -d '%')
            mem_pct=$(echo "$line" | awk '{print $NF}' | tr -d '%')
            node=$(echo "$line" | awk '{print $1}')
            if [[ "$cpu_pct" =~ ^[0-9]+$ ]] && [[ "$cpu_pct" -ge "$CPU_WARN_THRESHOLD" ]] 2>/dev/null; then
                HIGH_USAGE_NODES+=("$node")
            elif [[ "$mem_pct" =~ ^[0-9]+$ ]] && [[ "$mem_pct" -ge "$MEM_WARN_THRESHOLD" ]] 2>/dev/null; then
                HIGH_USAGE_NODES+=("$node")
            fi
        done < <(oc adm top nodes --no-headers 2>/dev/null)
        HIGH_USAGE_NODES=($(printf '%s\n' "${HIGH_USAGE_NODES[@]}" | sort -u))
        CMDS=()
        for n in "${HIGH_USAGE_NODES[@]}"; do
            [ -n "$n" ] && CMDS+=("oc describe node $n" "oc adm top node $n")
        done
        CMDS+=("oc adm top nodes" "oc get pods -A --field-selector=status.phase=Running -o wide")
        [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Nodes Exceeding CPU/Memory Threshold" "${CMDS[@]}"
        printf "Some nodes exceed usage thresholds -- $CLRYLW WARNING $CLRRESET\n"
    fi
else
    printf "Metrics not available (metrics-server may not be running) -- $CLRYLW SKIPPED $CLRRESET\n"
fi

# Verify all nodes show ready to check for NotReady nodes
TOTALNODES=$(oc get nodes | grep -v NAME | wc -l)
TOTALNOTREADYNODE=$(oc get nodes | grep -v NAME | grep -vw Ready | wc -l)
printf "\n-- Node state --\n"
printf "Total Nodes:        %5d\n" $TOTALNODES
printf "Non-Ready Nodes:    %5d\n" $TOTALNOTREADYNODE

if [ $(($TOTALNOTREADYNODE)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get nodes | grep -v NAME | grep -vw Ready
    NOTREADY_NODES=($(oc get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status!="True")].metadata.name}' 2>/dev/null))
    if [ ${#NOTREADY_NODES[@]} -eq 0 ]; then
        NOTREADY_NODES=($(oc get nodes | grep -v NAME | grep -vw Ready | awk '{print $1}'))
    fi
    CMDS=()
    for n in "${NOTREADY_NODES[@]}"; do [ -n "$n" ] && CMDS+=("oc describe node $n"); done
    CMDS+=("oc get nodes" "oc get events -A --sort-by='.lastTimestamp' | tail -50")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "NotReady Nodes" "${CMDS[@]}"
    printf "Verify all nodes show ready -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify all nodes show ready -- $CLRGRN PASSED $CLRRESET\n"
fi

# Verify all cluster operators show available and that the control plane is healthy
TOTALCOTRUE=$(oc get co | grep -v NAME | wc -l)
TOTALCOFALSE=$(oc get co | grep -v NAME | grep -E -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)" | wc -l)

printf "\n-- Cluster Operator state --\n"
printf "Total COs:          %5d\n" $TOTALCOTRUE
printf "Non-Ready COs:      %5d\n" $TOTALCOFALSE
if [ $(($TOTALCOFALSE)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get co | grep -v NAME | grep -E -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)"
    FAILED_CO_NAMES=($(oc get co -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[] | select(.type=="Available" and .status!="True")) | .metadata.name' 2>/dev/null))
    [ ${#FAILED_CO_NAMES[@]} -eq 0 ] && FAILED_CO_NAMES=($(oc get co | grep -v NAME | grep -E -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)" | awk '{print $1}'))
    CMDS=()
    for co in "${FAILED_CO_NAMES[@]}"; do [ -n "$co" ] && CMDS+=("oc describe co $co"); done
    CMDS+=("oc get co")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Non-Ready Cluster Operators" "${CMDS[@]}"
    printf "Verify all cluster operators -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify all cluster operators -- $CLRGRN PASSED $CLRRESET\n"
fi

# API Services state
TOTALAPI=$(oc get apiservices | grep -v NAME | wc -l)
TOTALAPINOTREADY=$(oc get apiservices | grep -v NAME | grep -E -v "(.*)True(.*)" | wc -l)
printf "\n-- API Services state --\n"
printf "Total API Services:          %5d\n" $TOTALAPI
printf "Non-Ready API Services:      %5d\n" $TOTALAPINOTREADY
if [ $(($TOTALAPINOTREADY)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get apiservices | grep -v NAME | grep -E -v "(.*)True(.*)"
    FAILED_APISVC_NAMES=($(oc get apiservices -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Available" and .status!="True")) | .metadata.name' 2>/dev/null))
    [ ${#FAILED_APISVC_NAMES[@]} -eq 0 ] && FAILED_APISVC_NAMES=($(oc get apiservices | grep -v NAME | grep -E -v "(.*)True(.*)" | awk '{print $1}'))
    CMDS=()
    for api in "${FAILED_APISVC_NAMES[@]}"; do [ -n "$api" ] && CMDS+=("oc get apiservice $api -o yaml"); done
    CMDS+=("oc get apiservices")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Non-Ready API Services" "${CMDS[@]}"
    printf "Verify API Services state -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify API Services state -- $CLRGRN PASSED $CLRRESET\n"
fi

# Machine Config Pool state
TOTALMCP=$(oc get mcp | grep -v NAME | wc -l)
TOTALMCPNOTREADY=$(oc get mcp | grep -v NAME | grep -E -v "(.*)True(\s+)False(\s+)False(.*)" | wc -l)
printf "\n-- Machine Config Pool state --\n"
printf "Total MCPs:         %5d\n" $TOTALMCP
printf "Non-Ready MCPs:     %5d\n" $TOTALMCPNOTREADY
if [ $(($TOTALMCPNOTREADY)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get mcp | grep -v NAME | grep -E -v "(.*)True(\s+)False(\s+)False(.*)"
    FAILED_MCP_NAMES=($(oc get mcp -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Updated" and .status!="True")) | .metadata.name' 2>/dev/null))
    [ ${#FAILED_MCP_NAMES[@]} -eq 0 ] && FAILED_MCP_NAMES=($(oc get mcp | grep -v NAME | grep -E -v "(.*)True(\s+)False(\s+)False(.*)" | awk '{print $1}'))
    CMDS=()
    for mcp in "${FAILED_MCP_NAMES[@]}"; do [ -n "$mcp" ] && CMDS+=("oc describe mcp $mcp"); done
    CMDS+=("oc get mcp" "oc get mcp -o yaml")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Non-Ready Machine Config Pools" "${CMDS[@]}"
    printf "Verify machine Config Pool state -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify machine Config Pool state -- $CLRGRN PASSED $CLRRESET\n"
fi

# Operator state
TOTALCSV=$(oc get csv -A | grep -v NAMESPACE | wc -l)
TOTALCSVFAILED=$(oc get csv -A | grep -v NAMESPACE | grep -v Succeeded | wc -l)
printf "\n-- Operator state --\n"
printf "Total CSVs:         %5d\n" $TOTALCSV
printf "Failed CSVs:        %5d\n" $TOTALCSVFAILED
if [ $(($TOTALCSVFAILED)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get csv -A | grep -v NAMESPACE | grep -v Succeeded
    CMDS=()
    while read -r ns name rest; do
        [ -n "$ns" ] && [ -n "$name" ] && CMDS+=("oc describe csv -n $ns $name")
    done < <(oc get csv -A | grep -v NAMESPACE | grep -v Succeeded)
    CMDS+=("oc get csv -A")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Failed ClusterServiceVersions (CSVs)" "${CMDS[@]}"
    printf "Verify all operators states -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify all operators states -- $CLRGRN PASSED $CLRRESET\n"
fi

# Pod state
TOTALPOD=$(oc get pods -A | grep -v NAMESPACE | grep Running | wc -l)
TOTALPODNOTREADY=$(oc get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed | wc -l)
printf "\n-- Pod state --\n"
printf "Total Running Pods: %5d\n" $TOTALPOD
printf "Non-Running Pods:   %5d\n" $TOTALPODNOTREADY
if [ $(($TOTALPODNOTREADY)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed
    CMDS=()
    while read -r ns name rest; do
        if [ -n "$ns" ] && [ -n "$name" ] && [ "$ns" != "NAMESPACE" ]; then
            CMDS+=("oc describe pod -n $ns $name")
            CMDS+=("oc logs -n $ns $name --tail=50")
        fi
    done < <(oc get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed)
    CMDS+=("oc get pods -A | grep -v Running | grep -v Completed")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Non-Running Pods" "${CMDS[@]}"
    printf "Verify pod states -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify pod states -- $CLRGRN PASSED $CLRRESET\n"
fi

# Pending CSR
TOTALPENDINGCSR=$(oc get csr | grep -i Pending | wc -l)
printf "\n-- Pending CSR(s) --\n"
printf "Total pending CSR(s): %5d\n" $TOTALPENDINGCSR
if [ $(($TOTALPENDINGCSR)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get csr | grep -i Pending
    PENDING_CSR_NAMES=($(oc get csr -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions==null) | .metadata.name' 2>/dev/null))
    [ ${#PENDING_CSR_NAMES[@]} -eq 0 ] && PENDING_CSR_NAMES=($(oc get csr | grep -i Pending | awk '{print $1}'))
    CMDS=()
    for csr in "${PENDING_CSR_NAMES[@]}"; do [ -n "$csr" ] && CMDS+=("oc describe csr $csr"); done
    CMDS+=("oc get csr" "# To approve: oc adm certificate approve <csr-name>")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Pending Certificate Signing Requests" "${CMDS[@]}"
    printf "Verify pending CSR(s) -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify pending CSR(s) -- $CLRGRN PASSED $CLRRESET\n"
fi

# Persistent Volume status (additional check)
printf "\n-- Persistent Volume state --\n"
TOTALPV=$(oc get pv | grep -v NAME | wc -l)
PVNOTAVAILABLE=$(oc get pv | grep -v NAME | grep -v Available | grep -v Bound | wc -l)
printf "Total PVs:          %5d\n" $TOTALPV
printf "PVs not Available/Bound: %5d\n" $PVNOTAVAILABLE
if [ $(($PVNOTAVAILABLE)) -gt 0 ]; then
    printf "\nResource to investigate:\n"
    oc get pv | grep -v NAME | grep -v Available | grep -v Bound
    FAILED_PV_NAMES=($(oc get pv -o json 2>/dev/null | jq -r '.items[] | select(.status.phase!="Available" and .status.phase!="Bound") | .metadata.name' 2>/dev/null))
    [ ${#FAILED_PV_NAMES[@]} -eq 0 ] && FAILED_PV_NAMES=($(oc get pv | grep -v NAME | grep -v Available | grep -v Bound | awk '{print $1}'))
    CMDS=()
    for pv in "${FAILED_PV_NAMES[@]}"; do [ -n "$pv" ] && CMDS+=("oc describe pv $pv"); done
    CMDS+=("oc get pvc -A" "oc get storageclass")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Persistent Volumes (not Available/Bound)" "${CMDS[@]}"
    printf "\nPV status meanings (non Available/Bound):\n"
    printf "  Released - PVC was deleted; volume not yet reclaimed. Common with Retain policy.\n"
    printf "  Failed   - Volume failed reclamation or storage backend error. Volume unusable.\n"
    printf "  Pending  - Volume not yet provisioned. Check provisioner and StorageClass.\n"
    printf "\nTroubleshooting steps:\n"
    printf "  1. oc describe pv <pv-name>           - Get detailed status and events\n"
    printf "  2. oc get pvc -A                      - Check related PVCs\n"
    printf "  3. oc get storageclass                - Verify storage configuration\n"
    printf "  Released: Recreate PVC or manually delete/reclaim the PV.\n"
    printf "  Failed:   Fix storage backend, then delete PV to allow reprovisioning.\n"
    printf "  Pending:  Fix provisioner or StorageClass so volume can be provisioned.\n"
    printf "\nVerify PV state -- $CLRRED FAILED $CLRRESET\n"
else
    printf "Verify PV state -- $CLRGRN PASSED $CLRRESET\n"
fi

# Image registry health (additional check)
printf "\n-- Image Registry --\n"
if oc get clusteroperator image-registry 2>/dev/null | grep -q "True"; then
    printf "Image registry cluster operator -- $CLRGRN AVAILABLE $CLRRESET\n"
else
    write_troubleshoot "Image Registry Not Available" \
        "oc describe co image-registry" \
        "oc get pods -n openshift-image-registry" \
        "oc get pv | grep image-registry"
    printf "Image registry cluster operator -- $CLRRED NOT AVAILABLE $CLRRESET\n"
fi

# Certificate expiration (additional check - next 30 days)
printf "\n-- Certificate Expiration (next 30 days) --\n"
CERT_EXPIRING=$(oc get secret -A -o json 2>/dev/null | jq -r '
  .items[] | select(.metadata.annotations["auth.openshift.io/certificate-not-after"] != null) |
  .metadata.annotations["auth.openshift.io/certificate-not-after"] as $exp |
  .metadata.namespace + "/" + .metadata.name + " " + $exp' | while read nsname exp; do
    exp_epoch=$(date -d "$exp" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    days_left=$(( (exp_epoch - now_epoch) / 86400 ))
    if [ "$days_left" -lt 30 ] 2>/dev/null && [ "$days_left" -ge 0 ] 2>/dev/null; then
        echo "$nsname expires in $days_left days"
    fi
done)
if [ -n "$CERT_EXPIRING" ]; then
    printf "$CERT_EXPIRING\n"
    CMDS=()
    while read -r entry; do
        ns_sec="${entry%% *}"
        ns="${ns_sec%/*}"
        secret="${ns_sec#*/}"
        [ -n "$ns" ] && [ -n "$secret" ] && CMDS+=("oc get secret -n $ns $secret -o yaml")
    done < <(echo "$CERT_EXPIRING" | awk '{print $1}')
    CMDS+=("# Check cert expiration: oc get secret -n <namespace> <secret-name> -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}'")
    [ ${#CMDS[@]} -gt 0 ] && write_troubleshoot "Certificates Expiring in 30 Days" "${CMDS[@]}"
    printf "Certificates expiring within 30 days -- $CLRYLW WARNING $CLRRESET\n"
else
    printf "No certificates expiring in the next 30 days -- $CLRGRN PASSED $CLRRESET\n"
fi

# Etcd health - validated against oc get etcd cluster structure (see oc-get-etcd-cluster.yaml)
# Key conditions: EtcdMembersAvailable=True, StaticPodsAvailable=True, EtcdMembersDegraded=False
# Degraded-type conditions: status False = healthy, status True = degraded
printf "\n-- Etcd status --\n"
ETCD_CLUSTER_JSON=$(oc get etcd cluster -o json 2>/dev/null)
ETCD_STATUS=$(echo "$ETCD_CLUSTER_JSON" | jq -r '.status' 2>/dev/null)

# Validate using structure from oc-get-etcd-cluster.yaml
ETCD_MEMBERS_AVAIL=$(echo "$ETCD_STATUS" | jq -r '.conditions[]? | select(.type=="EtcdMembersAvailable") | .status' 2>/dev/null | head -1)
ETCD_STATIC_AVAIL=$(echo "$ETCD_STATUS" | jq -r '.conditions[]? | select(.type=="StaticPodsAvailable") | .status' 2>/dev/null | head -1)
ETCD_MEMBERS_DEGRADED=$(echo "$ETCD_STATUS" | jq -r '.conditions[]? | select(.type=="EtcdMembersDegraded") | .status' 2>/dev/null | head -1)

# Check nodeStatuses for failures (lastFailedCount > 0, per oc-get-etcd-cluster.yaml)
LATEST_REV=$(echo "$ETCD_STATUS" | jq -r '.latestAvailableRevision' 2>/dev/null)
ETCD_NODE_ISSUES=$(echo "$ETCD_STATUS" | jq -r '
    .nodeStatuses[]? | select(.lastFailedCount > 0) |
    "  - \(.nodeName): lastFailedCount=\(.lastFailedCount), lastFailedReason=\(.lastFailedReason // "none"), currentRevision=\(.currentRevision)"
' 2>/dev/null)

# Healthy when: EtcdMembersAvailable=True, StaticPodsAvailable=True, EtcdMembersDegraded=False
ETCD_HEALTHY=1
[ "$ETCD_MEMBERS_AVAIL" = "True" ] && [ "$ETCD_STATIC_AVAIL" = "True" ] && [ "$ETCD_MEMBERS_DEGRADED" != "True" ] && ETCD_HEALTHY=0

if [ $ETCD_HEALTHY -eq 0 ]; then
    printf "Etcd cluster -- $CLRGRN HEALTHY $CLRRESET\n"
    printf "  EtcdMembersAvailable: %s | StaticPodsAvailable: %s | EtcdMembersDegraded: %s\n" \
        "${ETCD_MEMBERS_AVAIL:-N/A}" "${ETCD_STATIC_AVAIL:-N/A}" "${ETCD_MEMBERS_DEGRADED:-N/A}"
else
    # Build exact failure description from oc-get-etcd-cluster.yaml condition structure
    ETCD_FAILURE_DESC="Validation failed (reference: oc-get-etcd-cluster.yaml)"
    ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n\n'"Core conditions (expected):"
    ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n'"  EtcdMembersAvailable: ${ETCD_MEMBERS_AVAIL:-missing} (expected: True)"
    ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n'"  StaticPodsAvailable:  ${ETCD_STATIC_AVAIL:-missing} (expected: True)"
    ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n'"  EtcdMembersDegraded:  ${ETCD_MEMBERS_DEGRADED:-missing} (expected: False)"

    # List all failing conditions: Available/StaticPods not True, or Degraded types with status True
    ETCD_FAIL_CONDITIONS=$(echo "$ETCD_STATUS" | jq -r '
        .conditions[]? | select(
            ((.type == "EtcdMembersAvailable" or .type == "StaticPodsAvailable") and .status != "True") or
            ((.type == "EtcdMembersDegraded") and .status == "True") or
            ((.type | test("Degraded$")) and .status == "True")
        ) | "  - \(.type): status=\(.status), reason=\(.reason // "N/A"), message=\(.message // "N/A"), lastTransition=\(.lastTransitionTime // "N/A")"
    ' 2>/dev/null)
    [ -n "$ETCD_FAIL_CONDITIONS" ] && ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n\n'"Failing conditions:"$'\n'"${ETCD_FAIL_CONDITIONS}"

    [ -n "$ETCD_NODE_ISSUES" ] && ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n\n'"Node status (revision/failure):"$'\n'"${ETCD_NODE_ISSUES}"
    ETCD_FAILURE_DESC="${ETCD_FAILURE_DESC}"$'\n\n'"latestAvailableRevision: ${LATEST_REV:-N/A}"

    if [ -z "$ETCD_STATUS" ] || [ "$ETCD_STATUS" = "null" ]; then
        ETCD_FAILURE_DESC="Unable to retrieve etcd cluster status. Command: oc get etcd cluster -o json. Etcd resource may be missing or API unavailable."
    fi

    write_troubleshoot_with_desc "Etcd Cluster Unhealthy" "$ETCD_FAILURE_DESC" \
        "oc get etcd cluster -o json | jq '.status'" \
        "oc get etcd cluster -o json | jq '.status.conditions'" \
        "oc get etcd cluster -o json | jq '.status.nodeStatuses'" \
        "oc get etcd -o yaml" \
        "oc get pods -n openshift-etcd" \
        "oc logs -n openshift-etcd -l app=etcd --tail=100" \
        "oc get events -n openshift-etcd --sort-by='.lastTimestamp'"
    printf "Etcd cluster -- $CLRRED CHECK REQUIRED $CLRRESET\n"
    printf "  EtcdMembersAvailable: %s | StaticPodsAvailable: %s | EtcdMembersDegraded: %s\n" \
        "${ETCD_MEMBERS_AVAIL:-N/A}" "${ETCD_STATIC_AVAIL:-N/A}" "${ETCD_MEMBERS_DEGRADED:-N/A}"
fi

# Report deprecated API Usage
printf "\n-- Deprecated API Usage --\n"
oc get apirequestcounts -o json 2>/dev/null | jq -r '[
  .items[]
  | select(.status.removedInRelease)
  | .metadata.name as $api 
  | {name: .metadata.name, removedInRelease: .status.removedInRelease}
    + (.status.last24h[] | select(has("byNode")) | .byNode[] | select(has("byUser")) | .byUser[] | {username,userAgent,"verb": .byVerb[].verb})
    + {currHour: .status.currentHour.requestCount, last24H: .status.requestCount}
]
| group_by( {name, removedInRelease, username, userAgent} )
| map(first + {verb: map(.verb) | unique})
| .[] | [.removedInRelease, .name, .username, .userAgent, (.verb | join(",")),.currHour, .last24H]
| join("\t")' 2>/dev/null | sort | column -N "DEPREL,NAME,USERNAME,USERAGENT,VERB,CURRHOUR,LAST24H" -t 2>/dev/null || printf "No deprecated API usage detected or unable to query.\n"

printf "\n-- End of health check report --\n\n"

if [ $TROUBLESHOOT_CREATED -eq 1 ]; then
    printf "${CLRYLW}Troubleshooting file created: ${TROUBLESHOOT_FILE}${CLRRESET}\n"
    printf "Run the commands in that file to investigate failures.\n\n"
fi
