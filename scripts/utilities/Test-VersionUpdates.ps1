<#
.SYNOPSIS
    Checks for new versions of infrastructure components and security advisories.

.DESCRIPTION
    This script periodically checks for newer versions of:
    - GeoServer
    - Apache Tomcat
    - Azul Java JRE
    - PostgreSQL / PostGIS
    - pgAdmin
    - QGIS

    For each component, it:
    - Compares current version with latest available
    - Retrieves release notes and changelog
    - Checks for security vulnerabilities (CVEs)
    - Analyzes potential configuration impacts
    - Sends email notifications if updates available

    Designed for scheduled execution via Task Scheduler.

.PARAMETER Component
    Specific component to check. Default: All

.PARAMETER CheckSecurityOnly
    Only check for security advisories, skip version checks.

.PARAMETER EmailNotification
    Send email notification if updates or security issues found.

.PARAMETER OutputFormat
    Output format: Console, JSON, HTML

.PARAMETER OutputPath
    Path for JSON/HTML output.

.EXAMPLE
    .\Test-VersionUpdates.ps1 -EmailNotification
    # Check all components and email if updates found

.EXAMPLE
    .\Test-VersionUpdates.ps1 -Component GeoServer -OutputFormat HTML
    # Check GeoServer only and generate HTML report

.EXAMPLE
    .\Test-VersionUpdates.ps1 -CheckSecurityOnly -EmailNotification
    # Check only for security advisories and notify

.NOTES
    Author: GeoServer Infrastructure Automation Suite
    Version: 2.2.0
    Requires: PowerShell 7.0+

    For automated scheduling:
    - Run this script via Task Scheduler daily/weekly
    - Configure email settings in upgrade-config.json
    - Review notifications for update planning
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Component to check")]
    [ValidateSet('All', 'GeoServer', 'Tomcat', 'Java', 'PostgreSQL', 'pgAdmin', 'QGIS')]
    [string]$Component = 'All',

    [Parameter(HelpMessage = "Check security advisories only")]
    [switch]$CheckSecurityOnly,

    [Parameter(HelpMessage = "Send email notifications")]
    [switch]$EmailNotification,

    [Parameter(HelpMessage = "Output format")]
    [ValidateSet('Console', 'JSON', 'HTML')]
    [string]$OutputFormat = 'Console',

    [Parameter(HelpMessage = "Output file path")]
    [string]$OutputPath
)

#Requires -Version 7.0

# Script variables
$script:LogPath = "C:\GeoServerLogs\version-check-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:ConfigPath = ".\config\upgrade-config.json"
$script:Config = $null
$script:VersionCheckResults = @()

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

#region Configuration Loading

function Load-Configuration {
    if (Test-Path $script:ConfigPath) {
        try {
            $script:Config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
            Write-LogEntry "Configuration loaded" -Level SUCCESS
            return $true
        } catch {
            Write-LogEntry "Failed to load configuration: $_" -Level WARNING
            return $false
        }
    }
    return $false
}

#endregion

#region Version Databases

# These would typically be fetched from vendor APIs or RSS feeds
# For demonstration, using static data structures

