# Virt8ra Demo Video Scripts

Three video scripts for the IPCEI-CIS deliverable. No audio needed. All actions are screen-recorded with on-screen text overlays or subtitles.

---

## Video 1: Federation and Multi-tenancy

**Title:** "Geopatriation by design"

### Goal

Demonstrate the first Worldwide Virtual Hyperscaler Prototype based on cloud availability zones federation across different EU cloud service providers using Virt8ra.

### Intro

We demonstrate how Virt8ra provides a "single pane of glass" for nine worldwide federated availability zones running on different EU Cloud Service Providers. Our nine federated Virt8ra clouds are deployed across five Virt8ra OnDemand Certified providers: Arsys, IONOS, OVH Cloud (spillover), Scaleway (spillover), and Stackscale (spillover).

Covering Spain, France, Germany, Poland, UK, Australia and Canada across different time zones.

### Goal and environment

Our goal is to showcase centralized orchestration across these distinct providers.

The Virt8ra.Cloud installation on Stackscale acts as the Master Node. The other eight availability zones are configured as Slave Zones.

| Zone | Provider | Country | Role |
|------|----------|---------|------|
| Spain0 (OpenNebula) | Stackscale | Spain | MASTER |
| Spain1 | Arsys | Spain | Slave |
| France0 | Scaleway | France | Slave |
| Germany0 | IONOS | Germany | Slave |
| Germany1 | Arsys | Germany | Slave |
| Poland0 | Scaleway | Poland | Slave |
| UK0 | OVH Cloud | United Kingdom | Slave |
| Canada0 | OVH Cloud | Canada | Slave |
| Australia0 | OVH Cloud | Australia | Slave |

The Virt8ra frontends' control traffic integration uses a hybrid connectivity model with secure segmentation of control plane and service plane.

Why not include the US? Contractual restrictions for EU CSPs operating in the US create misalignment with current EU compliance like the GDPR and the EU Data Act.

### Steps

#### Step 1: Infrastructure Inspection

**Show the list of zones**

- Open browser and navigate to `fed.virt8ra.cloud`
- Log in as `oneadmin` (Virt8ra Cloud Administrator)
- Click Infrastructure > Zones
- Scroll slowly through all 9 zones so names and providers are readable

As mentioned, we have nine Virt8ra availability zones: Spain0 (Stackscale, Madrid) is acting as the master node, while the other eight are configured as slaves.

Zones: Spain0 (Stackscale, MASTER), Spain1 (Arsys), France0 (Scaleway), Germany0 (IONOS), Germany1 (Arsys), Poland0 (Scaleway), UK0 (OVH Cloud), Canada0 (OVH Cloud), Australia0 (OVH Cloud).

**Show available hypervisors**

- Click Infrastructure > Hosts
- In the zone selector, switch to France0

We are currently logged into the master frontend. From here, we can inspect the infrastructure and see which hosts we have available for each deployment. Looking at the France0 zone, we can see that the hypervisor is an AMD EPYC 8124P 16-Core with 128 GB DDR5 RAM, NVMe storage, and no GPU.

- Click on the host to show CPU cores, 128 GB RAM, and that there is NO GPU

- Switch zone view to Germany0

Now, we change the view to the Germany0 zone. You can see two instances acting as hypervisors: both AMD Ryzen 9 PRO 3900 12-Core with 128 GB RAM. One host is in the default cluster and another in the EuroDesk cluster, illustrating multi-tenant resource isolation.

- Switch zone view to Spain0 (Master)

We check the master zone: a single AMD EPYC 4464P 12-Core with 128 GB RAM.

- Switch zone view to Canada0

Finally, we check Canada, where we have a single AMD EPYC 4345P 8-Core hypervisor.

#### Step 2: Marketplace

- Click Storage > Marketplace (or the Marketplace section)

We visualize the Virt8ra marketplace and the available appliances. This is a federated marketplace: appliances published here are visible and deployable across all nine zones. It provides visibility to partners' application integrations.

