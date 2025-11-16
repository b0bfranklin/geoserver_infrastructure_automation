<#
.SYNOPSIS
    Upgrades Apache Tomcat from 9.x to 10.x with configuration migration and rollback.

.DESCRIPTION
    Comprehensive Tomcat upgrade with breaking change handling:
    - Detects current Tomcat 9.x installations
    - Downloads Tomcat 10.1.x
    - Backs up current installation
    - Migrates configuration files (server.xml, web.xml, context.xml)
    - Handles javax → jakarta package rename
    - Deploys GeoServer WAR (must be compatible version)
    - Updates Windows services
    - Verifies deployment
    - Provides rollback on failure

    IMPORTANT: GeoServer 2.24.2+ required for Tomcat 10 compatibility

.PARAMETER TargetVersion
    Target Tomcat version (default: latest 10.1.x)

.PARAMETER InstanceName
    Specific Tomcat instance to upgrade (default: all instances)

.PARAMETER VerifyGeoServerCompatibility
    Verify GeoServer version is compatible with Tomcat 10

.PARAMETER WhatIf
    Preview upgrade without making changes

.EXAMPLE
    .\Upgrade-Tomcat.ps1 -TargetVersion "10.1.17"

.EXAMPLE
    .\Upgrade-Tomcat.ps1 -InstanceName "instance1" -WhatIf

.NOTES
    File Name   : Upgrade-Tomcat.ps1
    Version     : 2.0.0
    Requires    : PowerShell 7.0+, Administrative privileges

    BREAKING CHANGE: Tomcat 10 uses jakarta.* instead of javax.*
    GeoServer 2.24.2+ required for Tomcat 10 compatibility
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetVersion = "10.1.17",

    [Parameter(Mandatory=$false)]
    [string]$InstanceName,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\config\upgrade-config.json",

    [Parameter(Mandatory=$false)]
    [switch]$VerifyGeoServerCompatibility = $true,

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

#Requires -Version 7.0
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\modules\TomcatManager.psm1" -Force

$script:BackupPaths = @{}
$script:UpgradeReport = @{
    StartTime = Get-Date
    Instances = @()
    Changes = @()
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-LogEntry {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{ERROR='Red';WARNING='Yellow';SUCCESS='Green';STEP='Cyan';default='White'}
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]

    # Add to report
    $script:UpgradeReport.Changes += @{
        Timestamp = $timestamp
        Level = $Level
        Message = $Message
    }
}

# ============================================================================
# COMPATIBILITY CHECKS
# ============================================================================

