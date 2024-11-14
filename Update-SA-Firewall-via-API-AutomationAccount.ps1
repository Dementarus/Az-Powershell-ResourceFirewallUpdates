# Update-SA-Firewall-via-API-AutomationAccount.ps1
# Outline varibles
# Full list of tags can be found using "(Get-AzNetworkServiceTag -Location northeurope).values"
$serviceTagNEU = "PowerPlatformPlex.northeurope"
$serviceTagWEU = "PowerPlatformPlex.westeurope"
$region= "northeurope"
$subID = 'ENTER SUBSCRIPTION ID HERE'
$UAMI = 'ENTER USER MANAGED ID CLIENT ID HERE'
$StorageAccountName = "ENTER STORAGE ACCOUNT NAME HERE"
$ResourceGroupName = "ENTER RESOURCE GROUP NAME HERE"
 
#Connnect and set AzContext
Write-Output "Connecting to Azure..."
Connect-AzAccount -Identity -AccountId $UAMI
Write-Output "Setting context to subscription $subID..."
Set-AzContext -Subscription $subID
Write-Output "Context set successfully."
 
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

#Create Functions
function Add-UniqueIpAddress {
    param (
        [string]$SAName,
        [string]$ResourceGroup,
        [string]$ipAddress
    )
    Write-Output "Checking IP address $ipAddress in Key Vault $SAName..."
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
    Write-Output "Removing obsolete IP addresses from Key Vault $SAName..."
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
