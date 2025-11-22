<#
.SYNOPSIS
    Executes baseline tests against GeoServer infrastructure with comparison to known-good results.

.DESCRIPTION
    This script performs comprehensive testing of GeoServer, Tomcat, and related services
    with the ability to:
    - Save baseline "known-good" test results
    - Compare current results against saved baseline
    - Generate detailed test reports with pass/fail/changed status
    - Email test checklists to configured recipients
    - Support custom test URLs and authentication

    Use this before and after upgrades to verify functionality is preserved.

.PARAMETER Mode
    Test mode: SaveBaseline, CompareBaseline, or TestOnly

.PARAMETER TestProfile
    Test profile to use: Quick, Standard, or Comprehensive

.PARAMETER BaselineName
    Name for the baseline (e.g., "production-2024-01", "pre-upgrade-v2.24")

.PARAMETER CustomTestsPath
    Path to JSON file containing custom test definitions

.PARAMETER GenerateChecklist
    Generate email checklist for manual verification steps

.PARAMETER EmailRecipients
    Email addresses to send checklist to (comma-separated)

.PARAMETER IncludeScreenshots
    Capture screenshots of web interfaces (requires browser automation)

.EXAMPLE
    # Save baseline before upgrade
    .\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName "pre-upgrade-2.24"

.EXAMPLE
    # Compare after upgrade
    .\Invoke-BaselineTests.ps1 -Mode CompareBaseline -BaselineName "pre-upgrade-2.24"

.EXAMPLE
    # Generate and email checklist
    .\Invoke-BaselineTests.ps1 -GenerateChecklist -EmailRecipients "admin@example.com,team@example.com"

.NOTES
    File Name   : Invoke-BaselineTests.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+
    Version     : 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Test mode")]
    [ValidateSet('SaveBaseline', 'CompareBaseline', 'TestOnly')]
    [string]$Mode = 'TestOnly',

    [Parameter(Mandatory=$false, HelpMessage="Test profile")]
    [ValidateSet('Quick', 'Standard', 'Comprehensive')]
    [string]$TestProfile = 'Standard',

    [Parameter(Mandatory=$false, HelpMessage="Baseline name")]
    [string]$BaselineName,

    [Parameter(Mandatory=$false, HelpMessage="Path to custom tests JSON")]
    [string]$CustomTestsPath,

    [Parameter(Mandatory=$false, HelpMessage="Generate email checklist")]
    [switch]$GenerateChecklist,

    [Parameter(Mandatory=$false, HelpMessage="Email recipients (comma-separated)")]
    [string]$EmailRecipients,

    [Parameter(Mandatory=$false, HelpMessage="Include screenshots")]
    [switch]$IncludeScreenshots,

    [Parameter(Mandatory=$false, HelpMessage="Path to configuration file")]
    [string]$ConfigPath
)

#Requires -Version 7.0

# ============================================================================
# REPOSITORY ROOT DETECTION
# ============================================================================

$script:RepositoryRoot = if ($PSScriptRoot) {
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:RepositoryRoot "config\upgrade-config.json"
}

if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    throw "Configuration file not found: $ConfigPath"
}

# Log directory
$script:LogDirectory = if ($env:GEOSERVER_LOG_DIR) {
    $env:GEOSERVER_LOG_DIR
} elseif ($IsWindows) {
    "C:\GeoServerLogs"
} else {
    Join-Path $script:RepositoryRoot "logs"
}

if (-not (Test-Path $script:LogDirectory)) {
    New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
}

# Baseline storage
$script:BaselineDirectory = Join-Path $script:RepositoryRoot "test-baselines"
if (-not (Test-Path $script:BaselineDirectory)) {
    New-Item -Path $script:BaselineDirectory -ItemType Directory -Force | Out-Null
}

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"  # Continue on test failures

