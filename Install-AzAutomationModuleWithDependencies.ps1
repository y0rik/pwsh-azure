function Check-InstalledModule {
    <#
    .SYNOPSIS
        Checks if a module is installed for Azure Automation resource. If the module has older version than required - removes the module
    .DESCRIPTION
        Checks if a module is installed for Azure Automation resource. If the module has older version than required - removes the module
    .PARAMETER AutomationAccountName
        Target Azure automation account's name
    .PARAMETER ResourceGroupName
        Target Azure automation account's resource group
    .PARAMETER ModuleName
        Module name
    .PARAMETER ModuleVersion
        Module version
    .OUTPUTS
        Returns [bool] or Error/[string] data depending on circumstances
            [bool]$true - the module is found and satisfies version parameter
            [bool]$false - the module is not installed or has been removed due to its version
            [string]/error - in case of errors
    .EXAMPLE
        Check-InstalledModule -AutomationAccountName 'SampleAutomation' -ResourceGroupName 'SampleRG' -ModuleName 'Az.Accounts' -ModuleVersion '1.8'
        Checking if SampleAutomation automation accound belonging to SampleRG resource group has Az.Accounts module with ver. 1.8 or higher
    #>
    #Requires -Module 'Az.Automation'
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$AutomationAccountName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModuleName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModuleVersion
    )

    # check if connected to azure context
    if (-not $(Get-Azcontext)) {
        Write-Error "No subscription found in the context.  Please ensure that the credentials you provided are authorized to access an Azure subscription, then run Connect-AzAccount to login."
    }

    $Return = $false

    # check if module exists
    $ModuleExists = Get-AzAutomationModule -AutomationAccountName "$AutomationAccountName" -ResourceGroupName "$ResourceGroupName" `
                                            -Name "$ModuleName" -ErrorAction SilentlyContinue

    if ($ModuleExists) {
    # check the version
        if ([version]$ModuleExists.Version -ge [version]$ModuleVersion) {
            $Return = $true
        }
        else {
            Write-Warning "The module is installed, but it has version issues: $($ModuleExists.Version)"

            Write-Host "Removing Module: " -NoNewline
            Write-Host "$($ModuleExists.Name)" -ForegroundColor Yellow -NoNewline
            Write-Host "; Version:" -NoNewline
            Write-Host "$($ModuleExists.Version)" -ForegroundColor Yellow -NoNewline
            Write-Host "; AutomationAccountName:" -NoNewline
            Write-Host "$AutomationAccountName" -ForegroundColor Yellow -NoNewline
            Write-Host "; ResourceGroupName:" -NoNewline
            Write-Host "$ResourceGroupName" -ForegroundColor Yellow

            # removing
            try {
                Remove-AzAutomationModule -AutomationAccountName "$AutomationAccountName" -ResourceGroupName "$ResourceGroupName" `
                                            -Name "$ModuleName" -ErrorAction SilentlyContinue -Force
            }
            catch {
                # error handling
                Write-Error $_.Exception
                return $_.Exception
            }

            # verification
            $Timeout = 90
            $Timer = 0
            $Step = 2
            do {
                Write-Host '.' -NoNewline
                Start-Sleep -Seconds $Step
                $Timer += $Step

                $ModuleExists = Get-AzAutomationModule -AutomationAccountName "$AutomationAccountName" -ResourceGroupName "$ResourceGroupName" `
                                                        -Name "$ModuleName" -ErrorAction SilentlyContinue
            } while (($null -ne $ModuleExists) -or ($Timer -lt $Timeout))

            Write-Host ''

            # checking verification timeout
            if ($ModuleExists -and ($Timer -ge $Timeout)) {
                $Err = "Error removing the module, existed on timout: $Timeout"
                Write-Error $Err
                return $Err
            }
            else {Write-Host 'Removed'}
        }

    }

    return $Return
}

function Get-ModuleDependenciesRecursively {
    <#
    .SYNOPSIS
        Searches a module dependencies recursively utilising PowerShellGet module and returns the list as a custom object
    .DESCRIPTION
        Searches a module dependencies recursively utilising PowerShellGet module and returns the list as a custom object
    .PARAMETER ModuleName
        Root module name
    .PARAMETER Level
        Recursivity level for each run, helps to build installation sequesnce
    .PARAMETER MinVersion
        Module minimum version
    .PARAMETER ReqVersion
        Module required version
    .PARAMETER RepositoryName
        Repository name to search in
    .OUTPUTS
        Returns ps custom object with all dependencies recursively
    .EXAMPLE
        Get-ModuleDependenciesRecursively -ModuleName 'Az' -Level 0 -ReqVersion 1.5.5 -RepositoryName 'PSGallery'
        Searching for all dependencies for Az module with required version 1.5.5 in PSGallery repository
    #>
    #Requires -Module PowerShellGet
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModuleName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][int]$Level,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string]$MinVersion,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string]$ReqVersion,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RepositoryName
    )

    # check if connected to azure context
    if (-not $(Get-Azcontext)) {
        Write-Error "No subscription found in the context.  Please ensure that the credentials you provided are authorized to access an Azure subscription, then run Connect-AzAccount to login."
    }

    # collection of modules to return
    $ModulesToReturn = @()

    # get the module
    if ($ReqVersion) {
        $Module = Find-Module -Name "$ModuleName" -RequiredVersion "$ReqVersion" -Repository "$RepositoryName"
    }
    else {
        $Module = Find-Module -Name "$ModuleName" -Repository "$RepositoryName"
    }

    # check min version
    if ($MinVersion) {
        if ([version]$($Module.Version) -lt [version]$MinVersion) {
            Write-Error "Module:'$($Module.Name)', ModuleVersion:'$($Module.Version)' found in RepositoryName:'$($Module.Repository)' is less than MininumVersion:'$MinVersion'"
            return $null
        }
    }

    $ModulesToReturn += [pscustomobject]@{
                                            Name = "$($Module.Name)"
                                            Version = "$($Module.Version)"
                                            Repository = "$($Module.Repository)"
                                            Priority = $Level
                                        }

    # get root module's dependencies
    $ModuleDependencies = $Module.Dependencies

    foreach ($Dependency in $ModuleDependencies) {
        # set $RequiredVersion
        if ($Dependency.RequiredVersion) {
            $ModulesToReturn += Get-ModuleDependenciesRecursively -ModuleName "$($Dependency.Name)" -ReqVersion "$($Dependency.RequiredVersion)" `
                                            -RepositoryName "$($Module.Repository)" -Level $($Level+1)
        }
        elseif ($Dependency.MinimumVersion) {
            $ModulesToReturn += Get-ModuleDependenciesRecursively -ModuleName "$($Dependency.Name)" -MinVersion "$($Dependency.MinimumVersion)" `
                                            -RepositoryName "$($Module.Repository)" -Level $($Level+1)
        }
        else {
            $ModulesToReturn += Get-ModuleDependenciesRecursively -ModuleName "$($Dependency.Name)" `
                                            -RepositoryName "$($Module.Repository)" -Level $($Level+1)
        }
    }

    return $ModulesToReturn
}

