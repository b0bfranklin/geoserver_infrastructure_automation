<#
.SYNOPSIS
    Performs unattended component upgrades with automated testing and rollback.

.DESCRIPTION
    This script orchestrates fully unattended infrastructure upgrades:
    1. Checks for available component updates
    2. Creates comprehensive backup
    3. Performs upgrades in dependency order
    4. Runs integration tests after each upgrade
    5. Automatically rolls back on test failures
    6. Sends email notifications of results

    Designed for scheduled execution via Task Scheduler during maintenance windows.

.PARAMETER Components
    Components to upgrade (default: all with updates available).

.PARAMETER SkipTests
    Skip post-upgrade integration tests (NOT RECOMMENDED).

.PARAMETER EmailReport
    Email detailed upgrade report.

.PARAMETER DryRun
    Simulate upgrade without making changes.

.EXAMPLE
    .\Invoke-UnattendedUpgrade.ps1 -EmailReport
    # Run unattended upgrades and email results

.EXAMPLE
    .\Invoke-UnattendedUpgrade.ps1 -DryRun
    # Simulate upgrade process

.NOTES
    Author: GeoServer Infrastructure Automation Suite
    Version: 2.2.0
    Requires: PowerShell 7.0+, Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Components to upgrade")]
    [string[]]$Components,

    [Parameter(HelpMessage = "Skip integration tests")]
    [switch]$SkipTests,

    [Parameter(HelpMessage = "Email upgrade report")]
    [switch]$EmailReport,

    [Parameter(HelpMessage = "Dry run (no changes)")]
    [switch]$DryRun
)

#Requires -Version 7.0
#Requires -RunAsAdministrator

# ============================================================================
# REPOSITORY ROOT DETECTION
# ============================================================================

# Determine repository root (works regardless of execution directory)
$script:RepositoryRoot = if ($PSScriptRoot) {
    # Scripts are in scripts/utilities/, so go up 2 levels
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
} else {
    # Fallback for interactive sessions
    Get-Location | Select-Object -ExpandProperty Path
}

# Validate repository root
if (-not (Test-Path (Join-Path $script:RepositoryRoot "config"))) {
    throw "Repository root detection failed. Expected config directory at: $script:RepositoryRoot"
}

# Determine log directory (platform-aware)
$script:LogDirectory = if ($env:GEOSERVER_LOG_DIR) {
    # Use environment variable if set
    $env:GEOSERVER_LOG_DIR
} elseif ($IsWindows) {
    # Windows default
    "C:\GeoServerLogs"
} else {
    # Linux/macOS default
    Join-Path $script:RepositoryRoot "logs"
}

# Ensure log directory exists
if (-not (Test-Path $script:LogDirectory)) {
    New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
}

# Script variables
$script:LogPath = Join-Path $script:LogDirectory "unattended-upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:UpgradeResults = @()

#region Logging Functions

function Write-LogEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    $logDir = Split-Path $script:LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Add-Content -Path $script:LogPath -Value $logMessage

    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'DEBUG'   { Write-Host $logMessage -ForegroundColor Gray }
        default   { Write-Host $logMessage -ForegroundColor White }
    }
}

function Write-SectionHeader {
    param([string]$Title)
    $separator = "=" * 80
    Write-LogEntry $separator -Level INFO
    Write-LogEntry "  $Title" -Level INFO
    Write-LogEntry $separator -Level INFO
}

#endregion

#region Upgrade Orchestration

