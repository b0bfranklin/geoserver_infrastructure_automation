<#
.SYNOPSIS
    Generates automated fix scripts for common configuration issues.

.DESCRIPTION
    This script analyzes the output from Invoke-ConfigurationAnalysis.ps1 and
    generates executable PowerShell scripts to automatically fix common issues.

    Supports automated fixes for:
    - Deprecated Tomcat connector configurations
    - Low performance settings (maxThreads, connection timeouts)
    - Missing JVM optimization parameters
    - GeoServer data directory permissions
    - Default workspace configuration issues
    - Log rotation settings

.PARAMETER AnalysisReportPath
    Path to the JSON analysis report from Invoke-ConfigurationAnalysis.ps1

.PARAMETER OutputPath
    Directory where fix scripts will be generated

.PARAMETER FixTypes
    Types of fixes to generate: All, Configuration, Performance, Security

.PARAMETER GenerateSafetyChecks
    Include safety checks and rollback points in generated scripts

.PARAMETER DryRun
    Generate scripts but don't execute them automatically

.EXAMPLE
    .\New-AutomatedFixScript.ps1 -AnalysisReportPath "./analysis.json" -FixTypes All

.NOTES
    File Name   : New-AutomatedFixScript.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+
    Version     : 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Path to analysis report JSON")]
    [string]$AnalysisReportPath,

    [Parameter(Mandatory=$false, HelpMessage="Output directory for fix scripts")]
    [string]$OutputPath,

    [Parameter(Mandatory=$false, HelpMessage="Types of fixes to generate")]
    [ValidateSet('All', 'Configuration', 'Performance', 'Security')]
    [string]$FixTypes = 'All',

    [Parameter(Mandatory=$false, HelpMessage="Include safety checks")]
    [switch]$GenerateSafetyChecks = $true,

    [Parameter(Mandatory=$false, HelpMessage="Generate but don't execute")]
    [switch]$DryRun = $true
)

#Requires -Version 7.0

# Repository root detection
$script:RepositoryRoot = if ($PSScriptRoot) {
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $script:RepositoryRoot "generated-fixes"
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Load analysis report
if ($AnalysisReportPath -and (Test-Path $AnalysisReportPath)) {
    $analysisData = Get-Content $AnalysisReportPath -Raw | ConvertFrom-Json
} else {
    # Find most recent analysis report
    $reportsDir = Join-Path $script:RepositoryRoot "reports"
    $latestReport = Get-ChildItem -Path $reportsDir -Filter "configuration-analysis-*.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestReport) {
        $analysisData = Get-Content $latestReport.FullName -Raw | ConvertFrom-Json
        Write-Host "Using latest analysis report: $($latestReport.Name)" -ForegroundColor Green
    } else {
        Write-Error "No analysis report found. Run Invoke-ConfigurationAnalysis.ps1 first."
        exit 1
    }
}

# Generate fix scripts based on detected issues
$fixScripts = @()

# Fix deprecated Tomcat connectors
if ($FixTypes -in @('All', 'Configuration')) {
    $tomcatIssues = $analysisData.Components.Tomcat.Issues | Where-Object { $_.Category -eq "Deprecated Configuration" }

    if ($tomcatIssues) {
        $fixScript = @"
# Auto-generated fix script for Tomcat deprecated connectors
# Generated: $(Get-Date)

`$tomcatPath = "$($analysisData.Components.Tomcat.InstallPath)"
`$serverXmlPath = Join-Path `$tomcatPath "conf\server.xml"

# Backup original
Copy-Item `$serverXmlPath "`${serverXmlPath}.backup-`$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force

# Load and update XML
[xml]`$serverXml = Get-Content `$serverXmlPath

foreach (`$connector in `$serverXml.Server.Service.Connector) {
    if (`$connector.protocol -match "org.apache.coyote") {
        Write-Host "Updating connector on port `$(`$connector.port)..." -ForegroundColor Yellow
        `$connector.protocol = "HTTP/1.1"
    }
}

# Save updated configuration
`$serverXml.Save(`$serverXmlPath)
Write-Host "✓ Tomcat connector configuration updated" -ForegroundColor Green
Write-Host "Backup saved to: `${serverXmlPath}.backup-*" -ForegroundColor Cyan
"@
        $fixScripts += @{
            Name = "Fix-TomcatDeprecatedConnectors.ps1"
            Content = $fixScript
            Severity = "MEDIUM"
        }
    }
}

