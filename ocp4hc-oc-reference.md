# OpenShift CLI Reference — `ocp4hc-extended.sh`

Commands extracted from the extended cluster health check script. Placeholders such as `<node-name>`, `<namespace>`, and `<resource-name>` stand in for runtime variables from the script.

---

## Session & cluster identity

| Command | Description |
|---------|-------------|
| `oc whoami --show-server` | Show the API server URL for the current login context (used in troubleshooting report headers). |
| `oc get clusterversion -o=jsonpath={.items[*].status.desired.version}` | Read the cluster’s desired OpenShift version. |
| `oc get clusterversion -o=jsonpath={.items[*].spec.clusterID}` | Read the unique cluster ID from the ClusterVersion resource. |

---

## Cluster & nodes

| Command | Description |
|---------|-------------|
| `oc get nodes` | List all nodes and their high-level status (Ready, roles, version). |
| `oc get node <node-name> -o json` | Get full node JSON (CPU/memory capacity, conditions) for a single node. |
| `oc get nodes -l node-role.kubernetes.io/master= -o json` | List master nodes as JSON for capacity totals. |
| `oc get nodes -l node-role.kubernetes.io/worker= -o json` | List worker nodes as JSON for capacity totals. |
| `oc get nodes -l node-role.kubernetes.io/infra= -o json` | List infra nodes as JSON for capacity totals. |
| `oc get nodes -o json` | List all nodes as JSON (e.g. OVN pod network node list). |
| `oc get nodes -o wide` | List nodes with extra columns (IPs, OS) for network troubleshooting. |
| `oc get nodes -o jsonpath='{.items[*].metadata.name}'` | Extract all node names (machine network section). |
| `oc get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'` | List InternalIPs for all nodes (derive machine network CIDR). |
| `oc get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status!="True")].metadata.name}'` | List node names that are not Ready. |
| `oc get node <node-name> -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'` | Get a single node’s InternalIP. |
| `oc describe node <node-name>` | Detailed node status, conditions, and events (NotReady or high CPU/memory). |
| `oc adm top nodes` | Show live CPU and memory usage per node (requires metrics-server). |
| `oc adm top nodes --no-headers` | Same as above, without column headers (for scripted threshold checks). |
| `oc adm top node <node-name>` | Resource usage for one node. |
| `oc get pods -A --field-selector=status.phase=Running -o wide` | List running pods cluster-wide with node placement (workload on hot nodes). |
| `oc get events -A --sort-by='.lastTimestamp'` | Recent cluster events (often paired with `tail` for NotReady investigation). |

---

## Platform & control plane

| Command | Description |
|---------|-------------|
| `oc get co` | List cluster operators and their Available/Progressing/Degraded state. |
| `oc get co -o json` | Cluster operators as JSON (filter failing Available conditions with jq). |
| `oc describe co <operator-name>` | Events and conditions for a degraded cluster operator. |
| `oc get co/network -o json` | Network cluster operator resource as JSON (condition inspection). |
| `oc get apiservices` | List aggregated API services and availability. |
| `oc get apiservices -o json` | API services as JSON (find non-Available entries). |
| `oc get apiservice <name> -o yaml` | Full definition and status of one API service. |
| `oc get mcp` | List MachineConfigPools and update/degraded state. |
| `oc get mcp -o json` | Machine config pools as JSON (find non-Updated pools). |
| `oc get mcp -o yaml` | Full MCP configuration and status. |
| `oc describe mcp <pool-name>` | Detailed MCP status and machine config rollout issues. |

---

## Operators & workloads

| Command | Description |
|---------|-------------|
| `oc get csv -A` | List CSVs cluster-wide (install state); default output includes VERSION — filter with `awk` below for a quick view. |
| `oc get csv -A -o json` | CSVs as JSON for operator listing or failure diagnosis (optional jq filter below). |
| `oc get csv -A -o go-template=...` | List installed operators with version without jq (see go-template example below). |
| `oc describe csv -n <namespace> <csv-name>` | Diagnose a failed or non-Succeeded operator install. |
| `oc get pods -A` | List pods in all namespaces (running vs non-running counts). |
| `oc describe pod -n <namespace> <pod-name>` | Pod events, scheduling, and container state for failing pods. |
| `oc logs -n <namespace> <pod-name> --tail=50` | Recent container logs for a non-running pod. |

