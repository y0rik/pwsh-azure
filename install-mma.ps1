param (
    [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$WorkSpaceID,
    [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$WorkSpaceKey,
    [parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][string]$rootFolder = 'C:\tmp'
)

function Test-MMAInstallation {
    $installedProd = Get-WmiObject win32_Product | where{$_.Name -eq 'Microsoft Monitoring Agent'}
    if ($installedProd) {return $true}
    else {return $false}
}
function Test-ExistingMMAWorkspace {
    param (
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ws
    )
    $mmaWSFound = $false

    $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
    $mmaWSs = $mma.GetCloudWorkspaces()
    $mmaWSs | %{if ($_.workspaceId -eq "$ws") {$mmaWSFound = $true} }
    return $mmaWSFound
}

# set paths
$mmaFileName = "MMASetup-AMD64.exe"
$mmaFullPath = Join-Path -Path "$rootFolder" -ChildPath "$mmaFileName"
$mmaLogPullPath = "c:\MMAInstallLog-$((get-date).tostring('yyyyddMM_HHmmss')).txt"
$mmaURL = "http://download.microsoft.com/download/1/5/E/15E274B9-F9E2-42AE-86EC-AC988F7631A0/MMASetup-AMD64.exe"

# start logging the actions
Start-Transcript -Path "$mmaLogPullPath" -NoClobber

# check if installed
$mmaInstalled = Test-MMAInstallation

if ($mmaInstalled) {
    Write-Host "MMA already installed"
    Write-Host "Checking the workspace: $WorkSpaceID"
    $mmaWSExists = Test-ExistingMMAWorkspace -ws "$WorkSpaceID"
    if ($mmaWSExists) {
        # NO ACTION
        Write-Host "The workspace is already added: $WorkSpaceID"
    }
    else {
        # ADD WORKSPACE
        Write-Host "Adding the workspace: $WorkSpaceID" -NoNewline
        $added = $true
        try {
            $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
            $mma.AddCloudWorkspace("$WorkSpaceID", "$WorkSpaceKey")
            $mma.ReloadConfiguration()
        }
        catch {
            $added = $false
            $err = $_.Exception.Message
        }
        if ($added) {Write-Host "`tdone!" -ForegroundColor Green}
        else {
            Write-Host "`tfailed!" -ForegroundColor Red
            Write-Error $err
        }
    }
}
else {
    # INSTALL
    # check if folder exists, if not, create it
    if (Test-Path -Path "$rootFolder") {
        Write-Host "Root folder already exists: $rootFolder"
    } 
    else 
    {
        Write-Host "Creating root folder: $rootFolder" -NoNewline
        $created = $true
        try {$null = New-Item -Path "$rootFolder" -type Directory}
        catch {
            $created = $false
            $err = $_.Exception.Message
        }
        if ($created) {Write-Host "`tdone!" -ForegroundColor Green}
        else {
            Write-Host "`tfailed!" -ForegroundColor Red
            Write-Error $err
        }
    }

    # check if MMA file exists, if not, download it
    if (Test-Path -Path "$mmaFullPath") {
        Write-Host "MMA file exists: $mmaFullPath"
    }
    else {
        Write-Host "MMA file doesn't exist, downloading: $mmaFullPath" -NoNewline
        $downloaded = $true
        try {$null = Invoke-WebRequest -Uri "$mmaURL" -OutFile "$mmaFullPath" -UseBasicParsing}
        catch {
            $downloaded = $false
            $err = $_.Exception.Message
        }
        if ($downloaded) {Write-Host "`tdone!" -ForegroundColor Green}
        else {
            Write-Host "`tfailed!" -ForegroundColor Red
            Write-Error $err
        }
    }

    # install the Microsoft Monitoring Agent
    Write-Host "installing MMA.." -nonewline
    $ArgumentList = '/C:"setup.exe /qn ADD_OPINSIGHTS_WORKSPACE=1 '+  "OPINSIGHTS_WORKSPACE_ID=$WorkspaceID " + "OPINSIGHTS_WORKSPACE_KEY=$WorkSpaceKey " +'AcceptEndUserLicenseAgreement=1"'
    $installed = $true
    try {$null = Start-Process "$mmaFullPath" -ArgumentList $ArgumentList -ErrorAction Stop -Wait}
    catch {
        $installed = $false
        $err = $_.Exception.Message
    }

    if ($installed) {Write-Host "`tdone!" -ForegroundColor Green}
    else {
        Write-Host "`tfailed!" -ForegroundColor Red
        Write-Error $err
    }
}

# stop transcript
Stop-Transcript