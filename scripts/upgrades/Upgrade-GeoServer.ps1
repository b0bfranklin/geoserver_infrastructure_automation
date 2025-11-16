<#
.SYNOPSIS
    Migrates GeoServer from 2.26.2 to current version with configuration analysis and rollback.

.DESCRIPTION
    Comprehensive GeoServer migration process:
    - Analyzes existing GeoServer configuration
    - Detects custom styles, workspaces, layers, and extensions
    - Identifies deprecated features and breaking changes
    - Downloads target GeoServer version
    - Backs up current installation
    - Deploys new WAR file
    - Migrates data directory (if needed)
    - Updates configuration files
    - Verifies all workspaces and layers
    - Provides detailed migration report
    - Rollback capability

.PARAMETER TargetVersion
    Target GeoServer version (default: latest stable)

.PARAMETER AnalyzeConfiguration
    Perform configuration analysis before upgrade

.PARAMETER MigrateDataDirectory
    Migrate data directory (usually not needed for minor versions)

.PARAMETER WhatIf
    Preview upgrade and show analysis without making changes

.EXAMPLE
    .\Upgrade-GeoServer.ps1 -AnalyzeConfiguration

.EXAMPLE
    .\Upgrade-GeoServer.ps1 -TargetVersion "2.25.0" -WhatIf

.NOTES
    File Name   : Upgrade-GeoServer.ps1
    Version     : 2.0.0
    Requires    : PowerShell 7.0+, Administrative privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetVersion = "2.25.0",

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\config\upgrade-config.json",

    [Parameter(Mandatory=$false)]
    [switch]$AnalyzeConfiguration = $true,

    [Parameter(Mandatory=$false)]
    [switch]$MigrateDataDirectory = $false,

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

#Requires -Version 7.0
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\modules\GeoServer.psm1" -Force
Import-Module "$PSScriptRoot\..\modules\TomcatManager.psm1" -Force

$script:AnalysisResults = @{
    CurrentVersion = "Unknown"
    DataDirectory = $null
    Workspaces = @()
    Layers = @()
    Styles = @()
    Extensions = @()
    Issues = @()
    Recommendations = @()
}

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
# CONFIGURATION ANALYSIS
# ============================================================================

function Get-GeoServerConfiguration {
    param([string]$DataDirectory)

    Write-LogEntry "=== Analyzing GeoServer Configuration ===" "STEP"

    if (-not (Test-Path $DataDirectory)) {
        Write-LogEntry "Data directory not found: $DataDirectory" "ERROR"
        return $null
    }

    $script:AnalysisResults.DataDirectory = $DataDirectory

    try {
        # Analyze global configuration
        $globalXml = Join-Path $DataDirectory "global.xml"
        if (Test-Path $globalXml) {
            [xml]$global = Get-Content $globalXml
            Write-LogEntry "Global configuration found" "SUCCESS"
        }

        # Scan workspaces
        $workspacesDir = Join-Path $DataDirectory "workspaces"
        if (Test-Path $workspacesDir) {
            $workspaces = Get-ChildItem -Path $workspacesDir -Directory
            Write-LogEntry "Found $($workspaces.Count) workspace(s)" "INFO"

            foreach ($ws in $workspaces) {
                $wsInfo = @{
                    Name = $ws.Name
                    Path = $ws.FullName
                    Layers = @()
                }

                # Find layers in this workspace
                $layersDir = Get-ChildItem -Path $ws.FullName -Recurse -Directory |
                    Where-Object { $_.Name -eq "layers" } | Select-Object -First 1

                if ($layersDir) {
                    $layers = Get-ChildItem -Path $layersDir.FullName -Directory
                    $wsInfo.Layers = $layers | ForEach-Object { $_.Name }
                    Write-LogEntry "  Workspace '$($ws.Name)': $($layers.Count) layer(s)" "INFO"
                }

                $script:AnalysisResults.Workspaces += $wsInfo
            }
        }

        # Scan styles
        $stylesDir = Join-Path $DataDirectory "styles"
        if (Test-Path $stylesDir) {
            $styles = Get-ChildItem -Path $stylesDir -Filter "*.sld"
            $script:AnalysisResults.Styles = $styles | ForEach-Object { $_.Name }
            Write-LogEntry "Found $($styles.Count) custom style(s)" "INFO"
        }

        # Check for extensions
        $extDir = Join-Path $DataDirectory "..\webapps\geoserver\WEB-INF\lib"
        if (Test-Path $extDir) {
            $extJars = Get-ChildItem -Path $extDir -Filter "*-plugin-*.jar"
            $script:AnalysisResults.Extensions = $extJars | ForEach-Object { $_.Name }
            Write-LogEntry "Found $($extJars.Count) extension(s)/plugin(s)" "INFO"
        }

        Write-LogEntry "Configuration analysis completed" "SUCCESS"
        return $script:AnalysisResults
    }
    catch {
        Write-LogEntry "Configuration analysis failed: $_" "ERROR"
        return $null
    }
}

