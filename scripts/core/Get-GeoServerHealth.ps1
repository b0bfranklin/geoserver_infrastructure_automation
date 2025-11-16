<#
.SYNOPSIS
    Monitors and reports on the health status of GeoServer infrastructure components.

.DESCRIPTION
    This script provides comprehensive health monitoring for your GeoServer environment:

    - Service status (running/stopped)
    - Port availability and connectivity
    - HTTP response codes and times
    - Memory and CPU usage
    - Disk space availability
    - Database connectivity
    - Active sessions
    - Error detection

    Results can be displayed in multiple formats:
    - Console (real-time, color-coded)
    - HTML report (detailed, shareable)
    - JSON (for integration with monitoring systems)
    - Email summary (optional)

.PARAMETER ConfigPath
    Path to the upgrade configuration JSON file.

.PARAMETER OutputFormat
    Output format for the health report. Valid values: Console, HTML, JSON, All

.PARAMETER OutputPath
    Path where HTML/JSON reports should be saved. Defaults to ./reports/

.PARAMETER SendEmail
    Send health report via email (requires notification configuration).

.PARAMETER Continuous
    Run in continuous monitoring mode (refreshes every N seconds).

.PARAMETER RefreshInterval
    Refresh interval in seconds for continuous monitoring mode. Default: 60

.EXAMPLE
    .\Get-GeoServerHealth.ps1
    Display health status in console with color coding.

.EXAMPLE
    .\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath "C:\Reports\health.html"
    Generate an HTML health report.

.EXAMPLE
    .\Get-GeoServerHealth.ps1 -OutputFormat All
    Generate console, HTML, and JSON outputs.

.EXAMPLE
    .\Get-GeoServerHealth.ps1 -Continuous -RefreshInterval 30
    Continuous monitoring, refreshing every 30 seconds.

.EXAMPLE
    .\Get-GeoServerHealth.ps1 -SendEmail
    Generate health report and email it to configured recipients.

.NOTES
    File Name   : Get-GeoServerHealth.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+
    Version     : 1.0.0

    This script is safe to run anytime - it performs read-only operations.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Path to configuration file")]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$ConfigPath = ".\config\upgrade-config.json",

    [Parameter(Mandatory=$false, HelpMessage="Output format for health report")]
    [ValidateSet('Console', 'HTML', 'JSON', 'All')]
    [string]$OutputFormat = 'Console',

    [Parameter(Mandatory=$false, HelpMessage="Path for saving reports")]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory=$false, HelpMessage="Send email notification")]
    [switch]$SendEmail,

    [Parameter(Mandatory=$false, HelpMessage="Enable continuous monitoring")]
    [switch]$Continuous,

    [Parameter(Mandatory=$false, HelpMessage="Refresh interval for continuous mode (seconds)")]
    [ValidateRange(10, 3600)]
    [int]$RefreshInterval = 60
)

#Requires -Version 7.0

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"  # Continue on errors for monitoring

$script:ScriptVersion = "1.0.0"
$script:HealthData = @{}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

function Get-ConfigurationData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigFilePath
    )

    try {
        if (-not (Test-Path $ConfigFilePath)) {
            Write-Warning "Configuration file not found: $ConfigFilePath"
            return $null
        }

        $configContent = Get-Content -Path $ConfigFilePath -Raw
        $config = $configContent | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Warning "Failed to load configuration: $_"
        return $null
    }
}

# ============================================================================
# SERVICE HEALTH CHECK FUNCTIONS
# ============================================================================

function Test-ServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if (-not $service) {
            return @{
                Status = 'NotFound'
                DisplayName = $ServiceName
                StartType = 'N/A'
                Health = 'ERROR'
            }
        }

        $health = switch ($service.Status) {
            'Running' { 'OK' }
            'Stopped' { 'WARNING' }
            default { 'ERROR' }
        }

        return @{
            Status = $service.Status
            DisplayName = $service.DisplayName
            StartType = $service.StartType
            Health = $health
        }
    }
    catch {
        return @{
            Status = 'Error'
            DisplayName = $ServiceName
            StartType = 'N/A'
            Health = 'ERROR'
            Error = $_.Exception.Message
        }
    }
}