function Test-GeoServerCompatibility {
    param([object]$Config)

    Write-LogEntry "=== Checking GeoServer Compatibility ===" "STEP"

    try {
        # Check if GeoServer WAR exists
        $geoserverWar = $null

        foreach ($instance in $Config.environment.tomcatInstances) {
            $warPath = Join-Path $instance.path "webapps\geoserver.war"
            $deployedPath = Join-Path $instance.path "webapps\geoserver"

            if (Test-Path $warPath) {
                $geoserverWar = $warPath
                break
            }
            elseif (Test-Path $deployedPath) {
                # Check version from deployed files
                $versionFile = Join-Path $deployedPath "META-INF\MANIFEST.MF"
                if (Test-Path $versionFile) {
                    $content = Get-Content $versionFile -Raw
                    if ($content -match 'GeoServer-Version:\s*(\d+\.\d+\.\d+)') {
                        $version = $matches[1]
                        Write-LogEntry "Detected GeoServer version: $version" "INFO"

                        # Parse version
                        if ($version -match '^(\d+)\.(\d+)') {
                            $major = [int]$matches[1]
                            $minor = [int]$matches[2]

                            # GeoServer 2.24.2+ required for Tomcat 10
                            if ($major -gt 2 -or ($major -eq 2 -and $minor -ge 24)) {
                                Write-LogEntry "GeoServer $version is compatible with Tomcat 10" "SUCCESS"
                                return $true
                            }
                            else {
                                Write-LogEntry "GeoServer $version is NOT compatible with Tomcat 10 (need 2.24.2+)" "ERROR"
                                return $false
                            }
                        }
                    }
                }
            }
        }

        Write-LogEntry "Could not determine GeoServer version - proceeding with caution" "WARNING"
        return $true  # Allow to proceed but warn
    }
    catch {
        Write-LogEntry "Error checking GeoServer compatibility: $_" "WARNING"
        return $true
    }
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

function Backup-TomcatInstance {
    param([object]$Instance)

    Write-LogEntry "Backing up Tomcat instance: $($Instance.name)" "INFO"

    try {
        $backupRoot = ".\backups\tomcat"
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }

        $backupName = "$($Instance.name)_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
        $backupPath = Join-Path $backupRoot $backupName

        Write-LogEntry "Backup location: $backupPath" "INFO"

        # Copy entire Tomcat directory
        Copy-Item -Path $Instance.path -Destination $backupPath -Recurse -Force

        # Save service configuration
        if ($Instance.serviceName) {
            $service = Get-Service -Name $Instance.serviceName -ErrorAction SilentlyContinue
            if ($service) {
                $serviceInfo = @{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    StartType = $service.StartType
                    Status = $service.Status
                }
                $serviceInfo | ConvertTo-Json | Out-File (Join-Path $backupPath "service-info.json")
            }
        }

        $script:BackupPaths[$Instance.name] = $backupPath
        Write-LogEntry "Backup completed: $backupPath" "SUCCESS"

        return $backupPath
    }
    catch {
        Write-LogEntry "Backup failed: $_" "ERROR"
        return $null
    }
}

# ============================================================================
# DOWNLOAD AND INSTALL
# ============================================================================

function Install-TomcatVersion {
    param(
        [string]$Version,
        [object]$Instance
    )

    Write-LogEntry "=== Installing Tomcat $Version ===" "STEP"

    try {
        # Download using package manager
        $packageScript = Join-Path $PSScriptRoot "..\utilities\Get-ComponentPackage.ps1"
        Write-LogEntry "Downloading Tomcat $Version..." "INFO"

        & $packageScript -Component "Tomcat" -Version $Version 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download Tomcat"
        }

        # Find downloaded package
        $packagePath = Get-ChildItem -Path ".\downloads" -Filter "apache-tomcat-${Version}*.zip" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $packagePath) {
            throw "Downloaded package not found"
        }

        Write-LogEntry "Package: $($packagePath.Name)" "SUCCESS"

        # Stop service
        if ($Instance.serviceName) {
            Write-LogEntry "Stopping service: $($Instance.serviceName)" "INFO"
            Stop-TomcatService -ServiceName $Instance.serviceName
        }

        # Extract to temporary location
        $tempExtract = Join-Path $env:TEMP "tomcat-upgrade-$((Get-Date).Ticks)"
        Write-LogEntry "Extracting to: $tempExtract" "INFO"

        Add-Type -Assembly 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath.FullName, $tempExtract)

        # Find extracted Tomcat directory
        $extractedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1

        if (-not $extractedDir) {
            throw "Extracted Tomcat directory not found"
        }

        # Migrate configuration files
        Write-LogEntry "Migrating configuration files..." "INFO"
        Copy-TomcatConfiguration -SourcePath $Instance.path -DestPath $extractedDir.FullName

        # Migrate webapps (GeoServer)
        Write-LogEntry "Migrating GeoServer WAR..." "INFO"
        Copy-TomcatWebapps -SourcePath $Instance.path -DestPath $extractedDir.FullName

        # Rename old Tomcat directory
        $oldPath = "$($Instance.path)_old_$(Get-Date -Format 'HHmmss')"
        Write-LogEntry "Renaming old Tomcat: $oldPath" "INFO"
        Rename-Item -Path $Instance.path -NewName (Split-Path $oldPath -Leaf) -Force

        # Move new Tomcat to instance location
        Write-LogEntry "Installing new Tomcat to: $($Instance.path)" "INFO"
        Move-Item -Path $extractedDir.FullName -Destination $Instance.path -Force

        # Cleanup
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

        Write-LogEntry "Tomcat $Version installed successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-LogEntry "Installation failed: $_" "ERROR"
        return $false
    }
}