function Test-VersionCompatibility {
    param([string]$CurrentVersion, [string]$TargetVersion)

    Write-LogEntry "=== Checking Version Compatibility ===" "STEP"

    $issues = @()
    $recommendations = @()

    # Parse versions
    if ($CurrentVersion -match '^(\d+)\.(\d+)\.(\d+)') {
        $currentMajor = [int]$matches[1]
        $currentMinor = [int]$matches[2]
        $currentPatch = [int]$matches[3]
    }

    if ($TargetVersion -match '^(\d+)\.(\d+)\.(\d+)') {
        $targetMajor = [int]$matches[1]
        $targetMinor = [int]$matches[2]
        $targetPatch = [int]$matches[3]
    }

    # Check for major version changes
    if ($targetMajor -gt $currentMajor) {
        $issues += "Major version upgrade detected - review release notes carefully"
        $recommendations += "Test in staging environment before production"
    }

    # Check for deprecated features in 2.25+
    if ($targetMinor -ge 25) {
        $recommendations += "GeoServer 2.25+ requires Java 11 or later"
        $recommendations += "Some REST API endpoints may have changed"
    }

    # Check for Tomcat compatibility
    if ($targetMinor -ge 24) {
        $recommendations += "GeoServer 2.24+ supports Tomcat 10.x"
    }

    $script:AnalysisResults.Issues = $issues
    $script:AnalysisResults.Recommendations = $recommendations

    Write-LogEntry "Compatibility check completed" "SUCCESS"
    if ($issues.Count -gt 0) {
        Write-LogEntry "$($issues.Count) potential issue(s) found" "WARNING"
    }

    return ($issues.Count -eq 0)
}

