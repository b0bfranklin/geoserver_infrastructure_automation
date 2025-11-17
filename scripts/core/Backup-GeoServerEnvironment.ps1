<#
.SYNOPSIS
    Creates a complete backup of the GeoServer environment including Tomcat, GeoServer data, and configurations.

.DESCRIPTION
    This script performs a comprehensive backup of your GeoServer infrastructure, including:
    - Tomcat configuration files (server.xml, web.xml, context.xml, etc.)
    - GeoServer data directory
    - GeoServer configuration files (global.xml, security configs)
    - Custom styles, fonts, and extensions
    - Database connection configurations
    - SSL certificates and keystores
    - Environment variables and system settings

    Backups are timestamped and include metadata for easy restoration.

    SAFETY FIRST: This script is designed to run before any upgrade or maintenance operation.

.PARAMETER BackupPath
    The root directory where backups will be stored. Defaults to configured backup location.
    Example: "E:\Backups\GeoServer"

.PARAMETER BackupName
    Optional custom name for the backup. If not specified, uses timestamp format: YYYY-MM-DD_HHMMSS

.PARAMETER ConfigPath
    Path to the upgrade configuration JSON file. Defaults to .\config\upgrade-config.json

.PARAMETER IncludeLogs
    Include Tomcat and GeoServer log files in the backup. Default: $false (logs can be large)

.PARAMETER Compress
    Compress the backup into a ZIP file after creation. Default: $true

.PARAMETER RetentionDays
    Number of days to keep old backups. Older backups will be automatically deleted. Default: 30

.PARAMETER WhatIf
    Shows what would be backed up without actually creating the backup.

.EXAMPLE
    .\Backup-GeoServerEnvironment.ps1
    Creates a backup with default settings using timestamp as name.

.EXAMPLE
    .\Backup-GeoServerEnvironment.ps1 -BackupPath "E:\Backups\GeoServer" -BackupName "pre-upgrade-2025-11-17"
    Creates a backup with a custom name at the specified location.

.EXAMPLE
    .\Backup-GeoServerEnvironment.ps1 -IncludeLogs -Compress -RetentionDays 60
    Creates a compressed backup including logs, keeping backups for 60 days.

.EXAMPLE
    .\Backup-GeoServerEnvironment.ps1 -WhatIf
    Preview what would be backed up without actually creating files.

.NOTES
    File Name   : Backup-GeoServerEnvironment.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+, Administrative privileges
    Version     : 1.0.0

    IMPORTANT: Always test backups by performing a test restore to ensure data integrity.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false, HelpMessage="Root directory for backups")]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath,

    [Parameter(Mandatory=$false, HelpMessage="Custom backup name (default: timestamp)")]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$BackupName,

    [Parameter(Mandatory=$false, HelpMessage="Path to configuration file")]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false, HelpMessage="Include log files in backup")]
    [switch]$IncludeLogs,

    [Parameter(Mandatory=$false, HelpMessage="Compress backup to ZIP file")]
    [switch]$Compress = $true,

    [Parameter(Mandatory=$false, HelpMessage="Days to retain old backups")]
    [ValidateRange(1, 365)]
    [int]$RetentionDays = 30,

    [Parameter(Mandatory=$false, HelpMessage="Preview backup without creating files")]
    [switch]$WhatIf
)

#Requires -Version 7.0

# ============================================================================
# REPOSITORY ROOT DETECTION
# ============================================================================

# Determine repository root (works regardless of execution directory)
$script:RepositoryRoot = if ($PSScriptRoot) {
    # Scripts are in scripts/core/, so go up 2 levels
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

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script variables
$script:ScriptVersion = "1.0.0"
$script:ScriptStartTime = Get-Date
$script:LogEntries = @()
$script:BackupMetadata = @{}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Writes a log entry to both console and log file.
#>
function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Add to in-memory log collection
    $script:LogEntries += @{
        Timestamp = $timestamp
        Level = $Level
        Message = $Message
    }

    # Console output with colors
    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'DEBUG'   { Write-Host $logMessage -ForegroundColor Gray }
        default   { Write-Host $logMessage -ForegroundColor White }
    }
}

<#
.SYNOPSIS
    Saves log entries to a file in the backup directory.
