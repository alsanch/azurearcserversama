# Deployment Variables to choose what to deploy
$deployLAW = $true
$deployAMAagents = $true
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

# Deploys for Azure VMs the same services selected for Azure Arc-enabled servers
$deployForAzureVMs = $true

# Global variables
$parametersFilePath = ".\Parameters.csv"
$parametersFileInput = $(Import-Csv $parametersFilePath)
$subscriptionName = $parametersFileInput.Subscription
$resourceGroup = $parametersFileInput.ResourceGroup
$namingPrefix = $parametersFileInput.NamingPrefix
$location = $parametersFileInput.Location
$policiesScope = $parametersFileInput.Scope
$emailAddress = $parametersFileInput.Email
$MonitorWSName = $namingPrefix + "-la-monitor"
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
    $templateFile = ".\LogAnalyticsWorkspace\logAnalyticsWorkspace.json"
        
    # Deploy the workspace
    Write-Host "Deploying log analytics workspace $MonitorWSName"
    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile `
        -workspaceName $MonitorWSName -location $location | Out-Null
    
}
else {
    Write-Host "Skipped"
}
#endregion

#region ### Deploy Azure Monitor Agent
Write-Host ""
Write-Host -ForegroundColor Cyan "Deploying Azure Monitor Agent Policies"
if ($deployAMAagents -eq $true) {        

    # Assign the policies
    $templateBasePath = ".\AzureMonitorAgent\Policies"

    # Get the AzurePolicies ARM template files
    $azurePoliciesCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId
        
    ## Per each policy
    foreach ($azurePolicyItem in $azurePoliciesCollection) {

        # Skip Azure VMs Policies if deployment for AzureVMs is not required
        if (($deployForAzureVMs -eq $false) -And ($azurePolicyItem -notlike "*Arc*" -eq $true)) {
            continue
        }
        
        $azurePolicyName = "[MON] " + $($azurePolicyItem.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($azurePolicyItem.Name)"
        $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '').Replace('[MON]', '')
        $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyName"
        if ($policiesScope -eq "subscription") {
            # Azure Arc-enabled servers
            New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
                -policyAssignmentName $azurePolicyName -resourceGroupID $resourceGroupID | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            # Azure Arc-enabled servers
            New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyName `
                -resourceGroupID $resourceGroupID | Out-Null
        }
    }
      
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
            -workspaceName $MonitorWSName -location $location -prefix $namingPrefix | Out-Null
    }

    ## Assign Azure Policies to associate DCRs
    $templateBasePath = ".\Policies"

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    ## Get the Data Collection Rules previously created
    $DCRs = Get-AzDataCollectionRule -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like '*DCR-AMA-*' }

    # Assign the policies
    foreach ($DCR in $DCRs) {
        if ($DCR.Name -like "*Windows*") {
            $arcAzurePolicyName = "[MON] Configure Windows Arc Machine to be associated with " + $DCR.Name
            $arcTemplateFile = "$templateBasePath\Configure Windows Arc Machine to be associated with a DCR.json"
            
            # Deployment for Azure Windows VMs
            if ($deployForAzureVMs -eq $true) {
                $azAzurePolicyName = "[MON] Configure Windows Machine to be associated with " + $DCR.Name
                $azTemplateFile = "$templateBasePath\Configure Windows Machine to be associated with a DCR.json"
            }
        }
        elseif ($DCR.Name -like "*Linux*") {
            $arcAzurePolicyName = "[MON] Configure Linux Arc Machine to be associated with " + $DCR.Name
            $arcTemplateFile = "$templateBasePath\Configure Linux Arc Machine to be associated with a DCR.json"
            
            # Deployment for Azure Linux VMs
            if ($deployForAzureVMs -eq $true) {
                $azAzurePolicyName = "[MON] Configure Linux Machine to be associated with " + $DCR.Name
                $azTemplateFile = "$templateBasePath\Configure Linux Machine to be associated with a DCR.json"
            }
        }
        
        # Deployment for Azure Arc VMs
        $arcDeploymentName = "assign_policy_$($arcAzurePolicyName)".Replace(' ', '').Replace('[MON]', '')
        $arcDeploymentName = $arcDeploymentName.substring(0, [System.Math]::Min(63, $arcDeploymentName.Length))

        # Deployment for Azure VMs
        if ($deployForAzureVMs -eq $true) {
            $azDeploymentName = "assign_policy_$($azAzurePolicyName)".Replace(' ', '').Replace('[MON]', '')
            $azDeploymentName = $azDeploymentName.substring(0, [System.Math]::Min(63, $azDeploymentName.Length))
        }

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $arcAzurePolicyName"
        if ($policiesScope -eq "subscription") {

            # Azure Arc Windows VMs
            New-AzDeployment -Name $arcDeploymentName -location $location -TemplateFile $arcTemplateFile `
                -policyAssignmentName $arcAzurePolicyName -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null

            # Deployment for Azure Windows VMs
            if ($deployForAzureVMs -eq $true) {
                Write-Host "Assigning Azure Policy: $azAzurePolicyName"
                New-AzDeployment -Name $azDeploymentName -location $location -TemplateFile $azTemplateFile `
                    -policyAssignmentName $azAzurePolicyName -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
            }
        }
        elseif ($policiesScope -eq "resourcegroup") {
            
            # Azure Arc Linux VMs
            New-AzResourceGroupDeployment -Name $arcDeploymentName -ResourceGroupName $resourceGroup `
                -TemplateFile $arcTemplateFile -location $location -policyAssignmentName $arcAzurePolicyName `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null

            # Deployment for Azure Linux VMs
            if ($deployForAzureVMs -eq $true) {
                Write-Host "Assigning Azure Policy: $azAzurePolicyName"
                New-AzDeployment -Name $azDeploymentName -location $location -TemplateFile $azTemplateFile `
                    -policyAssignmentName $azAzurePolicyName -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
            }
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
    if ($deployVMInsightsPerfAndMap -eq $true -and $deployVMInsightsPerfOnly -eq $true) {
        $deployVMInsightsPerfOnly = $false
    }

    ## PART 1. Dependency Agent Policies (only needed for Map)
    if ($deployVMInsightsPerfAndMap -eq $true) {

    # Assign the policies
    $templateBasePath = ".\DataCollection-VMInsights\Policies"

    # Get the AzurePolicies ARM template files
    $azurePoliciesCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId
        
    ## Per each policy
    foreach ($azurePolicyItem in $azurePoliciesCollection) {

        # Skip Azure VMs Policies if deployment for AzureVMs is not required
        if (($deployForAzureVMs -eq $false) -And ($azurePolicyItem -notlike "*Arc*" -eq $true)) {
            continue
        }
        
        $azurePolicyName = "[MON] " + $($azurePolicyItem.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($azurePolicyItem.Name)"
        $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '').Replace('[MON]', '')
        $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyName"
        if ($policiesScope -eq "subscription") {
            # Azure Arc-enabled servers
            New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
                -policyAssignmentName $azurePolicyName -resourceGroupID $resourceGroupID | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            # Azure Arc-enabled servers
            New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup `
                -TemplateFile $templateFile -location $location -policyAssignmentName $azurePolicyName `
                -resourceGroupID $resourceGroupID | Out-Null
        }
    }
        
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
                -workspaceName $MonitorWSName -location $location -prefix $namingPrefix | Out-Null
        }
    }

    ## PART 3. Assign Azure Policies to associate DCRs
    ## Get the Data Collection Rules previously created
    $DCRs = Get-AzDataCollectionRule -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like '*DCR-VMI-*' }

    # Assign the policies. There is a single DCR for VMInsights
    foreach ($DCR in $DCRs) {

        # Associate Arc Windows VMInsights DCR via Azure Policy
        $arcAzurePolicyNameWindows = "[MON] Configure Windows Arc Machine to be associated with " + $DCR.Name
        $arcTemplateFileWindows = ".\Policies\Configure Windows Arc Machine to be associated with a DCR.json"
        $arcDeploymentNameWindows = "assign_policy_$($arcAzurePolicyNameWindows)".Replace(' ', '').Replace('[MON]', '')
        $arcDeploymentNameWindows = $arcDeploymentNameWindows.substring(0, [System.Math]::Min(63, $arcDeploymentNameWindows.Length))

        # Associate Arc Linux VMInsights DCR via Azure Policy
        $arcAzurePolicyNameLinux = "[MON] Configure Linux Arc Machine to be associated with " + $DCR.Name
        $arcTemplateFileLinux = ".\Policies\Configure Linux Arc Machine to be associated with a DCR.json"
        $arcDeploymentNameLinux = "assign_policy_$($arcAzurePolicyNameLinux)".Replace(' ', '').Replace('[MON]', '')
        $arcDeploymentNameLinux = $arcDeploymentNameLinux.substring(0, [System.Math]::Min(63, $arcDeploymentNameLinux.Length))  
        
        # Azure VMs
        if ($deployForAzureVMs -eq $true) {
            # Associate Azure Windows VMInsights DCR via Azure Policy
            $azAzurePolicyNameWindows = "[MON] Configure Windows Machine to be associated with " + $DCR.Name
            $azTemplateFileWindows = ".\Policies\Configure Windows Machine to be associated with a DCR.json"
            $azDeploymentNameWindows = "assign_policy_$($azAzurePolicyNameWindows)".Replace(' ', '').Replace('[MON]', '')
            $azDeploymentNameWindows = $azDeploymentNameWindows.substring(0, [System.Math]::Min(63, $azDeploymentNameWindows.Length))

            # Associate Azure Linux VMInsights DCR via Azure Policy
            $azAzurePolicyNameLinux = "[MON] Configure Linux Machine to be associated with " + $DCR.Name
            $azTemplateFileLinux = ".\Policies\Configure Linux Machine to be associated with a DCR.json"
            $azDeploymentNameLinux = "assign_policy_$($azAzurePolicyNameLinux)".Replace(' ', '').Replace('[MON]', '')
            $azDeploymentNameLinux = $azDeploymentNameLinux.substring(0, [System.Math]::Min(63, $azDeploymentNameLinux.Length))  
        }

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $arcAzurePolicyNameWindows"
        Write-Host "Assigning Azure Policy: $arcAzurePolicyNameLinux"
        if ($policiesScope -eq "subscription") {
            # Arc Windows
            New-AzDeployment -Name $arcDeploymentNameWindows -location $location -TemplateFile $arcTemplateFileWindows `
                -policyAssignmentName $arcAzurePolicyNameWindows -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
            # Arc Linux
            New-AzDeployment -Name $arcDeploymentNameLinux -location $location -TemplateFile $arcTemplateFileLinux `
                -policyAssignmentName $arcAzurePolicyNameLinux -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null

            # Azure VMs
            if ($deployForAzureVMs -eq $true) {
                Write-Host "Assigning Azure Policy: $azAzurePolicyNameWindows"
                Write-Host "Assigning Azure Policy: $azAzurePolicyNameLinux"
                # Azure Windows
                New-AzDeployment -Name $azDeploymentNameWindows -location $location -TemplateFile $azTemplateFileWindows `
                    -policyAssignmentName $azAzurePolicyNameWindows -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
                # Azure Linux
                New-AzDeployment -Name $azDeploymentNameLinux -location $location -TemplateFile $azTemplateFileLinux `
                    -policyAssignmentName $azAzurePolicyNameLinux -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
            }
        }
        elseif ($policiesScope -eq "resourcegroup") {
            # Arc Windows
            New-AzResourceGroupDeployment -Name $arcDeploymentNameWindows -ResourceGroupName $resourceGroup `
                -TemplateFile $arcTemplateFileWindows -location $location -policyAssignmentName $arcAzurePolicyNameWindows `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
            # Arc Linux
            New-AzResourceGroupDeployment -Name $arcDeploymentNameLinux -ResourceGroupName $resourceGroup `
                -TemplateFile $arcTemplateFileLinux -location $location -policyAssignmentName $arcAzurePolicyNameLinux `
                -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null

            # Azure VMs
            if ($deployForAzureVMs -eq $true) {
                Write-Host "Assigning Azure Policy: $azAzurePolicyNameWindows"
                Write-Host "Assigning Azure Policy: $azAzurePolicyNameLinux"
                # Azure Windows
                New-AzResourceGroupDeployment -Name $azDeploymentNameWindows -ResourceGroupName $resourceGroup `
                    -TemplateFile $azTemplateFileWindows -location $location -policyAssignmentName $azAzurePolicyNameWindows `
                    -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
                # Azure Linux
                New-AzResourceGroupDeployment -Name $azDeploymentNameLinux -ResourceGroupName $resourceGroup `
                    -TemplateFile $azTemplateFileLinux -location $location -policyAssignmentName $azAzurePolicyNameLinux `
                    -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null      
            }
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
            -workspaceName $MonitorWSName -location $location -prefix $namingPrefix | Out-Null
    }

    # Assign the policies
    $templateBasePath = ".\ChangeTrackingAndInventory\Policies"

    # Get the AzurePolicies ARM template files
    $azurePoliciesCollection = $(Get-ChildItem -Path $templateBasePath | Where-Object { $_.name -like "*.json" })

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    ## Get the Data Collection Rule previously created
    $DCR = Get-AzDataCollectionRule -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like '*DCR-ChangeTracking*' }
        
    ## Per each policy
    foreach ($azurePolicyItem in $azurePoliciesCollection) {

        # Skip Azure VMs Policies if deployment for AzureVMs is not required
        if (($deployForAzureVMs -eq $false) -And ($azurePolicyItem -notlike "*Arc*" -eq $true)) {
            continue
        }
        
        $azurePolicyName = "[CT] " + $($azurePolicyItem.Name).Split(".")[0]
        $templateFile = "$templateBasePath\$($azurePolicyItem.Name)"
        $deploymentName = "assign_policy_$($azurePolicyName)".Replace(' ', '').Replace('[CT]', '')
        $deploymentName = $deploymentName.substring(0, [System.Math]::Min(63, $deploymentName.Length))

        # Assign the policy at resource group/subscription scope
        Write-Host "Assigning Azure Policy: $azurePolicyName"
        if ($policiesScope -eq "subscription") {
            # Azure Arc-enabled servers
            New-AzDeployment -Name $deploymentName -location $location -TemplateFile $templateFile `
                -policyAssignmentName $azurePolicyName -dcrResourceId $DCR.Id -resourceGroupID $resourceGroupID | Out-Null
        }
        elseif ($policiesScope -eq "resourcegroup") {
            # Azure Arc-enabled servers
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

    # Parameter to make unique Microsoft.Authorization/roleAssignments name at tenant level
    $resourceGroupID = (Get-AzResourceGroup -Name $resourceGroup).ResourceId

    # Azure Arc-enabled servers
    $arcTemplateFile = "$templateBasePath\Configure periodic checking for missing system updates on azure Arc-enabled servers.json"
    # Windows Update Assessment Policy Assignment
    $arcPolicyNameWindows = "[UM] Configure periodic checking for missing system updates on Windows Arc-enabled servers"
    $arcDeploymentNameWindows = "assign_policy_windows$($arcPolicyNameWindows)".Replace(' ', '').Replace('[UM]', '')
    $arcDeploymentNameWindows = $arcDeploymentNameWindows.substring(0, [System.Math]::Min(63, $arcDeploymentNameWindows.Length))

    # Linux Update Assessment Policy Assignment
    $arcPolicyNameLinux = "[UM] Configure periodic checking for missing system updates on Linux Arc-enabled servers"
    $arcDeploymentNameLinux = "assign_policy_linux$($arcPolicyNameLinux)".Replace(' ', '').Replace('[UM]', '')
    $arcDeploymentNameLinux = $arcDeploymentNameLinux.substring(0, [System.Math]::Min(63, $arcDeploymentNameLinux.Length))

    # Azure VMs
    if ($deployForAzureVMs -eq $true) {
        # Azure servers
        $azTemplateFile = "$templateBasePath\Configure periodic checking for missing system updates on azure virtual machines.json"
        # Windows Update Assessment Policy Assignment
        $azPolicyNameWindows = "[UM] Configure periodic checking for missing system updates on Windows servers"
        $azDeploymentNameWindows = "assign_policy_windows$($azPolicyNameWindows)".Replace(' ', '').Replace('[UM]', '')
        $azDeploymentNameWindows = $azDeploymentNameWindows.substring(0, [System.Math]::Min(63, $azDeploymentNameWindows.Length))

        # Linux Update Assessment Policy Assignment
        $azPolicyNameLinux = "[UM] Configure periodic checking for missing system updates on Linux servers"
        $azDeploymentNameLinux = "assign_policy_linux$($azPolicyNameLinux)".Replace(' ', '').Replace('[UM]', '')
        $azDeploymentNameLinux = $azDeploymentNameLinux.substring(0, [System.Math]::Min(63, $azDeploymentNameLinux.Length))
    }

    # Assign the policy at resource group/subscription scope
    Write-Host "Assigning Azure Policy: $arcPolicyNameWindows"
    Write-Host "Assigning Azure Policy: $arcPolicyNameLinux"
    if ($policiesScope -eq "subscription") {
        # Azure Arc Windows
        New-AzDeployment -Name $arcDeploymentNameWindows -location $location -TemplateFile $arcTemplateFile `
            -policyAssignmentName $arcPolicyNameWindows -osType "Windows" -resourceGroupID $resourceGroupID | Out-Null
        # Azure Arc Linux
        New-AzDeployment -Name $arcDeploymentNameLinux -location $location -TemplateFile $arcTemplateFile `
            -policyAssignmentName $arcPolicyNameLinux -osType "Linux" -resourceGroupID $resourceGroupID | Out-Null

        # Azure VMs
        if ($deployForAzureVMs -eq $true) {
            Write-Host "Assigning Azure Policy: $azPolicyNameWindows"
            Write-Host "Assigning Azure Policy: $azPolicyNameLinux"
            # Azure Windows
            New-AzDeployment -Name $azDeploymentNameWindows -location $location -TemplateFile $azTemplateFile `
                -policyAssignmentName $azPolicyNameWindows -osType "Windows" -resourceGroupID $resourceGroupID | Out-Null
            # Azure Linux
            New-AzDeployment -Name $azDeploymentNameLinux -location $location -TemplateFile $azTemplateFile `
                -policyAssignmentName $azPolicyNameLinux -osType "Linux" -resourceGroupID $resourceGroupID | Out-Null
        }        
    }
    elseif ($policiesScope -eq "resourcegroup") {
        # Azure Arc Windows
        New-AzResourceGroupDeployment -Name $arcDeploymentNameWindows -ResourceGroupName $resourceGroup `
            -TemplateFile $arcTemplateFile -location $location -policyAssignmentName $arcPolicyNameWindows `
            -osType "Windows" -resourceGroupID $resourceGroupID | Out-Null
        # Azure Arc Linux
        New-AzResourceGroupDeployment -Name $arcDeploymentNameLinux -ResourceGroupName $resourceGroup `
            -TemplateFile $arcTemplateFile -location $location -policyAssignmentName $arcPolicyNameLinux `
            -osType "Linux" -resourceGroupID $resourceGroupID | Out-Null

        # Azure VMs
        if ($deployForAzureVMs -eq $true) {
            Write-Host "Assigning Azure Policy: $azPolicyNameWindows"
            Write-Host "Assigning Azure Policy: $azPolicyNameLinux"
            # Azure Windows
            New-AzResourceGroupDeployment -Name $azDeploymentNameWindows -ResourceGroupName $resourceGroup `
                -TemplateFile $azTemplateFile -location $location -policyAssignmentName $azPolicyNameWindows `
                -osType "Windows" -resourceGroupID $resourceGroupID | Out-Null
            # Azure Linux
            New-AzResourceGroupDeployment -Name $azDeploymentNameLinux -ResourceGroupName $resourceGroup `
                -TemplateFile $azTemplateFile -location $location -policyAssignmentName $azPolicyNameLinux `
                -osType "Linux" -resourceGroupID $resourceGroupID | Out-Null
        } 
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
            -workspaceName $MonitorWSName -location $location -actionGroupName $actionGroupName -prefix $namingPrefix | Out-Null
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
            -workspaceName $MonitorWSName -prefixName $namingPrefix | Out-Null
            
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
    $templateFile = ".\Dashboard\dashboard.json"
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