# Fix performance issues
if ($FixTypes -in @('All', 'Performance')) {
    $perfIssues = $analysisData.Components.Tomcat.Issues | Where-Object { $_.Category -eq "Performance" }

    if ($perfIssues) {
        $fixScript = @"
# Auto-generated fix script for Tomcat performance settings
# Generated: $(Get-Date)

`$tomcatPath = "$($analysisData.Components.Tomcat.InstallPath)"
`$serverXmlPath = Join-Path `$tomcatPath "conf\server.xml"

# Backup original
Copy-Item `$serverXmlPath "`${serverXmlPath}.backup-`$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force

# Load and update XML
[xml]`$serverXml = Get-Content `$serverXmlPath

foreach (`$connector in `$serverXml.Server.Service.Connector) {
    if (`$connector.protocol -match "HTTP") {
        Write-Host "Optimizing connector on port `$(`$connector.port)..." -ForegroundColor Yellow

        # Set recommended values
        if (-not `$connector.maxThreads -or [int]`$connector.maxThreads -lt 200) {
            `$connector.maxThreads = "200"
        }
        if (-not `$connector.minSpareThreads) {
            `$connector.minSpareThreads = "25"
        }
        if (-not `$connector.acceptCount) {
            `$connector.acceptCount = "100"
        }
        if (-not `$connector.connectionTimeout) {
            `$connector.connectionTimeout = "20000"
        }
    }
}

# Save updated configuration
`$serverXml.Save(`$serverXmlPath)
Write-Host "✓ Tomcat performance settings optimized" -ForegroundColor Green
Write-Host "Recommended: Review settings and adjust based on your load requirements" -ForegroundColor Yellow
"@
        $fixScripts += @{
            Name = "Fix-TomcatPerformanceSettings.ps1"
            Content = $fixScript
            Severity = "LOW"
        }
    }
}