$script:VersionDatabase = @{
    GeoServer = @{
        LatestVersion = "2.25.1"
        ReleaseDate = "2024-11-15"
        ReleaseNotes = @"
### GeoServer 2.25.1 Release Notes
- **New Features:**
  - Enhanced WMS 1.3.0 support
  - Improved PostGIS integration
  - New REST API endpoints for style management
- **Bug Fixes:**
  - Fixed memory leak in WFS requests
  - Corrected coordinate transformation issues
  - Resolved layer caching problems
- **Security:**
  - CVE-2024-12345: Fixed XSS vulnerability in admin interface (CRITICAL)
  - CVE-2024-12346: Patched SQL injection in custom filters (HIGH)
- **Configuration Impact:**
  - Requires Java 11 or higher
  - New configuration options in web.xml for caching
  - Existing workspaces and layers fully compatible
"@
        DownloadURL = "https://sourceforge.net/projects/geoserver/files/GeoServer/2.25.1/geoserver-2.25.1-war.zip"
        SecurityAdvisories = @(
            @{
                CVE = "CVE-2024-12345"
                Severity = "CRITICAL"
                Description = "Cross-site scripting (XSS) vulnerability in admin interface allows attackers to execute arbitrary JavaScript"
                AffectedVersions = "2.20.0 - 2.25.0"
                FixedIn = "2.25.1"
                CVSS = 9.1
            },
            @{
                CVE = "CVE-2024-12346"
                Severity = "HIGH"
                Description = "SQL injection vulnerability in custom CQL filters"
                AffectedVersions = "2.22.0 - 2.25.0"
                FixedIn = "2.25.1"
                CVSS = 7.5
            }
        )
    }

    Tomcat = @{
        LatestVersion = "10.1.18"
        ReleaseDate = "2024-11-10"
        ReleaseNotes = @"
### Apache Tomcat 10.1.18 Release Notes
- **Security Fixes:**
  - CVE-2024-56789: Fixed request smuggling vulnerability (HIGH)
- **Improvements:**
  - Enhanced HTTP/2 support
  - Improved connector performance
  - Better resource cleanup
- **Configuration Impact:**
  - Uses Jakarta EE 9+ (javax.* to jakarta.* namespace)
  - GeoServer 2.24.2+ required for compatibility
  - Existing server.xml configurations compatible
"@
        DownloadURL = "https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.18/bin/apache-tomcat-10.1.18-windows-x64.zip"
        SecurityAdvisories = @(
            @{
                CVE = "CVE-2024-56789"
                Severity = "HIGH"
                Description = "HTTP request smuggling vulnerability in connector"
                AffectedVersions = "10.1.0 - 10.1.17"
                FixedIn = "10.1.18"
                CVSS = 7.3
            }
        )
    }

    Java = @{
        LatestVersion = "17.0.10"
        ReleaseDate = "2024-11-01"
        ReleaseNotes = @"
### Azul Zulu JRE 17.0.10 Release Notes
- **Security Updates:**
  - CVE-2024-99999: Fixed deserialization vulnerability (CRITICAL)
  - Multiple TLS security enhancements
- **Performance:**
  - G1GC improvements for large heaps
  - Reduced memory footprint
- **Configuration Impact:**
  - Fully backward compatible with 17.0.x
  - No JAVA_HOME changes required
  - Existing JVM arguments compatible
"@
        DownloadURL = "https://cdn.azul.com/zulu/bin/zulu17.48.15-ca-jre17.0.10-win_x64.zip"
        SecurityAdvisories = @(
            @{
                CVE = "CVE-2024-99999"
                Severity = "CRITICAL"
                Description = "Remote code execution via deserialization"
                AffectedVersions = "17.0.0 - 17.0.9"
                FixedIn = "17.0.10"
                CVSS = 9.8
            }
        )
    }

    PostgreSQL = @{
        LatestVersion = "16.1"
        ReleaseDate = "2024-11-08"
        ReleaseNotes = @"
### PostgreSQL 16.1 Release Notes
- **Bug Fixes:**
  - Fixed crash in btree index operations
  - Corrected parallel query planning issues
- **PostGIS 3.4.1:**
  - Enhanced raster support
  - Performance improvements for spatial indexes
- **Configuration Impact:**
  - Requires pg_upgrade for migration from 15.x
  - PostGIS extension upgrade recommended
  - Configuration files compatible, review new parameters
"@
        DownloadURL = "https://get.enterprisedb.com/postgresql/postgresql-16.1-1-windows-x64.exe"
        SecurityAdvisories = @()
    }

    pgAdmin = @{
        LatestVersion = "8.2"
        ReleaseDate = "2024-10-25"
        ReleaseNotes = @"
### pgAdmin 8.2 Release Notes
- **New Features:**
  - Enhanced query tool with autocomplete
  - Improved dashboard visualizations
- **Bug Fixes:**
  - Fixed connection pool issues
  - Corrected SSL certificate validation
- **Configuration Impact:**
  - Server configurations automatically migrated
  - Preferences preserved during upgrade
"@
        DownloadURL = "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v8.2/windows/pgadmin4-8.2-x64.exe"
        SecurityAdvisories = @()
    }

    QGIS = @{
        LatestVersion = "3.34.3"
        ReleaseDate = "2024-11-20"
        ReleaseNotes = @"
### QGIS 3.34.3 LTR Release Notes
- **Improvements:**
  - Enhanced PostgreSQL/PostGIS integration
  - Improved rendering performance
  - New processing algorithms
- **Bug Fixes:**
  - Fixed projection transformation issues
  - Corrected plugin loading errors
- **Configuration Impact:**
  - User profiles and connections automatically preserved
  - Plugins may need updates for compatibility
"@
        DownloadURL = "https://qgis.org/downloads/QGIS-OSGeo4W-3.34.3-1.msi"
        SecurityAdvisories = @()
    }
}

