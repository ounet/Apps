﻿# Standalone application install script for VDI environment - (C)2023 Jonathan Pitre

#Requires -Version 5.1
#Requires -RunAsAdministrator

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#region Initialisations

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
# Set the script execution policy for this process
Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force } Catch {}
# Unblock ps1 script
Get-ChildItem -Recurse *.ps*1 | Unblock-File
$env:SEE_MASK_NOZONECHECKS = 1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$Modules = @("PSADT", "Nevergreen") # Modules list

Function Get-ScriptPath
{
    <#
    .SYNOPSIS
        Get-ScriptPath returns the path of the current script.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    Param()

    Begin
    {
        Remove-Variable appScriptPath
    }
    Process
    {
        If ($psEditor) { Split-Path -Path $psEditor.GetEditorContext().CurrentFile.Path } # Visual Studio Code
        ElseIf ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") { Split-Path -Path $My$MyInvocation.MyCommand.Source } # PS1 converted to EXE
        ElseIf ($null -ne $HostInvocation) { $HostInvocation.MyCommand.Path } # SAPIEN PowerShell Studio
        ElseIf ($psISE) { Split-Path -Path $psISE.CurrentFile.FullPath } # Windows PowerShell ISE
        ElseIf ($MyInvocation.PSScriptRoot) { $MyInvocation.PSScriptRoot } # Windows PowerShell 3.0+
        ElseIf ($MyInvocation.MyCommand.Path) { Split-Path -Path $MyInvocation.MyCommand.Path -Parent } # Windows PowerShell
        Else
        {
            Write-Host -Object "Unable to resolve script's file path!" -ForegroundColor Red
            Exit 1
        }
    }
}

Function Get-ScriptName
{
    <#
    .SYNOPSIS
        Get-ScriptName returns the name of the current script.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    Param()
    Begin
    {
        Remove-Variable appScriptName
    }
    Process
    {
        If ($psEditor) { Split-Path -Path $psEditor.GetEditorContext().CurrentFile.Path -Leaf } # Visual Studio Code Host
        ElseIf ($psEXE) { [System.Diagnotics.Process]::GetCurrentProcess.Name } # PS1 converted to EXE
        ElseIf ($null -ne $HostInvocation) { $HostInvocation.MyCommand.Name } # SAPIEN PowerShell Studio
        ElseIf ($psISE) { $psISE.CurrentFile.DisplayName.Trim("*") } # Windows PowerShell ISE
        ElseIf ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } # Windows PowerShell
        Else
        {
            Write-Host -Object "Uanble to resolve script's file name!" -ForegroundColor Red
            Exit 1
        }
    }
}

Function Initialize-Module
{
    <#
    .SYNOPSIS
        Initialize-Module install and import modules from PowerShell Galllery.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Module
    )
    Write-Host -Object "Importing $Module module..." -ForegroundColor Green

    # If module is imported say that and do nothing
    If (Get-Module | Where-Object { $_.Name -eq $Module })
    {
        Write-Host -Object "Module $Module is already imported." -ForegroundColor Green
    }
    Else
    {
        # If module is not imported, but available on disk then import
        If ( [boolean](Get-Module -ListAvailable | Where-Object { $_.Name -eq $Module }) )

        {
            $InstalledModuleVersion = (Get-InstalledModule -Name $Module).Version
            $ModuleVersion = (Find-Module -Name $Module).Version
            $ModulePath = (Get-InstalledModule -Name $Module).InstalledLocation
            $ModulePath = (Get-Item -Path $ModulePath).Parent.FullName
            If ([version]$ModuleVersion -gt [version]$InstalledModuleVersion)
            {
                Update-Module -Name $Module -Force
                Remove-Item -Path $ModulePath\$InstalledModuleVersion -Force -Recurse
                Write-Host -Object "Module $Module was updated." -ForegroundColor Green
            }
            Import-Module -Name $Module -Force -Global -DisableNameChecking
            Write-Host -Object "Module $Module was imported." -ForegroundColor Green
        }
        Else
        {
            # Install Nuget
            If (-not(Get-PackageProvider -ListAvailable -Name NuGet))
            {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                Write-Host -Object "Package provider NuGet was installed." -ForegroundColor Green
            }

            # Add the Powershell Gallery as trusted repository
            If ((Get-PSRepository -Name "PSGallery").InstallationPolicy -eq "Untrusted")
            {
                Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
                Write-Host -Object "PowerShell Gallery is now a trusted repository." -ForegroundColor Green
            }

            # Update PowerShellGet
            $InstalledPSGetVersion = (Get-PackageProvider -Name PowerShellGet).Version
            $PSGetVersion = [version](Find-PackageProvider -Name PowerShellGet).Version
            If ($PSGetVersion -gt $InstalledPSGetVersion)
            {
                Install-PackageProvider -Name PowerShellGet -Force
                Write-Host -Object "PowerShellGet Gallery was updated." -ForegroundColor Green
            }

            # If module is not imported, not available on disk, but is in online gallery then install and import
            If (Find-Module -Name $Module | Where-Object { $_.Name -eq $Module })
            {
                # Install and import module
                Install-Module -Name $Module -AllowClobber -Force -Scope AllUsers
                Import-Module -Name $Module -Force -Global -DisableNameChecking
                Write-Host -Object "Module $Module was installed and imported." -ForegroundColor Green
            }
            Else
            {
                # If the module is not imported, not available and not in the online gallery then abort
                Write-Host -Object "Module $Module was not imported, not available and not in an online gallery, exiting." -ForegroundColor Red
                EXIT 1
            }
        }
    }
}