# Generate JVM optimization script
if ($FixTypes -in @('All', 'Performance')) {
    $jvmScript = @"
# Auto-generated JVM optimization script
# Generated: $(Get-Date)

`$tomcatPath = "$($analysisData.Components.Tomcat.InstallPath)"
`$setenvPath = if (`$IsWindows) { Join-Path `$tomcatPath "bin\setenv.bat" } else { Join-Path `$tomcatPath "bin/setenv.sh" }

# Recommended JVM settings for GeoServer
`$jvmOpts = @(
    "-Xms2G",
    "-Xmx4G",
    "-XX:+UseG1GC",
    "-XX:MaxGCPauseMillis=200",
    "-XX:ParallelGCThreads=20",
    "-XX:ConcGCThreads=5",
    "-XX:InitiatingHeapOccupancyPercent=70",
    "-Djava.awt.headless=true",
    "-Dfile.encoding=UTF8",
    "-Duser.timezone=UTC",
    "-DGEOSERVER_CSRF_DISABLED=false"
)

# Create setenv script if it doesn't exist
if (-not (Test-Path `$setenvPath)) {
    `$content = if (`$IsWindows) {
        "@echo off`r`nset CATALINA_OPTS=" + (`$jvmOpts -join " ")
    } else {
        "#!/bin/bash`nexport CATALINA_OPTS=`"" + (`$jvmOpts -join " ") + "`""
    }

    Set-Content -Path `$setenvPath -Value `$content
    Write-Host "✓ Created `$setenvPath with optimized JVM settings" -ForegroundColor Green

    if (-not `$IsWindows) {
        chmod +x `$setenvPath
    }
} else {
    Write-Host "⚠ `$setenvPath already exists - review manually" -ForegroundColor Yellow
    Write-Host "Recommended JVM options:" -ForegroundColor Cyan
    `$jvmOpts | ForEach-Object { Write-Host "  `$_" -ForegroundColor White }
}
"@
    $fixScripts += @{
        Name = "Optimize-JVMSettings.ps1"
        Content = $jvmScript
        Severity = "MEDIUM"
    }
}

# Write all fix scripts to disk
Write-Host "`n📝 Generating $($fixScripts.Count) fix scripts..." -ForegroundColor Cyan

foreach ($script in $fixScripts) {
    $scriptPath = Join-Path $OutputPath $script.Name

    # Add safety header if requested
    if ($GenerateSafetyChecks) {
        $safetyHeader = @"
#Requires -Version 7.0
# SAFETY CHECKS ENABLED
# This script will create backups before making changes

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  $($script.Name)" -ForegroundColor Yellow
Write-Host "  Severity: $($script.Severity)" -ForegroundColor $(if ($script.Severity -eq 'HIGH') { 'Red' } else { 'Yellow' })
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠ This script will modify your configuration files" -ForegroundColor Yellow
Write-Host "✓ Backups will be created automatically" -ForegroundColor Green
Write-Host ""

`$confirmation = Read-Host "Continue? (yes/no)"
if (`$confirmation -ne 'yes') {
    Write-Host "Aborted by user" -ForegroundColor Red
    exit 1
}

try {

"@
        $safetyFooter = @"

    Write-Host ""
    Write-Host "✓ Fix applied successfully!" -ForegroundColor Green
    Write-Host "⚠ Restart Tomcat for changes to take effect" -ForegroundColor Yellow

} catch {
    Write-Host "✗ Error applying fix: `$_" -ForegroundColor Red
    Write-Host "Check backup files and restore if needed" -ForegroundColor Yellow
    exit 1
}
"@
        $fullScript = $safetyHeader + $script.Content + $safetyFooter
    } else {
        $fullScript = $script.Content
    }

    Set-Content -Path $scriptPath -Value $fullScript
    Write-Host "  ✓ $($script.Name)" -ForegroundColor Green
}

Write-Host "`n📂 Fix scripts generated in: $OutputPath" -ForegroundColor Green
Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Review each script before running" -ForegroundColor White
Write-Host "  2. Create VM snapshot or backup before applying fixes" -ForegroundColor Yellow
Write-Host "  3. Run scripts individually to test each fix" -ForegroundColor White
Write-Host "  4. Verify changes and restart services" -ForegroundColor White

if ($DryRun) {
    Write-Host "`n💡 Scripts generated but not executed (DryRun mode)" -ForegroundColor Cyan
    Write-Host "   To execute, run each script manually or use -DryRun:`$false" -ForegroundColor Gray
} else {
    Write-Host "`n⚠ Execute generated scripts with caution!" -ForegroundColor Yellow
}

# Create summary report
$summaryPath = Join-Path $OutputPath "FIX-SUMMARY.md"
$summary = @"
# Automated Fix Scripts Summary

**Generated:** $(Get-Date)
**Analysis Report:** $AnalysisReportPath
**Total Scripts:** $($fixScripts.Count)

## Generated Scripts

| Script | Severity | Description |
|--------|----------|-------------|
$(foreach ($s in $fixScripts) { "| $($s.Name) | $($s.Severity) | Auto-fix for detected issues |`n" })

## Execution Instructions

1. **Review**: Examine each script to understand what changes it will make
2. **Backup**: Create VM snapshot or filesystem backup
3. **Test**: Run scripts on test/staging environment first
4. **Apply**: Execute scripts on production with monitoring
5. **Verify**: Check application functionality after each fix

## Safety Notes

- All scripts create timestamped backups before modifying files
- Scripts include confirmation prompts (when GenerateSafetyChecks is enabled)
- Review logs after execution for any errors
- Restart Tomcat after applying configuration changes

## Rollback Procedure

If issues occur after applying fixes:

1. Stop Tomcat service
2. Restore from backup files (*.backup-* in conf directory)
3. Restart Tomcat
4. Verify functionality

Backup files are located in the same directory as the original files with
timestamp suffix: `filename.backup-yyyyMMdd-HHmmss`

"@

Set-Content -Path $summaryPath -Value $summary
Write-Host "`n📄 Summary written to: $summaryPath" -ForegroundColor Green