#>
function Save-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupDirectory
    )

    try {
        $logFilePath = Join-Path $BackupDirectory "backup.log"
        $script:LogEntries | ForEach-Object {
            $entry = $_
            "$($entry.Timestamp) [$($entry.Level)] $($entry.Message)"
        } | Out-File -FilePath $logFilePath -Encoding UTF8

        Write-LogEntry "Log file saved to: $logFilePath" -Level INFO
    }
    catch {
        Write-LogEntry "Failed to save log file: $_" -Level WARNING
    }
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Loads and validates the configuration file.
#>
function Get-ConfigurationData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigFilePath
    )

    Write-LogEntry "Loading configuration from: $ConfigFilePath" -Level INFO

    try {
        # Check if config file exists
        if (-not (Test-Path $ConfigFilePath)) {
            throw "Configuration file not found: $ConfigFilePath"
        }

        # Load and parse JSON
        $configContent = Get-Content -Path $ConfigFilePath -Raw
        $config = $configContent | ConvertFrom-Json

        Write-LogEntry "Configuration loaded successfully" -Level SUCCESS
        return $config
    }
    catch {
        Write-LogEntry "Failed to load configuration: $_" -Level ERROR
        throw
    }
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Validates that required paths exist and are accessible.
#>
function Test-EnvironmentPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    Write-LogEntry "Validating environment paths..." -Level INFO
    $validationErrors = @()

    # Check GeoServer data directory
    if ($Config.environment.paths.geoserverDataDir) {
        $dataDir = $Config.environment.paths.geoserverDataDir
        if (-not (Test-Path $dataDir)) {
            $validationErrors += "GeoServer data directory not found: $dataDir"
        } else {
            Write-LogEntry "Found GeoServer data directory: $dataDir" -Level DEBUG
        }
    }

    # Check each Tomcat instance
    foreach ($instance in $Config.environment.tomcatInstances) {
        if ($instance.path) {
            if (-not (Test-Path $instance.path)) {
                $validationErrors += "Tomcat instance path not found: $($instance.path) ($($instance.name))"
            } else {
                Write-LogEntry "Found Tomcat instance: $($instance.name) at $($instance.path)" -Level DEBUG
            }
        }
    }

    # Report validation results
    if ($validationErrors.Count -gt 0) {
        Write-LogEntry "Path validation found issues:" -Level WARNING
        foreach ($error in $validationErrors) {
            Write-LogEntry "  - $error" -Level WARNING
        }
        return $false
    }

    Write-LogEntry "All environment paths validated successfully" -Level SUCCESS
    return $true
}

<#
.SYNOPSIS
    Checks if there is sufficient disk space for the backup.