function Invoke-ComponentUpgrade {
    <#
    .SYNOPSIS
        Upgrades a single component with testing and rollback.
    #>
    param(
        [string]$ComponentName,
        [string]$UpgradeScript
    )

    Write-SectionHeader "Upgrading $ComponentName"

    $startTime = Get-Date
    $result = [PSCustomObject]@{
        Component = $ComponentName
        StartTime = $startTime
        EndTime = $null
        Duration = $null
        Status = "Unknown"
        Message = ""
        TestsPassed = $false
        RolledBack = $false
    }

    try {
        # Execute upgrade
        if ($DryRun) {
            Write-LogEntry "DRY RUN: Would execute $UpgradeScript" -Level INFO
            $result.Status = "DryRun"
            $result.Message = "Simulated upgrade"
        } else {
            Write-LogEntry "Executing upgrade script: $UpgradeScript" -Level INFO
            & $UpgradeScript

            if ($LASTEXITCODE -eq 0) {
                Write-LogEntry "$ComponentName upgrade completed" -Level SUCCESS
                $result.Status = "UpgradeSuccess"
                $result.Message = "Upgrade completed successfully"
            } else {
                Write-LogEntry "$ComponentName upgrade failed with exit code $LASTEXITCODE" -Level ERROR
                $result.Status = "UpgradeFailed"
                $result.Message = "Upgrade failed with exit code $LASTEXITCODE"
            }
        }

        # Run integration tests if upgrade succeeded and not skipped
        if ($result.Status -eq "UpgradeSuccess" -and -not $SkipTests) {
            Write-LogEntry "Running integration tests for $ComponentName..." -Level INFO
            $testScript = Join-Path $script:RepositoryRoot "tests\integration\Invoke-IntegrationTests.ps1"

            if (Test-Path $testScript) {
                & $testScript -StopOnFailure

                if ($LASTEXITCODE -eq 0) {
                    Write-LogEntry "Integration tests passed" -Level SUCCESS
                    $result.TestsPassed = $true
                } else {
                    Write-LogEntry "Integration tests FAILED - initiating rollback" -Level ERROR
                    $result.TestsPassed = $false

                    # Rollback
                    Write-LogEntry "Rolling back $ComponentName..." -Level WARNING
                    $rollbackScript = Join-Path $script:RepositoryRoot "scripts\core\Restore-GeoServerEnvironment.ps1"

                    if (Test-Path $rollbackScript) {
                        & $rollbackScript -RestoreComponents $ComponentName
                        $result.RolledBack = $true
                        $result.Status = "RolledBack"
                        $result.Message = "Upgrade failed tests, rolled back to previous version"
                    }
                }
            } else {
                Write-LogEntry "Integration test script not found" -Level WARNING
                $result.TestsPassed = $null
            }
        }

    } catch {
        Write-LogEntry "Error during $ComponentName upgrade: $_" -Level ERROR
        $result.Status = "Error"
        $result.Message = $_.Exception.Message
    }

    $result.EndTime = Get-Date
    $result.Duration = $result.EndTime - $startTime

    $script:UpgradeResults += $result
    return $result
}

