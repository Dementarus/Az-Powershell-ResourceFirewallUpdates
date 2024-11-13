# Outline varibles
# Full list of tags can be found using "(Get-AzNetworkServiceTag -Location northeurope).values"
$serviceTagNEU = "PowerPlatformPlex.northeurope"
$serviceTagWEU = "PowerPlatformPlex.westeurope"
$region= "northeurope"
$subID = 'ENTER SUBSCRIPTION ID HERE'
$UAMI = 'ENTER USER MANAGED ID CLIENT ID HERE'
$keyVaultName = "ENTER KEY VAULT NAME HERE"
  
#Connnect and Set AzContext
Write-Output "Connecting to Azure..."
Connect-AzAccount -Identity -AccountId $UAMI
Write-Output "Setting context to subscription $subID..."
Set-AzContext -Subscription $subID
Write-Output "Context set successfully."
Import-Module Az.network -DisableNameChecking
 
#Retrieve the list of IPv4 addresses
Write-Output "Retrieving service tags for region $region..."
$serviceTags = Get-AzNetworkServiceTag -Location $region
Write-Output "Service tags retrieved: $($serviceTags.Values.Count)"
$serviceTagInfoNEU = $serviceTags.Values | Where-Object {$_.Name -eq $serviceTagNEU}
$serviceTagInfoWEU = $serviceTags.Values | Where-Object {$_.Name -eq $serviceTagWEU}
Write-Output "Service Tag NEU: $($serviceTagInfoNEU.Name)"
Write-Output "Service Tag WEU: $($serviceTagInfoWEU.Name)"

 
#Extract the IPv4 addresses, filter out IPv6 addresses.
$ipAddressesNEU = $serviceTagInfoNEU.Properties.AddressPrefixes | Where-Object {$_ -notmatch ":"}
$ipAddressesWEU = $serviceTagInfoWEU.Properties.AddressPrefixes | Where-Object {$_ -notmatch ":"}
Write-Output "IP Addresses NEU: $($ipAddressesNEU.Count)"
Write-Output "IP Addresses WEU: $($ipAddressesWEU.Count)"
$allipAddresses = $ipAddressesNEU + $ipAddressesWEU

(Get-AzKeyVault -VaultName $keyVaultName).VaultName
(Get-AzKeyVault -VaultName $keyVaultName).NetworkAcls
 
#Create Functions
function Add-UniqueIpAddress {
    param (
        [string]$vaultName,
        [string]$ipAddress
    )
    Write-Output "Checking IP address $ipAddress in Key Vault $vaultName..."
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
    Write-Output "Removing obsolete IP addresses from Key Vault $vaultName..."
    $existingRules = (Get-AzKeyVault -VaultName $vaultName).NetworkAcls.IpAddressRanges
    foreach ($rule in $existingRules) {
        if ($currentIpAddresses -notcontains $rule) {
            Write-Output "Removed obsolete IP address $rule from the firewall rules."
            Remove-AzKeyVaultNetworkRule -VaultName $vaultName -IpAddressRange $rule
        }
    }
}


# Check allipaddress variable is not null. 
if ($null -eq $allipAddresses) {
    Write-Host "All allipaddresses variable is empty, script is exiting!"
    exit
} else {
    Write-Output "Updating firewall rules with IP addresses..."
    foreach ($ip in $allipAddresses) {
        Add-UniqueIpAddress -vaultName $keyVaultName -ipAddress $ip
    }

    Write-Output "Removing obsolete IP addresses..."
    Remove-ObsoleteIpAddress -vaultName $keyVaultName -currentIpAddresses $allipAddresses

    Write-Output "Verifying changes..."
    (Get-AzKeyVault -VaultName $keyVaultName).VaultName
    (Get-AzKeyVault -VaultName $keyVaultName).NetworkAcls
}
