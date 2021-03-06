<#
.Synopsis
   get everything you want to know about any computer
.DESCRIPTION
   get inventory from a list of remote computers or run locally thru startup script
.EXAMPLE
   INV_DataCollection -EnumHardware
   get basic OS data + BIOS information
.EXAMPLE
   INV_DataCollection -EnumUsers
   get basic OS data + logged on user sessions
.EXAMPLE
   Get-Adcomputer workstation007 | INV_DataCollection -EnumDrivers
   get basic OS data + known system devices from an AD computer object
.INPUTS
   can handle pipeline input for computernames
.OUTPUTS
   nested object, can be converted to CLI XML or JSON for database processing
   can be piped to output
.NOTES
   advanced output thru nested custom objects,
   can contain functions that are still in beta
.COMPONENT
   Chriske.Inventory.Computer
.ROLE
   Inventory
.FUNCTIONALITY
   get all Windows OS info for network inventory
#>
[CmdletBinding(DefaultParameterSetName='EnumPart',SupportsShouldProcess=$true)]
Param (
[Parameter(Position=0,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$true,
ParameterSetName='EnumPart')]
[Parameter(Position=0,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$true,
ParameterSetName='EnumComplete')]
[Alias("Name","ComputerName")][string[]]$Computers=@($env:ComputerName),
[Parameter(ParameterSetName='EnumPart')][switch] $EnumHardware,
[Parameter(ParameterSetName='EnumPart')][switch] $EnumSoftware,
[Parameter(ParameterSetName='EnumPart')][switch] $EnumDrivers,
[Parameter(ParameterSetName='EnumPart')][switch] $EnumUsers,
[Parameter(ParameterSetName='EnumComplete')][switch] $EnumAll
)

process{
Write-Progress -activity "Getting Inventory report" -status "Starting" -id 1
foreach ($Computer in $Computers){
	[int]$pct = ($script:cntr / $Computers.count) * 100
	$NodeInfo = New-Object PSObject -Property @{
		Host = $Computer
		Date = (Get-Date)
		}
	if (Test-connection $Computer -quiet -count 1){
		Write-Progress -activity "Getting data" -status $Computer -id 1 -percent $pct -current "OS details..."
		write-verbose "Inventory report for $Computer"
		$NodeInfo | add-member NoteProperty -Name OS -Value (GetOS $Computer)
		$NodeInfo | add-member NoteProperty -Name POWER -Value (GetActivePowerPlan $Computer)
		$NodeInfo | add-member NoteProperty -Name Environment -Value (GetEnvVariables $Computer)
		$NodeInfo | add-member NoteProperty -Name WSMAN -Value (GetShares $Computer)
		if ($EnumHardware){
			Write-Progress -activity "Getting data" -status $Computer -id 1 -percent $pct -current "Hardware..."
			$NodeInfo | add-member NoteProperty -Name BIOS -Value (GetBIOS $Computer)
			$NodeInfo | add-member NoteProperty -Name CPU -Value (GetProcessor $Computer)
			$NodeInfo | add-member NoteProperty -Name RAM -Value (GetMemory $Computer)
			$NodeInfo | add-member NoteProperty -Name DISK -Value (GetLocalDisk $Computer)
			$NodeInfo | add-member NoteProperty -Name LAN -Value (GetNIC $Computer)
			}
		if ($EnumDrivers){
			Write-Progress -activity "Getting data" -status $Computer -id 1 -percent $pct -current "Drivers..."
			$NodeInfo | add-member NoteProperty -Name VGA -Value (GetGraphics $Computer)
			$NodeInfo | add-member NoteProperty -Name AUDIO -Value (GetAudio $Computer)
			}
		if ($EnumSoftware){
			Write-Progress -activity "Getting data" -status $Computer -id 1 -percent $pct -current "Software..."
			$NodeInfo | add-member NoteProperty -Name SOFT -Value (GetApps $Computer)
			$NodeInfo | add-member NoteProperty -Name WUPD -Value (GetUpdates $Computer)
			$NodeInfo | add-member NoteProperty -Name SCHED -Value (GetSchedTasks $Computer)
			}
		if ($EnumUsers){
			Write-Progress -activity "Getting data" -status $Computer -id 1 -percent $pct -current "Sessions..."
			$NodeInfo | add-member NoteProperty -Name USERS -Value (GetLoggedOnUsers $Computer)
			}
		$Result = "Success"
		}
	else {
		Write-Progress -activity "Getting data" -status $Computer -id 1 -percent $pct -current "Unreachable..."
		write-error "$Computer cannot be reached"
		$Result = "Unreachable"
		}
	$script:cntr++
	$NodeInfo | add-member NoteProperty -Name Result -Value $Result
	$script:outInv += $NodeInfo
	}#foreach
}#process