- Show the Virt8ra Public Marketplace with partner appliances (Nextcloud, Lithops, srsRAN, UERANSIM, Phoenix RTOS, RabbitMQ, NixOS, etc.)
- Scroll through the appliance list to show the catalog breadth (13 partner appliances + 100+ OpenNebula community appliances)

#### Step 3: Non-EU Zone Inspection (Canada0)

- In the zone selector, switch to Canada0

- Click the Network tab

We inspect the network configuration for this zone: the eurocopilot-net network is visible on the virbr0 bridge, showing the secure segmentation between control plane and service plane.

- Click the Instances > VMs tab

We can see the instances currently running in this zone. A Virtual Router VM maintains the cross-site overlay network connectivity.

#### Step 4: Multi-tenancy

We return to the Master Zone to visualize multi-tenancy. The Virt8ra platform serves two independent customers, each with their own isolated Virtual Data Center.

- Switch zone selector back to Spain0 (Master)
- Navigate to the Groups / VDC section

**a) Customer 1: EuroDesk**

- Click on the EuroDesk VDC
- Show the VDC configuration: allocated zones (Germany0, cluster "EuroDesk" only)
- Show resource quotas

EuroDesk is a tenant providing an EU Office365 alternative using Nextcloud. Their VDC is restricted to a specific EU cluster in Germany0, enforcing sovereignty by design. They have dedicated resources on isolated hosts and cannot access non-EU zones or EuroCopilot resources.

**b) Customer 2: EuroCopilot**

- Click on the EuroCopilot VDC
- Show the VDC configuration: allocated zones (ALL clusters in ALL 9 zones)
- Show resource quotas
- Note the Load Balancer endpoint in France0

EuroCopilot is a tenant providing a European alternative to Microsoft Copilot using an open-source AI coding platform. Their VDC spans all zones with CPU resources, and they have a load-balanced inference endpoint in France0 (Scaleway, Paris).

### ACK

This work has been made possible in the scope of the IPCEI-CIS project.

---

## Video 2: Co-pilot Service Deployment and Operations

**Title:** "EU Microsoft Copilot Alternative"

### Goal

Demonstrate the deployment and operation of a sovereign AI coding platform on the first Worldwide Virtual Hyperscaler Prototype, using Virt8ra federated infrastructure across different EU cloud service providers.

### Intro

Same as Video 1 intro (nine federated zones, five providers).

### Goal and environment

Our goal is to showcase the co-pilot service: a distributed AI coding assistant built on marketplace appliances deployed across the federation, running entirely on CPU with no GPU dependency.

Customer 2: EuroCopilot. Application Stack: Devstral Small 2 (24B) via llama.cpp + LiteLLM Load Balancer. Goal: EU Copilot alternative. Resources: All Zones VDC (CPU). Balancer Endpoint: France0.

We introduce Devstral, Mistral's agentic LLM for software engineering tasks. Devstral is built under a collaboration between Mistral AI and All Hands AI, and outperforms all open-source models on SWE-Bench Verified by a large margin. Mistral released Devstral under the Apache 2.0 license.

### Steps

#### Step 1: Login as EuroCopilot

- Open browser and navigate to `fed.virt8ra.cloud`
- Enter credentials: `eurocopilot` user
- Click Login

We log in as Customer 2, EuroCopilot. This is a tenant whose goal is to provide an EU alternative to Microsoft Copilot. The dashboard loads, showing only the resources allocated to this tenant: All Zones VDC with CPU resources.

#### Step 2: Overview of Zones

- Show the zone selector dropdown
- Scroll through the available zones

Unlike EuroDesk which is restricted to a single EU cluster, EuroCopilot has access to all nine availability zones. This enables distributed inference across the entire federation.

#### Step 3: Navigate to Key Zones

**France0 (Load Balancer)**

- Switch zone to France0
- Click Instances > VMs
- Show running VMs: EuroCopilot LB (VM 95, 8 vCPU, 32 GB) + Virtual Router

In France0 (Scaleway, Paris), we have the central component: the EuroCopilot LB which runs the LiteLLM load balancer as the single API endpoint, plus a local llama-server inference backend.

