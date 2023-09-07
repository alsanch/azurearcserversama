# Deployment Variables to choose what to deploy
$deployLAW = $true
$deployDataCollectionPerfEvents = $true
$deployVMInsightsPerfAndMap = $true
$deployVMInsightsPerfOnly = $true
$deployChangeTrackingAndInventory = $true
$deployUpdateManager = $true
$deployActionGroup = $true
$deployAlerts = $true
$deployWorkbooks = $true
$deployDashboard = $true
$deploySQLBPA = $true

$deployDefenderForCloud = $false



# Global variables
$parametersFilePath = ".\Parameters.csv"
$parametersFileInput = $(Import-Csv $parametersFilePath)
$subscriptionName = $parametersFileInput.Subscription
$resourceGroup = $parametersFileInput.ResourceGroup
$namingPrefix = $parametersFileInput.NamingPrefix
$location = $parametersFileInput.Location
$MonitorWSName = $namingPrefix + "-la-monitor"
$SecurityWSName = $namingPrefix + "-la-security"
$ActionGroupName = $namingPrefix + "-ag-arc"
$ActionGroupShortName = $namingPrefix + "-agarc"

# Option to interrupt the deployment  
Write-Host -ForegroundColor Green "STARTING THE DEPLOYMENT"
Write-Host -ForegroundColor Red "NOTE: Press CTRL+C within 10 seconds to cancel the deployment"
Start-Sleep -Seconds 10 

# Login to Azure
if ($(Get-AzContext).Name -eq "Default") {
    Login-AzAccount  
}

# Switch Context to designated subscription if needed
if ((Get-AzContext).Subscription.Name -ne $subscriptionName) {
    Select-AzSubscription -SubscriptionName $subscriptionName | Out-Null
}

# Create the ResourceGroup if needed
Get-AzResourceGroup -Name $resourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue | Out-Null
if ($notPresent) {
    Write-Host "Creating resource group $resourceGroup"
    New-AzResourceGroup -Name $resourceGroup -Location $location | Out-Null
}