function Install-AzAutomationModuleWithDependencies {
        <#
    .SYNOPSIS
        Installs Azure automation account module with all dependencies recursively
        Can be used with -ResolveOnly switch only to resolve and show the dependencies
    .DESCRIPTION
        Installs Azure automation account module with all dependencies recursively
        Can be used with -ResolveOnly switch only to resolve and show the dependencies
    .PARAMETER AutomationAccountName
        Target Azure automation account's name
    .PARAMETER ResourceGroupName
        Target Azure automation account's resource group
    .PARAMETER ModuleName
        Module name
    .PARAMETER ModuleVersion
        Module version
    .PARAMETER RepositoryName
        Repository name to search in. By default it's 'PSGallery'
    .PARAMETER ResolveOnly
        Allows to resolve dependencies and output them without installing the modules 
    .OUTPUTS

    .EXAMPLE
        Install-AzAutomationModuleWithDependencies -AutomationAccountName 'SampleAutomation' -ResourceGroupName 'SampleRG' -ModuleName 'Az'
        Installs latest Az module version with all dependencies into SampleAutomation automation account belonging tp SampleRG resource group
    .EXAMPLE
        Install-AzAutomationModuleWithDependencies -AutomationAccountName 'SampleAutomation' -ResourceGroupName 'SampleRG' -ModuleName 'Az.Accounts' -ModuleVersion '1.8' -ResolveOnly
        Resolves dependencies for Az.Accounts ver 1.8 without installing the module and its dependencies
    #>
    #Requires -Module 'PowerShellGet','Az.Automation'
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$AutomationAccountName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModuleName,
        [Parameter(Mandatory = $false)][string]$ModuleVersion,
        [Parameter(Mandatory = $false)][string]$RepositoryName = 'PSGallery',
        [Parameter(Mandatory = $false)][switch]$ResolveOnly
    )

    # check if connected to azure context
    if (-not $(Get-Azcontext)) {
        Write-Error "No subscription found in the context.  Please ensure that the credentials you provided are authorized to access an Azure subscription, then run Connect-AzAccount to login."
    }

    if ($ResolveOnly) {Write-Warning "No modules will be installed, the script is running in ResolveOnly mode"}
    Write-Host "Searching for root module..."

    # get root module 
    if ($ModuleVersion) {
        $RootModule = Find-Module -Name "$ModuleName" -RequiredVersion "$ModuleVersion" -Repository "$RepositoryName"
    }
    else {
        $RootModule = Find-Module -Name "$ModuleName" -Repository "$RepositoryName"
    }

    Write-Host "Root module found: " -NoNewline
    Write-Host "$($RootModule.Name)" -ForegroundColor Yellow -NoNewline
    Write-Host "; Version:" -NoNewline
    Write-Host "$($RootModule.Version)" -ForegroundColor Yellow -NoNewline
    Write-Host "; Repository: " -NoNewline
    Write-Host "$($RootModule.Repository)" -ForegroundColor Yellow

    Write-Host "Resolving dependencies..."
    # initiate recursive dependencies search
    if ($RootModule) {
        $ModulesInstallationList = Get-ModuleDependenciesRecursively -ModuleName "$($RootModule.Name)" `
                                            -ReqVersion "$($RootModule.Version)" -RepositoryName "$($RootModule.Repository)" -Level 0
    }
    else {
        Write-Error "Module:'$ModuleName', ModuleVersion:'$ModuleVersion' canot be found in RepositoryName:'$RepositoryName'"
        Exit 1
    }

    # sort the modules in their installation sequence and get only unique items
    $ModulesInstallationList = $ModulesInstallationList | Sort-Object Priority -Descending | Select-Object Name, Version, Repository, Priority -Unique

    # get deployment phases
    $DeploymentPhases = $ModulesInstallationList.Priority | Get-Unique | Sort-Object -Descending

    Write-Host "Modules found: " -NoNewline
    Write-Host "$($ModulesInstallationList.count)" -ForegroundColor Yellow
    $ModulesInstallationList | Format-Table -AutoSize

    # if we di the actual installation
    if (-not $ResolveOnly) {
        Write-Host "Processing..."
        foreach ($Phase in $DeploymentPhases) {
            Write-Host "Deployment phase: " -NoNewline; Write-Host "$Phase" -ForegroundColor Yellow

            $ModulesInstallationPhase = $ModulesInstallationList.where({$_.Priority -eq $Phase})
            # installation
            foreach ($Module in $ModulesInstallationPhase) {

                Write-Host "Installing Module: " -NoNewline
                Write-Host "$($Module.Name)" -ForegroundColor Yellow -NoNewline
                Write-Host "; Version:" -NoNewline
                Write-Host "$($Module.Version)" -ForegroundColor Yellow -NoNewline
                Write-Host "; Repository: " -NoNewline
                Write-Host "$($Module.Repository)" -ForegroundColor Yellow

                # check if the module exists
                $ModuleExists = Check-InstalledModule -AutomationAccountName "$AutomationAccountName" -ResourceGroupName "$ResourceGroupName" `
                                                -ModuleName "$($Module.Name)" -ModuleVersion "$($Module.Version)"
                if ($ModuleExists -is [bool]) {
                    if ($ModuleExists) {
                        Write-Host "Skipped, already installed"
                    }
                    else {
                        try {
                            $null = New-AzAutomationModule -AutomationAccountName "$AutomationAccountName" -ResourceGroupName "$ResourceGroupName" `
                                        -Name "$($Module.Name)" -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$($Module.Name)/$($Module.Version)" -ErrorAction Stop
                        }
                        catch {
                            # error handling
                            Write-Error $_.Exception
                            return $_.Exception
                        }
                        Write-Host "Installation initiated"
                    }
                }
                else {Exit}

            }

            # verification
            $Timeout = 300 + ($ModulesInstallationPhase.count * 10)
            $Timer = 0
            $Step = 5
            # initial verification collections
            $ModulesInstallationInProgress = $ModulesInstallationPhase
            $ModulesInstallationCompleted = @()
            do {
                Write-Host '.' -NoNewline
                Start-Sleep -Seconds $Step
                $Timer += $Step

                $ModulesInstallationStatus = @()
                foreach ($Module in $ModulesInstallationInProgress) {
                    $ModulesInstallationStatus += Get-AzAutomationModule -AutomationAccountName "$AutomationAccountName" -ResourceGroupName "$ResourceGroupName" `
                                                            -Name "$($Module.Name)" -ErrorAction SilentlyContinue

                }
                # accumulate completed deployments
                $ModulesInstallationCompleted += $ModulesInstallationStatus.where({$_.ProvisioningState -eq 'Succeeded' -or $_.ProvisioningState -eq 'Failed'})
                # get in progress deployments
                $ModulesInstallationInProgress = $ModulesInstallationStatus.where({$_.ProvisioningState -ne 'Succeeded' -and $_.ProvisioningState -ne 'Failed'})
            } until (($ModulesInstallationInProgress.count -eq 0) -or ($Timer -ge $Timeout))

            Write-Host ''

            # checking verification timeout
            if ($ModulesInstallationInProgress -and ($Timer -ge $Timeout)) {
                $Err = "Error processing phase $Phase, existed on timout: $Timeout"
                Write-Error $Err
                return $Err
            }
            else {
                # output results
                $ModulesInstallationCompleted | Select-Object Name,@{label='Status';expression={$_.ProvisioningState}} | 
                                                                Sort-Object Name | Format-Table -AutoSize

                Write-Host "Deployment phase: " -NoNewline; Write-Host "$Phase" -ForegroundColor Yellow -NoNewline
                Write-Host " is completed"
            }

        }
    }
}

<#
$tknId = ''
$tknSecret = ''
$tenantId = ''

$token = New-Object System.Management.Automation.PSCredential($tknId,$(ConvertTo-SecureString $tknSecret -AsPlainText -Force))

Connect-AzAccount -ServicePrincipal -Credential $token -Tenant $tenantId

Install-AzAutomationModuleWithDependencies -AutomationAccountName '' -ResourceGroupName '' -ModuleName '' #-ResolveOnly
#>