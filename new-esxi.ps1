#Remove all variable before hand and clean environment
rv * -ea SilentlyContinue; rmo *; $error.Clear(); cls

#Set PowerCLI environment
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -InvalidCertificateAction ignore -Confirm:$false | Out-Null

#Connect VIServer (PREDEFINED)
$viServer = "vcsa@domain.com", "administrator@vsphere.local", "VMware1!"
Connect-VIServer $viServer[0] -User $viServer[1] -Password $viServer[2]

#Simple break script if not connected
if ($? -eq $false) {Write-Host "Unable to connect to vCenter, bye bye`n"; break}

"`n"

#The script expects ESXi has been installed
#The only config that needed to be done during ESXi installation is a reachable IP
#Then the host needed to be added into vCenter with default Maintenence Mode on
#DNS is REQUIRED for to add into vCenter and the script to run

#Host details, expects working and resolvable DNS to Host
$hostname = "HOST001"
$domainName = "domain.com"
$searchDomain = $domainName

#"type" is used for naming generation (eg Datastore name)
$type = "Tier 0"

$location = "MY"

$datastore_name = "$location-$type-$($hostname.ToUpper()):local1"

$ntp1 = "172.30.166.17"
$ntp2 = "172.30.166.18"

$dnsAddress = [ipaddress]"172.30.152.31", [ipaddress]"172.30.152.32"


$esxi = $hostname + '.' + $domainName


$mgmt_vds = "MY-DVS-Mgmt-$location $type"
$mgmt_nic1 = "0"
$mgmt_nic2 = "4"
$mgmt_portgroup = "MYDPG-Mgmt-204 $type"

$vmotion_vds = "MY-DVS-vMotion-$location $type"
$vmotion_nic1 = "1"
$vmotion_nic2 = "5"

$uplink_vds = "MY-DVS-PublicNetwork-$location $type"
$uplink_nic1 = "2"
$uplink_nic2 = "6"

$backup_vds = "MY-DVS-Backup-$location $type"
$backup_nic1 = "3"
$backup_nic2 = "7"


$domain = "domain.com", "username", "password"















do {

    Write-Host "Please review Parameters"
    Write-Host "_______________________________________________________________________"
    "`n"
    Write-Host "VMHost = $esxi"
    Write-Host "Type = $type"
    Write-Host "Datastore Name = $datastore_name"
    "`n"
    Write-Host "NTP = $ntp1, $ntp2"
    Write-Host "DNS = "$dnsAddress | ft IPaddress*
    "`n"
    Write-Host "MGMT VDS = $mgmt_vds"
    Write-Host "MGMT VDS nic = $mgmt_nic1, $mgmt_nic2"
    Write-Host "MGMT VDS portgroup = $mgmt_portgroup"
    "`n"
    Write-Host "VMOTION VDS = $vmotion_vds"
    Write-Host "VMOTION VDS nic = $vmotion_nic1, $vmotion_nic2"

    "`n"
    Write-Host "UPLINK VDS = $uplink_vds"
    Write-Host "UPLINK VDS nic = $uplink_nic1, $uplink_nic2"

    "`n"
    Write-Host "BACKUP VDS = $backup_vds"
    Write-Host "BACKUP VDS nic = $backup_nic1, $backup_nic2"
    
    "`n"
    Write-Host "_______________________________________________________________________"
    "`n"
    $confirm1 = ""
    while ($confirm1 -notmatch "[y|n]") {Write-Host -NoNewline  ">> Please confirm $esxi is ABSOLUTELY correct (Y/N)"; $confirm1 = Read-Host }


} While ($confirm1 -notmatch "[y|n]")
        if ($confirm1 -eq "n") {Write-Host "Bye bye"; break}



Write-Host "Testing $esxi connectivity..."
if ((Test-Connection $esxi -Count 4 -Quiet) -ne $true) { Write-Host "Ping $esxi failed. bye bye"; break}


if ((Get-VMHost $esxi).ConnectionState -eq "Maintenance") { Write-Host "$esxi in maintenance mode, proceeding..."}
    else { Write-Host "$esxi not in maintenance mode. bye bye"; break}






#Configure NTP server
Get-VMHostNtpServer -VMHost $esxi | ForEach {Remove-VMHostNtpServer $_} -Confirm:$false
Add-VmHostNtpServer -VMHost $esxi -NtpServer $ntp1
Add-VmHostNtpServer -VMHost $esxi -NtpServer $ntp2

#Allow NTP queries outbound through the firewall
Get-VMHostFirewallException -VMHost $esxi | where {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true

#Start NTP client service and set to automatic
Get-VmHostService -VMHost $esxi | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService
Get-VmHostService -VMHost $esxi | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "automatic"

#Set HostNetwork TCP/IP
Get-VMHostNetwork -VMHost $esxi | Set-VMHostNetwork -DomainName $domainName
Get-VMHostNetwork -VMHost $esxi | Set-VMHostNetwork -SearchDomain $searchDomain
Get-VMHostNetwork -VMHost $esxi | Set-VMHostNetwork -DnsAddress $dnsAddress


#Hostname
Get-VMHostNetwork -VMHost $esxi | Set-VMHostNetwork -HostName $hostname


Get-VMHost $esxi  | Get-Datastore | where-object {$_.name -match "datastore1"} | Set-Datastore -Name $datastore_name

############################################################################################################################################################



Add-VDSwitchVMHost -VDSwitch $mgmt_vds -VMHost $esxi -Confirm:$false
Get-VDSwitch $mgmt_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$mgmt_nic2) -Confirm:$false
Start-Sleep -Seconds 2
Set-VMHostNetworkAdapter -PortGroup (Get-VDPortgroup -name $mgmt_portgroup -VDSwitch $mgmt_vds) -VirtualNic (Get-VMHostNetworkAdapter -Name vmk0 -VMHost $esxi) -Confirm:$false
Start-Sleep -Seconds 1
Get-VDSwitch $mgmt_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$mgmt_nic1) -Confirm:$false
Start-Sleep -Seconds 1


Add-VDSwitchVMHost -VDSwitch $vmotion_vds -VMHost $esxi -Confirm:$false
Get-VDSwitch $vmotion_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$vmotion_nic1) -Confirm:$false
Start-Sleep -Seconds 1
Get-VDSwitch $vmotion_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$vmotion_nic2) -Confirm:$false
Start-Sleep -Seconds 1


Add-VDSwitchVMHost -VDSwitch $uplink_vds -VMHost $esxi -Confirm:$false
Get-VDSwitch $uplink_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$uplink_nic1) -Confirm:$false
Start-Sleep -Seconds 1
Get-VDSwitch $uplink_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$uplink_nic2) -Confirm:$false
Start-Sleep -Seconds 1


Add-VDSwitchVMHost -VDSwitch $backup_vds -VMHost $esxi -Confirm:$false
Get-VDSwitch $backup_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$backup_nic1) -Confirm:$false
Start-Sleep -Seconds 1
Get-VDSwitch $backup_vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic (Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic$backup_nic2) -Confirm:$false
Start-Sleep -Seconds 1

Get-VMHost $esxi | Get-VirtualSwitch -Standard | Remove-VirtualSwitch -Confirm:$false

# Hardware -> Power Management
(Get-View (Get-VMHost $esxi | Get-View).ConfigManager.PowerSystem).ConfigurePowerPolicy(1)

Write-Host "All done, bye bye"
