#!/bin/bash

# Global variables
CLRGRN=$'\033[32m'; 
CLRRED=$'\033[31m'; 
CLRRESET=$'\033[0m';

# Verify the oc command is installed
if ! command -v oc &> /dev/null
then
    echo "The oc command could not be found"
    echo "Please make sure the Openshift client tool is installed"
    exit 1
fi

# OCP cluster info
OCPVER=$(oc get clusterversion -o=jsonpath={.items[*].status.desired.version})
OCPCLUSTERID=$(oc get clusterversion -o=jsonpath={.items[*].spec.clusterID})
printf "\n-- Cluster info --\n"
printf "OCP version   :  ${OCPVER}\n"
printf "OCP cluster ID:  ${OCPCLUSTERID}\n"

# Node information
printf "\n-- Node details --\n"
printf "\nMaster nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; oc get nodes | grep master | awk '{print $1" "$3}' | while read node role;  do echo "$(oc get node $node -o json | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role" ; done ) | column -s"|" -t
oc get nodes -l node-role.kubernetes.io/master=  -o json | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'
printf "\nWorker nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; oc get nodes | grep worker | grep -v infra | awk '{print $1" "$3}' | while read node role;  do echo "$(oc get node $node -o json | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done ) | column -s"|" -t
oc get nodes -l node-role.kubernetes.io/worker=  -o json | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'
printf "\nInfra nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; oc get nodes | grep infra | awk '{print $1" "$3}' | while read node role;  do echo "$(oc get node $node -o json | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done ) | column -s"|" -t
oc get nodes -l node-role.kubernetes.io/infra=  -o json | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'

# Verify all nodes show ready to check for NotReady nodes.
TOTALNODES=$(oc get nodes | grep -v NAME | wc -l)
TOTALNOTREADYNODE=$(oc get nodes | grep -v NAME | grep -vw Ready | wc -l)
printf "\n-- Node state --\n"
printf "Total Nodes:        %5d\n" $TOTALNODES
printf "Non-Ready Nodes:    %5d\n" $TOTALNOTREADYNODE

if [ $(($TOTALNOTREADYNODE)) -gt 0 ]
then
  printf "\nResource to investigate:\n"
  oc get nodes | grep -v NAME | grep -vw Ready
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
if [ $(($TOTALCOFALSE)) -gt 0 ]
then
  printf "\nResource to investigate:\n"
  oc get co | grep -v NAME | grep -E -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)"
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
if [ $(($TOTALAPINOTREADY)) -gt 0 ]
then
  printf "\nResource to investigate:\n"
  oc get apiservices | grep -v NAME | grep -E -v "(.*)True(.*)"
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
if [ $(($TOTALAPINOTREADY)) -gt 0 ]
then
  printf "\nResource to investigate:\n"
  oc get mcp | grep -v NAME | grep -E -v "(.*)True(\s+)False(\s+)False(.*)"
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
if [ $(($TOTALCSVFAILED)) -gt 0 ]
then
  printf "\nResource to investigate:\n"
  oc get csv -A | grep -v NAMESPACE | grep -v Succeeded
  printf "Verify all operators states -- $CLRRED FAILED $CLRRESET\n"
else
  printf "Verify all operators states -- $CLRGRN PASSED $CLRRESET\n"
fi