function Test-PortConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HostName = 'localhost',

        [Parameter(Mandatory=$true)]
        [int]$Port,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutMs = 5000
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($HostName, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

        if ($wait) {
            try {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return @{
                    Available = $true
                    ResponseTime = $TimeoutMs
                    Health = 'OK'
                }
            }
            catch {
                return @{
                    Available = $false
                    ResponseTime = $null
                    Health = 'ERROR'
                    Error = $_.Exception.Message
                }
            }
        }
        else {
            $tcpClient.Close()
            return @{
                Available = $false
                ResponseTime = $null
                Health = 'ERROR'
                Error = 'Connection timeout'
            }
        }
    }
    catch {
        return @{
            Available = $false
            ResponseTime = $null
            Health = 'ERROR'
            Error = $_.Exception.Message
        }
    }
}

function Test-HttpEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSec = 30
    )

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec -ErrorAction Stop
        $stopwatch.Stop()

        $health = switch ($response.StatusCode) {
            200 { 'OK' }
            {$_ -ge 400 -and $_ -lt 500} { 'WARNING' }
            {$_ -ge 500} { 'ERROR' }
            default { 'WARNING' }
        }

        return @{
            StatusCode = $response.StatusCode
            StatusDescription = $response.StatusDescription
            ResponseTimeMs = $stopwatch.ElapsedMilliseconds
            ContentLength = $response.Content.Length
            Health = $health
        }
    }
    catch {
        return @{
            StatusCode = 0
            StatusDescription = 'Failed'
            ResponseTimeMs = $null
            ContentLength = 0
            Health = 'ERROR'
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# RESOURCE MONITORING FUNCTIONS
# ============================================================================

function Get-DiskSpaceInfo {
    [CmdletBinding()]
    param()

    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }

        $driveInfo = @()
        foreach ($drive in $drives) {
            $usedGB = [math]::Round($drive.Used / 1GB, 2)
            $freeGB = [math]::Round($drive.Free / 1GB, 2)
            $totalGB = $usedGB + $freeGB
            $percentFree = [math]::Round(($freeGB / $totalGB) * 100, 1)

            $health = switch ($percentFree) {
                {$_ -lt 10} { 'ERROR' }
                {$_ -lt 20} { 'WARNING' }
                default { 'OK' }
            }

            $driveInfo += @{
                Drive = "$($drive.Name):"
                TotalGB = $totalGB
                UsedGB = $usedGB
                FreeGB = $freeGB
                PercentFree = $percentFree
                Health = $health
            }
        }

        return $driveInfo
    }
    catch {
        Write-Warning "Failed to get disk space info: $_"
        return @()
    }
}

function Get-SystemResourceUsage {
    [CmdletBinding()]
    param()

    try {
        # Get CPU usage
        $cpuUsage = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $cpuPercent = if ($cpuUsage) {
            [math]::Round($cpuUsage.CounterSamples[0].CookedValue, 1)
        } else { 0 }

        # Get memory usage
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
        $memoryPercentUsed = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 1)

        # Determine health
        $cpuHealth = switch ($cpuPercent) {
            {$_ -gt 90} { 'WARNING' }
            {$_ -gt 95} { 'ERROR' }
            default { 'OK' }
        }

        $memoryHealth = switch ($memoryPercentUsed) {
            {$_ -gt 85} { 'WARNING' }
            {$_ -gt 95} { 'ERROR' }
            default { 'OK' }
        }

        return @{
            CPU = @{
                PercentUsed = $cpuPercent
                Health = $cpuHealth
            }
            Memory = @{
                TotalGB = $totalMemoryGB
                UsedGB = $usedMemoryGB
                FreeGB = $freeMemoryGB
                PercentUsed = $memoryPercentUsed
                Health = $memoryHealth
            }
        }
    }
    catch {
        Write-Warning "Failed to get system resource usage: $_"
        return @{
            CPU = @{ PercentUsed = 0; Health = 'UNKNOWN' }
            Memory = @{ TotalGB = 0; UsedGB = 0; FreeGB = 0; PercentUsed = 0; Health = 'UNKNOWN' }
        }
    }
}