$script:ScriptVersion = "1.0.0"
$script:StartTime = Get-Date
$script:LogPath = Join-Path $script:LogDirectory "baseline-tests-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:Config = $null
$script:TestResults = @{
    Timestamp = $script:StartTime
    BaselineName = $BaselineName
    TestProfile = $TestProfile
    Tests = @()
    Summary = @{
        Total = 0
        Passed = 0
        Failed = 0
        Changed = 0
        Skipped = 0
    }
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-LogEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color

    try {
        Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue
    } catch {}
}

function Write-SectionHeader {
    param([string]$Title)
    $separator = "=" * 80
    Write-LogEntry $separator -Level INFO
    Write-LogEntry "  $Title" -Level INFO
    Write-LogEntry $separator -Level INFO
}

# ============================================================================
# CONFIGURATION
# ============================================================================

function Load-Configuration {
    Write-LogEntry "Loading configuration from: $ConfigPath" -Level INFO
    try {
        $script:Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-LogEntry "Configuration loaded successfully" -Level SUCCESS
    } catch {
        Write-LogEntry "Failed to load configuration: $_" -Level ERROR
        throw
    }
}

function Load-CustomTests {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) {
        Write-LogEntry "No custom tests file provided or file not found" -Level DEBUG
        return @()
    }

    try {
        $customTests = Get-Content $Path -Raw | ConvertFrom-Json
        Write-LogEntry "Loaded $($customTests.Count) custom tests" -Level SUCCESS
        return $customTests
    } catch {
        Write-LogEntry "Failed to load custom tests: $_" -Level WARNING
        return @()
    }
}

# ============================================================================
# TEST DEFINITIONS
# ============================================================================

function Get-StandardTests {
    <#
    .SYNOPSIS
        Returns standard test suite for GeoServer infrastructure.
    #>

    $tests = @(
        @{
            Name = "Tomcat Service Status"
            Category = "Service"
            Type = "ServiceCheck"
            Target = "Tomcat"
            Critical = $true
            ExpectedResult = "Running"
        }
        @{
            Name = "GeoServer Web Admin Access"
            Category = "WebInterface"
            Type = "HTTP"
            URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/web/"
            ExpectedStatusCode = 200
            ExpectedContent = "GeoServer"
            Critical = $true
            Credentials = $null
        }
        @{
            Name = "GeoServer REST API - Version"
            Category = "API"
            Type = "REST"
            URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/rest/about/version.json"
            Method = "GET"
            ExpectedStatusCode = 200
            Critical = $false
            Credentials = $null
        }
        @{
            Name = "WMS GetCapabilities"
            Category = "OGC-Services"
            Type = "HTTP"
            URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities"
            ExpectedStatusCode = 200
            ExpectedContent = "WMS_Capabilities"
            Critical = $true
        }
        @{
            Name = "WFS GetCapabilities"
            Category = "OGC-Services"
            Type = "HTTP"
            URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/wfs?service=WFS&version=2.0.0&request=GetCapabilities"
            ExpectedStatusCode = 200
            ExpectedContent = "WFS_Capabilities"
            Critical = $true
        }
        @{
            Name = "PostgreSQL Service Status"
            Category = "Service"
            Type = "ServiceCheck"
            Target = "PostgreSQL"
            Critical = $true
            ExpectedResult = "Running"
        }
        @{
            Name = "PostgreSQL Connection Test"
            Category = "Database"
            Type = "Database"
            Target = "PostgreSQL"
            Critical = $true
        }
        @{
            Name = "Data Directory Accessible"
            Category = "FileSystem"
            Type = "PathCheck"
            Target = $script:Config.components.geoserver.dataDirectory
            Critical = $true
        }
        @{
            Name = "Tomcat Response Time"
            Category = "Performance"
            Type = "ResponseTime"
            URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/web/"
            MaxResponseTimeMs = 5000
            Critical = $false
        }
        @{
            Name = "GeoWebCache Status"
            Category = "Caching"
            Type = "HTTP"
            URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/gwc/rest/statistics"
            ExpectedStatusCode = 200
            Critical = $false
        }
    )

    # Add comprehensive tests if requested
    if ($TestProfile -eq 'Comprehensive') {
        $tests += @(
            @{
                Name = "WCS GetCapabilities"
                Category = "OGC-Services"
                Type = "HTTP"
                URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/wcs?service=WCS&version=2.0.1&request=GetCapabilities"
                ExpectedStatusCode = 200
                ExpectedContent = "Capabilities"
                Critical = $false
            }
            @{
                Name = "WPS GetCapabilities"
                Category = "OGC-Services"
                Type = "HTTP"
                URL = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/wps?service=WPS&version=1.0.0&request=GetCapabilities"
                ExpectedStatusCode = 200
                ExpectedContent = "ProcessOfferings"
                Critical = $false
            }
            @{
                Name = "Memory Usage Check"
                Category = "Performance"
                Type = "MemoryCheck"
                Target = "java"
                MaxMemoryMB = 4096
                Critical = $false
            }
        )
    }

    return $tests
}