[string]$appScriptPath = Get-ScriptPath # Get the current script path
[string]$appScriptName = Get-ScriptName # Get the current script name

# Install and import modules list
Foreach ($Module in $Modules)
{
    Initialize-Module -Module $Module
}

#endregion

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#region Functions
Function Get-DruideAntidote
{
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding()]
    Param ()
    $DownloadURL = "https://www.antidote.info/fr/assistance/mises-a-jour/installation/antidote-10/windows"

    Try
    {
        $DownloadText = (Invoke-WebRequest -Uri $DownloadURL -DisableKeepAlive -UseBasicParsing).Links
    }
    Catch
    {
        Throw "Failed to connect to URL: $DownloadURL with error $_."
        Break
    }
    Finally
    {
        $RegExAntidote = "href\=(https.+\/Diff_Antidote_10_C_((?:\d+\.)+(?:\d+))\.msp)"
        $VersionAntidote = ($DownloadText | Select-String -Pattern $RegExAntidote).Matches.Groups[2].Value
        $URLAntidote = ($DownloadText | Select-String -Pattern $RegExAntidote).Matches.Groups[1].Value

        $RegExAntidoteF = "href\=(https.+\/Diff_Antidote_10_Module_F_((?:\d+\.)+(?:\d+))\.msp)"
        $VersionAntidoteF = ($DownloadText | Select-String -Pattern $RegExAntidoteF).Matches.Groups[2].Value
        $URLAntidoteF = ($DownloadText | Select-String -Pattern $RegExAntidoteF).Matches.Groups[1].Value

        $RegExAntidoteE = "href\=(https.+\/Diff_Antidote_10_Module_E_((?:\d+\.)+(?:\d+))\.msp)"
        $VersionAntidoteE = ($DownloadText | Select-String -Pattern $RegExAntidoteE).Matches.Groups[2].Value
        $URLAntidoteE = ($DownloadText | Select-String -Pattern $RegExAntidoteE).Matches.Groups[1].Value

        $RegExConnectix = "href\=(https.+\/Diff_Connectix_10_C_((?:\d+\.)+(?:\d+))\.msp)"
        $VersionConnectix = ($DownloadText | Select-String -Pattern $RegExConnectix).Matches.Groups[2].Value
        $URLConnectix = ($DownloadText | Select-String -Pattern $RegExConnectix).Matches.Groups[1].Value

        $URLGestionnaire = "https://telechargement.druide.com/telecharger/Reseau/antidote_10/GestionnaireMultiposte_Antidote10.exe"

        if ($VersionAntidote -and $URLAntidote)
        {
            [PSCustomObject]@{
                Name         = 'Antidote'
                Architecture = 'x86'
                Type         = 'Msp'
                Version      = $VersionAntidote
                Uri          = $URLAntidote
            }
        }

        if ($VersionAntidoteF -and $URLAntidoteF)
        {
            [PSCustomObject]@{
                Name         = 'Antidote French Module'
                Architecture = 'x86'
                Type         = 'Msp'
                Version      = $VersionAntidoteF
                Uri          = $URLAntidoteF
            }
        }

        if ($VersionAntidoteE -and $URLAntidoteE)
        {
            [PSCustomObject]@{
                Name         = 'Antidote English Module'
                Architecture = 'x86'
                Type         = 'Msp'
                Version      = $VersionAntidoteE
                Uri          = $URLAntidoteE
            }
        }

        if ($VersionConnectix -and $URLConnectix)
        {
            [PSCustomObject]@{
                Name         = 'Connectix'
                Architecture = 'x86'
                Type         = 'Msp'
                Version      = $VersionConnectix
                Uri          = $URLConnectix
            }
        }

        if ($URLGestionnaire)
        {
            [PSCustomObject]@{
                Name         = 'Gestionnaire Multiposte'
                Architecture = 'x86'
                Type         = 'Exe'
                Uri          = $URLGestionnaire
            }
        }
    }
}

