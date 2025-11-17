<#
.SYNOPSIS
    Comprehensive integration testing suite for GeoServer Infrastructure Automation.

.DESCRIPTION
    This script runs end-to-end integration tests across all automation components:
    - GeoServer WMS/WFS endpoints
    - PostgreSQL/PostGIS connectivity
    - Tomcat service management
    - Backup/restore operations
    - Upgrade workflow validation
    - Configuration integrity
    - Performance baselines

    Designed for both manual testing and automated CI/CD pipelines.

.PARAMETER TestSuite
    Specific test suite to run. Options: All, Services, Endpoints, Database, Backup, Performance

.PARAMETER Environment
    Environment to test against: Development, Staging, Production

.PARAMETER GenerateReport
    Generate HTML test report.

.PARAMETER EmailReport
    Email the test report to configured recipients.

.PARAMETER StopOnFailure
    Stop test execution on first failure (default: continue all tests).

.EXAMPLE
    .\Invoke-IntegrationTests.ps1 -TestSuite All -GenerateReport
    # Run all tests and generate HTML report

.EXAMPLE
    .\Invoke-IntegrationTests.ps1 -TestSuite Services -Environment Production -EmailReport
    # Test services in production and email results

.NOTES
    Author: GeoServer Infrastructure Automation Suite
    Version: 2.2.0
    Requires: PowerShell 7.0+
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Test suite to execute")]
    [ValidateSet('All', 'Services', 'Endpoints', 'Database', 'Backup', 'Performance', 'Upgrade')]
    [string]$TestSuite = 'All',

    [Parameter(HelpMessage = "Target environment")]
    [ValidateSet('Development', 'Staging', 'Production')]
    [string]$Environment = 'Development',

    [Parameter(HelpMessage = "Generate HTML report")]
    [switch]$GenerateReport,

    [Parameter(HelpMessage = "Email report to configured recipients")]
    [switch]$EmailReport,

    [Parameter(HelpMessage = "Stop on first failure")]
    [switch]$StopOnFailure
)

#Requires -Version 7.0

# ============================================================================
# REPOSITORY ROOT DETECTION
# ============================================================================