**Installed operators with version** — Succeeded-phase CSVs with namespace, display name, and `spec.version`. Output is **deduplicated by operator name** (one row per operator; if the same operator appears in multiple namespaces, the first row after sort is kept). Matches health check “Installed operators (OLM)” logic with deduplication applied.

*With jq:*

```bash
oc get csv -A -o json | jq -r '
  [.items[] | select(.status.phase=="Succeeded")
    | .metadata.name as $csvname
    | {
        namespace: .metadata.namespace,
        operator: ((.spec.displayName | if . == null or . == "" then $csvname else . end)),
        version: (.spec.version // "N/A")
      }
  ]
  | sort_by(.operator, .namespace, .version)
  | unique_by(.operator)
  | [.namespace, .operator, .version]
  | @tsv' | column -t
```

*Without jq* — uses `oc` go-template, `sort`, and `awk` (POSIX-friendly; no `jq` or `column` required):

```bash
printf "%-28s %-48s %s\n" NAMESPACE OPERATOR VERSION
oc get csv -A -o go-template='{{range .items}}{{if eq .status.phase "Succeeded"}}{{.metadata.namespace}}{{"	"}}{{if .spec.displayName}}{{.spec.displayName}}{{else}}{{.metadata.name}}{{end}}{{"	"}}{{if .spec.version}}{{.spec.version}}{{else}}N/A{{end}}{{"\n"}}{{end}}{{end}}' \
  | LC_ALL=C sort -t '	' -k2,2 -k1,1 -k3,3 \
  | awk -F'	' '!seen[$2]++ {printf "%-28s %-48s %s\n", $1, $2, ($3 != "" ? $3 : "N/A")}'
```

*Quick view* — tab-separated fields, deduplicated by operator (column 2):

```bash
printf "%-28s %-48s %s\n" NAMESPACE OPERATOR VERSION
oc get csv -A -o go-template='{{range .items}}{{if eq .status.phase "Succeeded"}}{{.metadata.namespace}}{{"	"}}{{if .spec.displayName}}{{.spec.displayName}}{{else}}{{.metadata.name}}{{end}}{{"	"}}{{if .spec.version}}{{.spec.version}}{{else}}N/A{{end}}{{"\n"}}{{end}}{{end}}' \
  | LC_ALL=C sort -t '	' -k2,2 \
  | awk -F'	' '!seen[$2]++ {print $1, $2, $3}'
```

---

## Storage & security

| Command | Description |
|---------|-------------|
| `oc get csr` | List certificate signing requests (pending node/cert approvals). |
| `oc get csr -o json` | CSRs as JSON (find requests with no status/conditions). |
| `oc describe csr <csr-name>` | Details of a pending certificate request. |
| `oc adm certificate approve <csr-name>` | Approve a pending CSR (documented in troubleshooting output). |
| `oc get pv` | List persistent volumes and phases (Available, Bound, Released, etc.). |
| `oc get pv -o json` | PVs as JSON (find volumes not Available or Bound). |
| `oc describe pv <pv-name>` | PV events, claim reference, and reclamation status. |
| `oc get pvc -A` | List persistent volume claims cluster-wide (map to problematic PVs). |
| `oc get storageclass` | List storage classes (provisioner and reclaim policy checks). |

---

## Network