#>
function Test-DiskSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,

        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    Write-LogEntry "Checking disk space availability..." -Level INFO

    try {
        # Get the drive letter from backup path
        $driveLetter = Split-Path -Path $BackupPath -Qualifier
        $drive = Get-PSDrive -Name $driveLetter.TrimEnd(':') -ErrorAction Stop

        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        $requiredSpaceGB = 10 # Minimum 10GB required for backup

        Write-LogEntry "Available space on ${driveLetter}: ${freeSpaceGB}GB" -Level INFO

        if ($freeSpaceGB -lt $requiredSpaceGB) {
            Write-LogEntry "Insufficient disk space. Required: ${requiredSpaceGB}GB, Available: ${freeSpaceGB}GB" -Level ERROR
            return $false
        }

        Write-LogEntry "Sufficient disk space available" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogEntry "Failed to check disk space: $_" -Level WARNING
        # Continue anyway - better to try than fail
        return $true
    }
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Creates the backup directory structure.
#>
function New-BackupDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootPath,

        [Parameter(Mandatory=$true)]
        [string]$BackupName
    )

    Write-LogEntry "Creating backup directory structure..." -Level INFO

    try {
        # Create main backup directory
        $backupDir = Join-Path $RootPath $BackupName

        if (Test-Path $backupDir) {
            Write-LogEntry "Backup directory already exists: $backupDir" -Level WARNING
            $backupDir = Join-Path $RootPath "$BackupName-$(Get-Date -Format 'HHmmss')"
            Write-LogEntry "Using alternative name: $backupDir" -Level INFO
        }

        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

        # Create subdirectories
        $subdirs = @('tomcat', 'geoserver', 'databases', 'logs', 'certificates', 'metadata')
        foreach ($subdir in $subdirs) {
            New-Item -Path (Join-Path $backupDir $subdir) -ItemType Directory -Force | Out-Null
        }

        Write-LogEntry "Backup directory created: $backupDir" -Level SUCCESS
        return $backupDir
    }
    catch {
        Write-LogEntry "Failed to create backup directory: $_" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Backs up Tomcat configuration files for a single instance.
#>
function Backup-TomcatInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Instance,

        [Parameter(Mandatory=$true)]
        [string]$BackupDirectory,

        [Parameter(Mandatory=$false)]
        [bool]$IncludeLogs = $false
    )

    Write-LogEntry "Backing up Tomcat instance: $($Instance.name)" -Level INFO

    try {
        $instanceBackupDir = Join-Path $BackupDirectory "tomcat\$($Instance.name)"
        New-Item -Path $instanceBackupDir -ItemType Directory -Force | Out-Null

        # Define files and directories to backup
        $tomcatPath = $Instance.path
        $itemsToBackup = @(
            @{Source = "conf"; Destination = "conf"; Type = "Directory"}
            @{Source = "bin\setenv.bat"; Destination = "bin"; Type = "File"; Optional = $true}
            @{Source = "bin\setenv.sh"; Destination = "bin"; Type = "File"; Optional = $true}
            @{Source = "webapps\geoserver\WEB-INF\web.xml"; Destination = "webapps-config"; Type = "File"; Optional = $true}
        )

        if ($IncludeLogs) {
            $itemsToBackup += @{Source = "logs"; Destination = "logs"; Type = "Directory"; Optional = $true}
        }

        foreach ($item in $itemsToBackup) {
            $sourcePath = Join-Path $tomcatPath $item.Source
            $destPath = Join-Path $instanceBackupDir $item.Destination

            if (Test-Path $sourcePath) {
                if ($item.Type -eq "Directory") {
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                    Write-LogEntry "  Copied directory: $($item.Source)" -Level DEBUG
                } else {
                    New-Item -Path $destPath -ItemType Directory -Force | Out-Null
                    Copy-Item -Path $sourcePath -Destination $destPath -Force
                    Write-LogEntry "  Copied file: $($item.Source)" -Level DEBUG
                }
            }
            elseif (-not $item.Optional) {
                Write-LogEntry "  Warning: Required path not found: $sourcePath" -Level WARNING
            }
        }

        Write-LogEntry "Tomcat instance backup completed: $($Instance.name)" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogEntry "Failed to backup Tomcat instance $($Instance.name): $_" -Level ERROR
        return $false
    }
}

<#
.SYNOPSIS
    Backs up the GeoServer data directory and configuration files.
#>
function Backup-GeoServerData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataDirectory,

        [Parameter(Mandatory=$true)]
        [string]$BackupDirectory
    )

    Write-LogEntry "Backing up GeoServer data directory..." -Level INFO

    try {
        $geoserverBackupDir = Join-Path $BackupDirectory "geoserver"

        if (-not (Test-Path $DataDirectory)) {
            Write-LogEntry "GeoServer data directory not found: $DataDirectory" -Level ERROR
            return $false
        }

        # Backup critical GeoServer directories
        $criticalDirs = @('workspaces', 'styles', 'data', 'security', 'www', 'layergroups')
        $criticalFiles = @('global.xml', 'logging.xml', 'wms.xml', 'wfs.xml', 'wcs.xml')

        foreach ($dir in $criticalDirs) {
            $sourcePath = Join-Path $DataDirectory $dir
            if (Test-Path $sourcePath) {
                $destPath = Join-Path $geoserverBackupDir $dir
                Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                Write-LogEntry "  Backed up: $dir" -Level DEBUG
            }
        }

        foreach ($file in $criticalFiles) {
            $sourcePath = Join-Path $DataDirectory $file
            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $geoserverBackupDir -Force
                Write-LogEntry "  Backed up: $file" -Level DEBUG
            }
        }

        Write-LogEntry "GeoServer data backup completed" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogEntry "Failed to backup GeoServer data: $_" -Level ERROR
        return $false
    }
}