#region ### Deploy the Monitor Log Analytics workspace
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying the Monitor Log Analytics Workspace"
if ($deployLAW -eq $true) {
    $deploymentName = "deploy_monitor_loganalytics_workspace"
    $templateFile = ".\LogAnalyticsWorkspace\logAnalyticsWorkpsace.json"
        
    # Deploy the workspace
    Write-Host "Deploying log analytics workspace $MonitorWSName"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName -location $location | Out-Null
    
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy Data Collection Rules and Assign Azure Policies to associate DCRs
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Perf and Events Data Collection Rules"
if ($deployDataCollectionPerfEvents -eq $true) {       

    ## Deploy Data Collection Rules
    $templateBasePath = ".\DataCollection-PerfEvents\DCRs"

    # Get the DCRs ARM template files
    $DCRsCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })
        
    # Deploy all the DCRs
    foreach ($DCR in $DCRsCollection) {
        $DCRName = $($DCR.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($DCR.Name)"
        $deploymentName = $("deploy_DCR_$DCRName").ToLower()

        # Deploy this DCR
        Write-Host "Deploying DCR: $DCRName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
            -workspaceName $MonitorWSName -location $location | Out-Null
    }

    ## Assign Azure Policies to associate DCRs
    $templateBasePath = ".\Policies"
    $policiesScope = $parametersFileInput.Scope

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    ## Get the Data Collection Rules previously created
    $DCRs = Get-AzDataCollectionRule -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like 'DCR-AMA-*' }

    # Assign the policies
    foreach ($DCR in $DCRs) {
        if ($DCR.Name -like "*Windows*"){
            $azurePolicyName = "[MON] Configure Windows Arc Machine to be associated with " + $DCR.Name
            $templateFile = "$templateBasePath\Configure Windows Arc Machine to be associated with a DCR.json"
        }
        elseif($DCR.Name -like "*Linux*"){
            $azurePolicyName = "[MON] Configure Linux Arc Machine to be associated with " + $DCR.Name
            $templateFile = "$templateBasePath\Configure Linux Arc Machine to be associated with a DCR.json"
        }
        
        $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '').Replace('[MON]', '')
        $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyName"
        if ($policiesScope -eq "subscription") {
            New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
                -policyAssignmentName $azurePolicyName -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyName `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
    }
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy VMInsights
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying VMInsights DCRs and related policies"
if ($deployVMInsightsPerfAndMap -eq $true -or $deployVMInsightsPerfOnly -eq $true) {

    # Control: only one variable can be true
    if ($deployVMInsightsPerfAndMap -eq $true -and $deployVMInsightsPerfOnly -eq $true){
        $deployVMInsightsPerfOnly = $false
    }

    ## PART 1. Dependency Agent Policies
    $templateBasePath = ".\DataCollection-VMInsights\Policies"
    $policiesScope = $parametersFileInput.Scope

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    # Windows
    $depAgentPolicyNameWindows = "[MON] Configure Dependency agent on Azure Arc enabled Windows servers"
    $templateFileDepAgentWindows = "$templateBasePath\Configure Dependency agent on Azure Arc enabled Windows servers.json"
    $deploymentNameDepAgentWindows = "assign_policy_$($depAgentPolicyNameWindows)".Replace(' ', '').Replace('[MON]', '')
    $deploymentNameDepAgentWindows = $deploymentNameDepAgentWindows.substring(0, [System.Math]::Min(63, $deploymentNameDepAgentWindows.Length))

    # Linux
    $depAgentPolicyNameLinux = "[MON] Configure Dependency agent on Azure Arc enabled Linux servers"
    $templateFileDepAgentLinux = "$templateBasePath\Configure Dependency agent on Azure Arc enabled Linux servers.json"
    $deploymentNameDepAgentLinux = "assign_policy_$($depAgentPolicyNameLinux)".Replace(' ', '').Replace('[MON]', '')
    $deploymentNameDepAgentLinux = $deploymentNameDepAgentLinux.substring(0, [System.Math]::Min(63, $deploymentNameDepAgentLinux.Length))

    # Assign the policy at resource group/subscription scope
    Write-Host "Assigning Azure Policy: $depAgentPolicyNameWindows"
    Write-Host "Assigning Azure Policy: $depAgentPolicyNameLinux"
    if ($policiesScope -eq "subscription") {
        # Windows
        New-AzDeployment -Name $deploymentNameDepAgentWindows -location $location -TemplateFile $templateFileDepAgentWindows `
            -policyAssignmentName $depAgentPolicyNameWindows -resourceGroupID $resourceGroupID | Out-Null
        # Linux
        New-AzDeployment -Name $deploymentNameDepAgentLinux -location $location -TemplateFile $templateFileDepAgentLinux `
            -policyAssignmentName $depAgentPolicyNameLinux -resourceGroupID $resourceGroupID | Out-Null
    }
    elseif ($policiesScope -eq "resourcegroup") {
        # Windows
        New-AzResourceGroupDeployment -Name $deploymentNameDepAgentWindows -ResourceGroupName $resourceGroup `
            -TemplateFile $templateFileDepAgentWindows -location $location -policyAssignmentName $depAgentPolicyNameWindows `
            -resourceGroupID $resourceGroupID | Out-Null

        # Linux
        New-AzResourceGroupDeployment -Name $deploymentNameDepAgentLinux -ResourceGroupName $resourceGroup `
            -TemplateFile $templateFileDepAgentLinux -location $location -policyAssignmentName $depAgentPolicyNameLinux `
            -resourceGroupID $resourceGroupID | Out-Null
    }

    ## PART 2. Deploy Data Collection Rules
    $templateBasePath = ".\DataCollection-VMInsights\DCRs"

    # Get the DCRs ARM template files
    $DCRsCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })
        
    # Deploy all the DCRs
    foreach ($DCR in $DCRsCollection) {

        if (($deployVMInsightsPerfAndMap -eq $true -and $DCR.Name -like "*PerfAndMap*") -or ($deployVMInsightsPerfOnly -eq $true -and $DCR.Name -like "*PerfOnly*")) {
        $DCRName = $($DCR.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($DCR.Name)"
        $deploymentName = $("deploy_DCR_$DCRName").ToLower()

        # Deploy this DCR
        Write-Host "Deploying DCR: $DCRName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
            -workspaceName $MonitorWSName -location $location | Out-Null
        }
    }

    ## PART 3. Assign Azure Policies to associate DCRs
    ## Get the Data Collection Rules previously created
    $DCRs = Get-AzDataCollectionRule -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like 'DCR-VMI-*' }

    # Assign the policies
    foreach ($DCR in $DCRs) {

        # Associate Windows VMInsights DCR via Azure Policy
        $azurePolicyNameWindows = "[MON] Configure Windows Arc Machine to be associated with " + $DCR.Name
        $templateFileWindows = ".\Policies\Configure Windows Arc Machine to be associated with a DCR.json"
        $deploymentNameWindows = "assign_policy_$($azurePolicyNameWindows)".Replace(' ', '').Replace('[MON]', '')
        $deploymentNameWindows = $deploymentNameWindows.substring(0, [System.Math]::Min(63, $deploymentNameWindows.Length))

        # Associate Linux VMInsights DCR via Azure Policy
        $azurePolicyNameLinux = "[MON] Configure Linux Arc Machine to be associated with " + $DCR.Name
        $templateFileLinux = ".\Policies\Configure Linux Arc Machine to be associated with a DCR.json"
        $deploymentNameLinux = "assign_policy_$($azurePolicyNameLinux)".Replace(' ', '').Replace('[MON]', '')
        $deploymentNameLinux = $deploymentNameLinux.substring(0, [System.Math]::Min(63, $deploymentNameLinux.Length))   

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyNameWindows"
        Write-Host "Assigning Azure Policy: $azurePolicyNameLinux"
        if ($policiesScope -eq "subscription") {
            # Windows
            New-AzDeployment -Name $deploymentNameWindows -location $location -TemplateFile $templateFileWindows `
                -policyAssignmentName $azurePolicyNameWindows -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
            # Linux
            New-AzDeployment -Name $deploymentNameLinux -location $location -TemplateFile $templateFileLinux `
                -policyAssignmentName $azurePolicyNameLinux -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            # Windows
            New-AzResourceGroupDeployment -Name $deploymentNameWindows -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFileWindows -location $location -policyAssignmentName $azurePolicyNameWindows `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null

            # Linux
            New-AzResourceGroupDeployment -Name $deploymentNameLinux -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFileLinux -location $location -policyAssignmentName $azurePolicyNameLinux `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
    }

}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy Change Tracking and Inventory
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Change Tracking and Inventory"
if ($deployChangeTrackingAndInventory -eq $true) {       

    ## Deploy Data Collection Rules
    $templateBasePath = ".\ChangeTrackingAndInventory\DCRs"

    # Get the DCRs ARM template files
    $DCRsCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })
        
    # Deploy all the DCRs
    foreach ($DCR in $DCRsCollection) {
        $DCRName = $($DCR.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($DCR.Name)"
        $deploymentName = $("deploy_DCR_$DCRName").ToLower()

        # Deploy this DCR
        Write-Host "Deploying DCR: $DCRName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
            -workspaceName $MonitorWSName -location $location | Out-Null
    }

    ## Assign Azure Policies to associate DCRs
    $templateBasePath = ".\ChangeTrackingAndInventory\Policies"
    $policiesScope = $parametersFileInput.Scope

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    ## Get the Data Collection Rules previously created
    $DCRs = Get-AzDataCollectionRule -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like 'DCR-ChangeTracking*' }

    # Assign the policies
    foreach ($DCR in $DCRs) {
        $azurePolicyName = "[CT] Enable ChangeTracking and Inventory for Arc-enabled virtual machines"
        $templateFile = "$templateBasePath\Enable ChangeTracking and Inventory for Arc-enabled virtual machines.json"
        $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '').Replace('[CT]', '')
        $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyName"
        if ($policiesScope -eq "subscription") {
            New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
                -policyAssignmentName $azurePolicyName -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyName `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
    }
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy Azure Update Manager
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Azure Update Manager Policies"
if ($deployUpdateManager -eq $true) {        
    $templateBasePath = ".\UpdateManager\Policies"
    $templateFile = "$templateBasePath\Configure periodic checking for missing system updates on azure Arc-enabled servers.json"
    $policiesScope = $parametersFileInput.Scope

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    # Windows Update Assessment Policy Assignment
    $azurePolicyNameWindows = "[UM] Configure periodic checking for missing system updates on Windows Arc-enabled servers"
    $deploymentNameWindows = "assign_policy_windows$($azurePolicyNameWindows)".Replace(' ', '').Replace('[UM]', '')
    $deploymentNameWindows = $deploymentNameWindows.substring(0, [System.Math]::Min(63, $deploymentNameWindows.Length))

    # Linux Update Assessment Policy Assignment
    $azurePolicyNameLinux = "[UM] Configure periodic checking for missing system updates on Linux Arc-enabled servers"
    $deploymentNameLinux = "assign_policy_linux$($azurePolicyNameLinux)".Replace(' ', '').Replace('[UM]', '')
    $deploymentNameLinux = $deploymentNameLinux.substring(0, [System.Math]::Min(63, $deploymentNameLinux.Length))

    # Assign the policy at resource group/subscription scope
    Write-Host "Assigning Azure Policy: $azurePolicyNameWindows"
    Write-Host "Assigning Azure Policy: $azurePolicyNameLinux"
    if ($policiesScope -eq "subscription") {
        # Windows
        New-AzDeployment -Name $deploymentNameWindows -location $location -TemplateFile $templateFile `
            -policyAssignmentName $azurePolicyNameWindows -osType "Windows" -resourceGroupID $resourceGroupID | Out-Null
        # Linux
        New-AzDeployment -Name $deploymentNameLinux -location $location -TemplateFile $templateFile `
            -policyAssignmentName $azurePolicyNameLinux -osType "Linux" -resourceGroupID $resourceGroupID | Out-Null
    }
    elseif ($policiesScope -eq "resourcegroup") {
        # Windows
        New-AzResourceGroupDeployment -Name $deploymentNameWindows -ResourceGroupName $resourceGroup `
            -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyNameWindows `
            -osType "Windows" -resourceGroupID $resourceGroupID | Out-Null

        # Linux
        New-AzResourceGroupDeployment -Name $deploymentNameLinux -ResourceGroupName $resourceGroup `
            -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyNameLinux `
            -osType "Linux" -resourceGroupID $resourceGroupID | Out-Null
    }
      
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy SQL BPA
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying SQL BPA Policy"
if ($deploySQLBPA -eq $true) {        
    $templateBasePath = ".\SQLServerBPA\Policies"
    $templateFile = "$templateBasePath\Configure Arc-enabled Servers with SQL Server extension installed to enable SQL best practices assessment.json"
    $policiesScope = $parametersFileInput.Scope

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    # Windows Update Assessment Policy Assignment
    $azurePolicyName = "[SQL] Configure Arc-enabled Servers with SQL Server extension installed to enable SQL best practices assessment"
    $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '').Replace('[SQL]', '')
    $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

    # Assign the policy at resource group/subscription scope
    Write-Host "Assigning Azure Policy: $azurePolicyName"
    if ($policiesScope -eq "subscription") {
        New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
            -policyAssignmentName $azurePolicyName -workspaceName $MonitorWSName -resourceGroupID $resourceGroupID | Out-Null
    }
    elseif ($policiesScope -eq "resourcegroup") {
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup `
            -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyName `
            -workspaceName $MonitorWSName -resourceGroupID $resourceGroupID | Out-Null
    }
      
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Create Azure Monitor action group with an email address
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Azure Monitor Action Group"
if ($deployActionGroup -eq $true) {
    $deploymentName = "deploy_action_group"
    $templateFile = ".\ActionGroup\actionGroup.json"
    $emailAddress = $parametersFileInput.Email
        
    # Deploy the data sources
    Write-Host "Deploying Azure Monitor Action Group"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -actionGroupName $actionGroupName -actionGroupShortName $actionGroupShortName -emailAddress $emailAddress | Out-Null
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Set up the alert baseline
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Azure Monitor alerts"
if ($deployAlerts -eq $true) {         
    $templateBasePath = ".\Alerts"

    # Get the alerts ARM template files
    $alertCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })
        
    # Deploy all the alerts
    foreach ($alert in $alertCollection) {
        $alertName = $($alert.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($alert.Name)"
        $deploymentName = $("deploy_alert_$alertName").ToLower()

        # Deploy this alert
        Write-Host "Deploying alert: $alertName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
            -workspaceName $MonitorWSName -location $location -actionGroupName $actionGroupName | Out-Null
    }
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy Azure Workbooks
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Azure workbooks"
if ($deployWorkbooks -eq $true) {         
    $templateBasePath = ".\Workbooks"

    # Get the workbooks ARM template files
    $workbookCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })
        
    # Deploy all workbooks
    foreach ($workbook in $workbookCollection) {
        $workbookName = $($workbook.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($workbook.Name)"
        $deploymentName = $("Deploy_Workbook_$workbookName").ToLower()

        # Deploy this workbook
        Write-Host "Deploying workbook $workbookName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
            -workspaceName $MonitorWSName | Out-Null
            
    }
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy the Azure dashboard
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying the Azure Dashboard"
if ($deployDashboard -eq $true) {
    $deploymentName = "deploy_azure_dashboard"
    $templateFile = ".\Dashboard\deploy.json"
    $dashboardName = "Azure Arc Dashboard - " + $namingPrefix

    # Deploy the Azure Dashboard
    Write-Host "Deploying the Azure Dashboard"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName -location $location -dashboardName $dashboardName | Out-Null    
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy Microsoft Defender for Cloud
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Microsoft Defender for Cloud"
if ($deployDefenderForCloud -eq $true) {
    $templateFile = ".\DefenderForCloud\deploy.json"
    $templateFileAtSubscription = ".\DefenderForCloud\deployatsubscription.json"
    $deploymentName = "deploy_defenderforcloud_resources"
    $deploymentNameAtSubscription = "deploy_defenderforcloud_subscriptionsettings"
    $emailAddress = $parametersFileInput.Email
    $securityCollectionTier = $parametersFileInput.securityCollectionTier
       
    # Deploy Defender for Cloud
    Write-Host "Deploying Microsoft Defender for Cloud resources"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $SecurityWSName -location $location -securityCollectionTier $securityCollectionTier | Out-Null

    # Deployment at subscription level: defender for servers and defender notification settings
    Write-Host "Deploying Microsoft Defender for Cloud settings at subscription level"
    New-AzDeployment -Name $deploymentNameAtSubscription -Location $location -TemplateFile $templateFileAtSubscription `
        -emails $emailAddress | Out-Null    
}
else {
    Write-Host "Skipped"
}
#endregion