**Poland0 (Inference Backend)**

- Switch zone to Poland0
- Show running VMs: EuroCopilot (VM 43, 8 vCPU, 32 GB) + Virtual Router

In Poland0 (Scaleway, Warsaw), we have a dedicated inference backend running Devstral Small 2 on CPU. This backend auto-registered with the France0 load balancer on boot.

**Spain0 (On-premises Master)**

- Switch zone to Spain0
- Show running VMs: Virtual Router

Spain0 (Stackscale, Madrid) is the federation master. It currently runs the overlay network router for cross-site connectivity.

- Click on the EuroCopilot LB VM in France0 to show details: zone, host (AMD EPYC 8124P), IP (192.168.101.100), vCPU, RAM, CPU model host-passthrough

#### Step 4: LLM Balancer Service GUI

- Open a new browser tab
- Navigate to `https://<FRANCE0_LB_IP>:8443/ui`
- Accept self-signed certificate if prompted
- Login with admin credentials

We navigate to the LiteLLM load balancer service GUI. This is the central component that aggregates all inference backends across zones into a single OpenAI-compatible API endpoint.

**a) Show Deployed Models and Health**

- Click on the Models section in LiteLLM UI
- Show the list of registered backends:
  - `devstral-small-2` (local, France0 at 127.0.0.1:8444)
  - `devstral-small-2` (Poland0 at 192.168.102.100:8443)
- Show health status indicators

Here we can see the deployed inference backends and their health status. Each backend corresponds to a llama-server instance in a different Virt8ra zone. The load balancer uses least-busy routing to distribute requests across them.

**b) Show Deployed Model**

- Show the model name: Devstral Small 2

The deployed model is Devstral Small 2, a 24 billion parameter coding model by Mistral AI, quantized to Q4_K_M format (~14 GB), running entirely on CPU with no GPU dependency.

**c) Test Inference Through Balancer Playground**

- Click on the Playground or Test section in LiteLLM UI
- In the prompt field, type: "Write a quick sort algorithm in C++"
- Click Send / Submit
- Wait for the response to stream in
- Show the generated C++ quick sort code in the response panel

The request is routed through LiteLLM to one of the available backends using least-busy routing. The model generates working C++ code, proving the distributed inference service is functional end-to-end.

*Note: If inference is slow (~5-8 min on 8 CPU threads), this section can be sped up in post-production.*

#### Step 5: Return to OpenNebula

- Switch back to the Sunstone browser tab

We return to OpenNebula. Now we demonstrate automated deployment with auto-registration.

#### Step 6: Deploy Additional Inference Service to Canada0

- In Sunstone, switch zone to Canada0
- Navigate to Templates > VMs
- Show the EuroCopilot template (pre-configured)
- Click Instantiate on the EuroCopilot template
- Verify the context variables:
  - `ONEAPP_COPILOT_AI_MODEL` = Devstral Small 2
  - `ONEAPP_COPILOT_REGISTER_URL` = https://192.168.101.100:8443 (France LB)
  - `ONEAPP_COPILOT_REGISTER_SITE_NAME` = canada0
  - `CPU_MODEL` = host-passthrough
- Click Instantiate / Create
- Show the VM going from PENDING to RUNNING

We deploy an additional inference service to Canada0. This is a one-click deployment from a pre-configured template. The key is what happens next: when this backend comes online, it automatically registers itself with the LiteLLM load balancer in France0 without any manual configuration.

#### Step 7: Return to LLM Balancer - Check Auto-registration

- Switch to the LiteLLM GUI browser tab
- Click Refresh on the Models page
- Show the new Canada0 backend appearing in the list:
  - `devstral-small-2` (Canada0 at 192.168.105.100:8443)
- Highlight: healthy status, appeared automatically

And there it is: the new Canada0 backend has been added automatically to the pool. No manual configuration was needed. The common service endpoint remains the same. This is how the platform scales: deploy more appliances from the template, and they auto-register with the load balancer.

