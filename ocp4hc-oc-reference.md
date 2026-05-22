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

Analysis from `must-gather-siriusxm.tar.gz` (cluster **sv7-cl1-r2dt7**, bare-metal masters **cl1-con01/02/03**).

### Root cause (summary)

Master replacement for **cl1-con01.sv7.ocp.broadcast.siriusxm.com** (`sv7-cl1-r2dt7-master-0`) failed and left the control plane degraded:

1. **Replacement node never stabilized** — Node registered `2026-05-21T18:08:57Z`, first reported `KubeletNotReady` / **NetworkPluginNotReady** (no CNI in `/etc/kubernetes/cni/net.d/`), then **NodeStatusUnknown** from `2026-05-21T20:49:13Z` (kubelet stopped posting status).
2. **Stale / pending etcd member** — `clusteroperator/etcd` reports `NAME-PENDING-10.103.50.13 has not started` (only 2 of 3 members healthy). API server etcd URLs were updated to `https://10.103.50.13:2379` while the member never joined.
3. **IP inconsistency on the failing master** — Node `status.addresses` shows **10.103.50.13**, but the Machine and OVN annotations still reference **10.103.50.91**, blocking correct etcd endpoint and network alignment.
4. **Static pod rollout stuck** — `etcd` operator: `cl1-con01` at revision **39**, target **51**; `0 nodes have achieved new revision 51`. Missing static pods on cl1-con01 for kube-controller-manager and kube-scheduler.
5. **Machine drain blocked** — All master Machines show `Drainable=False` with `EtcdQuorumOperator` preDrain hook (expected until etcd approves removal).
6. **Downstream impact** — `machine-config` master pool: **2/3 ready**, **1 unavailable**; network operator rollouts stalled on the failed node.

**Remediation direction:** Restore cl1-con01 (correct L2/L3 address, OVN/CNI, kubelet) *or* complete etcd member removal/add per [Red Hat etcd recovery docs](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.20/html/postinstallation_network_configuration/configuration-changes-post-install#replacing-a-failed-etcd-member_post-install), then re-run master replacement. Do not delete a second master while etcd is degraded.

### OpenShift commands

| Command | Description |
|---------|-------------|
| `oc get nodes -l node-role.kubernetes.io/master= -o wide` | Master nodes, roles, IPs, and Ready state. |
| `oc describe node <node-name>` | Conditions, taints, events (NotReady, Unknown, unreachable). |
| `oc adm node-logs <node-name> kubelet` | Kubelet logs on the failing master (requires node access). |
| `oc debug node/<node-name> -- chroot /host journalctl -u kubelet -n 200` | Kubelet journal on the node (interactive debug). |
| `oc get machine -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master` | Master Machine objects and phase. |
| `oc describe machine <machine-name> -n openshift-machine-api` | Drainable/Terminable conditions, `EtcdQuorumOperator` hook, nodeRef. |
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
| `oc get openshiftapiserver cluster -o yaml` | Observed `etcd-servers` list (verify IP .91 vs .13 mismatch). |
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
| `oc adm must-gather` | Collect support bundle when replacing masters (as in this analysis). |

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

*Commands from `ocp4hc-extended.sh`; master replacement section informed by `must-gather-siriusxm.tar.gz` (2026-05-22).*