begin{
$script:outInv = @()
$script:cntr = 1
#EnumAll sets all switches to True
if ($EnumAll){$EnumHardware = $EnumSoftware = $EnumDrivers = $EnumUsers = $True}

Function CheckAdmin{
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

Function CheckRemote ($Computer){
[Bool](Invoke-Command -ComputerName $Computer -ScriptBlock {1} -EA SilentlyContinue)
}

Function GetOS ($Computer){
$SysData = Get-WMIObject -ComputerName $Computer -class Win32_Computersystem
$OSData = Get-WMIObject -ComputerName $Computer -class Win32_operatingsystem
$bits = (Gwmi -Class Win32_Processor -ComputerName $Computer).AddressWidth
$ProductInfo = (WindowsProduct $Computer $bits)
$DomainRole = "Stand alone workstation","Member workstation","Stand alone server","Member server","Backup DC","Primary DC"
$Result = New-Object PSObject -Property @{
	HostName = $SysData.Name
	Domain = $SysData.Domain
	PCType = ($SysData.description + $SysData.systemtype)
	Model = $SysData.Model
	CPUSockets = $SysData.NumberOfProcessors
	LogicCPU = $SysData.NumberOfLogicalProcessors
	Memory = "$([math]::round($($OSData.TotalVisibleMemorySize/1024))) MB"
	OSVersion = ($OSData.Caption + " SP" + $OSData.ServicePackMajorVersion) + " " + $bits + "bit"
	InstallDate = [System.Management.ManagementDateTimeconverter]::ToDateTime($OSData.InstallDate).ToLongDateString()
	WinDir = $OSData.WindowsDirectory
	IsDomainMember = $([System.Convert]::ToBoolean($SysData.partofdomain))
	Role = ($DomainRole[$SysData.DomainRole])
	ProductID = $ProductInfo.ProductID
	ProductKey = $ProductInfo.ProductKey
	Build = $OSData.Version
	BuildType = $OSData.BuildType
	LastBoot = [System.Management.ManagementDateTimeconverter]::ToDateTime($OSData.LastBootUpTime).ToLongDateString()
	}
return $Result
}

Function GetBIOS ($Computer){
$Result = New-Object PSObject -Property @{}
$x = 0
foreach ($bios in (get-wmiobject -ComputerName $Computer -class "Win32_BIOS")){
	$Result | add-member NoteProperty -Name "$("Manufacturer_$x")" -Value $bios.Manufacturer
	$Result | add-member NoteProperty -Name "$("Description_$x")" -Value $bios.Description
	$Result | add-member NoteProperty -Name "$("Version_$x")" -Value $bios.SMBIOSBIOSVersion
	$Result | add-member NoteProperty -Name "$("ReleaseDate_$x")" -Value $([System.Management.ManagementDateTimeconverter]::ToDateTime($bios.ReleaseDate).ToLongDateString())
	$Result | add-member NoteProperty -Name "$("SerialNr_$x")" -Value $bios.SerialNumber
	$x++
	}
	return $Result
}

Function GetModel ($Computer){
$model = Get-WmiObject -ComputerName $Computer win32_computersystemproduct
$Result = New-Object PSObject -Property @{
	Vendor = $model.Vendor
	ModelType = $model.Name
	Version = $model.Version
	IdNumber = $model.IdentifyingNumber
	UUID = $model.UUID
	}
return $Result
}

Function WindowsProduct ($Computer,$bits){
## retrieve Windows Product Key from any PC by Jakob Bindslet (jakob@bindslet.dk)
[hashtable]$Result = @{}
$hklm = 2147483650
$regPath = "Software\Microsoft\Windows NT\CurrentVersion"
$rr = [WMIClass]"\\$Computer\root\default:stdRegProv"
if ($bits -eq 64){$DigitalProductId = "DigitalProductId4"}
else {$DigitalProductId = "DigitalProductId"}
try{
	$data = $rr.GetBinaryValue($hklm,$regPath,$DigitalProductId)
	$binArray = ($data.uValue)[52..66]
	$charsArray = "B","C","D","F","G","H","J","K","M","P","Q","R","T","V","W","X","Y","2","3","4","6","7","8","9"
	## decrypt base24 encoded binary data
	For ($i = 24; $i -ge 0; $i--) {
		$k = 0
		For ($j = 14; $j -ge 0; $j--) {
			$k = $k * 256 -bxor $binArray[$j]
			$binArray[$j] = [math]::truncate($k / 24)
			$k = $k % 24
			}
		$ProductKey = $charsArray[$k] + $ProductKey
		If (($i % 5 -eq 0) -and ($i -ne 0)){$ProductKey = "-" + $ProductKey}
		}
	}
catch{$ProductKey = "nothing"}
try{$ProductID = ($rr.GetStringValue($hklm,$regPath,"ProductId")).svalue}
catch{$ProductID = "nothing"}
$Result.ProductKey = $ProductKey
$Result.ProductID = $ProductID
return $Result
}

Function GetProcessor ($Computer){
$Result = New-Object PSObject -Property @{}
try {
	$ErrorActionPreference = "Stop"
	$x=0
	foreach ($CPU in (Get-WMIObject -ComputerName $Computer -Class Win32_processor)){
		$Result | add-member NoteProperty -Name "$("Manufacturer_$x")" -Value ($CPU.manufacturer + " " + $CPU.name)
		$Result | add-member NoteProperty -Name "$("AddressWidth_$x")" -Value ($CPU.AddressWidth).ToString()
		$Result | add-member NoteProperty -Name "$("ClockSpeed_$x")" -Value ($CPU.MaxClockSpeed).ToString()
		$Result | add-member NoteProperty -Name "$("Cores_$x")" -Value ($CPU.NumberOfCores).ToString()
		$Result | add-member NoteProperty -Name "$("L2Cache_$x")" -Value ($CPU.L2CacheSize).ToString()
		$x++
		}
	}
catch{}
return $Result
$ErrorActionPreference = "Continue"
}

Function GetEnvVariables ($Computer){
$Result = New-Object PSObject -Property @{}
$x=0
foreach ($Envir in (gwmi -ComputerName $Computer -class Win32_Environment| ?{$_.username -eq '<system>'})){
	$Result | add-member NoteProperty -Name "$("Name_$x")" -Value $Envir.Name
	$Result | add-member NoteProperty -Name "$("Path_$x")" -Value $Envir.VariableValue
	$x++
	}#foreach
return $Result
}

function GetActivePowerPlan ($Computer){
write-verbose "Getting active plan..."
try{$Result = gwmi -Class Win32_PowerPlan -Namespace root\cimv2\power -ComputerName $Computer -Filter "IsActive ='True'" | select ElementName,Description,IsActive}
catch{$Result = "nothing"}
return $Result
}

Function GetSpecialFolders(){ #can this work from remote?
$Folders = New-Object PSObject -Property @{}
$x=0
foreach ($SpecialFolder in (@([system.Enum]::GetValues([System.Environment+SpecialFolder])))){
	$Folders | add-member NoteProperty -Name "$("Specialfolder_$x")" -Value $Specialfolder
	$Folders | add-member NoteProperty -Name "$("Path_$x")" -Value $([Environment]::getfolderpath($SpecialFolder))
	$x++
	}#foreach
return $Folders
}

Function GetLocalDisk ($Computer){
$Disks = New-Object PSObject -Property @{}
$x=0
foreach ($Disk in (Get-WMIObject -ComputerName $Computer -class Win32_Logicaldisk)){
	$Disks | add-member NoteProperty -Name "$("DriveLetter_$x")" -Value $Disk.caption
	$Disks | add-member NoteProperty -Name "$("Description_$x")" -Value $Disk.description
	$Disks | add-member NoteProperty -Name "$("Label_$x")" -Value $Disk.VolumeName
	$Disks | add-member NoteProperty -Name "$("FileSystem_$x")" -Value $Disk.FileSystem
	$Disks | add-member NoteProperty -Name "$("Compressed_$x")" -Value $Disk.compressed
	$Disks | add-member NoteProperty -Name "$("Size_$x")" -Value ([math]::round(($Disk.size / 1073741824),2))
	$Disks | add-member NoteProperty -Name "$("FreeSpace_$x")" -Value ([math]::round(($Disk.freespace / 1073741824),2))
	$Disks | add-member NoteProperty -Name "$("VolumeDirty_$x")" -Value $Disk.volumedirty
	$Disks | add-member NoteProperty -Name "$("VolumeName_$x")" -Value $Disk.volumename
	$x++
	}
return $Disks
}

Function GetPartitions ($Computer){
$Partitions = New-Object PSObject -Property @{}
$x=0
foreach ($Partition in (Get-WmiObject -Class Win32_DiskPartition -ComputerName $Computer)){
	$Partitions | add-member NoteProperty -Name "$("BlockSize_$x")" -Value $Partition.BlockSize
	$Partitions | add-member NoteProperty -Name "$("Bootable_$x")" -Value $Partition.Bootable
	$Partitions | add-member NoteProperty -Name "$("BootLoader_$x")" -Value $Partition.BootPartition
	$Partitions | add-member NoteProperty -Name "$("DeviceID_$x")" -Value $Partition.DeviceID
	$Partitions | add-member NoteProperty -Name "$("Primary_$x")" -Value $Partition.PrimaryPartition
	$Partitions | add-member NoteProperty -Name "$("OffsetAlignment_$x")" -Value $([bool]($Partition.StartingOffset % 4096))
	$Partitions | add-member NoteProperty -Name "$("SizeGB_$x")" -Value $([Math]::Round($Partition.Size/1GB))
	$x++
	}
return $Partitions
}

Function GetMemory ($Computer){
$RAMs = @()
# Memory type constants from win32_pysicalmemory.MemoryType
$RAMtypes = "Unknown", "Other", "DRAM", "Synchronous DRAM", "Cache DRAM", "EDO", "EDRAM", "VRAM", "SRAM", "RAM", "ROM", "Flash", "EEPROM", "FEPROM", "EPROM", "CDRAM", "3DRAM", "SDRAM", "SGRAM", "RDRAM", "DDR", "DDR-2"
foreach ($RAM in (Get-WMIObject -ComputerName $Computer -class Win32_PhysicalMemory)){
    $Result = New-Object PSObject -Property @{
		PartNR = $RAM.PartNumber
		CapacityMB = ($RAM.Capacity / 1073741.824)
		Speed = $RAM.Speed
		MemType = ($RAMtypes[$RAM.MemoryType])
		Location = $RAM.DeviceLocator
		}
    $RAMs += $Result
	}
return $RAMs
}

Function GetGraphics ($Computer){
$displays = @()
foreach ($display in (Get-WMIObject -ComputerName $Computer -class Win32_VideoController)){
	$Result = New-Object PSObject -Property @{
		DisplayName = $display.Name
		DriverVersion = $display.DriverVersion
		ColorDepth = $display.CurrentBitsPerPixel
		Resolution = $display.VideoModeDescription
		RefreshRate = "$($display.CurrentRefreshRate) Hz"
		}
	$displays += $result
	}
return $displays
}

Function GetAudio ($Computer){
$soundcards = @()
foreach ($soundcard in (Get-WMIObject -ComputerName $Computer -class win32_SoundDevice)){
	$Result = New-Object PSObject -Property @{
		Caption = $soundcard.Caption
		Manufacturer = $soundcard.manufacturer
		# $Filter = "DeviceID -eq '" + $soundcard.DeviceID + "'"
		# $PNPdriver = Get-WMIObject -ComputerName $Computer -class Win32_PNPSignedDriver -Filter $Filter
		# DriverName = $PNPdriver.DriverName
		# DriverVersion = $PNPdriver.DriverVersion
		# $DriverDate = [System.Management.ManagementDateTimeconverter]::ToDateTime($PNPdriver.DriverDate).ToShortDateString()
		# DriverDate = $DriverDate
		}
	$soundcards += $Result
	}
return $soundcards
}

Function GetNIC ($Computer){
$NICs = @()
foreach ($NIC in (gwmi -ComputerName $Computer -class win32_networkadapter | ?{$_.MACAddress -ne $null})){
	$NICs += New-Object PSObject -Property @{
		AdapterName = $NIC.Name
		AdapterType = $NIC.AdapterType
		MacAddress = $NIC.MACAddress
		Manufacturer = $NIC.Manufacturer
		PhysicalAdapter = ([System.Convert]::ToBoolean($NIC.PhysicalAdapter))
		NetworkEnabled = ([System.Convert]::ToBoolean($NIC.NetEnabled))
		ConnectedNetwork = $NIC.NetConnectionID
		}
	}#foreach
return $NICs
}

Function GetShares($Computer){
$Result = New-Object PSObject -Property @{}
$x=0
$ShareTypes = @{"2147483648"="admin";"2147483649"="print";"0"="file";"2147483651"="ipc"};
foreach ($Share in (gwmi -ComputerName $Computer -class Win32_Share)){
	$ShareType = $Share.Type.ToString()
	$Result | add-member NoteProperty -Name "$("Name_$x")" -Value $Share.Name
	$Result | add-member NoteProperty -Name "$("Type_$x")" -Value $ShareTypes[$ShareType] 
	$x++
	}
return $Result
}

Function GetStartUpApps($Computer){
$StartUpApps = @()
$hkcr = 2147483648 #Classes Root
$hkcu = 2147483649 #Current User
$hklm = 2147483650 #Local Machine
$hku = 2147483652 #Users
$hkcc = 2147483653 #Current Config
$rr = [WMIClass]"\\$Computer\root\default:stdRegProv"
#$StartupCommands = (gwmi -ComputerName $Computer -class "Win32_StartupCommand")
#enum of registry items under run key
$regPath = "Software\Microsoft\Windows\CurrentVersion"
$HKLMApps = @($rr.GetStringValue($hklm,$regPath,"Run"))
foreach ($HKLMApp in $HKLMApps){
	$StartUpApps += New-Object PSObject -Property @{
		StartUpType = "HKLM"
		}
	}
$HKCUApps = @($rr.GetStringValue($hkcu,$regPath,"Run"))
foreach ($HKCUApp in $HKCUApps){
	$StartUpApps += New-Object PSObject -Property @{
		StartUpType = "HKCU"
		}
	}
$MachineRuns = ""
foreach ($MachineRun in $MachineRuns){
	$StartUpApps += New-Object PSObject -Property @{
		StartUpType = "AllUsers"
		}
	}
$UserRuns = ""
foreach ($UserRun in $UserRuns){
	$StartUpApps += New-Object PSObject -Property @{
		StartUpType = "User"
		}
	}
return $StartUpApps
}

Function GetApps ($Computer){
#$ProductUsers = dir hklm:\software\microsoft\windows\currentversion\installer\userdata
#$Products = $ProductUsers |% {$p = [io.path]::combine($_.pspath, 'Products'); if (test-path $p){dir $p}}
#$ProductInfos = $Products |% {$p = [io.path]::combine($_.pspath, 'InstallProperties'); if (test-path $p){gp $p}}
$Products = (gwmi -class Win32_Product -ComputerName $Computer | select Name, Version, ProductID, Vendor, InstallDate, InstallSource)
return $Products
}

Function GetUpdates ($Computer){
$Updates = @()
foreach ($Update in (gwmi -ComputerName $Computer -class "Win32_QuickFixEngineering")){
	$Result = New-Object PSObject -Property @{
		HotFixID = $Update.HotFixID
		HotFixType = $Update.Description
		InstallDate = $Update.InstalledOn
		InstalledBy = $Update.InstalledBy
		}
	$Updates += $Result
	}
	return $Updates
}

Function GetSwapFile ($Computer){
$SwapFiles = @()
foreach($SwapFile in (gwmi -class Win32_PageFile -ComputerName $Computer)){
    $SwapFiles += New-Object PSObject -Property @{
	    Name         = $PageFile.Name
	    SizeGB       = [int]($PageFile.FileSize / 1GB)
	    InitialSize  = $PageFile.InitialSize
	    MaximumSize  = $PageFile.MaximumSize
	    }
    return $SwapFiles
    }
}

Function GetSchedTasks($Computer){
$SchedService = New-Object -ComObject Schedule.Service
$TaskStatus = "Unknown","Disabled","Queued","Ready","Running"
$SchedTasks = @()
write-verbose "Getting scheduled tasks for $Computer"
Try{
	#Defining Schedule.Service Variable as COM object and connecting to...
	$SchedService = New-Object -ComObject Schedule.Service
	$SchedService.Connect($Computer)
	$RootTasks = $SchedService.GetFolder("").GetTasks("")
	Foreach ($Task in $RootTasks) {
		$SchedTasks += New-Object PSObject -Property @{
			TaskName = $Task.Name
			RunAs = (([xml]$Task.Xml).DocumentElement.Principals.Principal.UserID).Trim()
			Enabled = $Task.Enabled
			Status = $TaskStatus[$Task.State]
			LastRunTime = $Task.LastRunTime
			Result = $Task.LastTaskResult
			NextRunTime = $Task.NextRunTime
			}
		}
	}
Catch {write-error "for $([string]$Computer): $($Error[0].Exception)"}
return $SchedTasks
}

Function GetServices($Computer){
$Services = @()
try{
	foreach ($Service in (Get-WmiObject -Class Win32_Service -ComputerName $Computer)){
		$Result = New-Object PSObject -Property @{
			Displayname = $Service.DisplayName
			ServiceAccount = $Service.StartName
			State = $Service.State
			StartMode = $Service.StartMode
			}
		if ($Service.DisplayName){$Services += $Result}
		}
	}
Catch {}
return $Services
}

Function GetSessions ($Computer){
$LocalSessions = @()
$regex = '.+Domain="(.+)",Name="(.+)"$'
try{
	foreach ($Session in (Get-WmiObject Win32_LoggedOnUser -ComputerName $Computer | Select Antecedent -Unique)){
		$Session.Antecedent -match $regex
		$LocalSessions += New-Object PSObject -Property @{
			Domain = $matches[1]
			User = $matches[2]
			}
		}
	}
catch{}
return $LocalSessions
}

Function GetLoggedOnUsers ($Computer, $Process = "explorer.exe"){
$LoggedOnUsers = @()
try{
	foreach ($Session in (Get-WMIObject Win32_Process -filter "name='$Process'" -ComputerName $Computer)){
		$owner = $Session.GetOwner()
		$LoggedOnUsers += New-Object PSObject -Property @{
			Domain = $owner.Domain
			User = $owner.User
			SessionID = $Session.SessionID
			WorkingDir = $Session.ExecutablePath #Path
			SessionStartDate = [System.Management.ManagementDateTimeconverter]::ToDateTime($Session.CreationDate).ToLongDateString()
			}
		}
	}
catch{}
return $LoggedOnUsers | Sort-Object | Get-Unique
}

}#begin

end{
if (-not $EnumHardware){write-warning "Enumeration of hardware was not enabled"}
if (-not $EnumDrivers){write-warning "Enumeration of drivers was not enabled"}
if (-not $EnumSoftware){write-warning "Enumeration of software was not enabled"}
if (-not $EnumUsers){write-warning "Enumeration of users was not enabled"}
write-host "End of inventory script" -fore green
$script:outInv
}