#endregion

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-SectionHeader "Unattended Upgrade Process Starting"
    Write-LogEntry "Log file: $script:LogPath" -Level INFO

    if ($DryRun) {
        Write-LogEntry "DRY RUN MODE - No changes will be made" -Level WARNING
    }

    # Step 1: Check for updates
    Write-SectionHeader "Checking for Available Updates"
    $versionCheckScript = Join-Path $script:RepositoryRoot "scripts\utilities\Test-VersionUpdates.ps1"
    $tempPath = Join-Path $script:RepositoryRoot "temp\version-check.json"
    & $versionCheckScript -OutputFormat JSON -OutputPath $tempPath

    # Load version check results
    $availableUpdates = @()
    if (Test-Path $tempPath) {
        $versionResults = Get-Content $tempPath -Raw | ConvertFrom-Json
        $availableUpdates = $versionResults | Where-Object { $_.UpdateAvailable -or $_.SecurityIssues.Count -gt 0 }
    }

    if ($availableUpdates.Count -eq 0) {
        Write-LogEntry "No updates available" -Level SUCCESS
        exit 0
    }

    Write-LogEntry "Found $($availableUpdates.Count) component(s) with available updates" -Level INFO
    foreach ($update in $availableUpdates) {
        Write-LogEntry "  - $($update.Component): $($update.CurrentVersion) → $($update.LatestVersion)" -Level INFO
        if ($update.SecurityIssues.Count -gt 0) {
            Write-LogEntry "    SECURITY: $($update.SecurityIssues.Count) issue(s) found" -Level WARNING
        }
    }

    # Step 2: Create backup
    if (-not $DryRun) {
        Write-SectionHeader "Creating Pre-Upgrade Backup"
        $backupScript = Join-Path $script:RepositoryRoot "scripts\core\Backup-GeoServerEnvironment.ps1"
        & $backupScript -BackupName "pre-unattended-upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    # Step 3: Upgrade components in dependency order
    $upgradeOrder = @(
        @{ Name = "Java"; Script = Join-Path $script:RepositoryRoot "scripts\upgrades\Upgrade-AzulJRE.ps1" },
        @{ Name = "Tomcat"; Script = Join-Path $script:RepositoryRoot "scripts\upgrades\Upgrade-Tomcat.ps1" },
        @{ Name = "PostgreSQL"; Script = Join-Path $script:RepositoryRoot "scripts\upgrades\Upgrade-PostgreSQL.ps1" },
        @{ Name = "GeoServer"; Script = Join-Path $script:RepositoryRoot "scripts\upgrades\Upgrade-GeoServer.ps1" },
        @{ Name = "pgAdmin"; Script = Join-Path $script:RepositoryRoot "scripts\upgrades\Upgrade-pgAdmin.ps1" },
        @{ Name = "QGIS"; Script = Join-Path $script:RepositoryRoot "scripts\upgrades\Upgrade-QGIS.ps1" }
    )

    foreach ($component in $upgradeOrder) {
        # Check if this component needs upgrading
        $needsUpgrade = $availableUpdates | Where-Object { $_.Component -eq $component.Name }

        if ($needsUpgrade -and (Test-Path $component.Script)) {
            Invoke-ComponentUpgrade -ComponentName $component.Name -UpgradeScript $component.Script

            # Stop if upgrade failed and rolled back
            $lastResult = $script:UpgradeResults | Select-Object -Last 1
            if ($lastResult.RolledBack) {
                Write-LogEntry "Stopping upgrade process due to rollback" -Level ERROR
                break
            }
        }
    }

    # Step 4: Generate report
    Write-SectionHeader "Upgrade Summary"
    $successful = ($script:UpgradeResults | Where-Object { $_.Status -eq "UpgradeSuccess" -and $_.TestsPassed }).Count
    $failed = ($script:UpgradeResults | Where-Object { $_.Status -ne "UpgradeSuccess" -or -not $_.TestsPassed }).Count

    Write-Host "`nUpgrade Results:" -ForegroundColor Cyan
    Write-Host "  Successful: " -NoNewline; Write-Host $successful -ForegroundColor Green
    Write-Host "  Failed:     " -NoNewline; Write-Host $failed -ForegroundColor Red

    foreach ($result in $script:UpgradeResults) {
        $color = if ($result.Status -eq "UpgradeSuccess" -and $result.TestsPassed) { "Green" } else { "Red" }
        Write-Host "`n$($result.Component):" -ForegroundColor White
        Write-Host "  Status: $($result.Status)" -ForegroundColor $color
        Write-Host "  Message: $($result.Message)" -ForegroundColor Gray
        Write-Host "  Duration: $([math]::Round($result.Duration.TotalMinutes, 2)) minutes" -ForegroundColor Gray
    }

    # Step 5: Send email report if requested
    if ($EmailReport) {
        $emailScript = Join-Path $script:RepositoryRoot "scripts\utilities\Send-EmailNotification.ps1"
        if (Test-Path $emailScript) {
            $templateData = @{
                Component = "Multiple Components"
                Message = "Unattended upgrade completed with $successful successful and $failed failed upgrade(s)"
            }
            & $emailScript -Template "MaintenanceScheduled" -TemplateData $templateData -AttachmentPath $script:LogPath
        }
    }

    Write-LogEntry "Unattended upgrade process completed" -Level SUCCESS
    exit ($failed -gt 0 ? 1 : 0)

} catch {
    Write-LogEntry "Critical error: $_" -Level ERROR
    Write-LogEntry $_.ScriptStackTrace -Level DEBUG
    exit 1
}