#endregion

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$appVendor = "Druide"
$appName = "Antidote"
$appProcesses = @("Antidote", "AgentAntidote", "Connectix", "AgentConnectix", "OUTLOOK", "WINWORD", "EXCEL", "POWERPNT", "CHROME", "msedge")
$appTransformAntidote = "ReseauAntidote.mst"
$appTransformConnectix = "ReseauConnectix.mst"
$appShortVersion = "10"
$DownloadText10= (Invoke-WebRequest -Uri "https://www.antidote.info/fr/assistance/mises-a-jour/installation/antidote-10/windows" -DisableKeepAlive -UseBasicParsing).Content
$appVersion = ($DownloadText10 | Select-String -Pattern "MSI ((?:\d+\.)+(?:\d+))").Matches.Groups[1].Value
$Nevergreen = Get-DruideAntidote
$appPatchVersion = ($Nevergreen | Where-Object { $_.Name -eq $appName }).Version
$appUrlPatchAntidote = ($Nevergreen | Where-Object { $_.Name -eq $appName }).Uri
$appUrlPatchAntidoteF = ($Nevergreen | Where-Object { $_.Name -eq "$appName French Module" }).Uri
$appUrlPatchAntidoteE = ($Nevergreen | Where-Object { $_.Name -eq "$appName English Module" }).Uri
$appUrlPatchConnectix = ($Nevergreen | Where-Object { $_.Name -eq "Connectix" }).Uri
$appUrlGestionnaire = ($Nevergreen | Where-Object { $_.Name -eq "Gestionnaire Multiposte" }).Uri
$appPatchAntidote = Split-Path -Path $appUrlPatchAntidote -Leaf
$appPatchAntidoteF = Split-Path -Path $appUrlPatchAntidoteF -Leaf
$appPatchAntidoteE = Split-Path -Path $appUrlPatchAntidoteE -Leaf
$appPatchConnectix = Split-Path -Path $appUrlPatchConnectix -Leaf
$appGestionnaire = Split-Path -Path $appUrlGestionnaire -Leaf
$appSetupAntidote = "Antidote$appShortVersion.msi"
$appSetupAntidoteF = "Antidote$appShortVersion-Module-francais.msi"
$appSetupAntidoteE = "Antidote$appShortVersion-English-module.msi"
$appSetupConnectix = "Antidote-Connectix$appShortVersion.msi"
$appInstallParameters = "/QB"
$appDestination = "${env:ProgramFiles(x86)}\$appVendor\$appName $appShortVersion\Application\Bin64"
[boolean]$isAppInstalled = [boolean](Get-InstalledApplication -Name "$appName \d{2}" -RegEx -Exact) | Select-Object -First 1
$appInstalledVersion = (Get-InstalledApplication -Name "$appName \d{2}" -RegEx -Exact).DisplayVersion | Select-Object -First 1

#-----------------------------------------------------------[Execution]------------------------------------------------------------

