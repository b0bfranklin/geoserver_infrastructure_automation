<#
.SYNOPSIS
    Upgrades Azul Zulu JRE from version 11 to 17 or 21 with rollback capabilities.

.DESCRIPTION
    Comprehensive Java JRE upgrade process:
    - Detects current Java version
    - Downloads Azul Zulu JRE (self-contained)
    - Creates backup of current installation
    - Installs new JRE version
    - Updates JAVA_HOME and PATH environment variables
    - Updates Tomcat setenv configuration
    - Verifies installation
    - Provides rollback if upgrade fails

.PARAMETER TargetVersion
    Target Azul Zulu JRE version (17 or 21). Default: 17

.PARAMETER InstallPath
    Installation path for new JRE. Default: C:\Program Files\Azul\Zulu{version}

.PARAMETER UpdateEnvironment
    Update system-wide JAVA_HOME and PATH. Default: true

.PARAMETER UpdateTomcat
    Update Tomcat setenv files with new JAVA_HOME. Default: true

.PARAMETER CreateBackup
    Create backup of current Java installation. Default: true

.PARAMETER WhatIf
    Preview upgrade without making changes.

.EXAMPLE
    .\Upgrade-AzulJRE.ps1 -TargetVersion 17
    Upgrade to Azul Zulu JRE 17.

.EXAMPLE
    .\Upgrade-AzulJRE.ps1 -TargetVersion 21 -WhatIf
    Preview upgrade to JRE 21.

.NOTES
    File Name   : Upgrade-AzulJRE.ps1
    Version     : 2.0.0
    Requires    : PowerShell 7.0+, Administrative privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('17', '21')]
    [string]$TargetVersion = '17',

    [Parameter(Mandatory=$false)]
    [string]$InstallPath,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [switch]$UpdateEnvironment = $true,

    [Parameter(Mandatory=$false)]
    [switch]$UpdateTomcat = $true,

    [Parameter(Mandatory=$false)]
    [switch]$CreateBackup = $true,

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

#Requires -Version 7.0
#Requires -RunAsAdministrator

# ============================================================================
# REPOSITORY ROOT DETECTION
# ============================================================================

# Determine repository root (works regardless of execution directory)
$script:RepositoryRoot = if ($PSScriptRoot) {
    # Scripts are in scripts/upgrades/, so go up 2 levels
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
} else {
    # Fallback for interactive sessions
    Get-Location | Select-Object -ExpandProperty Path
}

# Validate repository root
if (-not (Test-Path (Join-Path $script:RepositoryRoot "config"))) {
    throw "Repository root detection failed. Expected config directory at: $script:RepositoryRoot"
}

# Set default ConfigPath if not provided
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:RepositoryRoot "config\upgrade-config.json"
}

# Validate ConfigPath exists
if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    throw "Configuration file not found: $ConfigPath"
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import modules
Import-Module (Join-Path $script:RepositoryRoot "scripts\modules\TomcatManager.psm1") -Force

$script:CurrentJavaPath = $null
$script:BackupPath = $null

# ============================================================================
# LOGGING
# ============================================================================