| Command | Description |
|---------|-------------|
| `oc get clusteroperator/network` | Network cluster operator summary (troubleshooting entry point). |
| `oc get clusteroperator/network -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` | Whether the network operator reports Available. |
| `oc get clusteroperator/network -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}'` | Whether the network operator is Degraded. |
| `oc get clusteroperator/network -o jsonpath='{.status.conditions[?(@.type=="Degraded")].message}'` | Degraded condition message for the network operator. |
| `oc describe clusteroperators/network` | Full network operator status and related events. |
| `oc get network.config/cluster` | Verify cluster network configuration resource exists. |
| `oc get network.config/cluster -o jsonpath='{.spec.networkType}'` | Network plugin type (e.g. OVNKubernetes, OpenShiftSDN). |
| `oc get network.config/cluster -o jsonpath='{.spec.clusterNetwork[*].cidr}'` | Pod network CIDR(s). |
| `oc get network.config/cluster -o jsonpath='{.spec.clusterNetwork[*].hostPrefix}'` | Host prefix per cluster network entry. |
| `oc get network.config/cluster -o jsonpath='{.spec.serviceNetwork[*]}'` | Kubernetes service network CIDR(s). |
| `oc get network.config/cluster -o yaml` | Full cluster network configuration for review. |
| `oc get network.operator cluster -o yaml` | Cluster Network Operator configuration and defaults. |
| `oc get nns` | List NodeNetworkState resources (nmstate), if installed. |
| `oc get nns <node-name>` | Check whether a node has an NNS object. |
| `oc get nns <node-name> -o json` | Node interface and IPv4 prefix (machine network netmask). |
| `oc get pods -n openshift-ovn-kubernetes` | OVN-Kubernetes control plane and node pods. |
| `oc get pods -n openshift-ovn-kubernetes --no-headers` | OVN pod counts without headers (scripted health check). |
| `oc get pods -n openshift-sdn --no-headers` | OpenShift SDN plugin pods (legacy network type). |
| `oc get events -n openshift-ovn-kubernetes --sort-by='.lastTimestamp'` | Recent events in the OVN namespace. |
| `oc -n kube-system get cm/cluster-config-v1 -o yaml` | Cluster install config (machineNetwork CIDR from config map). |
| `oc get agentclusterinstall -A -o jsonpath='{.items[0].spec.networking.machineNetwork[0].cidr}'` | Machine network CIDR from AgentClusterInstall (assisted install). |
| `oc get clusterinstall -A -o jsonpath='{.items[0].spec.machineNetwork[0].cidr}'` | Machine network CIDR from ClusterInstall CR. |
| `oc get clusterdeployment -A -o jsonpath='{.items[0].spec.clusterMetadata.installConfig.configMapRef.name}'` | Install-config ConfigMap name (ACM-managed clusters). |
| `oc get clusterdeployment -A -o jsonpath='{.items[0].spec.clusterMetadata.installConfig.configMapRef.namespace}'` | Namespace of the install-config ConfigMap. |
| `oc get configmap <name> -n <namespace> -o jsonpath='{.data.install-config}'` | Read install-config YAML from a referenced ConfigMap. |
| `oc get clusteroperator/dns` | DNS operator availability. |
| `oc get clusteroperator/dns -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` | DNS operator Available condition only. |
| `oc get pods -n openshift-dns` | CoreDNS / dns operator pods. |
| `oc get pods -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default --no-headers` | Count default DNS daemonset pods. |
| `oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` | Default ingress controller Available state. |
| `oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}'` | Default ingress controller Degraded state. |
| `oc get ingresscontroller -n openshift-ingress-operator` | List ingress controllers in the ingress operator namespace. |
| `oc get pods -n openshift-ingress` | Ingress router / controller workload pods. |
| `oc get deployment network-operator -n openshift-network-operator -o jsonpath='{.status.readyReplicas}'` | Ready replicas of the network operator deployment. |
| `oc get deployment network-operator -n openshift-network-operator -o jsonpath='{.spec.replicas}'` | Desired replicas of the network operator deployment. |
| `oc get -n openshift-network-operator deployment/network-operator` | Network operator deployment resource. |
| `oc get proxy/cluster` | Check whether a cluster-wide HTTP/HTTPS proxy is configured. |
| `oc get proxy/cluster -o jsonpath='{.spec.httpProxy}'` | HTTP proxy URL, if set. |
| `oc get proxy/cluster -o jsonpath='{.spec.httpsProxy}'` | HTTPS proxy URL, if set. |
| `oc get proxy/cluster -o yaml` | Full cluster proxy configuration. |
| `oc get network-attachment-definitions -A --no-headers` | Count Multus NetworkAttachmentDefinitions (secondary networks). |
| `oc adm must-gather --image=quay.io/openshift/origin-must-gather:latest` | Collect general cluster diagnostics (network troubleshooting note). |
| `oc adm must-gather --image-stream=openshift/network-tools:latest` | Collect network-focused must-gather (OVN debug). |

---

## Registry & certificates

| Command | Description |
|---------|-------------|
| `oc get clusteroperator image-registry` | Image registry operator availability. |
| `oc describe co image-registry` | Image registry operator conditions and events. |
| `oc get pods -n openshift-image-registry` | Registry deployment pods. |
| `oc get secret -A -o json` | All secrets as JSON (find certs with expiration annotations). |
| `oc get secret -n <namespace> <secret-name> -o yaml` | Inspect a secret tied to an expiring certificate. |
| `oc get secret -n <namespace> <secret-name> -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}'` | Read certificate not-after date from annotation. |

