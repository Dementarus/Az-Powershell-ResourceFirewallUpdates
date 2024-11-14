# Update-SA-Firewall-via-API.ps1
# Outline varibles
# Full list of tags can be found using "(Get-AzNetworkServiceTag -Location northeurope).values"
$serviceTagNEU = "PowerPlatformPlex.northeurope"
$serviceTagWEU = "PowerPlatformPlex.westeurope"
$region= "northeurope"
$subID = 'ENTER SUBSCRIPTION ID HERE'
$tenantID = 'ENTER TENANT ID HERE'
$StorageAccountName = "ENTER EVENT HUB NAMESPACE NAME HERE"
$ResourceGroupName ="ENTER RESOURCE GROUP NAME HERE"
 
#Install Required Modules
Install-Module -Name az -scope CurrentUser
Import-Module -Name az.accounts -NoClobber
Import-Module -Name az.network -NoClobber
Import-Module -Name az.storage -NoClobber 
 
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
        [string]$SAName,
        [string]$ResourceGroup,
        [string]$ipAddress
    )
    $existingRules = (Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $SAName).NetworkRuleSet.IpRules.IPAddressOrRange
    if ($existingRules -notcontains $ipAddress) {
        Write-Output "Adding IP address $ipAddress"
        Add-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroup -Name $SAName -IPAddressOrRange $ipAddress | Out-Null
    } else {
        Write-Output "IP address $ipAddress already exists in the firewall rules."
    }
}
 
function Remove-ObsoleteIpAddress {
    param (
        [string]$SAName,
        [string]$ResourceGroup,
        [array]$currentIpAddresses
    )
    $existingRules = (Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $SAName).NetworkRuleSet.IpRules.IPAddressOrRange
    foreach ($rule in $existingRules) {
        if ($currentIpAddresses -notcontains $rule) {
            Write-Output "Removed obsolete IP address $rule from the firewall rules."
            Remove-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroup -Name $SAName -IPAddressOrRange $rule | Out-Null
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
        Add-UniqueIpAddress -SAName $StorageAccountName -ResourceGroup $ResourceGroupName -ipAddress $ip
    } 
    # Remove obsolete IP addresses
    Remove-ObsoleteIpAddress -SAName $StorageAccountName -ResourceGroup $ResourceGroupName -currentIpAddresses $allIpAddresses

    #Verify the changes have been applied.
    (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).StorageAccountName
    (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).NetworkRuleSet.IpRules.IPAddressOrRange
}