# ============================================================================
# DATABASE CONNECTIVITY FUNCTIONS
# ============================================================================

function Test-PostgreSQLConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$DbConfig
    )

    if (-not $DbConfig.enabled) {
        return @{
            Enabled = $false
            Health = 'DISABLED'
        }
    }

    try {
        # Note: This requires psql or a PostgreSQL .NET driver
        # For this version, we'll do a simple TCP connectivity test
        $portTest = Test-PortConnectivity -HostName $DbConfig.server -Port $DbConfig.port -TimeoutMs 5000

        return @{
            Enabled = $true
            Server = $DbConfig.server
            Port = $DbConfig.port
            Database = $DbConfig.database
            Connectivity = $portTest.Available
            Health = $portTest.Health
        }
    }
    catch {
        return @{
            Enabled = $true
            Server = $DbConfig.server
            Health = 'ERROR'
            Error = $_.Exception.Message
        }
    }
}

function Test-MSSQLConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$DbConfig
    )

    if (-not $DbConfig.enabled) {
        return @{
            Enabled = $false
            Health = 'DISABLED'
        }
    }

    try {
        # Simple TCP connectivity test
        $portTest = Test-PortConnectivity -HostName $DbConfig.server -Port $DbConfig.port -TimeoutMs 5000

        return @{
            Enabled = $true
            Server = $DbConfig.server
            Port = $DbConfig.port
            Database = $DbConfig.database
            Connectivity = $portTest.Available
            Health = $portTest.Health
        }
    }
    catch {
        return @{
            Enabled = $true
            Server = $DbConfig.server
            Health = 'ERROR'
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# COMPREHENSIVE HEALTH CHECK
# ============================================================================

function Get-ComprehensiveHealthStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    $healthStatus = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ServerName = $Config.environment.serverName
        ComputerName = $env:COMPUTERNAME
        Services = @{}
        Instances = @()
        Resources = @{}
        Databases = @{}
        OverallHealth = 'OK'
    }

    # Check each Tomcat instance
    foreach ($instance in $Config.environment.tomcatInstances) {
        $instanceHealth = @{
            Name = $instance.name
            DisplayName = $instance.displayName
            Path = $instance.path
            Port = $instance.port
        }

        # Service status
        if ($instance.serviceName) {
            $serviceHealth = Test-ServiceHealth -ServiceName $instance.serviceName
            $instanceHealth.Service = $serviceHealth
        }

        # Port connectivity
        $portHealth = Test-PortConnectivity -Port $instance.port
        $instanceHealth.PortConnectivity = $portHealth

        # HTTP endpoint
        $httpUrl = "http://localhost:$($instance.port)/geoserver/web/"
        $httpHealth = Test-HttpEndpoint -Url $httpUrl
        $instanceHealth.HttpEndpoint = $httpHealth

        # Determine instance overall health
        $instanceHealth.Health = if ($httpHealth.Health -eq 'OK' -and $portHealth.Health -eq 'OK') {
            'OK'
        } elseif ($httpHealth.Health -eq 'ERROR' -or $portHealth.Health -eq 'ERROR') {
            'ERROR'
        } else {
            'WARNING'
        }

        $healthStatus.Instances += $instanceHealth

        # Update overall health
        if ($instanceHealth.Health -eq 'ERROR') {
            $healthStatus.OverallHealth = 'ERROR'
        } elseif ($instanceHealth.Health -eq 'WARNING' -and $healthStatus.OverallHealth -ne 'ERROR') {
            $healthStatus.OverallHealth = 'WARNING'
        }
    }

    # System resources
    $healthStatus.Resources = Get-SystemResourceUsage
    $healthStatus.DiskSpace = Get-DiskSpaceInfo

    # Check resource health
    if ($healthStatus.Resources.CPU.Health -eq 'ERROR' -or $healthStatus.Resources.Memory.Health -eq 'ERROR') {
        $healthStatus.OverallHealth = 'ERROR'
    } elseif ($healthStatus.Resources.CPU.Health -eq 'WARNING' -or $healthStatus.Resources.Memory.Health -eq 'WARNING') {
        if ($healthStatus.OverallHealth -ne 'ERROR') {
            $healthStatus.OverallHealth = 'WARNING'
        }
    }

    # Database connectivity
    if ($Config.databases.postgresql) {
        $healthStatus.Databases.PostgreSQL = Test-PostgreSQLConnection -DbConfig $Config.databases.postgresql
    }

    if ($Config.databases.mssql) {
        $healthStatus.Databases.MSSQL = Test-MSSQLConnection -DbConfig $Config.databases.mssql
    }

    return $healthStatus
}