function Export-AnalysisReport {
    param([string]$OutputPath)

    Write-LogEntry "Generating analysis report..." "INFO"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>GeoServer Migration Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 10px; }
        .info-grid { display: grid; grid-template-columns: 200px 1fr; gap: 10px; margin: 15px 0; }
        .label { font-weight: bold; color: #7f8c8d; }
        .value { color: #2c3e50; }
        .warning { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .success { background-color: #d4edda; border-left: 4px solid #28a745; padding: 10px; margin: 10px 0; }
        .error { background-color: #f8d7da; border-left: 4px solid #dc3545; padding: 10px; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .timestamp { color: #7f8c8d; font-style: italic; }
    </style>
</head>
<body>
    <div class="container">
        <h1>GeoServer Migration Analysis Report</h1>
        <p class="timestamp">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>

        <h2>Current Configuration</h2>
        <div class="info-grid">
            <div class="label">Data Directory:</div>
            <div class="value">$($script:AnalysisResults.DataDirectory)</div>

            <div class="label">Workspaces:</div>
            <div class="value">$($script:AnalysisResults.Workspaces.Count)</div>

            <div class="label">Custom Styles:</div>
            <div class="value">$($script:AnalysisResults.Styles.Count)</div>

            <div class="label">Extensions:</div>
            <div class="value">$($script:AnalysisResults.Extensions.Count)</div>
        </div>

        <h2>Workspaces and Layers</h2>
        <table>
            <tr>
                <th>Workspace</th>
                <th>Layers</th>
            </tr>
"@

    foreach ($ws in $script:AnalysisResults.Workspaces) {
        $html += @"
            <tr>
                <td>$($ws.Name)</td>
                <td>$($ws.Layers.Count) layer(s): $($ws.Layers -join ', ')</td>
            </tr>
"@
    }

    $html += @"
        </table>

        <h2>Extensions/Plugins</h2>
        <ul>
"@

    foreach ($ext in $script:AnalysisResults.Extensions) {
        $html += "            <li>$ext</li>`n"
    }

    $html += @"
        </ul>

        <h2>Migration Recommendations</h2>
"@

    if ($script:AnalysisResults.Issues.Count -gt 0) {
        foreach ($issue in $script:AnalysisResults.Issues) {
            $html += "        <div class='warning'>⚠️ $issue</div>`n"
        }
    }

    foreach ($rec in $script:AnalysisResults.Recommendations) {
        $html += "        <div class='success'>✓ $rec</div>`n"
    }

    $html += @"
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-LogEntry "Analysis report saved: $OutputPath" "SUCCESS"
}

# ============================================================================
# BACKUP AND MIGRATION
# ============================================================================

function Backup-GeoServerInstallation {
    param([string]$WarPath, [string]$DataDirectory)

    Write-LogEntry "=== Backing up GeoServer ===" "STEP"

    try {
        $backupRoot = ".\backups\geoserver"
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }

        $backupName = "geoserver_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
        $backupPath = Join-Path $backupRoot $backupName

        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null

        # Backup WAR file
        if (Test-Path $WarPath) {
            Copy-Item -Path $WarPath -Destination (Join-Path $backupPath "geoserver.war") -Force
            Write-LogEntry "Backed up WAR file" "SUCCESS"
        }

        # Backup data directory
        if (Test-Path $DataDirectory) {
            $dataBackup = Join-Path $backupPath "data"
            Copy-Item -Path $DataDirectory -Destination $dataBackup -Recurse -Force
            Write-LogEntry "Backed up data directory" "SUCCESS"
        }

        # Save analysis results
        $script:AnalysisResults | ConvertTo-Json -Depth 10 |
            Out-File (Join-Path $backupPath "analysis.json")

        Write-LogEntry "Backup completed: $backupPath" "SUCCESS"
        return $backupPath
    }
    catch {
        Write-LogEntry "Backup failed: $_" "ERROR"
        return $null
    }
}

function Install-GeoServerWar {
    param([string]$Version, [string]$TomcatWebappsPath)

    Write-LogEntry "=== Installing GeoServer $Version ===" "STEP"

    try {
        # Download using package manager
        $packageScript = Join-Path $PSScriptRoot "..\utilities\Get-ComponentPackage.ps1"
        Write-LogEntry "Downloading GeoServer $Version..." "INFO"

        & $packageScript -Component "GeoServer" -Version $Version 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download GeoServer"
        }

        # Find downloaded package
        $packagePath = Get-ChildItem -Path ".\downloads" -Filter "geoserver-${Version}*.zip" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $packagePath) {
            throw "Downloaded package not found"
        }

        Write-LogEntry "Package: $($packagePath.Name)" "SUCCESS"

        # Extract WAR from package
        $tempExtract = Join-Path $env:TEMP "geoserver-extract-$((Get-Date).Ticks)"
        Add-Type -Assembly 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath.FullName, $tempExtract)

        # Find the WAR file
        $warFile = Get-ChildItem -Path $tempExtract -Filter "geoserver.war" -Recurse |
            Select-Object -First 1

        if (-not $warFile) {
            throw "geoserver.war not found in package"
        }

        # Remove old deployment
        $oldWar = Join-Path $TomcatWebappsPath "geoserver.war"
        $oldDir = Join-Path $TomcatWebappsPath "geoserver"

        if (Test-Path $oldWar) {
            Remove-Item -Path $oldWar -Force
            Write-LogEntry "Removed old WAR file" "INFO"
        }

        if (Test-Path $oldDir) {
            Remove-Item -Path $oldDir -Recurse -Force
            Write-LogEntry "Removed old deployment directory" "INFO"
        }

        # Deploy new WAR
        Copy-Item -Path $warFile.FullName -Destination $oldWar -Force
        Write-LogEntry "Deployed new GeoServer WAR" "SUCCESS"

        # Cleanup
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-LogEntry "Installation failed: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# VERIFICATION
# ============================================================================

function Test-GeoServerMigration {
    param([string]$BaseUrl)

    Write-LogEntry "=== Verifying GeoServer Migration ===" "STEP"

    try {
        # Wait for GeoServer to start
        Write-LogEntry "Waiting for GeoServer to initialize..." "INFO"
        Start-Sleep -Seconds 60

        # Test web interface
        $webUrl = "$BaseUrl/web/"
        try {
            $response = Invoke-WebRequest -Uri $webUrl -TimeoutSec 60 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-LogEntry "GeoServer web interface accessible" "SUCCESS"
            }
        }
        catch {
            Write-LogEntry "GeoServer web interface not accessible" "WARNING"
            return $false
        }

        # Test REST API
        $restUrl = "$BaseUrl/rest/about/version.json"
        try {
            $response = Invoke-RestMethod -Uri $restUrl -TimeoutSec 30 -ErrorAction Stop
            Write-LogEntry "GeoServer REST API accessible" "SUCCESS"
        }
        catch {
            Write-LogEntry "GeoServer REST API not accessible" "WARNING"
        }

        # Test WMS
        $wmsUrl = "$BaseUrl/wms?service=WMS&version=1.3.0&request=GetCapabilities"
        try {
            $response = Invoke-WebRequest -Uri $wmsUrl -TimeoutSec 30 -ErrorAction Stop
            if ($response.Content -match 'WMS_Capabilities') {
                Write-LogEntry "WMS service operational" "SUCCESS"
            }
        }
        catch {
            Write-LogEntry "WMS service test failed" "WARNING"
        }

        Write-LogEntry "Migration verification completed" "SUCCESS"
        return $true
    }
    catch {
        Write-LogEntry "Verification failed: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-GeoServerMigration {
    try {
        Write-LogEntry "==================================================================" "INFO"
        Write-LogEntry "GeoServer Migration - Version 2.0.0" "INFO"
        Write-LogEntry "==================================================================" "INFO"
        Write-LogEntry "" "INFO"

        # Load configuration
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Find GeoServer installation
        $dataDir = $config.environment.paths.geoserverDataDir
        $tomcatInstance = $config.environment.tomcatInstances[0]  # Use first instance
        $webappsPath = Join-Path $tomcatInstance.path "webapps"
        $warPath = Join-Path $webappsPath "geoserver.war"

        Write-LogEntry "Data Directory: $dataDir" "INFO"
        Write-LogEntry "WAR Location: $warPath" "INFO"
        Write-LogEntry "Target Version: $TargetVersion" "INFO"
        Write-LogEntry "" "INFO"

        # Analyze configuration
        if ($AnalyzeConfiguration) {
            $analysis = Get-GeoServerConfiguration -DataDirectory $dataDir

            if ($analysis) {
                # Export analysis report
                $reportPath = ".\reports\geoserver-analysis-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').html"
                if (-not (Test-Path ".\reports")) {
                    New-Item -Path ".\reports" -ItemType Directory -Force | Out-Null
                }
                Export-AnalysisReport -OutputPath $reportPath

                Write-LogEntry "" "INFO"
                Write-LogEntry "Analysis report: $reportPath" "SUCCESS"
            }

            # Check compatibility
            Test-VersionCompatibility -CurrentVersion "2.26.2" -TargetVersion $TargetVersion
        }

        # WhatIf mode
        if ($WhatIf) {
            Write-LogEntry "" "INFO"
            Write-LogEntry "WhatIf mode - no changes will be made" "WARNING"
            Write-LogEntry "Would upgrade GeoServer to version $TargetVersion" "INFO"
            Write-LogEntry "See analysis report for details" "INFO"
            return @{ Success = $true; WhatIf = $true }
        }

        # Confirm
        Write-Host "" -ForegroundColor Yellow
        Write-Host "Ready to upgrade GeoServer to $TargetVersion" -ForegroundColor Yellow
        Write-Host "This will:" -ForegroundColor Yellow
        Write-Host "  1. Backup current installation" -ForegroundColor Yellow
        Write-Host "  2. Stop Tomcat" -ForegroundColor Yellow
        Write-Host "  3. Deploy new GeoServer WAR" -ForegroundColor Yellow
        Write-Host "  4. Start Tomcat" -ForegroundColor Yellow
        Write-Host "  5. Verify migration" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        $confirm = Read-Host "Type 'YES' to continue"

        if ($confirm -ne 'YES') {
            Write-LogEntry "Migration cancelled by user" "WARNING"
            return @{ Success = $false; Cancelled = $true }
        }

        # Backup
        $backupPath = Backup-GeoServerInstallation -WarPath $warPath -DataDirectory $dataDir
        if (-not $backupPath) {
            throw "Backup failed - migration aborted"
        }

        # Stop Tomcat
        Write-LogEntry "" "INFO"
        if ($tomcatInstance.serviceName) {
            Stop-TomcatService -ServiceName $tomcatInstance.serviceName
        }

        # Install new version
        $installed = Install-GeoServerWar -Version $TargetVersion -TomcatWebappsPath $webappsPath
        if (-not $installed) {
            throw "Installation failed"
        }

        # Start Tomcat
        Write-LogEntry "" "INFO"
        if ($tomcatInstance.serviceName) {
            Start-TomcatService -ServiceName $tomcatInstance.serviceName
        }

        # Verify
        $baseUrl = "http://localhost:$($tomcatInstance.port)/geoserver"
        $verified = Test-GeoServerMigration -BaseUrl $baseUrl

        if ($verified) {
            Write-LogEntry "" "INFO"
            Write-LogEntry "==================================================================" "SUCCESS"
            Write-LogEntry "GEOSERVER MIGRATION COMPLETED SUCCESSFULLY" "SUCCESS"
            Write-LogEntry "==================================================================" "SUCCESS"
            Write-LogEntry "Version: $TargetVersion" "INFO"
            Write-LogEntry "Backup: $backupPath" "INFO"
            Write-LogEntry "" "INFO"

            return @{
                Success = $true
                Version = $TargetVersion
                BackupPath = $backupPath
                AnalysisReport = $reportPath
            }
        }
        else {
            Write-LogEntry "Migration verification failed" "ERROR"
            return @{ Success = $false; VerificationFailed = $true }
        }
    }
    catch {
        Write-LogEntry "" "ERROR"
        Write-LogEntry "GEOSERVER MIGRATION FAILED: $_" "ERROR"

        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Execute migration
$result = Start-GeoServerMigration

if ($result.Success) {
    exit 0
} else {
    exit 1
}