---

## etcd

| Command | Description |
|---------|-------------|
| `oc get etcd cluster -o json` | etcd cluster custom resource status (members, static pods, degraded). |
| `oc get etcd -o yaml` | Full etcd cluster resource definition and status. |
| `oc get pods -n openshift-etcd` | etcd member static pods on control plane nodes. |
| `oc logs -n openshift-etcd -l app=etcd --tail=100` | Recent logs from etcd pods. |
| `oc get events -n openshift-etcd --sort-by='.lastTimestamp'` | Recent etcd namespace events. |

---

## API deprecations

| Command | Description |
|---------|-------------|
| `oc get apirequestcounts -o json` | API request counts for deprecated APIs (removedInRelease, usage by user/agent). |

---

## Master node replacement troubleshooting

Typical failure pattern from must-gather analysis (bare-metal or IPI control plane). Replace placeholders with your cluster’s names and IPs.

### Root cause (summary)

A failed master replacement often leaves the control plane degraded:

1. **Replacement node never stabilized** — New Node object reports `KubeletNotReady` / **NetworkPluginNotReady** (CNI not ready), then **NodeStatusUnknown** (kubelet stopped posting status).
2. **Stale / pending etcd member** — `clusteroperator/etcd` reports a pending member (e.g. `NAME-PENDING-<new-ip> has not started`) with only 2 of 3 members healthy. API server etcd URLs may point at the new IP while the member never joined.
3. **Stale Machine vs new Node (topology drift)** — The **Machine** object (e.g. `<cluster-id>-master-0`) was **not deleted or updated** during replacement and still reports the **old IP** (`<old-ip>`). A **new Node** joined with the **new IP** (`<new-ip>`). Operators (**etcd**, **kube-apiserver**, **machine-config**) rely on Machine status and linked topology; the mismatch leaves endpoints and membership out of sync (OVN annotations on the node may still reference the old IP).
4. **Static pod rollout stuck** — etcd operator shows the failing node at an old revision with a higher target revision; `0 nodes have achieved new revision`. Missing static pods on that node for kube-controller-manager and kube-scheduler.
5. **Machine drain blocked** — Master Machines show `Drainable=False` with `EtcdQuorumOperator` preDrain hook (expected until etcd approves removal).
6. **Downstream impact** — `machine-config` master pool shows fewer ready machines than expected; network operator rollouts may stall on the failed node.