# ============================================================================
# TEST EXECUTION
# ============================================================================

function Invoke-Test {
    param([hashtable]$TestDefinition)

    $script:TestResults.Summary.Total++

    $testResult = @{
        Name = $TestDefinition.Name
        Category = $TestDefinition.Category
        Type = $TestDefinition.Type
        Critical = $TestDefinition.Critical
        Status = "Unknown"
        Message = ""
        ActualResult = $null
        ExpectedResult = $TestDefinition.ExpectedResult
        Duration = $null
        Timestamp = Get-Date
    }

    Write-LogEntry "Running test: $($TestDefinition.Name)" -Level INFO

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        switch ($TestDefinition.Type) {
            "ServiceCheck" {
                $service = Get-Service -Name $TestDefinition.Target -ErrorAction SilentlyContinue
                if ($service) {
                    $testResult.ActualResult = $service.Status.ToString()
                    if ($service.Status -eq 'Running') {
                        $testResult.Status = "PASS"
                        $testResult.Message = "Service is running"
                        $script:TestResults.Summary.Passed++
                    } else {
                        $testResult.Status = "FAIL"
                        $testResult.Message = "Service status: $($service.Status)"
                        $script:TestResults.Summary.Failed++
                    }
                } else {
                    $testResult.Status = "FAIL"
                    $testResult.Message = "Service not found"
                    $testResult.ActualResult = "Not Found"
                    $script:TestResults.Summary.Failed++
                }
            }

            "HTTP" {
                try {
                    $response = Invoke-WebRequest -Uri $TestDefinition.URL -Method Get -UseBasicParsing -TimeoutSec 30
                    $testResult.ActualResult = @{
                        StatusCode = $response.StatusCode
                        Content = $response.Content.Substring(0, [Math]::Min(500, $response.Content.Length))
                    }

                    $passed = $true
                    if ($TestDefinition.ExpectedStatusCode -and $response.StatusCode -ne $TestDefinition.ExpectedStatusCode) {
                        $passed = $false
                        $testResult.Message = "Expected status $($TestDefinition.ExpectedStatusCode), got $($response.StatusCode)"
                    }
                    if ($TestDefinition.ExpectedContent -and $response.Content -notmatch $TestDefinition.ExpectedContent) {
                        $passed = $false
                        $testResult.Message += " | Expected content pattern not found: $($TestDefinition.ExpectedContent)"
                    }

                    if ($passed) {
                        $testResult.Status = "PASS"
                        $testResult.Message = "HTTP request successful (Status: $($response.StatusCode))"
                        $script:TestResults.Summary.Passed++
                    } else {
                        $testResult.Status = "FAIL"
                        $script:TestResults.Summary.Failed++
                    }
                } catch {
                    $testResult.Status = "FAIL"
                    $testResult.Message = "HTTP request failed: $_"
                    $testResult.ActualResult = $_.Exception.Message
                    $script:TestResults.Summary.Failed++
                }
            }

            "ResponseTime" {
                try {
                    $timeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $response = Invoke-WebRequest -Uri $TestDefinition.URL -Method Get -UseBasicParsing -TimeoutSec 30
                    $timeStopwatch.Stop()

                    $responseTime = $timeStopwatch.ElapsedMilliseconds
                    $testResult.ActualResult = $responseTime

                    if ($responseTime -le $TestDefinition.MaxResponseTimeMs) {
                        $testResult.Status = "PASS"
                        $testResult.Message = "Response time: ${responseTime}ms (threshold: $($TestDefinition.MaxResponseTimeMs)ms)"
                        $script:TestResults.Summary.Passed++
                    } else {
                        $testResult.Status = "FAIL"
                        $testResult.Message = "Response time ${responseTime}ms exceeds threshold $($TestDefinition.MaxResponseTimeMs)ms"
                        $script:TestResults.Summary.Failed++
                    }
                } catch {
                    $testResult.Status = "FAIL"
                    $testResult.Message = "Response time test failed: $_"
                    $script:TestResults.Summary.Failed++
                }
            }

            "PathCheck" {
                if (Test-Path $TestDefinition.Target) {
                    $testResult.Status = "PASS"
                    $testResult.Message = "Path exists and is accessible"
                    $testResult.ActualResult = "Exists"
                    $script:TestResults.Summary.Passed++
                } else {
                    $testResult.Status = "FAIL"
                    $testResult.Message = "Path not found or not accessible"
                    $testResult.ActualResult = "Not Found"
                    $script:TestResults.Summary.Failed++
                }
            }

            "Database" {
                # PostgreSQL connection test
                try {
                    $pgPath = Join-Path $script:Config.components.postgresql.installPath "bin\psql.exe"
                    if (Test-Path $pgPath) {
                        $result = & $pgPath -U postgres -c "SELECT version();" 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $testResult.Status = "PASS"
                            $testResult.Message = "Database connection successful"
                            $testResult.ActualResult = "Connected"
                            $script:TestResults.Summary.Passed++
                        } else {
                            $testResult.Status = "FAIL"
                            $testResult.Message = "Database connection failed"
                            $testResult.ActualResult = $result
                            $script:TestResults.Summary.Failed++
                        }
                    } else {
                        $testResult.Status = "SKIP"
                        $testResult.Message = "PostgreSQL psql not found"
                        $script:TestResults.Summary.Skipped++
                    }
                } catch {
                    $testResult.Status = "FAIL"
                    $testResult.Message = "Database test error: $_"
                    $script:TestResults.Summary.Failed++
                }
            }

            default {
                $testResult.Status = "SKIP"
                $testResult.Message = "Unknown test type: $($TestDefinition.Type)"
                $script:TestResults.Summary.Skipped++
            }
        }
    } catch {
        $testResult.Status = "ERROR"
        $testResult.Message = "Test execution error: $_"
        $script:TestResults.Summary.Failed++
    }

    $stopwatch.Stop()
    $testResult.Duration = $stopwatch.ElapsedMilliseconds

    # Log result
    $statusColor = switch ($testResult.Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "CHANGED" { "Yellow" }
        "SKIP" { "Gray" }
        default { "White" }
    }
    Write-Host "  [$($testResult.Status)] $($TestDefinition.Name) - $($testResult.Message)" -ForegroundColor $statusColor

    $script:TestResults.Tests += $testResult
    return $testResult
}