# Determine repository root (works regardless of execution directory)
$script:RepositoryRoot = if ($PSScriptRoot) {
    # Scripts are in tests/integration/, so go up 2 levels
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
$script:LogPath = Join-Path $script:LogDirectory "integration-tests-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:TestResults = @()
$script:StartTime = Get-Date
$script:ConfigPath = Join-Path $script:RepositoryRoot "config\upgrade-config.json"
$script:Config = $null

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

function Write-TestHeader {
    param([string]$Title)
    $separator = "=" * 80
    Write-LogEntry $separator -Level INFO
    Write-LogEntry "  $Title" -Level INFO
    Write-LogEntry $separator -Level INFO
}

#endregion

#region Test Result Management

function New-TestResult {
    <#
    .SYNOPSIS
        Creates a test result object.
    #>
    param(
        [string]$TestName,
        [string]$Category,
        [string]$Status,
        [string]$Message,
        [timespan]$Duration,
        [object]$Details = $null
    )

    return [PSCustomObject]@{
        TestName = $TestName
        Category = $Category
        Status = $Status
        Message = $Message
        Duration = $Duration
        Timestamp = Get-Date
        Environment = $Environment
        Details = $Details
    }
}

function Add-TestResult {
    param([PSCustomObject]$Result)
    $script:TestResults += $Result

    $statusColor = switch ($Result.Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'SKIP' { 'Yellow' }
        default { 'White' }
    }

    Write-Host "  [$($Result.Status)] $($Result.TestName) - $($Result.Message) ($($Result.Duration.TotalSeconds)s)" -ForegroundColor $statusColor

    if ($StopOnFailure -and $Result.Status -eq 'FAIL') {
        Write-LogEntry "Stopping on failure as requested" -Level ERROR
        throw "Test failed: $($Result.TestName)"
    }
}

#endregion

#region Configuration Loading

function Load-Configuration {
    Write-LogEntry "Loading configuration from $script:ConfigPath..." -Level INFO

    if (-not (Test-Path $script:ConfigPath)) {
        Write-LogEntry "Configuration file not found, using defaults" -Level WARNING
        return $null
    }

    try {
        $script:Config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        Write-LogEntry "Configuration loaded successfully" -Level SUCCESS
        return $script:Config
    } catch {
        Write-LogEntry "Failed to load configuration: $_" -Level ERROR
        return $null
    }
}

#endregion

#region Service Tests

function Test-TomcatService {
    <#
    .SYNOPSIS
        Tests Tomcat service availability and health.
    #>
    Write-TestHeader "Testing Tomcat Services"

    if (-not $script:Config -or -not $script:Config.tomcatInstances) {
        $result = New-TestResult -TestName "Tomcat Services" -Category "Services" -Status "SKIP" -Message "No Tomcat instances configured" -Duration ([timespan]::Zero)
        Add-TestResult $result
        return
    }

    foreach ($instance in $script:Config.tomcatInstances) {
        $startTime = Get-Date

        try {
            # Test service status
            $service = Get-Service -Name $instance.serviceName -ErrorAction SilentlyContinue

            if (-not $service) {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "Tomcat Service: $($instance.name)" -Category "Services" -Status "FAIL" -Message "Service not found" -Duration $duration
                Add-TestResult $result
                continue
            }

            if ($service.Status -ne 'Running') {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "Tomcat Service: $($instance.name)" -Category "Services" -Status "FAIL" -Message "Service is $($service.Status)" -Duration $duration
                Add-TestResult $result
                continue
            }

            # Test HTTP endpoint
            $testUrl = "http://localhost:$($instance.port)"
            try {
                $response = Invoke-WebRequest -Uri $testUrl -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "Tomcat Service: $($instance.name)" -Category "Services" -Status "PASS" -Message "Service running, HTTP $($response.StatusCode)" -Duration $duration -Details @{Port = $instance.port; StatusCode = $response.StatusCode}
                Add-TestResult $result
            } catch {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "Tomcat Service: $($instance.name)" -Category "Services" -Status "FAIL" -Message "HTTP request failed: $_" -Duration $duration
                Add-TestResult $result
            }

        } catch {
            $duration = (Get-Date) - $startTime
            $result = New-TestResult -TestName "Tomcat Service: $($instance.name)" -Category "Services" -Status "FAIL" -Message "Error: $_" -Duration $duration
            Add-TestResult $result
        }
    }
}

function Test-PostgreSQLService {
    <#
    .SYNOPSIS
        Tests PostgreSQL database service and connectivity.
    #>
    Write-TestHeader "Testing PostgreSQL Services"

    if (-not $script:Config -or -not $script:Config.databases) {
        $result = New-TestResult -TestName "PostgreSQL Services" -Category "Services" -Status "SKIP" -Message "No databases configured" -Duration ([timespan]::Zero)
        Add-TestResult $result
        return
    }

    foreach ($db in $script:Config.databases) {
        if ($db.type -ne "PostgreSQL") { continue }

        $startTime = Get-Date

        try {
            # Test TCP connectivity
            $tcpTest = Test-NetConnection -ComputerName $db.server -Port $db.port -WarningAction SilentlyContinue -ErrorAction Stop

            if ($tcpTest.TcpTestSucceeded) {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "PostgreSQL: $($db.name)" -Category "Services" -Status "PASS" -Message "Port $($db.port) accessible" -Duration $duration -Details @{Server = $db.server; Port = $db.port}
                Add-TestResult $result
            } else {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "PostgreSQL: $($db.name)" -Category "Services" -Status "FAIL" -Message "Port $($db.port) not accessible" -Duration $duration
                Add-TestResult $result
            }

        } catch {
            $duration = (Get-Date) - $startTime
            $result = New-TestResult -TestName "PostgreSQL: $($db.name)" -Category "Services" -Status "FAIL" -Message "Error: $_" -Duration $duration
            Add-TestResult $result
        }
    }
}

#endregion

#region Endpoint Tests

function Test-GeoServerWMS {
    <#
    .SYNOPSIS
        Tests GeoServer WMS (Web Map Service) endpoints.
    #>
    Write-TestHeader "Testing GeoServer WMS Endpoints"

    if (-not $script:Config -or -not $script:Config.tomcatInstances) {
        $result = New-TestResult -TestName "GeoServer WMS" -Category "Endpoints" -Status "SKIP" -Message "No configuration available" -Duration ([timespan]::Zero)
        Add-TestResult $result
        return
    }

    foreach ($instance in $script:Config.tomcatInstances) {
        $startTime = Get-Date

        # Test GetCapabilities
        $wmsUrl = "http://localhost:$($instance.port)/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities"

        try {
            $response = Invoke-WebRequest -Uri $wmsUrl -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop

            if ($response.StatusCode -eq 200 -and $response.Content -like "*WMS_Capabilities*") {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "WMS GetCapabilities: $($instance.name)" -Category "Endpoints" -Status "PASS" -Message "Valid WMS response" -Duration $duration -Details @{URL = $wmsUrl; Size = $response.Content.Length}
                Add-TestResult $result
            } else {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "WMS GetCapabilities: $($instance.name)" -Category "Endpoints" -Status "FAIL" -Message "Invalid WMS response" -Duration $duration
                Add-TestResult $result
            }

        } catch {
            $duration = (Get-Date) - $startTime
            $result = New-TestResult -TestName "WMS GetCapabilities: $($instance.name)" -Category "Endpoints" -Status "FAIL" -Message "Request failed: $_" -Duration $duration
            Add-TestResult $result
        }
    }
}

function Test-GeoServerWFS {
    <#
    .SYNOPSIS
        Tests GeoServer WFS (Web Feature Service) endpoints.
    #>
    Write-TestHeader "Testing GeoServer WFS Endpoints"

    if (-not $script:Config -or -not $script:Config.tomcatInstances) {
        $result = New-TestResult -TestName "GeoServer WFS" -Category "Endpoints" -Status "SKIP" -Message "No configuration available" -Duration ([timespan]::Zero)
        Add-TestResult $result
        return
    }

    foreach ($instance in $script:Config.tomcatInstances) {
        $startTime = Get-Date

        # Test GetCapabilities
        $wfsUrl = "http://localhost:$($instance.port)/geoserver/wfs?service=WFS&version=2.0.0&request=GetCapabilities"

        try {
            $response = Invoke-WebRequest -Uri $wfsUrl -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop

            if ($response.StatusCode -eq 200 -and $response.Content -like "*WFS_Capabilities*") {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "WFS GetCapabilities: $($instance.name)" -Category "Endpoints" -Status "PASS" -Message "Valid WFS response" -Duration $duration -Details @{URL = $wfsUrl; Size = $response.Content.Length}
                Add-TestResult $result
            } else {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "WFS GetCapabilities: $($instance.name)" -Category "Endpoints" -Status "FAIL" -Message "Invalid WFS response" -Duration $duration
                Add-TestResult $result
            }

        } catch {
            $duration = (Get-Date) - $startTime
            $result = New-TestResult -TestName "WFS GetCapabilities: $($instance.name)" -Category "Endpoints" -Status "FAIL" -Message "Request failed: $_" -Duration $duration
            Add-TestResult $result
        }
    }
}

function Test-GeoServerREST {
    <#
    .SYNOPSIS
        Tests GeoServer REST API.
    #>
    Write-TestHeader "Testing GeoServer REST API"

    if (-not $script:Config -or -not $script:Config.tomcatInstances) {
        $result = New-TestResult -TestName "GeoServer REST" -Category "Endpoints" -Status "SKIP" -Message "No configuration available" -Duration ([timespan]::Zero)
        Add-TestResult $result
        return
    }

    foreach ($instance in $script:Config.tomcatInstances) {
        $startTime = Get-Date

        $restUrl = "http://localhost:$($instance.port)/geoserver/rest/about/version"

        try {
            # REST API typically requires authentication, so we expect 401 if no creds provided
            # But the endpoint should respond
            $response = Invoke-WebRequest -Uri $restUrl -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop

            $duration = (Get-Date) - $startTime
            $result = New-TestResult -TestName "REST API: $($instance.name)" -Category "Endpoints" -Status "PASS" -Message "REST API accessible (HTTP $($response.StatusCode))" -Duration $duration
            Add-TestResult $result

        } catch {
            # Check if it's a 401 (expected without auth)
            if ($_.Exception.Response.StatusCode.value__ -eq 401) {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "REST API: $($instance.name)" -Category "Endpoints" -Status "PASS" -Message "REST API accessible (auth required)" -Duration $duration
                Add-TestResult $result
            } else {
                $duration = (Get-Date) - $startTime
                $result = New-TestResult -TestName "REST API: $($instance.name)" -Category "Endpoints" -Status "FAIL" -Message "Request failed: $_" -Duration $duration
                Add-TestResult $result
            }
        }
    }
}

#endregion

#region Backup Tests

function Test-BackupFunctionality {
    <#
    .SYNOPSIS
        Tests backup creation and validation.
    #>
    Write-TestHeader "Testing Backup Functionality"

    $startTime = Get-Date
    $backupScript = ".\scripts\core\Backup-GeoServerEnvironment.ps1"

    if (-not (Test-Path $backupScript)) {
        $duration = (Get-Date) - $startTime
        $result = New-TestResult -TestName "Backup Script Existence" -Category "Backup" -Status "FAIL" -Message "Backup script not found" -Duration $duration
        Add-TestResult $result
        return
    }

    try {
        # Test backup in WhatIf mode
        Write-LogEntry "Testing backup in WhatIf mode..." -Level INFO
        $output = & $backupScript -WhatIf -BackupName "integration-test" 2>&1

        $duration = (Get-Date) - $startTime
        $result = New-TestResult -TestName "Backup WhatIf Mode" -Category "Backup" -Status "PASS" -Message "Backup script executed successfully in WhatIf mode" -Duration $duration
        Add-TestResult $result

    } catch {
        $duration = (Get-Date) - $startTime
        $result = New-TestResult -TestName "Backup WhatIf Mode" -Category "Backup" -Status "FAIL" -Message "Backup script failed: $_" -Duration $duration
        Add-TestResult $result
    }
}

function Test-RestoreFunctionality {
    <#
    .SYNOPSIS
        Tests restore script availability.
    #>
    Write-TestHeader "Testing Restore Functionality"

    $startTime = Get-Date
    $restoreScript = ".\scripts\core\Restore-GeoServerEnvironment.ps1"

    if (-not (Test-Path $restoreScript)) {
        $duration = (Get-Date) - $startTime
        $result = New-TestResult -TestName "Restore Script Existence" -Category "Backup" -Status "FAIL" -Message "Restore script not found" -Duration $duration
        Add-TestResult $result
        return
    }

    $duration = (Get-Date) - $startTime
    $result = New-TestResult -TestName "Restore Script Existence" -Category "Backup" -Status "PASS" -Message "Restore script available" -Duration $duration
    Add-TestResult $result
}

#endregion

#region Performance Tests

function Test-PerformanceBaseline {
    <#
    .SYNOPSIS
        Tests basic performance metrics.
    #>
    Write-TestHeader "Testing Performance Baselines"

    if (-not $script:Config -or -not $script:Config.tomcatInstances) {
        $result = New-TestResult -TestName "Performance Baseline" -Category "Performance" -Status "SKIP" -Message "No configuration available" -Duration ([timespan]::Zero)
        Add-TestResult $result
        return
    }

    foreach ($instance in $script:Config.tomcatInstances) {
        $startTime = Get-Date
        $wmsUrl = "http://localhost:$($instance.port)/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities"

        try {
            # Measure response time for GetCapabilities
            $measurements = @()
            for ($i = 0; $i -lt 5; $i++) {
                $measureStart = Get-Date
                $response = Invoke-WebRequest -Uri $wmsUrl -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
                $measureEnd = Get-Date
                $measurements += ($measureEnd - $measureStart).TotalMilliseconds
            }

            $avgResponseTime = ($measurements | Measure-Object -Average).Average
            $duration = (Get-Date) - $startTime

            # Define acceptable threshold (e.g., 5000ms)
            $threshold = 5000
            if ($avgResponseTime -lt $threshold) {
                $result = New-TestResult -TestName "WMS Response Time: $($instance.name)" -Category "Performance" -Status "PASS" -Message "Avg response time: $([math]::Round($avgResponseTime, 2))ms" -Duration $duration -Details @{AvgMs = $avgResponseTime; Threshold = $threshold}
                Add-TestResult $result
            } else {
                $result = New-TestResult -TestName "WMS Response Time: $($instance.name)" -Category "Performance" -Status "FAIL" -Message "Avg response time: $([math]::Round($avgResponseTime, 2))ms exceeds threshold" -Duration $duration -Details @{AvgMs = $avgResponseTime; Threshold = $threshold}
                Add-TestResult $result
            }

        } catch {
            $duration = (Get-Date) - $startTime
            $result = New-TestResult -TestName "WMS Response Time: $($instance.name)" -Category "Performance" -Status "FAIL" -Message "Performance test failed: $_" -Duration $duration
            Add-TestResult $result
        }
    }
}

#endregion

#region Test Orchestration

function Invoke-TestSuite {
    param([string]$Suite)

    Write-LogEntry "Starting test suite: $Suite" -Level INFO
    Write-LogEntry "Environment: $Environment" -Level INFO
    Write-LogEntry "Timestamp: $(Get-Date)" -Level INFO

    switch ($Suite) {
        'Services' {
            Test-TomcatService
            Test-PostgreSQLService
        }
        'Endpoints' {
            Test-GeoServerWMS
            Test-GeoServerWFS
            Test-GeoServerREST
        }
        'Database' {
            Test-PostgreSQLService
        }
        'Backup' {
            Test-BackupFunctionality
            Test-RestoreFunctionality
        }
        'Performance' {
            Test-PerformanceBaseline
        }
        'Upgrade' {
            # Upgrade-specific tests: backup, restore, and service health
            Write-SectionHeader "Upgrade Readiness Tests"
            Test-BackupFunctionality
            Test-RestoreFunctionality
            # Verify services are healthy before upgrade
            Test-TomcatService
            Test-PostgreSQLService
            Test-GeoServerWMS
        }
        'All' {
            Test-TomcatService
            Test-PostgreSQLService
            Test-GeoServerWMS
            Test-GeoServerWFS
            Test-GeoServerREST
            Test-BackupFunctionality
            Test-RestoreFunctionality
            Test-PerformanceBaseline
        }
    }
}

#endregion

#region Reporting

function New-HTMLReport {
    <#
    .SYNOPSIS
        Generates HTML test report.
    #>
    $totalDuration = (Get-Date) - $script:StartTime
    $passed = ($script:TestResults | Where-Object { $_.Status -eq 'PASS' }).Count
    $failed = ($script:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    $skipped = ($script:TestResults | Where-Object { $_.Status -eq 'SKIP' }).Count
    $total = $script:TestResults.Count

    $passRate = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 2) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Integration Test Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .metric { background: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
        .metric-value { font-size: 36px; font-weight: bold; margin: 10px 0; }
        .metric-label { color: #7f8c8d; font-size: 14px; text-transform: uppercase; }
        .passed .metric-value { color: #27ae60; }
        .failed .metric-value { color: #e74c3c; }
        .skipped .metric-value { color: #f39c12; }
        .total .metric-value { color: #3498db; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ecf0f1; }
        tr:hover { background: #f8f9fa; }
        .status-pass { color: #27ae60; font-weight: bold; }
        .status-fail { color: #e74c3c; font-weight: bold; }
        .status-skip { color: #f39c12; font-weight: bold; }
        .duration { color: #7f8c8d; font-size: 0.9em; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ecf0f1; color: #7f8c8d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Integration Test Report</h1>
        <p><strong>Test Suite:</strong> $TestSuite | <strong>Environment:</strong> $Environment | <strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary">
            <div class="metric passed">
                <div class="metric-label">Passed</div>
                <div class="metric-value">$passed</div>
            </div>
            <div class="metric failed">
                <div class="metric-label">Failed</div>
                <div class="metric-value">$failed</div>
            </div>
            <div class="metric skipped">
                <div class="metric-label">Skipped</div>
                <div class="metric-value">$skipped</div>
            </div>
            <div class="metric total">
                <div class="metric-label">Total Tests</div>
                <div class="metric-value">$total</div>
            </div>
        </div>

        <div style="background: #3498db; color: white; padding: 15px; border-radius: 8px; margin: 20px 0;">
            <strong>Pass Rate:</strong> $passRate% | <strong>Total Duration:</strong> $([math]::Round($totalDuration.TotalSeconds, 2))s
        </div>

        <h2>Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Test Name</th>
                    <th>Category</th>
                    <th>Status</th>
                    <th>Message</th>
                    <th>Duration</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($test in $script:TestResults) {
        $statusClass = switch ($test.Status) {
            'PASS' { 'status-pass' }
            'FAIL' { 'status-fail' }
            'SKIP' { 'status-skip' }
        }

        $html += @"
                <tr>
                    <td>$($test.TestName)</td>
                    <td>$($test.Category)</td>
                    <td class="$statusClass">$($test.Status)</td>
                    <td>$($test.Message)</td>
                    <td class="duration">$([math]::Round($test.Duration.TotalSeconds, 3))s</td>
                </tr>
"@
    }

    $html += @"
            </tbody>
        </table>

        <div class="footer">
            <p>Generated by GeoServer Infrastructure Automation Suite v2.2.0</p>
            <p>Log file: $script:LogPath</p>
        </div>
    </div>
</body>
</html>
"@

    $reportPath = Join-Path $script:LogDirectory "integration-test-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $html | Set-Content -Path $reportPath
    Write-LogEntry "HTML report generated: $reportPath" -Level SUCCESS

    return $reportPath
}

function Show-TestSummary {
    <#
    .SYNOPSIS
        Displays test summary to console.
    #>
    $totalDuration = (Get-Date) - $script:StartTime
    $passed = ($script:TestResults | Where-Object { $_.Status -eq 'PASS' }).Count
    $failed = ($script:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    $skipped = ($script:TestResults | Where-Object { $_.Status -eq 'SKIP' }).Count
    $total = $script:TestResults.Count

    Write-Host "`n" -NoNewline
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "  Total Tests:    " -NoNewline; Write-Host $total -ForegroundColor White
    Write-Host "  Passed:         " -NoNewline; Write-Host $passed -ForegroundColor Green
    Write-Host "  Failed:         " -NoNewline; Write-Host $failed -ForegroundColor Red
    Write-Host "  Skipped:        " -NoNewline; Write-Host $skipped -ForegroundColor Yellow
    Write-Host "  Duration:       " -NoNewline; Write-Host "$([math]::Round($totalDuration.TotalSeconds, 2))s" -ForegroundColor White
    Write-Host "=" * 80 -ForegroundColor Cyan

    if ($failed -eq 0 -and $total -gt 0) {
        Write-Host "`n  ALL TESTS PASSED!" -ForegroundColor Green
    } elseif ($failed -gt 0) {
        Write-Host "`n  SOME TESTS FAILED - Review log for details" -ForegroundColor Red
    }

    Write-Host ""
}

#endregion

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-LogEntry "Integration test suite starting" -Level INFO
    Write-LogEntry "Test Suite: $TestSuite" -Level INFO
    Write-LogEntry "Environment: $Environment" -Level INFO

    # Load configuration
    Load-Configuration

    # Execute tests
    Invoke-TestSuite -Suite $TestSuite

    # Show summary
    Show-TestSummary

    # Generate report if requested
    $reportPath = $null
    if ($GenerateReport) {
        $reportPath = New-HTMLReport
    }

    # Email report if requested
    if ($EmailReport -and $reportPath) {
        Write-LogEntry "Emailing report..." -Level INFO
        $emailScript = Join-Path $script:RepositoryRoot "scripts\utilities\Send-EmailNotification.ps1"
        if (Test-Path $emailScript) {
            & $emailScript -Subject "Integration Test Report - $TestSuite" -AttachmentPath $reportPath -BodyFile $reportPath
        } else {
            Write-LogEntry "Email script not found" -Level WARNING
        }
    }

    Write-LogEntry "Integration tests completed" -Level SUCCESS
    Write-LogEntry "Log file: $script:LogPath" -Level INFO

    # Exit code based on results
    $failed = ($script:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    if ($failed -gt 0) {
        exit 1
    } else {
        exit 0
    }

} catch {
    Write-LogEntry "Critical error during testing: $_" -Level ERROR
    Write-LogEntry $_.ScriptStackTrace -Level DEBUG
    exit 1
}