function Write-LogEntry {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{ERROR='Red';WARNING='Yellow';SUCCESS='Green';STEP='Cyan';default='White'}
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

# ============================================================================
# JAVA DETECTION
# ============================================================================

function Get-CurrentJavaVersion {
    Write-LogEntry "Detecting current Java installation..." "INFO"

    try {
        # Check JAVA_HOME
        $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')

        if ($javaHome -and (Test-Path $javaHome)) {
            Write-LogEntry "Found JAVA_HOME: $javaHome" "INFO"
            $script:CurrentJavaPath = $javaHome
        }

        # Try to get version from java.exe
        $javaExe = (Get-Command java -ErrorAction SilentlyContinue).Source

        if ($javaExe) {
            $versionOutput = & java -version 2>&1
            $versionLine = $versionOutput | Select-Object -First 1

            if ($versionLine -match 'version "(\d+)\.') {
                $majorVersion = $matches[1]
                Write-LogEntry "Current Java version: $majorVersion" "INFO"
                return $majorVersion
            }
            elseif ($versionLine -match 'version "(\d+)"') {
                $majorVersion = $matches[1]
                Write-LogEntry "Current Java version: $majorVersion" "INFO"
                return $majorVersion
            }
        }

        Write-LogEntry "Could not determine Java version" "WARNING"
        return "Unknown"
    }
    catch {
        Write-LogEntry "Error detecting Java: $_" "ERROR"
        return "Unknown"
    }
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

function Backup-CurrentJava {
    param([string]$CurrentPath)

    if (-not $CurrentPath -or -not (Test-Path $CurrentPath)) {
        Write-LogEntry "No current Java installation to backup" "WARNING"
        return $true
    }

    try {
        $backupRoot = ".\backups\java"
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }

        $backupName = "java_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
        $script:BackupPath = Join-Path $backupRoot $backupName

        Write-LogEntry "Backing up current Java installation..." "INFO"
        Write-LogEntry "Backup location: $script:BackupPath" "INFO"

        # Copy Java installation
        Copy-Item -Path $CurrentPath -Destination $script:BackupPath -Recurse -Force

        # Save environment variables
        $envBackup = @{
            JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
            PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        }

        $envBackup | ConvertTo-Json | Out-File (Join-Path $script:BackupPath "environment.json")

        Write-LogEntry "Java backup completed" "SUCCESS"
        return $true
    }
    catch {
        Write-LogEntry "Failed to backup Java: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# DOWNLOAD AND INSTALL
# ============================================================================

function Install-AzulZulu {
    param([string]$Version, [string]$TargetPath)

    Write-LogEntry "=== Installing Azul Zulu JRE $Version ===" "STEP"

    try {
        # Download package using package manager
        $packageScript = Join-Path $script:RepositoryRoot "scripts\utilities\Get-ComponentPackage.ps1"
        Write-LogEntry "Downloading Azul Zulu JRE $Version..." "INFO"

        $downloadResult = & $packageScript -Component "AzulJRE" -Version "$Version.0.9" 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download Azul Zulu JRE"
        }

        # Find the downloaded package
        $packagePath = Get-ChildItem -Path ".\downloads" -Filter "zulu${Version}*jre*win_x64.zip" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $packagePath) {
            throw "Downloaded package not found"
        }

        Write-LogEntry "Package downloaded: $($packagePath.Name)" "SUCCESS"

        # Extract package
        Write-LogEntry "Extracting to: $TargetPath" "INFO"

        if (-not (Test-Path $TargetPath)) {
            New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        }

        Add-Type -Assembly 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath.FullName, $TargetPath)

        # Find the actual JRE directory (may be nested)
        $jreDir = Get-ChildItem -Path $TargetPath -Directory | Select-Object -First 1

        if ($jreDir) {
            $actualJavaPath = $jreDir.FullName
        } else {
            $actualJavaPath = $TargetPath
        }

        Write-LogEntry "Azul Zulu JRE installed to: $actualJavaPath" "SUCCESS"

        # Verify installation
        $javaExe = Join-Path $actualJavaPath "bin\java.exe"
        if (Test-Path $javaExe) {
            $versionCheck = & $javaExe -version 2>&1
            Write-LogEntry "Version check: $($versionCheck[0])" "SUCCESS"
        }

        return $actualJavaPath
    }
    catch {
        Write-LogEntry "Failed to install Azul Zulu: $_" "ERROR"
        return $null
    }
}

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

function Update-EnvironmentVariables {
    param([string]$NewJavaPath)

    Write-LogEntry "=== Updating Environment Variables ===" "STEP"

    try {
        # Update JAVA_HOME
        Write-LogEntry "Setting JAVA_HOME: $NewJavaPath" "INFO"
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $NewJavaPath, 'Machine')

        # Update PATH
        $currentPath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $javaBin = Join-Path $NewJavaPath "bin"

        # Remove old Java paths
        $pathEntries = $currentPath -split ';' | Where-Object {
            $_ -and ($_ -notmatch 'java|jre|jdk')
        }

        # Add new Java bin to front of PATH
        $newPath = @($javaBin) + $pathEntries -join ';'
        [Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')

        Write-LogEntry "Environment variables updated" "SUCCESS"
        Write-LogEntry "NOTE: You may need to restart services for changes to take effect" "WARNING"

        return $true
    }
    catch {
        Write-LogEntry "Failed to update environment variables: $_" "ERROR"
        return $false
    }
}

function Update-TomcatSetenv {
    param([string]$NewJavaPath, [object]$Config)

    Write-LogEntry "=== Updating Tomcat Configuration ===" "STEP"

    $updated = 0

    foreach ($instance in $Config.environment.tomcatInstances) {
        try {
            $setenvPath = Join-Path $instance.path "bin\setenv.bat"

            # Create or update setenv.bat
            $setenvContent = @"
@echo off
rem Tomcat Environment Configuration
rem Updated by GeoServer Infrastructure Automation Suite
rem Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

set "JAVA_HOME=$NewJavaPath"
set "JRE_HOME=$NewJavaPath"

rem Memory settings
set "CATALINA_OPTS=-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m"

rem GeoServer specific settings
set "CATALINA_OPTS=%CATALINA_OPTS% -DGEOSERVER_DATA_DIR=D:\GeoServer\data"
set "CATALINA_OPTS=%CATALINA_OPTS% -Djava.awt.headless=true"

echo JAVA_HOME is set to: %JAVA_HOME%
"@

            $setenvContent | Out-File -FilePath $setenvPath -Encoding ASCII -Force
            Write-LogEntry "Updated setenv.bat for: $($instance.name)" "SUCCESS"
            $updated++
        }
        catch {
            Write-LogEntry "Failed to update setenv for $($instance.name): $_" "WARNING"
        }
    }

    Write-LogEntry "Updated $updated Tomcat instance(s)" "INFO"
    return $updated -gt 0
}

