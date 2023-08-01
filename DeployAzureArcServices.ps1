# Deployment Variables to choose what to deploy
$deployMonitorLAW = $true
$deployMonitorLAWDataSources = $true
$deployMonitorVMInsights = $true
$deployAutomationAccount = $true
$deployActionGroup = $true
$deployAlerts = $true
$deployWorkbooks = $true
$deployDashboard = $true
$deployAzurePolicies = $true
$deployDefenderForCloud = $true

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
$AutomationAccountName = $namingPrefix + "-aa-arcservers"

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
if ($deployMonitorLAW -eq $true) {
    $deploymentName = "deploy_monitor_loganalytics_workspace"
    $templateFile = ".\MonitorLogAnalyticsWorkspace\deploy.json"
        
    # Deploy the workspace
    Write-Host "Deploying log analytics workspace $MonitorWSName"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName -location $location | Out-Null
    
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Enable LA Monitor Data Sources: Events, Performance Counters, etc
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Data Sources in the Monitor the Log Analytics Workspace"
if ($deployMonitorLAWDataSources -eq $true) {
    $deploymentName = "deploy_data_sources"
    $templateFile = ".\MonitorLogAnalyticsWorkspace\DataSources\deploy.json"

    # Deploy the data sources
    Write-Host "Deploying data sources for $MonitorWSName"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName | Out-Null
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Enable LA Monitor VM Insights solution
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying VMInsights in the Monitor the Log Analytics Workspace"
if ($deployMonitorVMInsights -eq $true) {
    $deploymentName = "deploy_vminsights"
    $templateFile = ".\VMInsights\deploy.json"

    # Deploy VM Insights solution
    Write-Host "Deploying VMInsights solution for $MonitorWSName"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName -location $location | Out-Null
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Automation account related resources
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying the Automation Account and related resources"
if ($deployAutomationAccount -eq $true) {
    $deploymentName = "deploy_automation_account"
    $templateFile = ".\AutomationAccount\deploy.json"
    $managedIdentityScope = $parametersFileInput.Scope

    # Deploy and link the automation account
    Write-Host "Deploying and linking automation account to $MonitorWSName"
    Write-Host "Deploying Update Management, Change Tracking and Inventory in the automation account $automationAccountName"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName -automationAccountName $automationAccountName -location $location | Out-Null

    # Create and publish the runbook
    $runbookName = "AutoRemediatePolicyLAAgentAzureArcServers"
    $runbookType = "PowerShell"
    $runbookCodePath = ".\AutomationAccount\Runbook\AutoRemediatePolicyLAAgentAzureArcServers.ps1"
    Write-Host "Importing the required runbooks"
    Import-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroup  -Name $runbookName `
        -Type $runbookType -Path $runbookCodePath | Out-null 
           
    Write-Host "Publishing the required runbooks"
    Publish-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroup -Name $runbookName | Out-null

    # Create and link the schedule
    Write-Host "Creating the daily schedule and linking it to the runbook"
    $StartTime = Get-Date "23:00:00"
    if ($StartTime -lt (Get-Date)) { $StartTime = $StartTime.AddDays(1) }
    $EndTime = $StartTime.AddYears(99)
    $scheduleName = "dailyschedule11pm"
    $TimeZone = ([System.TimeZoneInfo]::Local).Id
    New-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $scheduleName -StartTime $StartTime -ExpiryTime `
        $EndTime -DayInterval 1 -ResourceGroupName $resourceGroup -TimeZone $TimeZone | Out-null
    # Policy remedation will happen at subscription or resource group level, depending on the Scope parameter
    if ($managedIdentityScope -eq "subscription") {
        Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName `
            -Name $runbookName -ScheduleName $scheduleName -ResourceGroupName $resourceGroup | Out-null
    }
    elseif ($managedIdentityScope -eq "resourcegroup") {
        Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName `
            -Name $runbookName -ScheduleName $scheduleName -ResourceGroupName $resourceGroup `
            -Parameters @{"resourceGroup" = $resourceGroup } | Out-null
    }    

    # Get automation account managed identity and assign permissions to remediate policies at subscription/resource group level

    #Wait for the system managed identity to be available
    Write-Host "Waiting for the automation account system managed identity... " -NoNewline
    while ($null -eq (Get-AzAutomationAccount -ResourceGroupName $resourceGroup -Name $automationAccountName -ErrorAction SilentlyContinue).Identity.PrincipalId) {
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5   
    }
    $principalId = (Get-AzAutomationAccount -ResourceGroupName $resourceGroup -Name $automationAccountName).Identity.PrincipalId
    if ($managedIdentityScope -eq "subscription") {
        New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Resource Policy Contributor" | Out-null
    }
    elseif ($managedIdentityScope -eq "resourcegroup") {
        New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Resource Policy Contributor" `
            -ResourceGroupName $resourceGroup | Out-null
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
    $templateFile = ".\ActionGroup\deploy.json"
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

#region ### Assign Azure Policies
Write-Host ""
Write-Host -ForegroundColor Cyan "Assigning required Azure Policies"
if ($deployAzurePolicies -eq $true) {        
    $templateBasePath = ".\Policies"
    $policiesScope = $parametersFileInput.Scope
    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId
    $monitorWSID = (Get-AzResource -ResourceGroupName $resourceGroup -Name $MonitorWSName).ResourceId

    # Get the AzurePolicies ARM template files
    $azurePoliciesCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })
        
    # Assign the policies
    foreach ($azurePolicyItem in $azurePoliciesCollection) {
        # Skip DependencyAgent Policies if VMInsights is not required
        if (($deployMonitorVMInsights -eq $false) -And ($azurePolicyItem -like "*Dependency*" -eq $true)) {
            continue
        }

        $azurePolicyName = $($azurePolicyItem.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($azurePolicyItem.Name)"
        $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '')
        $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyName"
        if ($policiesScope -eq "subscription") {
            New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
                -workspaceName $MonitorWSName -policyAssignmentName $azurePolicyName -resourceGroupID `
                $resourceGroupID -monitorWSID $monitorWSID  | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFile -workspaceName $MonitorWSName -location $location `
                -policyAssignmentName $azurePolicyName -resourceGroupID $resourceGroupID `
                -monitorWSID $monitorWSID | Out-Null
        }
    }
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
