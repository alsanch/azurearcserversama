<#
    .DESCRIPTION
        Remediate Azure Policies with PowerShell 
        Based on https://adatum.no/azure/azure-policy/remediate-azure-policy-with-powershell

    .NOTES
        AUTHOR: Alejandro Sanchez Gomez
        LASTEDIT: May 11, 2022

	THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
    EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
	MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#>

Param
(
    [Parameter (Mandatory = $false)]
    [String] $resourceGroup
)

"Please enable appropriate RBAC permissions to the system identity of this automation account. Otherwise, the runbook may fail..."

try {
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Definition name for policy Configure Log Analytics extension on Azure Arc enabled Windows/Linux servers
$policyDefinitionNames = @('845857af-0333-4c5d-bbbc-6076697da122', 'a4034bc6-ae50-406d-bf76-50f4ee5a7811', '94f686d6-9a24-4e19-91f1-de937dc171a4', 'ca817e41-e85a-4783-bc7f-dc532d36235e', '10caed8a-652c-4d1d-84e4-2805b7c07278', 'ec88097d-843f-4a92-8471-78016d337ba4', '4bb303db-d051-4099-95d2-e3e1428a4cd5', 'f08f556c-12ff-464d-a7de-40cb5b6cccec', '09a1f130-7697-42bc-8d84-8a9ea17e5192', 'bef2d677-e829-492d-9a3d-f5a20fda818f', 'ef9fe2ce-a588-4edd-829c-6247069dcfdb', 'b6faa975-0add-4f35-8d1c-70bba45c4424', '08a4470f-b26d-428d-97f4-7e3e9c92b366', '84cfed75-dfd4-421b-93df-725b479d356a', 'd55b81e1-984f-4a96-acab-fae204e3ca7f', '89ca9cc7-25cd-4d53-97ba-445ca7a1f222', 'fd2d1a6e-6d95-4df2-ad00-504bf0273406', 'd5c37ce1-5f52-4523-b949-f19bf945b73a', '2ea82cdd-f2e8-4500-af75-67a2e084ca74', 'c24c537f-2516-4c2f-aac5-2cd26baa3d26', 'eab1f514-22e3-42e3-9a1f-e1dc9199355c', 'f36de009-cacb-47b3-b936-9c4c9120d064', 'bfea026e-043f-4ff4-9d1b-bf301ca7ff46', '59efceea-0c96-497e-a4a1-4eb2290dac15')

# get all non-compliant policies that can be remediated
if ($resourceGroup) {
    # at resourceGroupLevel
    Write-Output "Getting non-compliant policies at resource group level..."
    $nonCompliantPolicies = Get-AzPolicyState -ResourceGroupName $resourceGroup | Where-Object { $_.ComplianceState -eq "NonCompliant" -and $_.PolicyDefinitionName -in $policyDefinitionNames -and $_.PolicyDefinitionAction -eq "deployIfNotExists" }
}
else {
    # at subscriptionLevel
    Write-Output "Getting non-compliant policies at subscription level..."
    $nonCompliantPolicies = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "NonCompliant" -and $_.PolicyDefinitionName -in $policyDefinitionNames -and $_.PolicyDefinitionAction -eq "deployIfNotExists" }
}

Write-Output "Non-compliant policies:"
Write-Output $nonCompliantPolicies

# loop through and start individual tasks per policy 
foreach ($policy in $nonCompliantPolicies) {

    $remediationName = "rem." + $policy.PolicyAssignmentName
    
    # Policy assigned at RG level -- Remedation done at RG level
    if ($policy.PolicyAssignmentId -like "*resourcegroups*") {
        Write-Output "Remediating $($policy.PolicyAssignmentName) at resource group level..."
        $scope = $policy.PolicyAssignmentId.Split("/")[4]
        Start-AzPolicyRemediation -Name $remediationName -ResourceGroupName $scope -PolicyAssignmentId $policy.PolicyAssignmentId -ResourceDiscoveryMode ReEvaluateCompliance
    }
    # Policy assigned at MG level -- Remedation done at MG level
    elseif ($policy.PolicyAssignmentId -like "*managementGroups*") {
        Write-Output "Remediating $($policy.PolicyAssignmentName) at management group level..."
        $scope = $policy.PolicyAssignmentId.Split("/")[4]
        Start-AzPolicyRemediation -Name $remediationName -ManagementGroupName $scope -PolicyAssignmentId $policy.PolicyAssignmentId -ResourceDiscoveryMode ReEvaluateCompliance    
    }
    # Policy assigned at subscription level -- Remedation done at subscription level
    else {
        Write-Output "Remediating $($policy.PolicyAssignmentName) at subscription level..."
        Start-AzPolicyRemediation -Name $remediationName -PolicyAssignmentId $policy.PolicyAssignmentId -ResourceDiscoveryMode ReEvaluateCompliance
    }
}