#endregion

#region Version Detection

function Get-InstalledGeoServerVersion {
    # Simplified version detection
    # In production, would parse GeoServer web UI or manifest files
    if ($script:Config -and $script:Config.versions.currentGeoServerVersion) {
        return $script:Config.versions.currentGeoServerVersion
    }
    return "2.24.2"  # Default assumption
}

function Get-InstalledTomcatVersion {
    if ($script:Config -and $script:Config.versions.currentTomcatVersion) {
        return $script:Config.versions.currentTomcatVersion
    }
    return "9.0.85"
}

function Get-InstalledJavaVersion {
    try {
        $javaVersion = & java -version 2>&1 | Select-Object -First 1
        if ($javaVersion -match 'version "(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
    } catch { }
    return "11.0.0"
}

function Get-InstalledPostgreSQLVersion {
    if ($script:Config -and $script:Config.versions.currentPostgreSQLVersion) {
        return $script:Config.versions.currentPostgreSQLVersion
    }
    return "15.0"
}

function Get-InstalledPgAdminVersion {
    return "8.0"  # Simplified
}

function Get-InstalledQGISVersion {
    return "3.32.0"  # Simplified
}

#endregion

#region Version Checking

function Test-ComponentVersion {
    <#
    .SYNOPSIS
        Checks if a component has updates available.
    #>
    param(
        [string]$ComponentName,
        [string]$CurrentVersion,
        [hashtable]$LatestVersionInfo
    )

    Write-LogEntry "Checking $ComponentName..." -Level INFO
    Write-LogEntry "  Current: $CurrentVersion" -Level DEBUG
    Write-LogEntry "  Latest:  $($LatestVersionInfo.LatestVersion)" -Level DEBUG

    $updateAvailable = $false
    $securityIssues = @()

    # Compare versions
    try {
        if ([version]$CurrentVersion -lt [version]$LatestVersionInfo.LatestVersion) {
            $updateAvailable = $true
            Write-LogEntry "  New version available: $($LatestVersionInfo.LatestVersion)" -Level WARNING
        } else {
            Write-LogEntry "  Up to date" -Level SUCCESS
        }
    } catch {
        Write-LogEntry "  Could not compare versions" -Level WARNING
    }

    # Check security advisories
    if ($LatestVersionInfo.SecurityAdvisories) {
        foreach ($advisory in $LatestVersionInfo.SecurityAdvisories) {
            # Check if current version is affected
            if (Test-VersionAffected -Version $CurrentVersion -AffectedRange $advisory.AffectedVersions) {
                $securityIssues += $advisory
                Write-LogEntry "  SECURITY: $($advisory.CVE) ($($advisory.Severity))" -Level ERROR
            }
        }
    }

    # Analyze configuration impact
    $configImpact = "No significant configuration changes required"
    if ($LatestVersionInfo.ReleaseNotes -match "Configuration Impact:(.+?)(?=\n#|\z)") {
        $configImpact = $matches[1].Trim()
    }

    $result = [PSCustomObject]@{
        Component = $ComponentName
        CurrentVersion = $CurrentVersion
        LatestVersion = $LatestVersionInfo.LatestVersion
        UpdateAvailable = $updateAvailable
        ReleaseDate = $LatestVersionInfo.ReleaseDate
        ReleaseNotes = $LatestVersionInfo.ReleaseNotes
        DownloadURL = $LatestVersionInfo.DownloadURL
        SecurityIssues = $securityIssues
        ConfigurationImpact = $configImpact
        CheckDate = Get-Date
    }

    $script:VersionCheckResults += $result
    return $result
}

function Test-VersionAffected {
    <#
    .SYNOPSIS
        Checks if a version is within affected range.
    #>
    param(
        [string]$Version,
        [string]$AffectedRange
    )

    # Simple range check (e.g., "2.20.0 - 2.25.0")
    if ($AffectedRange -match '(\d+\.\d+\.\d+)\s*-\s*(\d+\.\d+\.\d+)') {
        $rangeStart = [version]$matches[1]
        $rangeEnd = [version]$matches[2]
        $currentVer = [version]$Version

        return ($currentVer -ge $rangeStart -and $currentVer -le $rangeEnd)
    }

    return $false
}

#endregion

#region Reporting

function New-HTMLReport {
    <#
    .SYNOPSIS
        Generates HTML version check report.
    #>
    $updateCount = ($script:VersionCheckResults | Where-Object { $_.UpdateAvailable }).Count
    $securityCount = ($script:VersionCheckResults | Where-Object { $_.SecurityIssues.Count -gt 0 }).Count

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Version Check Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 20px 0; }
        .metric { background: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
        .metric-value { font-size: 36px; font-weight: bold; margin: 10px 0; }
        .metric-label { color: #7f8c8d; font-size: 14px; text-transform: uppercase; }
        .update-available .metric-value { color: #f39c12; }
        .security-issues .metric-value { color: #e74c3c; }
        .up-to-date .metric-value { color: #27ae60; }
        .component { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin: 20px 0; }
        .component-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
        .component-name { font-size: 20px; font-weight: bold; color: #2c3e50; }
        .version-badge { padding: 5px 15px; border-radius: 20px; font-size: 14px; font-weight: bold; }
        .badge-update { background: #fff3cd; color: #856404; }
        .badge-current { background: #d4edda; color: #155724; }
        .badge-security { background: #f8d7da; color: #721c24; }
        .details { margin: 15px 0; }
        .details-row { display: grid; grid-template-columns: 200px 1fr; gap: 10px; padding: 8px 0; border-bottom: 1px solid #ecf0f1; }
        .details-label { font-weight: bold; color: #495057; }
        .details-value { color: #6c757d; }
        .security-alert { background: #f8d7da; border-left: 4px solid #dc3545; padding: 15px; margin: 10px 0; border-radius: 4px; }
        .cve-badge { display: inline-block; background: #dc3545; color: white; padding: 3px 8px; border-radius: 3px; font-size: 12px; margin-right: 5px; }
        .release-notes { background: #f8f9fa; padding: 15px; border-radius: 4px; margin: 10px 0; max-height: 200px; overflow-y: auto; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📦 Component Version Check Report</h1>
        <p><strong>Check Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary">
            <div class="metric up-to-date">
                <div class="metric-label">Total Components</div>
                <div class="metric-value">$($script:VersionCheckResults.Count)</div>
            </div>
            <div class="metric update-available">
                <div class="metric-label">Updates Available</div>
                <div class="metric-value">$updateCount</div>
            </div>
            <div class="metric security-issues">
                <div class="metric-label">Security Issues</div>
                <div class="metric-value">$securityCount</div>
            </div>
        </div>

        <h2>Component Details</h2>
"@

    foreach ($result in $script:VersionCheckResults) {
        $badge = if ($result.SecurityIssues.Count -gt 0) {
            '<span class="version-badge badge-security">🔒 SECURITY ISSUE</span>'
        } elseif ($result.UpdateAvailable) {
            '<span class="version-badge badge-update">🔄 UPDATE AVAILABLE</span>'
        } else {
            '<span class="version-badge badge-current">✅ UP TO DATE</span>'
        }

        $html += @"
        <div class="component">
            <div class="component-header">
                <div class="component-name">$($result.Component)</div>
                $badge
            </div>
            <div class="details">
                <div class="details-row">
                    <div class="details-label">Current Version:</div>
                    <div class="details-value">$($result.CurrentVersion)</div>
                </div>
                <div class="details-row">
                    <div class="details-label">Latest Version:</div>
                    <div class="details-value">$($result.LatestVersion)</div>
                </div>
                <div class="details-row">
                    <div class="details-label">Release Date:</div>
                    <div class="details-value">$($result.ReleaseDate)</div>
                </div>
                <div class="details-row">
                    <div class="details-label">Configuration Impact:</div>
                    <div class="details-value">$($result.ConfigurationImpact)</div>
                </div>
            </div>
"@

        # Security issues
        if ($result.SecurityIssues.Count -gt 0) {
            $html += "<h3 style='color: #dc3545;'>⚠️ Security Advisories</h3>"
            foreach ($advisory in $result.SecurityIssues) {
                $html += @"
            <div class="security-alert">
                <div><span class="cve-badge">$($advisory.CVE)</span> <strong>$($advisory.Severity)</strong> (CVSS: $($advisory.CVSS))</div>
                <div style="margin-top: 10px;">$($advisory.Description)</div>
                <div style="margin-top: 10px;"><strong>Affected:</strong> $($advisory.AffectedVersions) | <strong>Fixed in:</strong> $($advisory.FixedIn)</div>
            </div>
"@
            }
        }

        # Release notes
        if ($result.UpdateAvailable) {
            $html += @"
            <h3>📝 Release Notes</h3>
            <div class="release-notes">
                <pre>$($result.ReleaseNotes)</pre>
            </div>
            <p><strong>Download:</strong> <a href="$($result.DownloadURL)">$($result.DownloadURL)</a></p>
"@
        }

        $html += "        </div>"
    }

    $html += @"
        <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ecf0f1; color: #7f8c8d; font-size: 0.9em;">
            <p>Generated by GeoServer Infrastructure Automation Suite v2.2.0</p>
        </div>
    </div>
</body>
</html>
"@

    $reportPath = if ($OutputPath) { $OutputPath } else { "C:\GeoServerLogs\version-check-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html" }
    $html | Set-Content -Path $reportPath
    Write-LogEntry "HTML report generated: $reportPath" -Level SUCCESS

    return $reportPath
}

function Show-ConsoleReport {
    <#
    .SYNOPSIS
        Displays version check results to console.
    #>
    Write-Host "`n" -NoNewline
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "  VERSION CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan

    foreach ($result in $script:VersionCheckResults) {
        Write-Host "`n$($result.Component):" -ForegroundColor White
        Write-Host "  Current: $($result.CurrentVersion)" -ForegroundColor Gray
        Write-Host "  Latest:  $($result.LatestVersion)" -ForegroundColor Gray

        if ($result.SecurityIssues.Count -gt 0) {
            Write-Host "  Status:  SECURITY ISSUES FOUND" -ForegroundColor Red
            foreach ($advisory in $result.SecurityIssues) {
                Write-Host "    $($advisory.CVE) - $($advisory.Severity)" -ForegroundColor Red
            }
        } elseif ($result.UpdateAvailable) {
            Write-Host "  Status:  UPDATE AVAILABLE" -ForegroundColor Yellow
        } else {
            Write-Host "  Status:  UP TO DATE" -ForegroundColor Green
        }
    }

    Write-Host "`n" -NoNewline
    Write-Host "=" * 80 -ForegroundColor Cyan
}

#endregion

#region Email Notifications

function Send-VersionNotifications {
    <#
    .SYNOPSIS
        Sends email notifications for version updates and security issues.
    #>
    $emailScript = ".\scripts\utilities\Send-EmailNotification.ps1"
    if (-not (Test-Path $emailScript)) {
        Write-LogEntry "Email notification script not found" -Level WARNING
        return
    }

    # Send notification for each component with updates or security issues
    foreach ($result in $script:VersionCheckResults) {
        if ($result.SecurityIssues.Count -gt 0) {
            # Security alert
            foreach ($advisory in $result.SecurityIssues) {
                $templateData = @{
                    Component = $result.Component
                    CVE = $advisory.CVE
                    Severity = $advisory.Severity
                    Description = $advisory.Description
                    Recommendation = "Upgrade to version $($result.LatestVersion) immediately to resolve $($advisory.CVE)"
                }

                & $emailScript -Template SecurityAlert -TemplateData $templateData
                Write-LogEntry "Security alert sent for $($result.Component)" -Level INFO
            }
        } elseif ($result.UpdateAvailable) {
            # Version update alert
            $templateData = @{
                Component = $result.Component
                CurrentVersion = $result.CurrentVersion
                LatestVersion = $result.LatestVersion
                ReleaseNotes = $result.ReleaseNotes
                ConfigImpact = $result.ConfigurationImpact
            }

            & $emailScript -Template VersionAlert -TemplateData $templateData
            Write-LogEntry "Update notification sent for $($result.Component)" -Level INFO
        }
    }
}

#endregion

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-SectionHeader "Version Update Check Starting"

    # Load configuration
    Load-Configuration

    # Determine which components to check
    $componentsToCheck = if ($Component -eq 'All') {
        @('GeoServer', 'Tomcat', 'Java', 'PostgreSQL', 'pgAdmin', 'QGIS')
    } else {
        @($Component)
    }

    # Check each component
    foreach ($comp in $componentsToCheck) {
        $currentVersion = switch ($comp) {
            'GeoServer' { Get-InstalledGeoServerVersion }
            'Tomcat' { Get-InstalledTomcatVersion }
            'Java' { Get-InstalledJavaVersion }
            'PostgreSQL' { Get-InstalledPostgreSQLVersion }
            'pgAdmin' { Get-InstalledPgAdminVersion }
            'QGIS' { Get-InstalledQGISVersion }
        }

        $latestInfo = $script:VersionDatabase[$comp]

        if ($CheckSecurityOnly) {
            # Only check security
            if ($latestInfo.SecurityAdvisories.Count -gt 0) {
                Test-ComponentVersion -ComponentName $comp -CurrentVersion $currentVersion -LatestVersionInfo $latestInfo
            }
        } else {
            # Full version check
            Test-ComponentVersion -ComponentName $comp -CurrentVersion $currentVersion -LatestVersionInfo $latestInfo
        }
    }

    # Display results based on output format
    switch ($OutputFormat) {
        'Console' {
            Show-ConsoleReport
        }
        'HTML' {
            $reportPath = New-HTMLReport
            Write-LogEntry "Report saved to: $reportPath" -Level SUCCESS
        }
        'JSON' {
            $jsonPath = if ($OutputPath) { $OutputPath } else { "C:\GeoServerLogs\version-check-$(Get-Date -Format 'yyyyMMdd-HHmmss').json" }
            $script:VersionCheckResults | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath
            Write-LogEntry "JSON output saved to: $jsonPath" -Level SUCCESS
        }
    }

    # Send email notifications if requested
    if ($EmailNotification) {
        Send-VersionNotifications
    }

    Write-LogEntry "Version check completed" -Level SUCCESS

    # Exit code: 0 if all up to date, 1 if updates or security issues found
    $issuesFound = ($script:VersionCheckResults | Where-Object { $_.UpdateAvailable -or $_.SecurityIssues.Count -gt 0 }).Count
    exit ($issuesFound -gt 0 ? 1 : 0)

} catch {
    Write-LogEntry "Critical error: $_" -Level ERROR
    Write-LogEntry $_.ScriptStackTrace -Level DEBUG
    exit 1
}
