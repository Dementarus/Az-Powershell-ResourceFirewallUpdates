# Update-KV-Firewall-via-API.ps1
# Outline varibles
# Full list of tags can be found using "(Get-AzNetworkServiceTag -Location northeurope).values"
$serviceTagNEU = "PowerPlatformPlex.northeurope"
$serviceTagWEU = "PowerPlatformPlex.westeurope"
$region= "northeurope"
$subID = 'ENTER SUBSCRIPTION ID HERE'
$tenantID = 'ENTER TENANT ID HERE'
$keyVaultName = "ENTER KEY VAULT NAMESPACE NAME HERE"
 
#Install Required Modules
Install-Module -Name az -scope CurrentUser
Import-Module -Name az.accounts -NoClobber
Import-Module -Name az.network -NoClobber
Import-Module -Name az.keyvault -NoClobber 
 
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
        [string]$vaultName,
        [string]$ipAddress
    )
    $existingRules = (Get-AzKeyVault -VaultName $vaultName).NetworkAcls.IpAddressRanges
    if ($existingRules -notcontains $ipAddress) {
        Write-Output "Adding IP address $ipAddress"
        Add-AzKeyVaultNetworkRule -VaultName $vaultName -IpAddressRange $ipAddress
    } else {
        Write-Output "IP address $ipAddress already exists in the firewall rules."
    }
}
 
function Remove-ObsoleteIpAddress {
    param (
        [string]$vaultName,
        [array]$currentIpAddresses
    )
    $existingRules = (Get-AzKeyVault -VaultName $vaultName).NetworkAcls.IpAddressRanges
    foreach ($rule in $existingRules) {
        if ($currentIpAddresses -notcontains $rule) {
            Write-Output "Removed obsolete IP address $rule from the firewall rules."
            Remove-AzKeyVaultNetworkRule -VaultName $vaultName -IpAddressRange $rule
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
        Add-UniqueIpAddress -vaultName $keyVaultName -ipAddress $ip
    }
 
    # Remove obsolete IP addresses
    Remove-ObsoleteIpAddress -vaultName $keyVaultName -currentIpAddresses $allIpAddresses
 
    #Verify the changes have been applied.
    (Get-AzKeyVault -VaultName $keyVaultName).VaultName
    (Get-AzKeyVault -VaultName $keyVaultName).NetworkAcls
}

