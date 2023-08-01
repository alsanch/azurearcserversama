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
  [Parameter (Mandatory= $false)]
  [String] $resourceGroup
)

"Please enable appropriate RBAC permissions to the system identity of this automation account. Otherwise, the runbook may fail..."

try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Definition name for policy Configure Log Analytics extension on Azure Arc enabled Windows/Linux servers
$policyDefinitionNames = @('69af7d4a-7b18-4044-93a9-2651498ef203','9d2b61b4-1d14-4a63-be30-d4498e7ad2cf', 'deacecc0-9f84-44d2-bb82-46f32d766d43', '91cb9edd-cd92-4d2f-b2f2-bdd8d065a3d4')

# get all non-compliant policies that can be remediated
if($resourceGroup)
{
    # at resourceGroupLevel
    Write-Output "Getting non-compliant policies at resource group level..."
    $nonCompliantPolicies = Get-AzPolicyState -ResourceGroupName $resourceGroup | Where-Object { $_.ComplianceState -eq "NonCompliant" -and $_.PolicyDefinitionName -in $policyDefinitionNames -and $_.PolicyDefinitionAction -eq "deployIfNotExists" }
}
else
{
    # at subscriptionLevel
    Write-Output "Getting non-compliant policies at subscription level..."
    $nonCompliantPolicies = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "NonCompliant" -and $_.PolicyDefinitionName -in $policyDefinitionNames -and $_.PolicyDefinitionAction -eq "deployIfNotExists" }
}

Write-Output "Non-compliant policies:"
Write-Output $nonCompliantPolicies

# loop through and start individual tasks per policy 
foreach ($policy in $nonCompliantPolicies) {

    $remediationName = "rem." + $policy.PolicyDefinitionName
    
    # Policy assigned at RG level -- Remedation done at RG level
    if($policy.PolicyAssignmentId -like "*resourcegroups*"){
        Write-Output "Remediating $($policy.PolicyDefinitionReferenceId) at resource group level..."
        $scope = $policy.PolicyAssignmentId.Split("/")[4]
        Start-AzPolicyRemediation -Name $remediationName -ResourceGroupName $scope -PolicyAssignmentId $policy.PolicyAssignmentId -PolicyDefinitionReferenceId $policy.PolicyDefinitionReferenceId -ResourceDiscoveryMode ReEvaluateCompliance
    }
    # Policy assigned at MG level -- Remedation done at MG level
    elseif($policy.PolicyAssignmentId -like "*managementGroups*") {
        Write-Output "Remediating $($policy.PolicyDefinitionReferenceId) at management group level..."
        $scope = $policy.PolicyAssignmentId.Split("/")[4]
        Start-AzPolicyRemediation -Name $remediationName -ManagementGroupName $scope -PolicyAssignmentId $policy.PolicyAssignmentId -PolicyDefinitionReferenceId $policy.PolicyDefinitionReferenceId -ResourceDiscoveryMode ReEvaluateCompliance    
    }
    # Policy assigned at subscription level -- Remedation done at subscription level
    else {
        Write-Output "Remediating $($policy.PolicyDefinitionReferenceId) at subscription level..."
        Start-AzPolicyRemediation -Name $remediationName -PolicyAssignmentId $policy.PolicyAssignmentId -PolicyDefinitionReferenceId $policy.PolicyDefinitionReferenceId -ResourceDiscoveryMode ReEvaluateCompliance
    }
}