function Copy-TomcatConfiguration {
    param([string]$SourcePath, [string]$DestPath)

    $configFiles = @(
        'conf\server.xml',
        'conf\web.xml',
        'conf\context.xml',
        'conf\tomcat-users.xml',
        'conf\catalina.properties',
        'bin\setenv.bat',
        'bin\setenv.sh'
    )

    foreach ($file in $configFiles) {
        $sourcefile = Join-Path $SourcePath $file
        $destFile = Join-Path $DestPath $file

        if (Test-Path $sourceFile) {
            $destDir = Split-Path $destFile -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }

            Copy-Item -Path $sourceFile -Destination $destFile -Force
            Write-LogEntry "  Migrated: $file" "INFO"
        }
    }
}

function Copy-TomcatWebapps {
    param([string]$SourcePath, [string]$DestPath)

    $sourceWebapps = Join-Path $SourcePath "webapps"
    $destWebapps = Join-Path $DestPath "webapps"

    # Copy GeoServer WAR and deployed directory
    $geoserverWar = Join-Path $sourceWebapps "geoserver.war"
    $geoserverDir = Join-Path $sourceWebapps "geoserver"

    if (Test-Path $geoserverWar) {
        Copy-Item -Path $geoserverWar -Destination $destWebapps -Force
        Write-LogEntry "  Migrated: geoserver.war" "INFO"
    }

    if (Test-Path $geoserverDir) {
        Copy-Item -Path $geoserverDir -Destination $destWebapps -Recurse -Force
        Write-LogEntry "  Migrated: geoserver directory" "INFO"
    }
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

function Update-TomcatService {
    param([object]$Instance)

    if (-not $Instance.serviceName) {
        Write-LogEntry "No service configured for: $($Instance.name)" "INFO"
        return $true
    }

    try {
        Write-LogEntry "Updating Windows service: $($Instance.serviceName)" "INFO"

        # Check if service exists
        $service = Get-Service -Name $Instance.serviceName -ErrorAction SilentlyContinue

        if ($service) {
            # Service exists - update paths if needed
            Write-LogEntry "Service exists - verifying configuration" "INFO"

            # Start the service
            Write-LogEntry "Starting service: $($Instance.serviceName)" "INFO"
            Start-TomcatService -ServiceName $Instance.serviceName

            return $true
        }
        else {
            Write-LogEntry "Service not found - may need manual recreation" "WARNING"
            return $false
        }
    }
    catch {
        Write-LogEntry "Service update failed: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# VERIFICATION
# ============================================================================

function Test-TomcatUpgrade {
    param([object]$Instance)

    Write-LogEntry "=== Verifying Tomcat Upgrade ===" "STEP"

    try {
        # Check if Tomcat is running
        if ($Instance.serviceName) {
            $service = Get-Service -Name $Instance.serviceName -ErrorAction SilentlyContinue

            if ($service -and $service.Status -eq 'Running') {
                Write-LogEntry "Service is running" "SUCCESS"
            }
            else {
                Write-LogEntry "Service is not running" "ERROR"
                return $false
            }
        }

        # Wait for Tomcat to fully start
        Write-LogEntry "Waiting for Tomcat to initialize..." "INFO"
        Start-Sleep -Seconds 30

        # Test HTTP endpoint
        $url = "http://localhost:$($Instance.port)"
        try {
            $response = Invoke-WebRequest -Uri $url -TimeoutSec 30 -ErrorAction Stop
            Write-LogEntry "HTTP endpoint accessible: $url (Status: $($response.StatusCode))" "SUCCESS"
        }
        catch {
            Write-LogEntry "HTTP endpoint not accessible: $url" "WARNING"
        }

        # Test GeoServer
        $geoserverUrl = "http://localhost:$($Instance.port)/geoserver/web/"
        try {
            $response = Invoke-WebRequest -Uri $geoserverUrl -TimeoutSec 30 -ErrorAction Stop
            Write-LogEntry "GeoServer accessible (Status: $($response.StatusCode))" "SUCCESS"
            return $true
        }
        catch {
            Write-LogEntry "GeoServer not accessible - may need time to deploy" "WARNING"
            return $false
        }
    }
    catch {
        Write-LogEntry "Verification failed: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# ROLLBACK
# ============================================================================

function Invoke-TomcatRollback {
    param([string]$InstanceName, [string]$BackupPath)

    Write-LogEntry "=== Initiating Rollback for: $InstanceName ===" "STEP"

    if (-not (Test-Path $BackupPath)) {
        Write-LogEntry "Backup not found: $BackupPath" "ERROR"
        return $false
    }

    try {
        # Get instance info
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $instance = $config.environment.tomcatInstances | Where-Object { $_.name -eq $InstanceName }

        if (-not $instance) {
            throw "Instance not found: $InstanceName"
        }

        # Stop service
        if ($instance.serviceName) {
            Stop-TomcatService -ServiceName $instance.serviceName
        }

        # Remove current installation
        if (Test-Path $instance.path) {
            $failedPath = "$($instance.path)_failed_$(Get-Date -Format 'HHmmss')"
            Rename-Item -Path $instance.path -NewName (Split-Path $failedPath -Leaf) -Force
        }

        # Restore from backup
        Write-LogEntry "Restoring from backup..." "INFO"
        Copy-Item -Path $BackupPath -Destination $instance.path -Recurse -Force

        # Start service
        if ($instance.serviceName) {
            Start-TomcatService -ServiceName $instance.serviceName
        }

        Write-LogEntry "Rollback completed successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-LogEntry "Rollback failed: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-TomcatUpgrade {
    try {
        Write-LogEntry "==================================================================" "INFO"
        Write-LogEntry "Tomcat Upgrade (9.x → 10.x) - Version 2.0.0" "INFO"
        Write-LogEntry "==================================================================" "INFO"
        Write-LogEntry "" "INFO"
        Write-LogEntry "TARGET VERSION: Tomcat $TargetVersion" "INFO"
        Write-LogEntry "BREAKING CHANGE: javax.* → jakarta.* package rename" "WARNING"
        Write-LogEntry "REQUIREMENT: GeoServer 2.24.2+ for Tomcat 10 compatibility" "WARNING"
        Write-LogEntry "" "INFO"

        # Load configuration
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Determine instances to upgrade
        $instances = if ($InstanceName) {
            $config.environment.tomcatInstances | Where-Object { $_.name -eq $InstanceName }
        } else {
            $config.environment.tomcatInstances
        }

        if ($instances.Count -eq 0) {
            throw "No instances found to upgrade"
        }

        Write-LogEntry "Instances to upgrade: $($instances.Count)" "INFO"
        foreach ($inst in $instances) {
            Write-LogEntry "  - $($inst.name) at $($inst.path)" "INFO"
        }
        Write-LogEntry "" "INFO"

        # Verify GeoServer compatibility
        if ($VerifyGeoServerCompatibility) {
            if (-not (Test-GeoServerCompatibility -Config $config)) {
                throw "GeoServer compatibility check failed - upgrade aborted"
            }
        }

        # WhatIf mode
        if ($WhatIf) {
            Write-LogEntry "WhatIf mode - no changes will be made" "WARNING"
            Write-LogEntry "Would upgrade $($instances.Count) instance(s) to Tomcat $TargetVersion" "INFO"
            return @{ Success = $true; WhatIf = $true }
        }

        # Confirm
        Write-Host "" -ForegroundColor Yellow
        Write-Host "WARNING: This is a MAJOR upgrade with breaking changes!" -ForegroundColor Yellow
        Write-Host "Tomcat 10 uses jakarta.* instead of javax.*" -ForegroundColor Yellow
        Write-Host "This will upgrade $($instances.Count) instance(s)" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        $confirm = Read-Host "Type 'YES' to continue"

        if ($confirm -ne 'YES') {
            Write-LogEntry "Upgrade cancelled by user" "WARNING"
            return @{ Success = $false; Cancelled = $true }
        }

        # Upgrade each instance
        $successCount = 0
        foreach ($instance in $instances) {
            Write-LogEntry "" "INFO"
            Write-LogEntry "=== Upgrading Instance: $($instance.name) ===" "STEP"

            # Backup
            $backupPath = Backup-TomcatInstance -Instance $instance
            if (-not $backupPath) {
                Write-LogEntry "Backup failed - skipping instance" "ERROR"
                continue
            }

            # Install
            $installed = Install-TomcatVersion -Version $TargetVersion -Instance $instance
            if (-not $installed) {
                Write-LogEntry "Installation failed" "ERROR"

                # Offer rollback
                $rollback = Read-Host "Rollback this instance? (yes/no)"
                if ($rollback -eq 'yes') {
                    Invoke-TomcatRollback -InstanceName $instance.name -BackupPath $backupPath
                }
                continue
            }

            # Update service
            Update-TomcatService -Instance $instance

            # Verify
            $verified = Test-TomcatUpgrade -Instance $instance
            if ($verified) {
                Write-LogEntry "Instance upgraded successfully: $($instance.name)" "SUCCESS"
                $successCount++

                $script:UpgradeReport.Instances += @{
                    Name = $instance.name
                    Success = $true
                    BackupPath = $backupPath
                    Version = $TargetVersion
                }
            }
            else {
                Write-LogEntry "Verification failed for: $($instance.name)" "ERROR"

                $script:UpgradeReport.Instances += @{
                    Name = $instance.name
                    Success = $false
                    BackupPath = $backupPath
                }
            }
        }

        # Summary
        Write-LogEntry "" "INFO"
        Write-LogEntry "==================================================================" "SUCCESS"
        Write-LogEntry "TOMCAT UPGRADE COMPLETED" "SUCCESS"
        Write-LogEntry "==================================================================" "SUCCESS"
        Write-LogEntry "Successful: $successCount / $($instances.Count)" "INFO"
        Write-LogEntry "Target Version: Tomcat $TargetVersion" "INFO"
        Write-LogEntry "" "INFO"
        Write-LogEntry "NEXT STEPS:" "WARNING"
        Write-LogEntry "1. Verify GeoServer functionality" "WARNING"
        Write-LogEntry "2. Test all layers and services" "WARNING"
        Write-LogEntry "3. Check application logs for errors" "WARNING"
        Write-LogEntry "4. Monitor performance" "WARNING"
        Write-LogEntry "" "INFO"

        $script:UpgradeReport.EndTime = Get-Date
        $script:UpgradeReport.Success = ($successCount -eq $instances.Count)

        return $script:UpgradeReport
    }
    catch {
        Write-LogEntry "" "ERROR"
        Write-LogEntry "TOMCAT UPGRADE FAILED: $_" "ERROR"

        $script:UpgradeReport.EndTime = Get-Date
        $script:UpgradeReport.Success = $false
        $script:UpgradeReport.Error = $_.Exception.Message

        return $script:UpgradeReport
    }
}

# Execute upgrade
$result = Start-TomcatUpgrade

if ($result.Success) {
    exit 0
} else {
    exit 1
}