# ============================================================================
# BASELINE MANAGEMENT
# ============================================================================

function Save-Baseline {
    param([string]$Name)

    if (-not $Name) {
        $Name = "baseline-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    $baselinePath = Join-Path $script:BaselineDirectory "$Name.json"

    $baselineData = @{
        Name = $Name
        Timestamp = Get-Date
        TestResults = $script:TestResults
        Environment = @{
            GeoServerVersion = "Detected"  # TODO: Detect version
            TomcatVersion = "Detected"
            JavaVersion = "Detected"
        }
    }

    $baselineData | ConvertTo-Json -Depth 10 | Set-Content -Path $baselinePath
    Write-LogEntry "Baseline saved: $baselinePath" -Level SUCCESS

    return $baselinePath
}

function Compare-ToBaseline {
    param(
        [string]$BaselineName,
        [array]$CurrentResults
    )

    $baselinePath = Join-Path $script:BaselineDirectory "$BaselineName.json"

    if (-not (Test-Path $baselinePath)) {
        Write-LogEntry "Baseline not found: $baselinePath" -Level ERROR
        return $null
    }

    $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
    Write-LogEntry "Comparing against baseline: $BaselineName (saved: $($baseline.Timestamp))" -Level INFO

    $comparison = @{
        BaselineName = $BaselineName
        BaselineDate = $baseline.Timestamp
        CurrentDate = Get-Date
        Changes = @()
        Summary = @{
            Identical = 0
            Changed = 0
            New = 0
            Missing = 0
        }
    }

    foreach ($currentTest in $CurrentResults) {
        $baselineTest = $baseline.TestResults.Tests | Where-Object { $_.Name -eq $currentTest.Name } | Select-Object -First 1

        if (-not $baselineTest) {
            $comparison.Changes += @{
                TestName = $currentTest.Name
                ChangeType = "NEW"
                Message = "Test not in baseline"
            }
            $comparison.Summary.New++
            continue
        }

        if ($currentTest.Status -ne $baselineTest.Status) {
            $comparison.Changes += @{
                TestName = $currentTest.Name
                ChangeType = "STATUS_CHANGED"
                BaselineStatus = $baselineTest.Status
                CurrentStatus = $currentTest.Status
                Message = "Status changed from $($baselineTest.Status) to $($currentTest.Status)"
            }
            $comparison.Summary.Changed++
            $currentTest.Status = "CHANGED"
            $script:TestResults.Summary.Changed++
        } elseif ($currentTest.ActualResult -ne $baselineTest.ActualResult) {
            $comparison.Changes += @{
                TestName = $currentTest.Name
                ChangeType = "RESULT_CHANGED"
                BaselineResult = $baselineTest.ActualResult
                CurrentResult = $currentTest.ActualResult
                Message = "Result changed"
            }
            $comparison.Summary.Changed++
        } else {
            $comparison.Summary.Identical++
        }
    }

    # Check for missing tests
    foreach ($baselineTest in $baseline.TestResults.Tests) {
        $currentTest = $CurrentResults | Where-Object { $_.Name -eq $baselineTest.Name }
        if (-not $currentTest) {
            $comparison.Changes += @{
                TestName = $baselineTest.Name
                ChangeType = "MISSING"
                Message = "Test exists in baseline but not in current run"
            }
            $comparison.Summary.Missing++
        }
    }

    return $comparison
}

# ============================================================================
# CHECKLIST GENERATION
# ============================================================================

function New-ManualTestChecklist {
    <#
    .SYNOPSIS
        Generates manual testing checklist.
    #>

    $checklist = @(
        @{
            Category = "Visual Verification"
            Items = @(
                "GeoServer web admin interface loads correctly",
                "Layer preview shows map tiles correctly",
                "Style editor opens and displays styles",
                "Workspace management page functions",
                "Security/authentication page accessible"
            )
        }
        @{
            Category = "Data Publishing"
            Items = @(
                "Can create new workspace",
                "Can add new datastore (shapefile/PostGIS)",
                "Can publish new layer",
                "Can configure layer styling",
                "Can set layer metadata"
            )
        }
        @{
            Category = "OGC Services"
            Items = @(
                "WMS GetMap request returns valid image",
                "WMS GetFeatureInfo returns attribute data",
                "WFS GetFeature returns GML/JSON correctly",
                "WCS GetCoverage returns raster data",
                "WPS process executes successfully"
            )
        }
        @{
            Category = "Performance"
            Items = @(
                "Map tile rendering speed acceptable",
                "Large dataset queries complete in reasonable time",
                "Memory usage stable under load",
                "No memory leaks after extended use",
                "Concurrent user access works"
            )
        }
        @{
            Category = "Data Integrity"
            Items = @(
                "All layers present in catalog",
                "Layer data matches pre-upgrade content",
                "Attribute data complete and correct",
                "Spatial extent/bounds correct",
                "SLD styles render identically"
            )
        }
        @{
            Category = "Integration"
            Items = @(
                "External applications can connect",
                "Authentication/authorization working",
                "LDAP/Active Directory integration functional",
                "Proxy/load balancer connectivity OK",
                "SSL/TLS certificates valid"
            )
        }
    )

    return $checklist
}

function Send-TestChecklist {
    param(
        [string]$Recipients,
        [object]$AutomatedResults,
        [object]$ManualChecklist
    )

    if (-not $Recipients) {
        Write-LogEntry "No email recipients specified" -Level WARNING
        return
    }

    $emailScript = Join-Path $script:RepositoryRoot "scripts\utilities\Send-EmailNotification.ps1"

    if (-not (Test-Path $emailScript)) {
        Write-LogEntry "Email notification script not found" -Level WARNING
        return
    }

    $checklistHtml = @"
<html>
<head>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
h1 { color: #2c3e50; }
h2 { color: #34495e; margin-top: 30px; }
.summary { background: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
.pass { color: green; font-weight: bold; }
.fail { color: red; font-weight: bold; }
.changed { color: orange; font-weight: bold; }
table { border-collapse: collapse; width: 100%; margin: 20px 0; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #34495e; color: white; }
.checklist { list-style-type: none; }
.checklist li { padding: 8px; margin: 5px 0; background: #f8f9fa; border-left: 4px solid #3498db; }
.checkbox { margin-right: 10px; }
</style>
</head>
<body>
<h1>🗺️ GeoServer Testing Checklist</h1>
<p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>

<div class="summary">
<h2>Automated Test Results</h2>
<p>
Total Tests: $($AutomatedResults.Summary.Total)<br>
<span class="pass">Passed: $($AutomatedResults.Summary.Passed)</span><br>
<span class="fail">Failed: $($AutomatedResults.Summary.Failed)</span><br>
<span class="changed">Changed: $($AutomatedResults.Summary.Changed)</span>
</p>
</div>

<h2>Automated Test Details</h2>
<table>
<tr><th>Test Name</th><th>Category</th><th>Status</th><th>Message</th></tr>
$(foreach ($test in $AutomatedResults.Tests) {
    $statusClass = $test.Status.ToLower()
    "<tr><td>$($test.Name)</td><td>$($test.Category)</td><td class='$statusClass'>$($test.Status)</td><td>$($test.Message)</td></tr>"
})
</table>

<h2>Manual Verification Checklist</h2>
<p><strong>Please complete the following manual tests and reply to this email with results:</strong></p>

$(foreach ($category in $ManualChecklist) {
    "<h3>$($category.Category)</h3>"
    "<ul class='checklist'>"
    foreach ($item in $category.Items) {
        "<li><input type='checkbox' class='checkbox'> $item</li>"
    }
    "</ul>"
})

<h2>Instructions</h2>
<ol>
<li>Review automated test results above</li>
<li>Work through each manual verification item</li>
<li>Mark checkboxes as you complete each item</li>
<li>Note any issues or unexpected behavior</li>
<li>Reply to this email with:
  <ul>
    <li>Completed checklist (copy/paste with [X] for checked items)</li>
    <li>Any failures or concerns</li>
    <li>Screenshots if applicable</li>
  </ul>
</li>
</ol>

<hr>
<p style="color: #7f8c8d; font-size: 12px;">
Generated by GeoServer Infrastructure Automation Suite v$($script:ScriptVersion)<br>
Log: $($script:LogPath)
</p>
</body>
</html>
"@

    try {
        & $emailScript `
            -To ($Recipients -split ',') `
            -Subject "GeoServer Testing Checklist - $(Get-Date -Format 'yyyy-MM-dd')" `
            -Body $checklistHtml `
            -BodyAsHtml

        Write-LogEntry "Test checklist emailed to: $Recipients" -Level SUCCESS
    } catch {
        Write-LogEntry "Failed to send email: $_" -Level ERROR
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-SectionHeader "GeoServer Baseline Testing - v$script:ScriptVersion"

    # Load configuration
    Load-Configuration

    # Get test definitions
    Write-SectionHeader "Loading Test Definitions"
    $standardTests = Get-StandardTests
    $customTests = Load-CustomTests -Path $CustomTestsPath
    $allTests = $standardTests + $customTests

    Write-LogEntry "Total tests to run: $($allTests.Count)" -Level INFO
    Write-LogEntry "  Standard tests: $($standardTests.Count)" -Level INFO
    Write-LogEntry "  Custom tests: $($customTests.Count)" -Level INFO

    # Execute tests
    Write-SectionHeader "Executing Tests"

    foreach ($test in $allTests) {
        Invoke-Test -TestDefinition $test
    }

    # Handle baseline operations
    if ($Mode -eq 'SaveBaseline') {
        Write-SectionHeader "Saving Baseline"
        $savedPath = Save-Baseline -Name $BaselineName
        Write-LogEntry "Baseline saved successfully: $savedPath" -Level SUCCESS
    }

    if ($Mode -eq 'CompareBaseline') {
        Write-SectionHeader "Comparing to Baseline"
        $comparison = Compare-ToBaseline -BaselineName $BaselineName -CurrentResults $script:TestResults.Tests

        if ($comparison) {
            Write-LogEntry "Comparison Summary:" -Level INFO
            Write-LogEntry "  Identical: $($comparison.Summary.Identical)" -Level SUCCESS
            Write-LogEntry "  Changed: $($comparison.Summary.Changed)" -Level WARNING
            Write-LogEntry "  New: $($comparison.Summary.New)" -Level INFO
            Write-LogEntry "  Missing: $($comparison.Summary.Missing)" -Level WARNING

            if ($comparison.Changes.Count -gt 0) {
                Write-LogEntry "Changes detected:" -Level WARNING
                foreach ($change in $comparison.Changes) {
                    Write-LogEntry "  - $($change.TestName): $($change.Message)" -Level WARNING
                }
            }
        }
    }

    # Generate checklist
    if ($GenerateChecklist) {
        Write-SectionHeader "Generating Manual Test Checklist"
        $manualChecklist = New-ManualTestChecklist

        if ($EmailRecipients) {
            Send-TestChecklist -Recipients $EmailRecipients -AutomatedResults $script:TestResults -ManualChecklist $manualChecklist
        } else {
            Write-LogEntry "Manual checklist generated (no email recipients specified)" -Level INFO
        }
    }

    # Summary
    Write-SectionHeader "Test Summary"
    Write-LogEntry "Total: $($script:TestResults.Summary.Total)" -Level INFO
    Write-LogEntry "Passed: $($script:TestResults.Summary.Passed)" -Level SUCCESS
    Write-LogEntry "Failed: $($script:TestResults.Summary.Failed)" -Level $(if ($script:TestResults.Summary.Failed -gt 0) { "ERROR" } else { "INFO" })
    Write-LogEntry "Changed: $($script:TestResults.Summary.Changed)" -Level $(if ($script:TestResults.Summary.Changed -gt 0) { "WARNING" } else { "INFO" })
    Write-LogEntry "Skipped: $($script:TestResults.Summary.Skipped)" -Level INFO

    # Save results
    $resultsPath = Join-Path $script:LogDirectory "test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $script:TestResults | ConvertTo-Json -Depth 10 | Set-Content -Path $resultsPath
    Write-LogEntry "Results saved: $resultsPath" -Level SUCCESS
    Write-LogEntry "Log file: $script:LogPath" -Level INFO

    # Exit code
    if ($script:TestResults.Summary.Failed -gt 0) {
        exit 1
    } else {
        exit 0
    }

} catch {
    Write-LogEntry "Testing failed: $_" -Level ERROR
    Write-LogEntry $_.ScriptStackTrace -Level DEBUG
    exit 99
}