If ([version]$appVersion -gt [version]$appInstalledVersion)
{
    Set-Location -Path $appScriptPath
    If (-Not(Test-Path -Path $appPatchVersion)) { New-Folder -Path $appPatchVersion }

    # Uninstall previous versions
    #Get-Process -Name $appProcesses | Stop-Process -Force
    #If ($IsAppInstalled) {
    #    Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
    #    Remove-MSIApplications -Name $appName -Parameters $appInstallParameters
    #}

    # Download latest Gestionnaire Multipostes setup
    Write-Log -Message "Downloading $appVendor $appName $appShortVersion Gestionnaire Multipostes..." -Severity 1 -LogType CMTrace -WriteHost $True
    Invoke-WebRequest -UseBasicParsing -Uri $appUrlGestionnaire -OutFile $appScriptPath\$appGestionnaire

    # Download latest setup file(s)
    If (-Not(Test-Path -Path $appScriptPath\$appPatchVersion\$appPatchAntidote))
    {
        Write-Log -Message "Downloading $appVendor $appName $appPatchVersion patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appUrlPatchAntidote -OutFile $appScriptPath\$appPatchVersion\$appPatchAntidote
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    If (-Not(Test-Path -Path $appScriptPath\$appPatchVersion\$appPatchAntidoteF))
    {
        Write-Log -Message "Downloading $appVendor $appName $appPatchVersion French module patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appUrlPatchAntidoteF -OutFile $appScriptPath\$appPatchVersion\$appPatchAntidoteF
    }

    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }
    If (-Not(Test-Path -Path $appScriptPath\$appPatchVersion\$appPatchAntidoteE))
    {
        Write-Log -Message "Downloading $appVendor $appName $appPatchVersion English module patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appUrlPatchAntidoteE -OutFile $appScriptPath\$appPatchVersion\$appPatchAntidoteE
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    If (-Not(Test-Path -Path $appScriptPath\$appPatchVersion\$appPatchConnectix))
    {
        Write-Log -Message "Downloading $appVendor $appName $appPatchVersion Connectix patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appUrlPatchConnectix -OutFile $appScriptPath\$appPatchVersion\$appPatchConnectix
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    # Antidote setup
    If ((Test-Path -Path $appScriptPath\$appSetupAntidote) -and (Test-Path -Path $appScriptPath\$appTransformAntidote))
    {
        Write-Log -Message "Installing $appVendor $appName $appPatchVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        # Install latest Antidote version
        Execute-MSI -Action Install -Path $appSetupAntidote -Parameters $appInstallParameters -Transform $appTransformAntidote -Patch "$appScriptPath\$appPatchVersion\$appPatchAntidote"
    }
    ElseIf (($isAppInstalled) -and (Test-Path -Path "$appScriptPath\$appPatchVersion\$appPatchAntidote"))
    {
        # Install latest Antidote patch
        Write-Log -Message "Setup file(s) are missing, MSP file(s) will be installed instead." -Severity 2 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing  $appVendor $appName $appPatchVersion patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSP -Path "$appScriptPath\$appPatchVersion\$appPatchAntidote"
    }
    Else
    {
        Write-Log -Message "Setup file(s) are missing." -Severity 2 -LogType CMTrace -WriteHost $True
        Exit-Script
    }

    # Antidote French module setup
    If ((Test-Path -Path $appScriptPath\$appSetupAntidoteF) -and (Test-Path -Path $appScriptPath\$appTransformAntidote))
    {
        Write-Log -Message "Installing $appVendor $appName $appPatchVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        # Install latest Antidote French module version
        Execute-MSI -Action Install -Path $appSetupAntidoteF -Parameters $appInstallParameters -Transform $appTransformAntidote -Patch "$appScriptPath\$appPatchVersion\$appPatchAntidoteF"
    }
    ElseIf (($isAppInstalled) -and (Test-Path -Path "$appScriptPath\$appPatchVersion\$appPatchAntidoteF"))
    {
        # Install latest Antidote French module patch
        Write-Log -Message "Setup file(s) are missing, MSP file(s) will be installed instead." -Severity 2 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing  $appVendor $appName $appPatchVersion French module patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSP -Path "$appScriptPath\$appPatchVersion\$appPatchAntidoteF"
    }
    Else
    {
        Write-Log -Message "Setup file(s) are missing." -Severity 2 -LogType CMTrace -WriteHost $True
        Exit-Script
    }

    # Antidote English module setup
    If ((Test-Path -Path $appScriptPath\$appSetupAntidoteE) -and (Test-Path -Path $appScriptPath\$appTransformAntidote))
    {
        Write-Log -Message "Installing $appVendor $appName $appPatchVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        # Install latest Antidote English module version
        Execute-MSI -Action Install -Path $appSetupAntidoteE -Parameters $appInstallParameters -Transform $appTransformAntidote -Patch "$appScriptPath\$appPatchVersion\$appPatchAntidoteE"
    }
    ElseIf (($isAppInstalled) -and (Test-Path -Path "$appScriptPath\$appPatchVersion\$appPatchAntidoteE"))
    {
        # Install latest Antidote English module patch
        Write-Log -Message "Setup file(s) are missing, MSP file(s) will be installed instead." -Severity 2 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing  $appVendor $appName $appPatchVersion English module patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSP -Path "$appScriptPath\$appPatchVersion\$appPatchAntidoteE"
    }
    Else
    {
        Write-Log -Message "Setup file(s) are missing." -Severity 3 -LogType CMTrace -WriteHost $True
        Exit-Script
    }

    # Connectix setup
    If ((Test-Path -Path $appScriptPath\$appSetupConnectix) -and (Test-Path -Path $appScriptPath\$appTransformConnectix))
    {
        Write-Log -Message "Installing $appVendor $appName $appPatchVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        # Install latest Connectix version
        Execute-MSI -Action Install -Path $appSetupConnectix -Parameters $appInstallParameters -Transform $appTransformConnectix -Patch "$appScriptPath\$appPatchVersion\$apspPatchConnectix"
    }
    ElseIf (($isAppInstalled) -and (Test-Path -Path "$appScriptPath\$appPatchVersion\$apspPatchConnectix"))
    {
        # Install latest Connectix patch
        Write-Log -Message "Setup file(s) are missing, MSP file(s) will be installed instead." -Severity 2 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing  $appVendor $appName $appPatchVersion Connectix patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSP -Path "$appScriptPath\$appPatchVersion\$apspPatchConnectix"
    }
    Else
    {
        Write-Log -Message "Setup file(s) are missing." -Severity 2 -LogType CMTrace -WriteHost $True
        Exit-Script
    }

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True

    # Go back to the parent folder
    Set-Location ..

    Write-Log -Message "$appVendor $appName $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True
}
Else
{
    Write-Log -Message "$appVendor $appName $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}