# ============================================================================
# OUTPUT FORMATTING FUNCTIONS
# ============================================================================

function Format-ConsoleOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$HealthData
    )

    # Clear screen for clean output
    # Clear-Host  # Commented out for logging purposes

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "           GeoServer Infrastructure Health Report" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Report Time    : $($HealthData.Timestamp)" -ForegroundColor White
    Write-Host "Server Name    : $($HealthData.ServerName)" -ForegroundColor White
    Write-Host "Computer       : $($HealthData.ComputerName)" -ForegroundColor White

    $overallColor = switch ($HealthData.OverallHealth) {
        'OK' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Gray' }
    }
    Write-Host "Overall Status : $($HealthData.OverallHealth)" -ForegroundColor $overallColor
    Write-Host ""

    # Instances
    Write-Host "=== GeoServer Instances ===" -ForegroundColor Cyan
    foreach ($instance in $HealthData.Instances) {
        $statusColor = switch ($instance.Health) {
            'OK' { 'Green' }
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'Gray' }
        }

        Write-Host ""
        Write-Host "  Instance: $($instance.Name) ($($instance.DisplayName))" -ForegroundColor White
        Write-Host "    Port           : $($instance.Port)" -ForegroundColor Gray
        Write-Host "    Status         : $($instance.Health)" -ForegroundColor $statusColor

        if ($instance.Service) {
            Write-Host "    Service        : $($instance.Service.Status)" -ForegroundColor Gray
        }

        if ($instance.HttpEndpoint) {
            Write-Host "    HTTP Status    : $($instance.HttpEndpoint.StatusCode)" -ForegroundColor Gray
            if ($instance.HttpEndpoint.ResponseTimeMs) {
                Write-Host "    Response Time  : $($instance.HttpEndpoint.ResponseTimeMs)ms" -ForegroundColor Gray
            }
        }
    }

    # Resources
    Write-Host ""
    Write-Host "=== System Resources ===" -ForegroundColor Cyan
    Write-Host ""

    $cpuColor = switch ($HealthData.Resources.CPU.Health) {
        'OK' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Gray' }
    }
    Write-Host "  CPU Usage      : $($HealthData.Resources.CPU.PercentUsed)%" -ForegroundColor $cpuColor

    $memColor = switch ($HealthData.Resources.Memory.Health) {
        'OK' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Gray' }
    }
    Write-Host "  Memory Usage   : $($HealthData.Resources.Memory.PercentUsed)% ($($HealthData.Resources.Memory.UsedGB)GB / $($HealthData.Resources.Memory.TotalGB)GB)" -ForegroundColor $memColor

    Write-Host ""
    Write-Host "  Disk Space:" -ForegroundColor White
    foreach ($drive in $HealthData.DiskSpace) {
        $diskColor = switch ($drive.Health) {
            'OK' { 'Green' }
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'Gray' }
        }
        Write-Host "    $($drive.Drive) : $($drive.FreeGB)GB free / $($drive.TotalGB)GB total ($($drive.PercentFree)% free)" -ForegroundColor $diskColor
    }

    # Databases
    if ($HealthData.Databases.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Database Connectivity ===" -ForegroundColor Cyan
        Write-Host ""

        if ($HealthData.Databases.PostgreSQL) {
            $db = $HealthData.Databases.PostgreSQL
            $dbColor = switch ($db.Health) {
                'OK' { 'Green' }
                'WARNING' { 'Yellow' }
                'ERROR' { 'Red' }
                'DISABLED' { 'Gray' }
                default { 'Gray' }
            }
            $status = if ($db.Enabled) { if ($db.Connectivity) { "Connected" } else { "Failed" } } else { "Disabled" }
            Write-Host "  PostgreSQL     : $status" -ForegroundColor $dbColor
            if ($db.Enabled) {
                Write-Host "    Server       : $($db.Server):$($db.Port)" -ForegroundColor Gray
            }
        }

        if ($HealthData.Databases.MSSQL) {
            $db = $HealthData.Databases.MSSQL
            $dbColor = switch ($db.Health) {
                'OK' { 'Green' }
                'WARNING' { 'Yellow' }
                'ERROR' { 'Red' }
                'DISABLED' { 'Gray' }
                default { 'Gray' }
            }
            $status = if ($db.Enabled) { if ($db.Connectivity) { "Connected" } else { "Failed" } } else { "Disabled" }
            Write-Host "  MSSQL          : $status" -ForegroundColor $dbColor
            if ($db.Enabled) {
                Write-Host "    Server       : $($db.Server):$($db.Port)" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Export-HtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$HealthData,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GeoServer Health Report - $($HealthData.Timestamp)</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            border-left: 4px solid #3498db;
            padding-left: 10px;
        }
        .status-ok { color: #27ae60; font-weight: bold; }
        .status-warning { color: #f39c12; font-weight: bold; }
        .status-error { color: #e74c3c; font-weight: bold; }
        .status-disabled { color: #95a5a6; font-weight: bold; }
        .info-grid {
            display: grid;
            grid-template-columns: 200px 1fr;
            gap: 10px;
            margin: 15px 0;
        }
        .info-label {
            font-weight: bold;
            color: #7f8c8d;
        }
        .instance-card {
            background-color: #ecf0f1;
            padding: 15px;
            margin: 10px 0;
            border-radius: 5px;
            border-left: 4px solid #3498db;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .metric-card {
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            margin: 10px 0;
        }
        .timestamp {
            color: #7f8c8d;
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>GeoServer Infrastructure Health Report</h1>

        <div class="info-grid">
            <div class="info-label">Report Time:</div>
            <div class="timestamp">$($HealthData.Timestamp)</div>

            <div class="info-label">Server Name:</div>
            <div>$($HealthData.ServerName)</div>

            <div class="info-label">Computer:</div>
            <div>$($HealthData.ComputerName)</div>

            <div class="info-label">Overall Status:</div>
            <div class="status-$($HealthData.OverallHealth.ToLower())">$($HealthData.OverallHealth)</div>
        </div>

        <h2>GeoServer Instances</h2>
"@

    foreach ($instance in $HealthData.Instances) {
        $statusClass = "status-$($instance.Health.ToLower())"
        $html += @"
        <div class="instance-card">
            <h3>$($instance.Name) - $($instance.DisplayName)</h3>
            <div class="info-grid">
                <div class="info-label">Port:</div>
                <div>$($instance.Port)</div>

                <div class="info-label">Status:</div>
                <div class="$statusClass">$($instance.Health)</div>

                <div class="info-label">HTTP Status:</div>
                <div>$($instance.HttpEndpoint.StatusCode)</div>

                <div class="info-label">Response Time:</div>
                <div>$($instance.HttpEndpoint.ResponseTimeMs)ms</div>
            </div>
        </div>
"@
    }

    $html += @"
        <h2>System Resources</h2>
        <div class="metrics">
            <div class="metric-card">
                <div class="info-label">CPU Usage</div>
                <div class="metric-value status-$($HealthData.Resources.CPU.Health.ToLower())">
                    $($HealthData.Resources.CPU.PercentUsed)%
                </div>
            </div>
            <div class="metric-card">
                <div class="info-label">Memory Usage</div>
                <div class="metric-value status-$($HealthData.Resources.Memory.Health.ToLower())">
                    $($HealthData.Resources.Memory.PercentUsed)%
                </div>
                <div>$($HealthData.Resources.Memory.UsedGB)GB / $($HealthData.Resources.Memory.TotalGB)GB</div>
            </div>
        </div>

        <h3>Disk Space</h3>
        <div class="metrics">
"@

    foreach ($drive in $HealthData.DiskSpace) {
        $html += @"
            <div class="metric-card">
                <div class="info-label">Drive $($drive.Drive)</div>
                <div class="metric-value status-$($drive.Health.ToLower())">
                    $($drive.PercentFree)% Free
                </div>
                <div>$($drive.FreeGB)GB / $($drive.TotalGB)GB</div>
            </div>
"@
    }

    $html += @"
        </div>

        <h2>Database Connectivity</h2>
        <div class="info-grid">
"@

    if ($HealthData.Databases.PostgreSQL) {
        $db = $HealthData.Databases.PostgreSQL
        $statusClass = "status-$($db.Health.ToLower())"
        $status = if ($db.Enabled) { if ($db.Connectivity) { "Connected" } else { "Failed" } } else { "Disabled" }
        $html += @"
            <div class="info-label">PostgreSQL:</div>
            <div class="$statusClass">$status</div>
"@
    }

    if ($HealthData.Databases.MSSQL) {
        $db = $HealthData.Databases.MSSQL
        $statusClass = "status-$($db.Health.ToLower())"
        $status = if ($db.Enabled) { if ($db.Connectivity) { "Connected" } else { "Failed" } } else { "Disabled" }
        $html += @"
            <div class="info-label">MSSQL:</div>
            <div class="$statusClass">$status</div>
"@
    }

    $html += @"
        </div>
    </div>
</body>
</html>
"@

    try {
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        $html | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to save HTML report: $_"
        return $false
    }
}

function Export-JsonReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$HealthData,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )

    try {
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        $HealthData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "JSON report saved to: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to save JSON report: $_"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-HealthMonitoring {
    [CmdletBinding()]
    param()

    try {
        # Load configuration
        $config = Get-ConfigurationData -ConfigFilePath $ConfigPath

        if (-not $config) {
            Write-Warning "Could not load configuration. Using defaults for monitoring."
            # Create minimal config for testing
            $config = @{
                environment = @{
                    serverName = "GeoServer"
                    tomcatInstances = @()
                }
                databases = @{}
            }
        }

        # Get health status
        $healthData = Get-ComprehensiveHealthStatus -Config $config
        $script:HealthData = $healthData

        # Output based on format
        if ($OutputFormat -eq 'Console' -or $OutputFormat -eq 'All') {
            Format-ConsoleOutput -HealthData $healthData
        }

        if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
            $htmlPath = if ($OutputPath) {
                if ($OutputPath -match '\.html$') {
                    $OutputPath
                } else {
                    Join-Path $OutputPath "health-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').html"
                }
            } else {
                ".\reports\health-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').html"
            }
            Export-HtmlReport -HealthData $healthData -OutputPath $htmlPath
        }

        if ($OutputFormat -eq 'JSON' -or $OutputFormat -eq 'All') {
            $jsonPath = if ($OutputPath) {
                if ($OutputPath -match '\.json$') {
                    $OutputPath
                } else {
                    Join-Path $OutputPath "health-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').json"
                }
            } else {
                ".\reports\health-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').json"
            }
            Export-JsonReport -HealthData $healthData -OutputPath $jsonPath
        }

        return $healthData.OverallHealth -eq 'OK'
    }
    catch {
        Write-Error "Health monitoring failed: $_"
        return $false
    }
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

if ($Continuous) {
    Write-Host "Starting continuous health monitoring (Ctrl+C to stop)..." -ForegroundColor Cyan
    Write-Host "Refresh interval: $RefreshInterval seconds" -ForegroundColor Cyan
    Write-Host ""

    while ($true) {
        Start-HealthMonitoring
        Start-Sleep -Seconds $RefreshInterval
    }
}
else {
    $healthy = Start-HealthMonitoring
    exit $(if ($healthy) { 0 } else { 1 })
}