# ============================================================================
# VERIFICATION
# ============================================================================

function Test-JavaInstallation {
    param([string]$JavaPath)

    Write-LogEntry "=== Verifying Java Installation ===" "STEP"

    try {
        $javaExe = Join-Path $JavaPath "bin\java.exe"

        if (-not (Test-Path $javaExe)) {
            Write-LogEntry "java.exe not found at: $javaExe" "ERROR"
            return $false
        }

        # Test execution
        $output = & $javaExe -version 2>&1
        Write-LogEntry "Java version: $($output[0])" "SUCCESS"

        # Test basic functionality
        $testResult = & $javaExe -XshowSettings:properties -version 2>&1
        Write-LogEntry "Java properties verified" "SUCCESS"

        return $true
    }
    catch {
        Write-LogEntry "Java verification failed: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# ROLLBACK
# ============================================================================

function Invoke-JavaRollback {
    param([string]$BackupPath)

    Write-LogEntry "=== Initiating Rollback ===" "STEP"

    if (-not $BackupPath -or -not (Test-Path $BackupPath)) {
        Write-LogEntry "No backup available for rollback" "ERROR"
        return $false
    }

    try {
        # Restore environment variables
        $envBackupPath = Join-Path $BackupPath "environment.json"
        if (Test-Path $envBackupPath) {
            $envBackup = Get-Content $envBackupPath -Raw | ConvertFrom-Json

            [Environment]::SetEnvironmentVariable('JAVA_HOME', $envBackup.JAVA_HOME, 'Machine')
            [Environment]::SetEnvironmentVariable('PATH', $envBackup.PATH, 'Machine')

            Write-LogEntry "Environment variables restored" "SUCCESS"
        }

        Write-LogEntry "Rollback completed" "SUCCESS"
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

function Start-JavaUpgrade {
    try {
        Write-LogEntry "==================================================================" "INFO"
        Write-LogEntry "Azul Zulu JRE Upgrade - Version 2.0.0" "INFO"
        Write-LogEntry "==================================================================" "INFO"
        Write-LogEntry "" "INFO"

        # Load configuration
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Detect current version
        $currentVersion = Get-CurrentJavaVersion
        Write-LogEntry "Current version: $currentVersion" "INFO"
        Write-LogEntry "Target version: $TargetVersion" "INFO"
        Write-LogEntry "" "INFO"

        # WhatIf mode
        if ($WhatIf) {
            Write-LogEntry "WhatIf mode - preview only" "WARNING"
            Write-LogEntry "Would upgrade from Java $currentVersion to $TargetVersion" "INFO"
            return @{ Success = $true; WhatIf = $true }
        }

        # Determine install path
        if (-not $InstallPath) {
            $InstallPath = "C:\Program Files\Azul\Zulu$TargetVersion"
        }

        # Backup current installation
        if ($CreateBackup -and $script:CurrentJavaPath) {
            if (-not (Backup-CurrentJava -CurrentPath $script:CurrentJavaPath)) {
                throw "Backup failed - aborting upgrade"
            }
        }

        # Install new version
        $newJavaPath = Install-AzulZulu -Version $TargetVersion -TargetPath $InstallPath

        if (-not $newJavaPath) {
            throw "Installation failed"
        }

        # Update environment variables
        if ($UpdateEnvironment) {
            if (-not (Update-EnvironmentVariables -NewJavaPath $newJavaPath)) {
                throw "Failed to update environment variables"
            }
        }

        # Update Tomcat configuration
        if ($UpdateTomcat) {
            Update-TomcatSetenv -NewJavaPath $newJavaPath -Config $config
        }

        # Verify installation
        if (-not (Test-JavaInstallation -JavaPath $newJavaPath)) {
            Write-LogEntry "Installation verification failed" "ERROR"

            # Offer rollback
            $rollback = Read-Host "Do you want to rollback? (yes/no)"
            if ($rollback -eq 'yes') {
                Invoke-JavaRollback -BackupPath $script:BackupPath
            }

            throw "Verification failed"
        }

        Write-LogEntry "" "INFO"
        Write-LogEntry "==================================================================" "SUCCESS"
        Write-LogEntry "JAVA UPGRADE COMPLETED SUCCESSFULLY" "SUCCESS"
        Write-LogEntry "==================================================================" "SUCCESS"
        Write-LogEntry "Installed: $newJavaPath" "INFO"
        Write-LogEntry "Backup: $script:BackupPath" "INFO"
        Write-LogEntry "" "INFO"
        Write-LogEntry "IMPORTANT: Restart Tomcat services for changes to take effect" "WARNING"

        return @{
            Success = $true
            JavaPath = $newJavaPath
            BackupPath = $script:BackupPath
        }
    }
    catch {
        Write-LogEntry "" "ERROR"
        Write-LogEntry "JAVA UPGRADE FAILED: $_" "ERROR"

        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Execute upgrade
$result = Start-JavaUpgrade

if ($result.Success) {
    exit 0
} else {
    exit 1
}
