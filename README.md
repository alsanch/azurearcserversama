# Azure Arc-enabled servers & Azure VMs - Hybrid Monitoring & Security
## Content
- [Overview](https://github.com/alsanch/azurearcservers#overview)
- [What resources are deployed?](https://github.com/alsanch/azurearcservers#what-resources-are-deployed)
- [Requirements](https://github.com/alsanch/azurearcservers#requirements)
- [Deployment steps](https://github.com/alsanch/azurearcservers#deployment-steps)
- [Limitations](https://github.com/alsanch/azurearcservers#limitations)
- [Screenshots](https://github.com/alsanch/azurearcservers#screenshots)
- [References](https://github.com/alsanch/azurearcservers#references)

## Overview
Azure Arc enables you to manage your entire environment, with a single pane of glass, by projecting your existing non-Azure, on-premises, or other-cloud resources into Azure Resource Manager. The first step is to onboard your on-premises servers into Azure Arc. Once your on-premises servers are onboarded, you can benefit from native Azure services like Azure Policy, Azure Monitor, Azure Automation and Microsoft Defender for Cloud. This project helps you on automating the deployment of these Azure Services. The same services can be deployed for Azure Virtual Machines as long as the *$deployForAzureVMs* parameter is *$true*

**Note:** the Azure Services deployed in this project could also be used for Azure VMs as long as they are connected to the Log Analytics Workspace for Azure Monitor. 

## What resources are deployed?
- **Log Analytics Workspace for Azure Monitor**
- **Azure Monitor Agent (AMA) Policies**
    - Configure Windows Arc-enabled machines to run Azure Monitor Agent
    - Configure Linux Arc-enabled machines to run Azure Monitor Agent
    - Configure Windows virtual machines to run Azure Monitor Agent using system-assigned managed identity
    - Configure Linux virtual machines to run Azure Monitor Agent with system-assigned managed identity
- **Data Collection Rules (DCRs) for:**
    - **Windows Events:** System, Application
    - **Windows Performance Counters:** Memory(*)\Pages/sec; Process(*)\% Processor Time; System(*)\Processor Queue Length
    - **Syslog:** auth; authpriv; daemon; kern
    - **Linux Performance Counters:** Logical Disk(*)\% Used Inodes; Memory(*)\% Used Swap Space
- **VM insights**: by using the deployment script parameters, you can choose whether to enable just *InsightsMetrics* or *InsigthsMetrics* and *Map*.
- **Change tracking and Inventory with AMA**
- **Azure Update Manager**
- **SQL Best Practices Analyzer for Azure Arc-enabled servers** enabled via Azure Policy
- **Azure Monitor action group with an email action**
- **Azure Monitor alerts:** heartbeatMissed; logicalDiskFreeSpacePercent; memoryAvailableMBytes; memoryAvailablePercent; processorTimePercent; unexpectedSystemShutdown
- **Azure Workbooks:** AlertsConsole; OSPerformanceAndCapacity; WindowsEvents
- **Azure Dashboard that provides a monitoring overview for your Azure Arc-enabled servers**

## Requirements
- **Tested in Powershell 7.4.0 and Azure Az 7.0.0 PowerShell module**
- **Azure Permissions:** Under construction
- **Azure AD Permissions:** User

## Deployment steps
1. **Provide the required parameters in the Parameters.csv file:**
    - **Subscription:** name of your Azure Subscription
    - **ResourceGroup:** name of an existing or new resource group where the framework is deployed
    - **NamingPrefix:** three letters lowercase prefix used in the name of the deployed resources
    - **Location:** Azure Region where the framework is deployed
    - **Email:** email account used in the Action Group for alerts and in the Microsoft Defender for Cloud notification settings
    - **Scope:** scope at which the Azure Policies and the Automation Account managed identity permissions are assigned. Allowed values: "subscription", "resourcegroup"
2. Open PowerShell and **change your working directory** to the project directory
3. Run **Login-AzAccount**
4. Run **DeployAzureArcServices.ps1**

**Note**: you can enable/disable what's deployed in this framework by using the deployment variables within DeployAzureArcServices.ps1.


## Screenshots
![image](https://user-images.githubusercontent.com/96136892/149989258-91061aae-c1f1-4624-9f16-c6ac5d37b43d.png)

![image](https://user-images.githubusercontent.com/96136892/149988755-5070e7ff-e706-409c-b2a2-1934268c5217.png)

![image](https://user-images.githubusercontent.com/96136892/149988907-35e7a699-99d2-4fb4-b702-4e74dab1f227.png)

![image](https://user-images.githubusercontent.com/96136892/149988605-fba9f597-fb00-4908-be07-85851483b7f6.png)

![image](https://user-images.githubusercontent.com/96136892/149989430-6f7f318e-d7cc-4e12-ba95-1f74fbba157b.png)

![image](https://user-images.githubusercontent.com/96136892/149989168-526f84cb-fb3a-4c64-a3c3-87ef356f4545.png)

## References
- **Azure Arc-enabled servers:** https://docs.microsoft.com/en-us/azure/azure-arc/servers/
- **Azure Arc Jumpstart:** https://azurearcjumpstart.io/
- **Jumpstart ArcBox:** https://azurearcjumpstart.io/azure_jumpstart_arcbox/
