# Azure CLI Extension List

**Source:** [learn.microsoft.com/en-us/cli/azure/azure-cli-extensions-list](https://learn.microsoft.com/en-us/cli/azure/azure-cli-extensions-list?view=azure-cli-latest)  
**Learn page date:** 2026-08-18  
**Recorded:** 2026-08-19 (UTC+5:30)  
**CLI version on this machine:** 2.89.0

---

## Installed on this machine

| Extension | Version | Preview |
|---|---|---|
| `account` | 0.2.5 | No |
| `application-insights` | 2.0.0b1 | Yes |
| `azure-devops` | 1.0.6 | No |
| `azure-firewall` | 2.2.1 | No |
| `bastion` | 1.4.3 | No |
| `cdn` | 1.0.0b2 | Yes |
| `costmanagement` | 1.0.0 | No |
| `dataprotection` | 1.11.3 | No |
| `dns-resolver` | 1.2.0 | No |
| `front-door` | 2.3.0 | No |
| `log-analytics` | 1.0.0b1 | Yes |
| `microsoft-fabric` | 1.0.0b1 | Yes |
| `quota` | 1.0.0 | No |
| `reservation` | 0.3.1 | No |
| `resource-graph` | 2.1.1 | No |
| `ssh` | 2.0.9 | No |
| `subscription` | 1.0.0b2 | Yes |
| `terraform` | 1.0.0b1 | Yes |
| `virtual-wan` | 1.0.1 | No |

To refresh this list at any time:

```powershell
az extension list --query "[].{Name:name,Version:version,Preview:preview}" -o table
```

To install an extension:

```powershell
az extension add --name <extension-name> --upgrade --yes
# For preview-only extensions add: --allow-preview true
```

---

## Full catalog from Microsoft Learn (2026-08-18)

### GA (Generally Available)

| Extension | Min CLI | Description | Latest Version |
|---|---|---|---|
| `account` | 2.38.0 | Subscription client | 0.2.5 |
| `acrtransfer` | 2.0.67 | ACR transfer | 2.0.0 |
| `ad` | 2.15.0 | Domain Services | 0.1.0 |
| `aem` | 2.19.1 | Azure Enhanced Monitoring for SAP | 1.0.2 |
| `aksarc` | 2.77.0 | Hybrid Container Service / AKS hybrid | 1.5.116 |
| `amg` | 2.75.0 | Azure Managed Grafana | 3.0.0 |
| `amlfs` | 2.75.0 | Azure Managed Lustre | 1.3.0 |
| `arcappliance` | 2.73.0 | Arc appliance | 1.8.0 |
| `arcdata` | 2.3.1 | Arc-enabled data services | 1.5.31 |
| `authV2` | 2.23.0 | Auth v2 | 1.0.1 |
| `azure-cli-ml` | 2.3.1 | Azure ML command module (v1) | 1.41.0 |
| `azure-devops` | 2.30.0 | Azure DevOps | 1.0.6 |
| `azure-firewall` | 2.75.0 | Azure Firewall | 2.2.1 |
| `azure-iot-ops` | 2.70.0 | Azure IoT Operations | 2.8.0 |
| `azure-sphere` | 2.75.0 | Azure Sphere | 1.0.4 |
| `bastion` | 2.62.0 | Azure Bastion | 1.4.3 |
| `cloud-service` | 2.55.0 | Cloud Services (classic compute) | 1.0.1 |
| `communication` | 2.67.0 | Azure Communication Services | 1.14.0 |
| `computelimit` | 2.75.0 | Compute limits | 1.0.0 |
| `confcom` | 2.26.2 | Confidential container security policy generator | 2.1.0 |
| `confidentialledger` | 2.67.0 | Confidential Ledger | 2.0.0 |
| `confluent` | 2.75.0 | Confluent | 1.2.0 |
| `connectedk8s` | 2.70.0 | Arc-enabled Kubernetes | 1.11.1 |
| `connectedvmware` | 2.0.67 | Arc VMware | 1.2.1 |
| `cosmosdb-preview` | 2.17.1 | Cosmos DB extra commands | 1.7.0 |
| `costmanagement` | 2.55.0 | Cost Management | 1.0.0 |
| `customlocation` | 2.70.0 | Custom locations | 0.1.4 |
| `databox` | 2.70.0 | Data Box | 1.2.0 |
| `databricks` | 2.57.0 | Azure Databricks | 1.3.2 |
| `datafactory` | 2.15.0 | Data Factory | 1.0.4 |
| `datamigration` | 2.75.0 | Database Migration | 1.0.0 |
| `dataprotection` | 2.75.0 | Data Protection / Azure Backup | 1.11.3 |
| `desktopvirtualization` | 2.55.0 | AVD / Desktop Virtualization | 1.0.0 |
| `dev-spaces` | 2.1.0 | Dev Spaces | 1.0.6 |
| `devcenter` | 2.75.0 | Dev Center / Dev Box | 8.0.0 |
| `discovery` | 2.75.0 | Microsoft Discovery | 1.0.2 |
| `dns-resolver` | 2.75.0 | DNS Private Resolver | 1.2.0 |
| `dynatrace` | 2.75.0 | Dynatrace | 2.0.0 |
| `elastic-san` | 2.75.0 | Elastic SAN | 1.3.2 |
| `express-route-cross-connection` | 2.61.0 | ExpressRoute cross-connection | 1.0.0 |
| `fileshare` | 2.75.0 | File share | 1.0.2 |
| `firmwareanalysis` | 2.75.0 | Firmware analysis | 2.0.1 |
| `fleet` | 2.61.0 | Azure Kubernetes Fleet | 1.11.0 |
| `fluid-relay` | 2.39.0 | Fluid Relay | 0.1.0 |
| `front-door` | 2.75.0 | Front Door (classic networking) | 2.3.0 |
| `healthbot` | 2.15.0 | Health Bot | 1.1.0 |
| `healthcareapis` | 2.66.0 | Health Data Services / Healthcare APIs | 1.0.1 |
| `hpc-cache` | 2.3.0 | HPC Cache / Storage Cache | 0.1.6 |
| `image-copy-extension` | 2.68.0 | Copy managed images between regions | 1.0.4 |
| `ip-group` | 2.50.0 | IP groups | 1.0.1 |
| `k8s-configuration` | 2.15.0 | Kubernetes configuration (GitOps) | 2.3.0 |
| `k8s-extension` | 2.51.0 | Cluster extensions | 1.8.0 |
| `k8s-runtime` | 2.70.0 | Kubernetes runtime | 2.0.1 |
| `kusto` | 2.15.0 | Azure Data Explorer (Kusto) | 0.5.0 |
| `load` | 2.66.0 | Azure Load Testing | 2.1.0 |
| `log-analytics-solution` | 2.50.0 | Log Analytics solutions | 1.0.1 |
| `logic` | 2.55.0 | Logic Apps | 1.1.0 |
| `managementpartner` | 2.61.0 | Management Partner | 1.0.0 |
| `mdp` | 2.57.0 | Managed DevOps Pools | 1.0.1 |
| `ml` | 2.15.0 | Azure Machine Learning CLI v2 | 2.44.1 |
| `monitor-control-service` | 2.61.0 | Monitor control service | 1.2.0 |
| `monitor-pipeline-group` | 2.75.0 | Monitor pipeline groups | 1.0.0 |
| `multicloud-connector` | 2.61.0 | Multicloud connector | 1.0.1 |
| `networkcloud` | 2.75.0 | Operator Nexus network cloud | 5.1.0 |
| `new-relic` | 2.61.0 | New Relic | 1.1.0 |
| `nginx` | 2.75.0 | NGINX on Azure | 2.0.0 |
| `nsp` | 2.75.0 | Network Security Perimeter | 1.1.0 |
| `oracle-database` | 2.75.0 | Oracle Database | 2.0.5 |
| `orbital` | 2.39.0 | Azure Orbital | 0.1.0 |
| `palo-alto-networks` | 2.75.0 | Palo Alto Networks | 1.1.2 |
| `peering` | 2.3.1 | Peering | 1.0.0 |
| `pscloud` | 2.75.0 | Pure Storage Cloud | 1.0.1 |
| `qumulo` | 2.75.0 | Qumulo | 3.0.0 |
| `quota` | 2.54.0 | Quota | 1.0.0 |
| `rdbms-connect` | 2.19.0 | Test MySQL/PostgreSQL connectivity | 1.0.7 |
| `redisenterprise` | 2.75.0 | Redis Enterprise | 1.4.0 |
| `reservation` | 2.50.0 | Reservations | 0.3.1 |
| `resource-graph` | 2.22.0 | Azure Resource Graph | 2.1.1 |
| `scvmm` | 2.15.0 | Arc SCVMM | 1.2.1 |
| `serviceconnector-passwordless` | 2.87.0 | Passwordless service connector | 3.3.7 |
| `spring` | 2.56.0 | Azure Spring Apps | 1.28.5 |
| `ssh` | 2.45.0 | SSH to VMs with RBAC / Entra OpenSSH certs | 2.0.9 |
| `stack-hci` | 2.54.0 | Azure Stack HCI | 1.1.0 |
| `stack-hci-vm` | 2.15.0 | Stack HCI VMs | 1.15.1 |
| `standbypool` | 2.75.0 | Standby pools | 2.1.0 |
| `storage-actions` | 2.75.0 | Storage Actions | 1.1.0 |
| `storage-discovery` | 2.75.0 | Storage Discovery | 1.0.0 |
| `storage-mover` | 2.75.0 | Storage Mover | 1.3.1 |
| `storagesync` | 2.55.0 | Azure File Sync | 1.0.1 |
| `stream-analytics` | 2.75.0 | Stream Analytics | 1.0.5 |
| `support` | 2.57.0 | Azure Support tickets | 2.0.1 |
| `timeseriesinsights` | 2.50.0 | Time Series Insights | 1.0.0b1 |
| `traffic-collector` | 2.40.0 | Traffic collector | 1.0.0 |
| `virtual-network-manager` | 2.75.0 | Virtual Network Manager | 3.0.2 |
| `virtual-wan` | 2.55.0 | Virtual WAN, hubs, VPN | 1.0.1 |
| `vm-repair` | 2.0.67 | VM auto-repair | 2.2.4 |
| `vmware` | 2.75.0 | Azure VMware Solution | 8.1.0 |
| `webpubsub` | 2.56.0 | Web PubSub | 1.7.2 |
| `workload-orchestration` | 2.67.0 | Workload orchestration | 5.2.1 |
| `workloads` | 2.61.0 | SAP / workloads | 1.1.0 |

### Preview

| Extension | Min CLI | Description | Latest Version |
|---|---|---|---|
| `acat` | 2.61.0 | App Compliance Automation Tool | 1.0.0b1 |
| `acrcssc` | 2.73.0 | ACR Container Secure Supply Chain | 1.0.0b7 |
| `acrquery` | 2.48.0 | ACR query | 1.0.1 |
| `ai-examples` | 2.2.0 | AI-powered help examples | 0.2.6 |
| `aimanager` | 2.61.0 | AI Manager for AKS GPU model deployments | 1.2.1b1 |
| `aks-agent` | 2.76.0 | Interactive AI debugging for AKS | 1.0.0b23 |
| `aks-preview` | 2.85.0 | Upcoming AKS features | 22.0.0b1 |
| `alb` | 2.67.0 | Application Load Balancer | 2.0.1 |
| `alertsmanagement` | 2.45.0 | Alerts Management | 1.0.0b2 |
| `alias` | 2.0.50.dev0 | Command aliases | 0.5.2 |
| `aosm` | 2.78.0 | Azure Operator Service Manager | 2.0.0b6 |
| `apic-extension` | 2.57.0 | API Center | 1.2.0b3 |
| `application-insights` | 2.71.0 | Application Insights manage/query | 2.0.0b1 |
| `appnet-preview` | 2.75.0 | AKS application network | 1.0.0b3 |
| `arcgateway` | 2.57.0 | Arc gateway | 1.0.0b1 |
| `arize-ai` | 2.75.0 | Arize AI | 1.0.0 |
| `artifact-signing` | 2.75.0 | Artifact signing | 1.0.0 |
| `attestation` | 2.55.0 | Attestation | 1.0.2 |
| `automanage` | 2.44.1 | Automanage | 0.1.2 |
| `automation` | 2.75.0 | Automation | 1.0.0b2 |
| `azure-changesafety` | 2.75.0 | Change safety | 1.0.0b2 |
| `azure-iot` | 2.70.0 | IoT Hub / IoT devices | 0.32.0b1 |
| `azurelargeinstance` | 2.57.0 | Azure Large Instance | 1.0.0b4 |
| `baremetal-infrastructure` | 2.57.0 | Bare-metal infrastructure | 3.0.0b2 |
| `billing-benefits` | 2.43.0 | Billing benefits | 0.1.0 |
| `blueprint` | 2.50.0 | Blueprints | 1.0.0b3 |
| `carbon` | 2.70.0 | Carbon optimization | 1.0.0b1 |
| `cdn` | 2.85.0 | CDN and Azure Front Door | 1.0.0b2 |
| `change-analysis` | 2.37.0 | Change analysis | 0.1.0 |
| `chaos` | 2.75.0 | Chaos Studio v2 | 1.0.0b1 |
| `cloudhsm` | 2.70.0 | Cloud HSM | 1.0.0b1 |
| `command-change` | 2.19.0 | Command change | 1.0.0b1 |
| `computeschedule` | 2.67.0 | Compute schedule | 1.0.0b1 |
| `connectedmachine` | 2.75.0 | Arc-enabled servers | 3.0.0b1 |
| `containerapp` | 2.79.0 | Container Apps extra commands | 1.3.0b4 |
| `data-transfer` | 2.0.24 | Data transfer | 1.0.0b2 |
| `datadog` | 2.75.0 | Datadog | 3.1.0b1 |
| `dell` | 2.75.0 | Dell.Storage filesystems | 1.0.0b1 |
| `dependency-map` | 2.70.0 | Dependency map | 1.0.0b1 |
| `deploy-to-azure` | 2.0.60 | Deploy via GitHub Actions | 0.2.0 |
| `dms-preview` | 2.27.0 | Database Migration Service extra scenarios | 0.15.0 |
| `dnc` | 2.51.0 | Delegated Network Controller | 0.2.1 |
| `documentdb` | 2.75.0 | DocumentDB | 1.0.0b2 |
| `durabletask` | 2.75.0 | Durable Task | 1.0.0b8 |
| `edge-action` | 2.75.0 | Front Door Edge Actions | 1.0.0b4 |
| `edgezones` | 2.57.0 | Edge zones | 1.0.0b1 |
| `elastic` | 2.75.0 | Elastic | 1.0.0b5 |
| `eventgrid` | 2.51.0 | Event Grid extra commands | 1.0.0b2 |
| `footprint` | 2.11.0 | Footprint monitoring | 1.0.1b1 |
| `functionapp` | 2.0.46 | Extra Azure Functions commands | 0.1.1 |
| `gallery-service-artifact` | 2.57.0 | Gallery service artifact | 1.0.0b1 |
| `graphservices` | 2.49.0 | Graph services | 1.0.0b1 |
| `hack` | 2.0.67 | Hack / demo helper | 0.4.3 |
| `health-models` | 2.75.0 | Azure Monitor health models | 1.0.0b2 |
| `horizondb` | 2.17.1 | HorizonDB | 1.0.0b7 |
| `image-gallery` | 2.3.0 | Image Gallery extra commands | 1.0.0b2 |
| `import-export` | 2.3.1 | Storage Import/Export | 1.0.0b1 |
| `informatica` | 2.70.0 | Informatica | 1.0.0b2 |
| `init` | 2.0.67 | Init | 0.1.0 |
| `interactive` | 2.0.62 | Interactive shell | 1.0.0b1 |
| `interconnect` | 2.75.0 | Interconnect | 1.0.0b2 |
| `internet-analyzer` | 2.0.67 | Internet Analyzer | 1.0.0b2 |
| `keyvault-preview` | 2.15.0 | Key Vault preview commands | 1.0.2 |
| `lambda-test` | 2.75.0 | LambdaTest | 1.0.0 |
| `log-analytics` | 2.61.0 | Log Analytics query | 1.0.0b1 |
| `maintenance` | 2.75.0 | Maintenance | 2.0.0b1 |
| `managedccfs` | 2.45.0 | Managed CCF | 0.2.0 |
| `managedcleanroom` | 2.75.0 | Managed clean room | 1.0.0b7 |
| `managednetworkfabric` | 2.75.0 | Operator Nexus network fabric | 10.0.0b1 |
| `mcc` | 2.70.0 | Microsoft Connected Cache | 1.0.0b3 |
| `mesh` | 2.67.0 | Service Fabric Mesh | 1.0.0b2 |
| `microsoft-fabric` | 2.61.0 | Microsoft Fabric | 1.0.0b1 |
| `migrate` | 2.75.0 | Azure Migrate | 3.0.0b5 |
| `mission` | 2.75.0 | Mission | 1.0.0b1 |
| `mixed-reality` | 2.49.0 | Mixed Reality | 1.0.0b1 |
| `mongo-db` | 2.75.0 | MongoDB | 1.1.0b1 |
| `napster` | 2.75.0 | Napster | 1.0.0b1 |
| `netappfiles-preview` | 2.61.0 | NetApp Files preview | 1.0.0b4 |
| `network-analytics` | 2.51.0 | Network analytics | 1.0.0b1 |
| `nexusidentity` | 2.61.0 | Nexus identity | 1.0.0b6 |
| `notification-hub` | 2.67.0 | Notification Hubs | 2.0.0b2 |
| `partnercenter` | 2.0.67 | Partner Center | 0.2.4 |
| `planetarycomputer` | 2.75.0 | Planetary Computer | 1.0.0b1 |
| `portal` | 2.67.0 | Azure portal dashboards | 1.0.0b2 |
| `powerbidedicated` | 2.56.0 | Power BI Dedicated | 1.0.0b1 |
| `prototype` | 2.50.0 | Rapid prototype generation | 0.2.1b7 |
| `providerhub` | 2.57.0 | Provider Hub | 1.0.0b2 |
| `purview` | 2.15.0 | Purview | 0.1.0 |
| `quantum` | 2.73.0 | Azure Quantum | 1.0.0b20 |
| `relationship` | 2.75.0 | Relationship | 1.0.0b1 |
| `resource-mover` | 2.50.0 | Resource Mover | 1.0.0b2 |
| `scheduled-query` | 2.54.0 | Scheduled query rules | 1.0.0b2 |
| `self-help` | 2.57.0 | Self-help diagnostics | 0.4.0 |
| `serial-console` | 2.15.0 | Serial Console | 1.0.0b4 |
| `servicegroup` | 2.67.0 | Service groups | 1.0.0b1 |
| `sftp` | 2.75.0 | Blob SFTP with SSH certificates | 1.0.0b3 |
| `site` | 2.75.0 | Site | 1.0.0b2 |
| `staticwebapp` | 2.39.0 | Static Web Apps extra commands | 1.0.1 |
| `storage-blob-preview` | 2.75.0 | Storage blob preview | 1.0.0b3 |
| `storage-preview` | 2.75.0 | Upcoming storage features | 1.0.0b8 |
| `subscription` | 2.61.0 | Subscription extra commands | 1.0.0b2 |
| `terraform` | 2.61.0 | Terraform | 1.0.0b1 |
| `trustedsigning` | 2.57.0 | Trusted Signing | 1.0.0b2 |
| `vi` | 2.38.0 | Video Indexer | 1.0.0b1 |
| `virtual-network-tap` | 2.61.0 | Virtual network tap (VTAP) | 1.0.0b2 |
| `vme` | 2.70.0 | VME | 1.0.0b5 |
| `webapp` | 2.23.0 | Extra App Service commands | 0.4.0 |
| `workload-orchestration-preview` | 2.67.0 | Workload orchestration preview | 0.1.0b2 |
| `zones` | 2.72.0 | Availability zones | 1.0.0b5 |

### Experimental

| Extension | Min CLI | Description | Latest Version |
|---|---|---|---|
| `cli-translator` | 2.13.0 | Translate ARM to Azure CLI | 0.3.0 |
| `custom-providers` | 2.3.1 | Custom providers | 0.2.1 |
| `datashare` | 2.15.0 | Data Share | 0.2.0 |
| `diskpool` | 2.15.0 | Disk / storage pool | 0.2.0 |
| `edgeorder` | 2.15.0 | Edge Order | 0.1.0 |
| `fzf` | 2.9.0 | Fuzzy finder helper | 1.0.2 |
| `guestconfig` | 2.3.1 | Guest Configuration | 0.1.1 |
| `hardware-security-modules` | 2.15.0 | Dedicated HSM | 0.2.0 |
| `next` | 2.20.0 | Next | 0.1.3 |
| `offazure` | 2.15.0 | Azure Migrate v2 / off-Azure | 0.1.0 |
| `scenario-guide` | 2.20.0 | Scenario guidance | 0.1.1 |
| `sentinel` | 2.37.0 | Microsoft Sentinel | 0.2.0 |
| `site-recovery` | 2.51.0 | Site Recovery | 1.0.0 |
