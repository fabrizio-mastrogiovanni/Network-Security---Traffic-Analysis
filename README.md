# Azure Network Security & Traffic Analysis

A hub and spoke network on Azure where every connection between workloads passes through a central firewall, is filtered twice, and is logged so it can be proven and investigated.

Built entirely with Terraform.

## The Business Problem

Companies run many workloads in the cloud: web apps, databases, internal tools. By default, cloud networks that are connected can talk to each other freely. That creates three risks:

1. **No control.** If one server is compromised, an attacker can move to other systems without being stopped.
2. **No visibility.** When something goes wrong, there is no record of who talked to whom, when, or why it was allowed.
3. **No proof.** Auditors and security teams ask "show me that this traffic is filtered." Without logs, the answer is a guess.

Regulated industries such as healthcare, finance, and insurance cannot operate with these gaps.

## The Solution

This project builds a network where:

* Workloads live in separate, isolated networks (spokes)
* All traffic between them is forced through one security checkpoint (the firewall in the hub)
* Each server has its own second layer of rules
* Every connection is recorded and searchable

In short: **traffic is routed, filtered twice, and logged.**

## Architecture

```
                    ┌─────────────────────────────┐
                    │      Hub VNet 10.0.0.0/16   │
                    │                             │
                    │   Azure Firewall (Basic)    │
                    │   + Firewall Policy         │
                    └──────┬───────────────┬──────┘
                           │   peering     │
              ┌────────────┘               └────────────┐
              ▼                                         ▼
┌───────────────────────────┐         ┌───────────────────────────┐
│  Spoke 1 VNet 10.1.0.0/16 │         │  Spoke 2 VNet 10.2.0.0/16 │
│                           │         │                           │
│  VM 1 (no public IP)      │         │  VM 2 (no public IP)      │
│  NSG + route table        │         │  NSG + route table        │
└───────────────────────────┘         └───────────────────────────┘

Traffic path:  VM 1 → Firewall → VM 2
All logs → Log Analytics workspace
```

## What Was Built

| Component | Role in plain words |
| :- | :- |
| **Hub VNet** | Central network that holds shared security services |
| **Spoke VNets** | Separate networks for each workload, isolated from each other |
| **VNet Peering** | Connects each spoke to the hub |
| **Azure Firewall (Basic)** | Central checkpoint that allows or blocks traffic between spokes |
| **Firewall Policy** | The rulebook the firewall follows, managed as code |
| **User Defined Routes (UDRs)** | Force spoke traffic through the firewall so it cannot be bypassed |
| **Network Security Groups (NSGs)** | A second set of rules on each server, for defense in depth |
| **VNet Flow Logs + Traffic Analytics** | Record network traffic and turn it into searchable data |
| **Network Watcher Packet Capture** | Records raw packets on a server, like a wiretap |
| **Log Analytics Workspace** | Central place where all logs are stored and queried |
| **Two Ubuntu VMs** | Test servers with no public IP, unreachable from the internet |

## Proof It Works

### 1. Traffic goes through the firewall

Every network device lowers a packet's TTL (Time To Live) by 1. A direct connection shows 64. One device in the middle shows 63.

```
64 bytes from 10.2.1.4: icmp_seq=1 ttl=63 time=14.9 ms
30 packets transmitted, 30 received, 0% packet loss
```

**TTL 63 proves exactly one hop: the firewall.**

### 2. The firewall is in control

The firewall rule was switched from Allow to Deny through Terraform. Pings stopped completely. Switching back restored them.

### 3. Packet level evidence

A packet capture opened in Wireshark shows outgoing requests with TTL 64 (captured before the firewall) and replies with TTL 63 (after passing through it).

### 4. Audit trail

Firewall logs record every connection with source, destination, action, and the exact rule that decided it.

```kql
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| where TimeGenerated > ago(2h)
| parse msg_s with Protocol " " * " from " SrcIP " to " DstIP ". Action: " Action "." *
| project TimeGenerated, Protocol, SrcIP, DstIP, Action
| order by TimeGenerated desc
```

Result:

```
ICMP Type=8 request from 10.1.1.4 to 10.2.1.4. Action: Allow.
Policy: fwpol-lab. Rule Collection Group: rcg-spoke-to-spoke. Rule: allow-icmp-tcp
```

### 5. Flow log queries

```kql
// Allowed flows
NTANetAnalytics
| where SubType == "FlowLog"
| where FlowStatus == "Allowed"
| project TimeGenerated, SrcIp, DestIp, DestPort, L4Protocol
| order by TimeGenerated desc

// Denied flows
NTANetAnalytics
| where SubType == "FlowLog"
| where FlowStatus == "Denied"
| summarize DeniedCount = count() by SrcIp, DestIp, DestPort
| order by DeniedCount desc
```

## Real Problems Solved

The original lab guide no longer matched how Azure works today. These are the issues found and fixed:

| Problem | Fix |
| :- | :- |
| Terraform syntax errors from multi value one line blocks | Rewrote blocks with one argument per line |
| Basic firewall requires a management connection | Added `AzureFirewallManagementSubnet` and a second public IP |
| Basic firewall does not support classic rules | Moved rules into a Firewall Policy and rule collection group |
| Azure now enforces MFA for all resource changes | Signed in with a session that completed multi factor authentication |
| Microsoft retired new NSG flow logs | Migrated to VNet flow logs and upgraded the AzureRM provider to v4 |
| VM size unavailable and quota limits | Selected a size with both regional capacity and subscription quota |
| SSH could not reach VMs with no public IP | Used Azure Run Command, which fits the no public IP design |
| Packet capture failed | Added the Network Watcher Agent VM extension in Terraform |
| Firewall changes made in the portal cause drift | Made all rule changes in Terraform only |

## Security Practices

* No hardcoded subscription IDs. Terraform reads them from environment variables.
* `terraform.tfvars` and state files are excluded through `.gitignore`.
* VMs have no public IP addresses.
* Two layers of filtering: firewall plus NSG.
* All infrastructure is defined as code and reproducible.

## How to Deploy

**Requirements:** Azure subscription, Azure CLI, Terraform 1.3 or newer.

1. Sign in to Azure with MFA:
   ```bash
   az login
   ```
2. Set your subscription as an environment variable:
   ```bash
   export ARM_SUBSCRIPTION_ID="<your-subscription-id>"
   ```
3. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values.
4. Deploy:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

Azure Firewall takes about 10 minutes to provision.

## Cost

Azure Firewall Basic is the main cost and is billed hourly. Run the lab in one session and destroy everything when finished.

```bash
terraform destroy
```

## Skills Demonstrated

* Hub and spoke network design
* Azure Firewall and Firewall Policy
* Custom routing with UDRs
* Defense in depth with NSGs
* Network monitoring with flow logs, Traffic Analytics, and packet capture
* Log analysis with KQL (Kusto Query Language)
* Infrastructure as Code with Terraform
* Troubleshooting outdated documentation against current Azure behavior