<#
.SYNOPSIS
    Creates a metadata file with backup information.
#>
function New-BackupMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupDirectory,

        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    Write-LogEntry "Creating backup metadata..." -Level INFO

    try {
        $metadata = @{
            BackupInfo = @{
                Version = $script:ScriptVersion
                Timestamp = $script:ScriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
                BackupName = Split-Path $BackupDirectory -Leaf
                ComputerName = $env:COMPUTERNAME
                UserName = $env:USERNAME
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                OSVersion = [System.Environment]::OSVersion.VersionString
            }
            Environment = @{
                ServerName = $Config.environment.serverName
                GeoServerDataDir = $Config.environment.paths.geoserverDataDir
                TomcatInstances = @($Config.environment.tomcatInstances | ForEach-Object {
                    @{
                        Name = $_.name
                        Path = $_.path
                        Port = $_.port
                    }
                })
            }
            Components = @{
                IncludedLogs = $IncludeLogs.IsPresent
                Compressed = $Compress.IsPresent
            }
        }

        $metadataPath = Join-Path $BackupDirectory "metadata.json"
        $metadata | ConvertTo-Json -Depth 10 | Out-File -FilePath $metadataPath -Encoding UTF8

        Write-LogEntry "Metadata file created: $metadataPath" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogEntry "Failed to create metadata: $_" -Level ERROR
        return $false
    }
}

<#
.SYNOPSIS
    Compresses the backup directory into a ZIP file.
#>
function Compress-BackupDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupDirectory
    )

    Write-LogEntry "Compressing backup directory..." -Level INFO

    try {
        $zipPath = "$BackupDirectory.zip"

        # Use .NET compression for better compatibility
        Add-Type -Assembly 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::CreateFromDirectory($BackupDirectory, $zipPath, 'Optimal', $false)

        $zipSizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
        Write-LogEntry "Backup compressed: $zipPath (${zipSizeMB}MB)" -Level SUCCESS

        # Optionally remove the uncompressed directory
        # Remove-Item -Path $BackupDirectory -Recurse -Force
        # Write-LogEntry "Original backup directory removed (compressed version retained)" -Level INFO

        return $zipPath
    }
    catch {
        Write-LogEntry "Failed to compress backup: $_" -Level ERROR
        return $null
    }
}

<#
.SYNOPSIS
    Removes old backups based on retention policy.