**Remediation direction:** Restore the failing master (correct L2/L3 address, OVN/CNI, kubelet) *or* complete etcd member removal/add per [Red Hat etcd recovery documentation](https://access.redhat.com/documentation/en-us/openshift_container_platform/latest/html/postinstallation_network_configuration/configuration-changes-post-install#replacing-a-failed-etcd-member_post-install), then re-run master replacement. Do not delete a second master while etcd is degraded.

### Verify stale Machine vs new Node

Compare **Machine age/IP** with **Node age/IP**. A large age gap plus different InternalIPs on the same hostname indicates the Machine was not reconciled during replacement.

*Single Machine — age, phase, linked node, IP from Machine status:*

```bash
oc get machines.machine.openshift.io <machine-name> -n openshift-machine-api -o wide
oc get machines.machine.openshift.io <machine-name> -n openshift-machine-api -o jsonpath='
  Machine:     {.metadata.name}
  Created:     {.metadata.creationTimestamp}
  Generation:  {.metadata.generation}
  Phase:       {.status.phase}
  NodeRef:     {.status.nodeRef.name}
  Machine IP:  {.status.addresses[?(@.type=="InternalIP")].address}
  ProviderID:  {.spec.providerID}
'
```

*Single Node — age, Ready, IP from Node status, link back to Machine:*

```bash
oc get node <node-name> -o wide
oc get node <node-name> -o jsonpath='
  Node:        {.metadata.name}
  Created:     {.metadata.creationTimestamp}
  Ready:       {.status.conditions[?(@.type=="Ready")].status} ({.status.conditions[?(@.type=="Ready")].reason})
  Node IP:     {.status.addresses[?(@.type=="InternalIP")].address}
  Machine:     {.metadata.annotations.machine\.openshift\.io/machine}
  OVN primary: {.metadata.annotations.k8s\.ovn\.org/node-primary-ifaddr}
'
```

*All masters — side-by-side Machine IP vs Node IP:*

(`custom-columns` does not support JSONPath filters such as `[?(@.type=="InternalIP")]`; use `go-template` and tab-separated fields instead.)

```bash
printf "%-32s %-20s %-16s %-32s %-20s %-16s\n" MACHINE M_CREATED MACHINE_IP NODE N_CREATED NODE_IP
oc get machines.machine.openshift.io -n openshift-machine-api \
  -l machine.openshift.io/cluster-api-machine-role=master \
  -o go-template='{{range .items}}{{.metadata.name}}{{"	"}}{{.metadata.creationTimestamp}}{{"	"}}{{range .status.addresses}}{{if eq .type "InternalIP"}}{{.address}}{{end}}{{end}}{{"	"}}{{if .status.nodeRef}}{{.status.nodeRef.name}}{{end}}{{"\n"}}{{end}}' \
| while IFS="$(printf '\t')" read -r m mc mip n; do
  [ -z "$m" ] && continue
  if [ -n "$n" ]; then
    nc=$(oc get node "$n" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
    nip=$(oc get node "$n" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
  else
    nc="N/A"
    nip="N/A"
  fi
  printf "%-32s %-20s %-16s %-32s %-20s %-16s\n" "$m" "$mc" "${mip:-N/A}" "$n" "${nc:-N/A}" "${nip:-N/A}"
done
```

*Alternative (two wide listings, no loop — compare MACHINE vs NODE columns manually):*

```bash
oc get machines.machine.openshift.io -n openshift-machine-api \
  -l machine.openshift.io/cluster-api-machine-role=master -o wide
oc get nodes -l node-role.kubernetes.io/master= -o wide
```

*Operators that depend on control-plane topology:*

```bash
oc get co etcd kube-apiserver machine-config -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[?(@.type=="Available")].status,DEGRADED:.status.conditions[?(@.type=="Degraded")].status,MESSAGE:.status.conditions[?(@.type=="Degraded")].message
oc describe co etcd | sed -n '/Message:/,/Reason:/p'
oc get openshiftapiserver cluster -o yaml | grep -E 'etcd-servers|storage'
oc get kubeapiserver cluster -o yaml | grep -E 'etcd-servers|storage'
oc get mcp master -o custom-columns=POOL:.metadata.name,MACHINES:.status.machineCount,READY:.status.readyMachineCount,UNAVAILABLE:.status.unavailableMachineCount,UPDATED:.status.updatedMachineCount
oc get etcd cluster -o jsonpath='{range .status.nodeStatuses[*]}{.nodeName}{"\t"}current={.currentRevision}{"\t"}target={.targetRevision}{"\n"}{end}'
```

**Expected when replacement failed:** Machine **M_CREATED** is much older than Node **N_CREATED**; **MACHINE_IP** (`<old-ip>`) ≠ **NODE_IP** (`<new-ip>`) for the same **NODE** name; etcd CO mentions a pending member at the Node IP while the Machine still advertises the old IP.

### OpenShift commands

| Command | Description |
|---------|-------------|
| `oc get nodes -l node-role.kubernetes.io/master= -o wide` | Master nodes, roles, IPs, and Ready state. |
| `oc describe node <node-name>` | Conditions, taints, events (NotReady, Unknown, unreachable). |
| `oc adm node-logs <node-name> kubelet` | Kubelet logs on the failing master (requires node access). |
| `oc debug node/<node-name> -- chroot /host journalctl -u kubelet -n 200` | Kubelet journal on the node (interactive debug). |
| `oc get machines.machine.openshift.io <machine-name> -n openshift-machine-api -o jsonpath='{.metadata.creationTimestamp}{"\n"}{.status.addresses}'` | Machine object age and status addresses (operator-facing IP). |
| `oc get node <node-name> -o jsonpath='{.metadata.creationTimestamp}{"\n"}{.status.addresses}'` | Node object age and status addresses (kubelet-reported IP). |
| `oc get machines.machine.openshift.io -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp,IP:.status.addresses[?(@.type=="InternalIP")].address,NODE:.status.nodeRef.name` | All master Machines with creation time and IP. |
| `oc get nodes -l node-role.kubernetes.io/master= -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp,IP:.status.addresses[?(@.type=="InternalIP")].address,MACHINE:.metadata.annotations.machine\.openshift\.io/machine` | All master Nodes with creation time, IP, and Machine annotation. |
| `oc get machines.machine.openshift.io -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master` | Master Machine objects and phase. |
| `oc describe machines.machine.openshift.io <machine-name> -n openshift-machine-api` | Drainable/Terminable conditions, `EtcdQuorumOperator` hook, nodeRef. |
| `oc get machineset -n openshift-machine-api` | MachineSets for control-plane (scale/replace context). |
| `oc get baremetalhost -n openshift-machine-api` | Bare-metal host provisioning state (IPI bare metal). |
| `oc describe baremetalhost <host-name> -n openshift-machine-api` | BMH errors, `operationalStatus`, consumerRef to Machine. |
| `oc get co etcd` | etcd cluster operator Available/Degraded/Progressing. |
| `oc describe co etcd` | Full etcd CO messages (pending members, master NotReady). |
| `oc get etcd cluster -o yaml` | etcd member status, `nodeStatuses`, target/current revisions. |
| `oc get etcd cluster -o jsonpath='{.status.nodeStatuses}'` | Per-master revision rollout (e.g. stuck at 39 → 51). |
| `oc get pods -n openshift-etcd -o wide` | etcd static pods per control-plane node. |
| `oc logs -n openshift-etcd -l app=etcd -c etcd --tail=200` | etcd container logs (member health, TLS, peers). |
| `oc get events -n openshift-etcd --sort-by='.lastTimestamp'` | etcd namespace events (installers, guards, failures). |
| `oc logs -n openshift-etcd-operator deployment/etcd-operator --tail=200` | cluster-etcd-operator reconciliation errors. |
| `oc get secret -n openshift-etcd \| grep <node-name>` | Per-node etcd serving certs (missing cert errors in operator logs). |
| `oc get endpoints -n openshift-etcd -o yaml` | etcd client endpoints published to the cluster. |
| `oc get kubeapiserver cluster -o jsonpath='{.status.latestAvailableRevision}'` | API server revision (correlate with etcd). |
| `oc get openshiftapiserver cluster -o yaml` | Observed `etcd-servers` list (verify old vs new IP mismatch). |
| `oc get pods -n openshift-kube-apiserver -o wide` | API server pods and which nodes they run on. |
| `oc get pods -n openshift-kube-controller-manager -o wide` | Missing static pod errors reference this namespace. |
| `oc get pods -n openshift-kube-scheduler -o wide` | Scheduler static pods on masters. |
| `oc get mcp master` | Master MachineConfigPool ready/unavailable counts. |
| `oc describe mcp master` | MCP updating/degraded; which nodes lack rendered config. |
| `oc get machineconfigpool master -o jsonpath='{.status}'` | Machine counts: ready vs unavailable during replacement. |
| `oc get pods -n openshift-ovn-kubernetes -o wide \| grep <node-name>` | OVN kube-node on the master (CNI readiness). |
| `oc get events -A --field-selector involvedObject.name=<node-name> --sort-by='.lastTimestamp'` | All events involving the failing master node. |
| `oc get csr` | Pending CSRs for new control-plane kubelet/API clients. |
| `oc adm certificate approve <csr-name>` | Approve pending node/kubelet certificates. |
| `oc get pods -n openshift-machine-api` | machine-api / baremetal operator pods. |
| `oc logs -n openshift-machine-api deployment/machine-api-controllers --tail=100` | Machine controller drain/delete errors. |
| `oc adm must-gather` | Collect support bundle when replacing masters. |

**On a healthy quorum node (advanced, use with care):**

| Command | Description |
|---------|-------------|
| `oc rsh -n openshift-etcd -c etcd etcd-<healthy-node> etcdctl member list -w table` | List etcd members (find stale `NAME-PENDING` entries). |
| `oc rsh -n openshift-etcd -c etcd etcd-<healthy-node> etcdctl endpoint health` | Check which etcd endpoints respond. |

---

## Notes

- Many checks pipe `oc` output through `grep`, `awk`, `jq`, or `column`; the table lists the underlying `oc` invocations.
- Commands with `-n <namespace>` use OpenShift/Kubernetes namespaces such as `openshift-ovn-kubernetes`, `openshift-dns`, `openshift-etcd`, and `kube-system`.
- Resource short names: `co` = clusteroperators, `mcp` = machineconfigpools, `csv` = clusterserviceversions, `csr` = certificatesigningrequests, `nns` = nodenetworkstates, `cm` = configmaps.

*Commands from `ocp4hc-extended.sh`; master replacement section derived from must-gather analysis (customer-specific details removed).*
