# Update-EH-Firewall-via-API.ps1
# Outline varibles
# Full list of tags can be found using "(Get-AzNetworkServiceTag -Location northeurope).values"
$serviceTagNEU = "PowerPlatformPlex.northeurope"
$serviceTagWEU = "PowerPlatformPlex.westeurope"
$region= "northeurope"
$subID = 'ENTER SUBSCRIPTION ID HERE'
$tenantID = 'ENTER TENANT ID HERE'
$EventHubName = "ENTER EVENT HUB NAMESPACE NAME HERE"
$ResourceGroupName ="ENTER RESOURCE GROUP NAME HERE"
 
#Install Required Modules
Install-Module -Name az -scope CurrentUser
Import-Module -Name az.accounts -NoClobber
Import-Module -Name az.network -NoClobber
Import-Module -Name az.eventhub -NoClobber 
 
#Connnect and Set AzContext
Update-AzConfig -EnableLoginByWam $false
Connect-AzAccount -tenantid $tenantID
Set-AzContext -Subscription $subID
 
#Retrieve the list of IPv4 addresses
$serviceTags = Get-AzNetworkServiceTag -Location $region
$serviceTagInfoNEU = $serviceTags.Values | Where-Object {$_.Name -eq $serviceTagNEU}
$serviceTagInfoWEU = $serviceTags.Values | Where-Object {$_.Name -eq $serviceTagWEU}
 
#Extract the IPv4 addresses, filter out IPv6 addresses.
$ipAddressesNEU = $serviceTagInfoNEU.Properties.AddressPrefixes | Where-Object {$_ -notmatch ":"}
$ipAddressesWEU = $serviceTagInfoWEU.Properties.AddressPrefixes | Where-Object {$_ -notmatch ":"}
$allipAddresses = $ipAddressesNEU + $ipAddressesWEU
 
#Create Functions
function Add-UniqueIpAddress {
    param (
        [string]$HubName,
        [string]$ResourceGroup,
        [string]$ipAddress
    )
    
    # Retrieve the existing IP rules
    $networkRuleSet = Get-AzEventHubNetworkRuleSet -ResourceGroupName $ResourceGroup -NamespaceName $HubName
    $existingRules = $networkRuleSet.IPRule

    # Check if the IP address already exists
    if ($existingRules.IPMask -notcontains $ipAddress) {
        Write-Output "Adding IP address $ipAddress"
        
        # Create a new IP rule
        $newRule = New-AzEventHubIPRuleConfig -IpMask $ipAddress -Action Allow
        
        # Add the new rule to the existing rules
        $updatedRules = $existingRules + $newRule
        
        # Update the network rule set with the new rule included
        Set-AzEventHubNetworkRuleSet -ResourceGroupName $ResourceGroup -NamespaceName $HubName -IPRule $updatedRules | Out-Null
    } else {
        Write-Output "IP address $ipAddress already exists in the firewall rules."
    }
}
 
function Remove-ObsoleteIpAddress {
    param (
        [string]$HubName,
        [string]$ResourceGroup,
        [array]$currentIpAddresses
    )
    
    # Retrieve the existing IP rules
    $networkRuleSet = Get-AzEventHubNetworkRuleSet -ResourceGroupName $ResourceGroup -NamespaceName $HubName
    $existingRules = $networkRuleSet.IPRule

    # Filter out obsolete IP addresses
    $updatedRules = $existingRules | Where-Object { $currentIpAddresses -contains $_.IPMask }

    # Update the network rule set with the filtered rules
    Set-AzEventHubNetworkRuleSet -ResourceGroupName $ResourceGroup -NamespaceName $HubName -IPRule $updatedRules | Out-Null

    # Output the removed IP addresses
    foreach ($rule in $existingRules) {
        if ($currentIpAddresses -notcontains $rule.IPMask) {
            Write-Output "Removed obsolete IP address $($rule.IPMask) from the firewall rules."
        }
    }
}
 
# Check allipaddress variable is not null. 
if($null -eq $allipAddresses){
    Write-Host "All allipaddresses variable is empty, script is exiting!"
    exit
}
else {
    #Update the firewall rules
    foreach ($ip in $allipAddresses){
        Add-UniqueIpAddress -hubname $EventHubName -ResourceGroup $ResourceGroupName -ipAddress $ip
    }

    # Remove obsolete IP addresses
    Remove-ObsoleteIpAddress -hubname $EventHubName -ResourceGroup $ResourceGroupName -currentIpAddresses $allIpAddresses
  
    #Verify the changes have been applied.
    (Get-AzEventHub -ResourceGroupName $ResourceGroupName -NamespaceName $EventHubName).Name
    (Get-AzEventHubNetworkRuleSet -ResourceGroupName $ResourceGroupName -NamespaceName $EventHubName).IPRule
}      
