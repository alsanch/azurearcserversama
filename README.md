# Azure Arc-enabled servers & Azure VMs - Hybrid Monitoring & Security
## Content
- [Overview](https://github.com/alsanch/azurearcservers#overview)
- [What resources are deployed?](https://github.com/alsanch/azurearcservers#what-resources-are-deployed)
- [Requirements](https://github.com/alsanch/azurearcservers#requirements)
- [Deployment steps](https://github.com/alsanch/azurearcservers#deployment-steps)
- [Screenshots](https://github.com/alsanch/azurearcservers#screenshots)
- [References](https://github.com/alsanch/azurearcservers#references)

## Overview
Azure Arc enables you to manage your entire environment, with a single pane of glass, by projecting your existing non-Azure, on-premises, or other-cloud resources into Azure Resource Manager. The first step is to onboard your on-premises servers into Azure Arc. Once your on-premises servers are onboarded, you can benefit from native Azure services like Azure Policy, Azure Monitor, Azure Automation and Microsoft Defender for Cloud. This project helps you on automating the deployment of these Azure Services. The same services can be deployed for Azure Virtual Machines as long as the *$deployForAzureVMs* parameter is *$true*

## What resources are deployed?
- **Log Analytics Workspace for Azure Monitor**
- **[Azure Monitor Agent (AMA)](https://learn.microsoft.com/azure/azure-monitor/agents/agents-overview) policies**
    - Configure Windows Arc-enabled machines to run Azure Monitor Agent
    - Configure Linux Arc-enabled machines to run Azure Monitor Agent
    - Configure Windows virtual machines to run Azure Monitor Agent using system-assigned managed identity
    - Configure Linux virtual machines to run Azure Monitor Agent with system-assigned managed identity
- **[Data Collection Rules (DCRs)](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview?tabs=portal) for:**
    - **Windows Events:** System, Application
    - **Windows Performance Counters:** Memory(*)\Pages/sec; Process(*)\% Processor Time; System(*)\Processor Queue Length
    - **Syslog:** auth; authpriv; daemon; kern
    - **Linux Performance Counters:** Logical Disk(*)\% Used Inodes; Memory(*)\% Used Swap Space
- **[VM insights](https://learn.microsoft.com/azure/azure-monitor/vm/vminsights-overview)**: by using the deployment script parameters, you can choose whether to enable just *InsightsMetrics* or *InsigthsMetrics* and *Map*.
- **[Change tracking and Inventory with AMA](https://learn.microsoft.com/azure/automation/change-tracking/overview-monitoring-agent?tabs=win-az-vm)**
- **[Azure Update Manager](https://learn.microsoft.com/azure/update-manager/overview?tabs=azure-vms)**
- **[SQL Best Practices Analyzer for Azure Arc-enabled servers](https://learn.microsoft.com/sql/sql-server/azure-arc/assess?view=sql-server-ver16)** enabled via Azure Policy
- **[Azure Monitor action group with an email action](https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups)**
- **[Azure Monitor alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview):** heartbeatMissed; logicalDiskFreeSpacePercent; memoryAvailableMBytes; memoryAvailablePercent; processorTimePercent; unexpectedSystemShutdown
- **[Azure Workbooks](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-overview):** AlertsConsole; OSPerformanceAndCapacity; WindowsEvents
- **[Azure Dashboard](https://learn.microsoft.com/azure/azure-portal/azure-portal-dashboards)** that provides a monitoring overview for your Azure Arc-enabled servers
- **Automation Account with:**
    - Runbook called AutoRemediateFrameworkPolicies.ps1, that triggers a remediation task for the policies assigned by this framework when there are pending resources to be remediated
      - Schedule to trigger the runbook once per day at 23:00:00 local time
      - Managed Identity with Resource Policy Contributor permissions at subscription/resource group level to trigger the remediation task

## Requirements
- **For Azure VMs, it is needed to have the Azure Monitor Agent (AMA) pre-installed.** You could deploy it at scale by using a user-assigned managed identity and these two Azure Policies:
    - Assign Built-In User-Assigned Managed Identity to Virtual Machines
    - Configure Windows virtual machines to run Azure Monitor Agent with user-assigned managed identity-based authentication
- **Tested in Powershell 7.4.0 and Azure Az 7.0.0 PowerShell module**
- **Azure Permissions:** Owner
    - Role required to assign the Resource Policy Contributor role to the Automation Account managed identity
- **Azure AD Permissions:** User

## Deployment steps
1. **Provide the required parameters in the Parameters.csv file:**
    - **Subscription:** name of your Azure Subscription
    - **ResourceGroup:** name of an existing or new resource group where the framework is deployed
    - **NamingPrefix:** three letters lowercase prefix used in the name of the deployed resources
    - **Location:** Azure Region where the framework is deployed
    - **Email:** email account used in the Action Group for the Azure Monitor alerts
    - **OptionalEmail:** optional email account used in the Action Group for the Azure Monitor alerts. Leave it as "" if this paramater is not needed.
    - **OptionalWebhook:** optional webhook URI used in the Action Group for the Azure Monitor alerts. Leave it as "" if this paramater is not needed.
    - **Scope:** scope at which the Azure Policies and the Automation Account managed identity permissions are assigned. Allowed values: "subscription", "resourcegroup"
2. Open PowerShell and **change your working directory** to the project directory
3. Run **Login-AzAccount**
4. Run **DeployAzureArcServices.ps1**

**Note**: you can enable/disable what's deployed in this framework by using the deployment variables within DeployAzureArcServices.ps1.


## Screenshots
![image](https://user-images.githubusercontent.com/96136892/149989258-91061aae-c1f1-4624-9f16-c6ac5d37b43d.png)

![image](https://user-images.githubusercontent.com/96136892/149988907-35e7a699-99d2-4fb4-b702-4e74dab1f227.png)

![image](https://user-images.githubusercontent.com/96136892/149988605-fba9f597-fb00-4908-be07-85851483b7f6.png)

![image](https://user-images.githubusercontent.com/96136892/149989430-6f7f318e-d7cc-4e12-ba95-1f74fbba157b.png)

![image](https://user-images.githubusercontent.com/96136892/149989168-526f84cb-fb3a-4c64-a3c3-87ef356f4545.png)

## References
- **Azure Arc-enabled servers:** https://docs.microsoft.com/en-us/azure/azure-arc/servers/
- **Azure Arc Jumpstart:** https://azurearcjumpstart.io/