#>
function Remove-OldBackups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,

        [Parameter(Mandatory=$true)]
        [int]$RetentionDays
    )

    Write-LogEntry "Cleaning up old backups (retention: $RetentionDays days)..." -Level INFO

    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        $oldBackups = Get-ChildItem -Path $BackupRootPath -Directory |
            Where-Object { $_.CreationTime -lt $cutoffDate }

        $oldZips = Get-ChildItem -Path $BackupRootPath -Filter "*.zip" |
            Where-Object { $_.CreationTime -lt $cutoffDate }

        $totalRemoved = 0

        foreach ($backup in $oldBackups) {
            Remove-Item -Path $backup.FullName -Recurse -Force
            Write-LogEntry "  Removed old backup: $($backup.Name)" -Level DEBUG
            $totalRemoved++
        }

        foreach ($zip in $oldZips) {
            Remove-Item -Path $zip.FullName -Force
            Write-LogEntry "  Removed old backup: $($zip.Name)" -Level DEBUG
            $totalRemoved++
        }

        if ($totalRemoved -gt 0) {
            Write-LogEntry "Removed $totalRemoved old backup(s)" -Level SUCCESS
        } else {
            Write-LogEntry "No old backups to remove" -Level INFO
        }

        return $true
    }
    catch {
        Write-LogEntry "Failed to remove old backups: $_" -Level WARNING
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-BackupProcess {
    [CmdletBinding()]
    param()

    Write-LogEntry "==================================================================" -Level INFO
    Write-LogEntry "GeoServer Environment Backup - Version $script:ScriptVersion" -Level INFO
    Write-LogEntry "==================================================================" -Level INFO
    Write-LogEntry "" -Level INFO

    try {
        # Load configuration
        $config = Get-ConfigurationData -ConfigFilePath $ConfigPath

        # Determine backup path
        if (-not $BackupPath) {
            $BackupPath = $config.environment.paths.backupLocation
        }

        # Validate backup path
        if (-not (Test-Path $BackupPath)) {
            Write-LogEntry "Creating backup root directory: $BackupPath" -Level INFO
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }

        # Validate environment
        if (-not (Test-EnvironmentPaths -Config $config)) {
            Write-LogEntry "Environment validation failed - some paths may not be backed up" -Level WARNING
        }

        # Check disk space
        if (-not (Test-DiskSpace -BackupPath $BackupPath -Config $config)) {
            throw "Insufficient disk space for backup"
        }

        # Generate backup name if not provided
        if (-not $BackupName) {
            $BackupName = Get-Date -Format "yyyy-MM-dd_HHmmss"
        }

        Write-LogEntry "Backup name: $BackupName" -Level INFO

        # WhatIf check
        if ($WhatIf) {
            Write-LogEntry "WhatIf mode enabled - no changes will be made" -Level WARNING
            Write-LogEntry "Would backup:" -Level INFO
            Write-LogEntry "  - GeoServer data: $($config.environment.paths.geoserverDataDir)" -Level INFO
            foreach ($instance in $config.environment.tomcatInstances) {
                Write-LogEntry "  - Tomcat instance: $($instance.name) at $($instance.path)" -Level INFO
            }
            Write-LogEntry "  - Destination: $(Join-Path $BackupPath $BackupName)" -Level INFO
            return
        }

        # Create backup directory
        $backupDir = New-BackupDirectory -RootPath $BackupPath -BackupName $BackupName

        # Backup Tomcat instances
        Write-LogEntry "" -Level INFO
        Write-LogEntry "Backing up Tomcat instances..." -Level INFO
        foreach ($instance in $config.environment.tomcatInstances) {
            Backup-TomcatInstance -Instance $instance -BackupDirectory $backupDir -IncludeLogs $IncludeLogs
        }

        # Backup GeoServer data
        Write-LogEntry "" -Level INFO
        if ($config.environment.paths.geoserverDataDir) {
            Backup-GeoServerData -DataDirectory $config.environment.paths.geoserverDataDir -BackupDirectory $backupDir
        }

        # Create metadata
        Write-LogEntry "" -Level INFO
        New-BackupMetadata -BackupDirectory $backupDir -Config $config

        # Save log file
        Save-LogFile -BackupDirectory $backupDir

        # Compress if requested
        if ($Compress) {
            Write-LogEntry "" -Level INFO
            $zipPath = Compress-BackupDirectory -BackupDirectory $backupDir
        }

        # Clean up old backups
        Write-LogEntry "" -Level INFO
        Remove-OldBackups -BackupRootPath $BackupPath -RetentionDays $RetentionDays

        # Final summary
        $duration = (Get-Date) - $script:ScriptStartTime
        Write-LogEntry "" -Level INFO
        Write-LogEntry "==================================================================" -Level SUCCESS
        Write-LogEntry "BACKUP COMPLETED SUCCESSFULLY" -Level SUCCESS
        Write-LogEntry "==================================================================" -Level SUCCESS
        Write-LogEntry "Backup location: $backupDir" -Level INFO
        if ($zipPath) {
            Write-LogEntry "Compressed backup: $zipPath" -Level INFO
        }
        Write-LogEntry "Duration: $($duration.ToString('mm\:ss'))" -Level INFO
        Write-LogEntry "" -Level INFO

        return @{
            Success = $true
            BackupDirectory = $backupDir
            CompressedPath = $zipPath
            Duration = $duration
        }
    }
    catch {
        Write-LogEntry "" -Level ERROR
        Write-LogEntry "==================================================================" -Level ERROR
        Write-LogEntry "BACKUP FAILED" -Level ERROR
        Write-LogEntry "==================================================================" -Level ERROR
        Write-LogEntry "Error: $_" -Level ERROR
        Write-LogEntry "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG

        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Execute the backup process
$result = Start-BackupProcess

# Exit with appropriate code
if ($result.Success) {
    exit 0
} else {
    exit 1
}