*Note: Auto-registration takes ~2-3 minutes while the model loads and llama-server starts. The VM needs to complete its bootstrap before registering. Speed up this wait in post-production if needed.*

#### Step 8: Developer Workflow Demo

- Open a new browser tab
- Open a terminal or coding client (aider / OpenCode)
- Configure it to point to the LiteLLM endpoint: `https://<FRANCE0_LB_IP>:8443/v1`
- Show a coding prompt being sent and a response streaming back
- Demonstrate a real coding task (e.g., refactoring Python code, writing a function)

We illustrate a real developer workflow: a coding assistant powered by the distributed EuroCopilot service. The developer connects to a single endpoint; the load balancer routes requests across all available backends transparently.

*Speed up this section 2-4x in post-production if inference is slow.*

#### Step 9: Final Shot

- Switch back to the Sunstone browser tab
- Navigate to Instances > VMs in France0
- Show all running VMs: EuroCopilot LB + Virtual Router
- Switch to Poland0: show backend + VR
- Switch to Canada0: show newly deployed backend + VR
- Pause for 5 seconds on the final view

All the pieces of the sovereign AI coding platform are visible: inference backends across multiple zones, the LiteLLM load balancer, and the overlay network. One marketplace appliance template, distributed across the European Virtual Hyperscaler. 100% open-source, 100% CPU, 100% sovereign infrastructure.

### ACK

This work has been made possible in the scope of the IPCEI-CIS project.

---

## Video 3: Nextcloud Deployment

**Title:** "Office365 EU Alternative"

### Goal

Demonstrate the deployment of an EU Office365 alternative on the first Worldwide Virtual Hyperscaler Prototype based on cloud availability zones federation across different EU cloud service providers using Virt8ra.

### Intro

Same as Video 1 intro (nine federated zones, five providers).

### Goal and environment

Our goal is to showcase deployment capabilities across these distinct providers using a practical use case: Nextcloud as a sovereign Office365 alternative for European SMEs.

Customer 1: EuroDesk. Application Stack [Virt8ra Marketplace]: All-in-one Nextcloud for SMEs. Goal: EU Office365 alternative. Resources: EU Zones VDC (CPU).

### Steps

#### Step 1: Login as EuroDesk

- Open browser and navigate to `fed.virt8ra.cloud`
- Enter credentials: `eurodesk` user
- Click Login
- Toggle between admin and cloud user views if available

We log in as Customer 1, EuroDesk. This tenant's goal is to provide an EU Office365 alternative for SMEs. We can see both admin and cloud user views, illustrating the self-service experience.

#### Step 2: Check Zones and Quotas

- Navigate to the zones view
- Show which zones EuroDesk has access to (EU zones)
- Show resource quotas allocated to this tenant

EuroDesk's VDC provides access to EU zones with CPU resources. The sovereignty constraint means this customer can deploy services within the EU.

#### Step 3: Zone Inspection (Germany0)

- Switch zone selector to Germany0
- Navigate to Marketplace: show appliance availability (Nextcloud All-in-One visible in catalog)
- Navigate to Instances > VMs
- Show the currently running Nextcloud instance ("nextcloud Germany", VM 9) alongside zone services (Prometheus monitoring, Zabbix, Ansible)

We navigate to Germany0 (IONOS). We check marketplace availability and see a Nextcloud instance already running alongside zone monitoring services (Prometheus, Zabbix) and automation (Ansible), demonstrating a production-ready environment.

#### Steps 4-6: Deploy Nextcloud to Multiple Zones

**Deploy to Germany0 (EU)**

- Switch zone selector to Germany0
- Navigate to Marketplace
- Click on the "Nextcloud All-in-One" appliance
- Click Instantiate / Import from marketplace
- Show the available hosts in the German zone (two AMD Ryzen 9 PRO 3900 12-Core)
- Name the VM: "All-in-one Nextcloud in EU"
- Use default configuration
- Click Instantiate
- Wait for the scheduler to place the VM

We verify that these hosts belong to the German zone and instantiate a new virtual machine, naming it "All-in-one Nextcloud in EU". We use the default configuration and wait for the scheduler to place the VM. It is now up and running.

**Deploy to UK0 (non-EU)**

- Switch zone selector to UK0
- Navigate to Marketplace > Nextcloud appliance
- Click Instantiate
- Name: "All-in-one Nextcloud Service out of EU"
- Click Instantiate
- Wait until the virtual machine becomes available

Continuing to the UK, we instantiate "All-in-one Nextcloud Service out of EU." We wait until the virtual machine becomes available. And there it is, running.

**Deploy to Spain0 (on-premises master)**

- Switch zone selector to Spain0 (Stackscale/Madrid)
- Navigate to Marketplace > Nextcloud appliance
- Click Instantiate
- Name: "All-in-one Nextcloud Service in EU (on premises)"
- Click Instantiate
- Wait for the infrastructure to make it available

Finally, we instantiate on our Master Node, Spain on-premises. We name this "All-in-one Nextcloud Service in EU (on premises)" and wait for it to become available.

Three deployments: Germany (IONOS, EU), UK (OVH, non-EU), Spain (Stackscale, on-premises EU). Three providers, three jurisdictions, one marketplace.

#### Step 7: Show All Three VMs Running

- Navigate to Instances > VMs
- Show all three Nextcloud VMs in the list
- Click on Germany VM: show zone, host (IONOS AMD Ryzen 9 PRO 3900), IP
- Click on UK VM: show zone, host (OVH AMD EPYC 4344P), IP
- Click on Spain VM: show zone, host (Stackscale AMD EPYC 4464P), IP

Three instances of the same appliance running across three zones on three different providers. Same user experience, different geography.

#### Step 8: Access Nextcloud Web UI

- Copy the IP/URL of one of the running Nextcloud VMs
- Open a new browser tab
- Navigate to the Nextcloud URL
- Show the Nextcloud dashboard: files, calendar, contacts, collaborative editing

The Nextcloud dashboard loads. A fully functional EU Office365 alternative, deployed in minutes from the marketplace, accessible from any zone.

### ACK

This work has been made possible in the scope of the IPCEI-CIS project.

---

## Deliverables

Upload all three videos to:
- Google Drive > Videos folder: https://drive.google.com/drive/folders/1h4FlQsIsQokcRSs4zTrci-BDbEtxxFER
- Whaller: https://my.whaller.com/sphere/7cc4wo/box/1219718

Mark Script + Recording complete in canvas F0AKEGPU9RD.

## Current Cluster State Reference

**Active EuroCopilot backends on LB (France0):**
- Local (France0): `127.0.0.1:8444` (llama-server on LB VM)
- Poland0: `192.168.102.100:8443`

**EuroCopilot templates available for deployment:**
- Spain0 (Master): Template #1 "EuroCopilot"
- France0: Template #27 "EuroCopilot"
- Canada0: Template #0 "EuroCopilot"
- Poland0: Template #10 "EuroCopilot"

**Hardware per zone:**

| Zone | CPU | Cores | RAM | Host Count |
|------|-----|-------|-----|------------|
| Spain0 | AMD EPYC 4464P | 12C | 128 GB | 1 |
| Spain1 | AMD Ryzen (split arch) | - | - | 1 |
| France0 | AMD EPYC 8124P | 16C | 128 GB | 1 |
| Germany0 | AMD Ryzen 9 PRO 3900 | 12C | 128 GB | 2 |
| Germany1 | AMD Ryzen (split arch) | - | - | 1 |
| Poland0 | AMD EPYC 8124P | 16C | 128 GB | 1 |
| UK0 | AMD EPYC 4344P | 8C | 128 GB | 1 |
| Canada0 | AMD EPYC 4345P | 8C | 128 GB | 1 |
| Australia0 | AMD EPYC 4344P | 8C | 128 GB | 1 |

**LiteLLM UI:** `https://192.168.101.100:8443/ui` (admin / api_key)

**Sunstone:** `https://fed.virt8ra.cloud` (oneadmin / eurocopilot / eurodesk)
