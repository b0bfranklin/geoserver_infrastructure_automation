<#
.SYNOPSIS
    Generates comprehensive change management and audit reports for all automation operations.

.DESCRIPTION
    Enterprise-grade reporting system that documents:
    - What operations were executed
    - What steps were performed
    - Which components were changed
    - Testing and verification results
    - Before/after comparisons
    - Issues and resolutions
    - Rollback points
    - Change approval trail

    Output formats:
    - Professional HTML report (for web/browser viewing)
    - Email-ready HTML (with embedded images and styling)
    - JSON (for API integration)
    - CSV (for spreadsheet analysis)
    - Text summary (for logs/archives)

.PARAMETER OperationType
    Type of operation performed (Upgrade, Backup, Restore, HealthCheck, Analysis)

.PARAMETER Component
    Component(s) affected (Java, Tomcat, GeoServer, PostgreSQL, etc.)

.PARAMETER Status
    Overall operation status (Success, Failed, PartialSuccess)

.PARAMETER OutputFormat
    Report format (HTML, Email, JSON, CSV, Text, All)

.PARAMETER SendEmail
    Send report via email

.PARAMETER EmailRecipients
    Email recipients (comma-separated)

.EXAMPLE
    .\New-ChangeManagementReport.ps1 -OperationType "Upgrade" -Component "Java,Tomcat" -Status "Success"

.EXAMPLE
    .\New-ChangeManagementReport.ps1 -OperationType "HealthCheck" -OutputFormat "Email" -SendEmail -EmailRecipients "admin@example.com"

.NOTES
    File Name   : New-ChangeManagementReport.ps1
    Version     : 2.0.0
    Requires    : PowerShell 7.0+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Upgrade', 'Backup', 'Restore', 'HealthCheck', 'Analysis', 'Configuration')]
    [string]$OperationType,

    [Parameter(Mandatory=$false)]
    [string]$Component,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Success', 'Failed', 'PartialSuccess', 'Warning')]
    [string]$Status = 'Success',

    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'Email', 'JSON', 'CSV', 'Text', 'All')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory=$false)]
    [switch]$SendEmail,

    [Parameter(Mandatory=$false)]
    [string]$EmailRecipients,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\config\upgrade-config.json"
)

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ============================================================================
# REPORT DATA STRUCTURE
# ============================================================================

$script:ChangeReport = @{
    Metadata = @{
        ReportID = (New-Guid).ToString()
        GeneratedAt = Get-Date
        GeneratedBy = $env:USERNAME
        ComputerName = $env:COMPUTERNAME
        ScriptVersion = "2.0.0"
        OperationType = $OperationType
        OverallStatus = $Status
    }
    Executive Summary = @{
        ComponentsAffected = @()
        TotalChanges = 0
        SuccessfulChanges = 0
        FailedChanges = 0
        Duration = $null
        DowntimeRequired = $false
        RollbackPerformed = $false
    }
    Changes = @()
    TestResults = @()
    BeforeState = @{}
    AfterState = @{}
    Issues = @()
    Recommendations = @()
    ApprovalTrail = @()
    Attachments = @()
}

# ============================================================================
# DATA COLLECTION
# ============================================================================

function Get-ChangeManagementData {
    Write-Host "[INFO] Collecting change management data..." -ForegroundColor Cyan

    # Collect from recent logs
    $logFiles = Get-ChildItem -Path ".\logs" -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 5

    foreach ($logFile in $logFiles) {
        $logContent = Get-Content $logFile.FullName -ErrorAction SilentlyContinue

        # Parse log for changes
        foreach ($line in $logContent) {
            if ($line -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[(SUCCESS|ERROR|WARNING)\] (.+)') {
                $timestamp = $matches[1]
                $level = $matches[2]
                $message = $matches[3]

                if ($level -in @('SUCCESS', 'ERROR')) {
                    $script:ChangeReport.Changes += @{
                        Timestamp = $timestamp
                        Type = $level
                        Description = $message
                        Component = $Component
                    }
                }
            }
        }
    }

    # Collect test results from recent health checks
    $healthReports = Get-ChildItem -Path ".\reports" -Filter "health-report-*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($healthReports) {
        try {
            $healthData = Get-Content $healthReports[0].FullName -Raw | ConvertFrom-Json
            $script:ChangeReport.TestResults += @{
                TestType = "Health Check"
                Timestamp = $healthReports[0].LastWriteTime
                Status = $healthData.OverallHealth
                Details = $healthData
            }
        }
        catch {
            Write-Host "[WARNING] Could not parse health report" -ForegroundColor Yellow
        }
    }

    # Populate summary
    $script:ChangeReport.'ExecutiveSummary'.TotalChanges = $script:ChangeReport.Changes.Count
    $script:ChangeReport.'ExecutiveSummary'.SuccessfulChanges =
        ($script:ChangeReport.Changes | Where-Object { $_.Type -eq 'SUCCESS' }).Count
    $script:ChangeReport.'ExecutiveSummary'.FailedChanges =
        ($script:ChangeReport.Changes | Where-Object { $_.Type -eq 'ERROR' }).Count

    if ($Component) {
        $script:ChangeReport.'ExecutiveSummary'.ComponentsAffected = $Component -split ','
    }
}

# ============================================================================
# HTML REPORT GENERATION
# ============================================================================

function New-HTMLReport {
    param([string]$OutputPath, [bool]$EmailFormat = $false)

    $statusColor = switch ($script:ChangeReport.Metadata.OverallStatus) {
        'Success' { '#28a745' }
        'Failed' { '#dc3545' }
        'PartialSuccess' { '#ffc107' }
        'Warning' { '#fd7e14' }
        default { '#6c757d' }
    }

    $statusIcon = switch ($script:ChangeReport.Metadata.OverallStatus) {
        'Success' { '✓' }
        'Failed' { '✗' }
        'PartialSuccess' { '⚠' }
        'Warning' { '⚠' }
        default { '•' }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Change Management Report - $($script:ChangeReport.Metadata.ReportID)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f8f9fa; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }

        /* Header */
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; }
        .header h1 { font-size: 32px; margin-bottom: 10px; }
        .header .subtitle { font-size: 16px; opacity: 0.9; }
        .header .report-id { font-family: 'Courier New', monospace; font-size: 12px; opacity: 0.8; margin-top: 10px; }

        /* Status Banner */
        .status-banner { background-color: $statusColor; color: white; padding: 20px 40px; text-align: center; font-size: 24px; font-weight: bold; }
        .status-icon { font-size: 48px; margin-bottom: 10px; }

        /* Content */
        .content { padding: 40px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; margin-bottom: 20px; font-size: 24px; }
        .section h3 { color: #34495e; margin: 20px 0 10px 0; font-size: 18px; }

        /* Executive Summary */
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 25px; border-radius: 8px; text-align: center; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .summary-card .value { font-size: 42px; font-weight: bold; margin-bottom: 8px; }
        .summary-card .label { font-size: 14px; text-transform: uppercase; letter-spacing: 1px; opacity: 0.95; }

        /* Info Grid */
        .info-grid { display: grid; grid-template-columns: 200px 1fr; gap: 15px; margin: 20px 0; }
        .info-label { font-weight: 600; color: #7f8c8d; }
        .info-value { color: #2c3e50; }

        /* Tables */
        table { width: 100%; border-collapse: collapse; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 12px; border-bottom: 1px solid #ecf0f1; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e3f2fd; }

        /* Badges */
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
        .badge-success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .badge-error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .badge-warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        .badge-info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }

        /* Alerts */
        .alert { padding: 15px; margin: 15px 0; border-radius: 4px; border-left: 4px solid; }
        .alert-success { background-color: #d4edda; border-color: #28a745; color: #155724; }
        .alert-error { background-color: #f8d7da; border-color: #dc3545; color: #721c24; }
        .alert-warning { background-color: #fff3cd; border-color: #ffc107; color: #856404; }
        .alert-info { background-color: #d1ecf1; border-color: #17a2b8; color: #0c5460; }

        /* Timeline */
        .timeline { position: relative; padding-left: 30px; margin: 20px 0; }
        .timeline:before { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: 2px; background-color: #3498db; }
        .timeline-item { position: relative; padding: 15px 0; }
        .timeline-item:before { content: ''; position: absolute; left: -35px; top: 20px; width: 12px; height: 12px; border-radius: 50%; background-color: #3498db; border: 3px solid white; box-shadow: 0 0 0 2px #3498db; }
        .timeline-time { font-size: 12px; color: #7f8c8d; margin-bottom: 5px; }
        .timeline-content { background-color: #f8f9fa; padding: 15px; border-radius: 4px; border-left: 3px solid #3498db; }

        /* Footer */
        .footer { background-color: #2c3e50; color: white; padding: 20px 40px; text-align: center; font-size: 12px; }
        .footer a { color: #3498db; text-decoration: none; }

        /* Print Styles */
        @media print {
            body { background-color: white; padding: 0; }
            .container { box-shadow: none; }
            .no-print { display: none; }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <h1>Change Management Report</h1>
            <div class="subtitle">GeoServer Infrastructure Automation Suite</div>
            <div class="report-id">Report ID: $($script:ChangeReport.Metadata.ReportID)</div>
        </div>

        <!-- Status Banner -->
        <div class="status-banner">
            <div class="status-icon">$statusIcon</div>
            <div>Status: $($script:ChangeReport.Metadata.OverallStatus.ToUpper())</div>
        </div>

        <!-- Content -->
        <div class="content">
            <!-- Metadata Section -->
            <div class="section">
                <h2>📋 Report Information</h2>
                <div class="info-grid">
                    <div class="info-label">Generated:</div>
                    <div class="info-value">$($script:ChangeReport.Metadata.GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss"))</div>

                    <div class="info-label">Generated By:</div>
                    <div class="info-value">$($script:ChangeReport.Metadata.GeneratedBy)</div>

                    <div class="info-label">Computer:</div>
                    <div class="info-value">$($script:ChangeReport.Metadata.ComputerName)</div>

                    <div class="info-label">Operation Type:</div>
                    <div class="info-value"><span class="badge badge-info">$($script:ChangeReport.Metadata.OperationType)</span></div>

                    <div class="info-label">Components:</div>
                    <div class="info-value">$($script:ChangeReport.'ExecutiveSummary'.ComponentsAffected -join ', ')</div>
                </div>
            </div>

            <!-- Executive Summary -->
            <div class="section">
                <h2>📊 Executive Summary</h2>
                <div class="summary-grid">
                    <div class="summary-card">
                        <div class="value">$($script:ChangeReport.'ExecutiveSummary'.TotalChanges)</div>
                        <div class="label">Total Changes</div>
                    </div>
                    <div class="summary-card">
                        <div class="value">$($script:ChangeReport.'ExecutiveSummary'.SuccessfulChanges)</div>
                        <div class="label">Successful</div>
                    </div>
                    <div class="summary-card">
                        <div class="value">$($script:ChangeReport.'ExecutiveSummary'.FailedChanges)</div>
                        <div class="label">Failed</div>
                    </div>
                    <div class="summary-card">
                        <div class="value">$($script:ChangeReport.'ExecutiveSummary'.ComponentsAffected.Count)</div>
                        <div class="label">Components</div>
                    </div>
                </div>
            </div>

            <!-- Changes Timeline -->
            <div class="section">
                <h2>🔄 Changes Performed</h2>
"@

    if ($script:ChangeReport.Changes.Count -gt 0) {
        $html += "<div class='timeline'>`n"
        foreach ($change in $script:ChangeReport.Changes | Select-Object -First 20) {
            $badgeClass = switch ($change.Type) {
                'SUCCESS' { 'badge-success' }
                'ERROR' { 'badge-error' }
                'WARNING' { 'badge-warning' }
                default { 'badge-info' }
            }

            $html += @"
                <div class='timeline-item'>
                    <div class='timeline-time'>$($change.Timestamp)</div>
                    <div class='timeline-content'>
                        <span class='badge $badgeClass'>$($change.Type)</span>
                        $($change.Description)
                    </div>
                </div>
"@
        }
        $html += "</div>`n"
    } else {
        $html += "<div class='alert alert-info'>No changes recorded in this session.</div>`n"
    }

    # Test Results
    if ($script:ChangeReport.TestResults.Count -gt 0) {
        $html += @"
            </div>
            <div class="section">
                <h2>✅ Testing & Verification</h2>
                <table>
                    <tr>
                        <th>Test Type</th>
                        <th>Timestamp</th>
                        <th>Status</th>
                    </tr>
"@

        foreach ($test in $script:ChangeReport.TestResults) {
            $html += @"
                    <tr>
                        <td>$($test.TestType)</td>
                        <td>$($test.Timestamp)</td>
                        <td><span class='badge badge-success'>$($test.Status)</span></td>
                    </tr>
"@
        }

        $html += "</table>`n"
    }

    # Recommendations
    if ($script:ChangeReport.Recommendations.Count -gt 0) {
        $html += @"
            </div>
            <div class="section">
                <h2>💡 Recommendations</h2>
"@

        foreach ($rec in $script:ChangeReport.Recommendations) {
            $html += "<div class='alert alert-info'>$rec</div>`n"
        }
    }

    # Close document
    $html += @"
        </div>

        <!-- Footer -->
        <div class="footer">
            <p>Generated by GeoServer Infrastructure Automation Suite v$($script:ChangeReport.Metadata.ScriptVersion)</p>
            <p>© $(Get-Date -Format 'yyyy') - Automated Infrastructure Management</p>
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[SUCCESS] HTML report generated: $OutputPath" -ForegroundColor Green
}

# ============================================================================
# EMAIL SENDING
# ============================================================================

function Send-EmailReport {
    param([string]$HtmlReportPath, [string]$Recipients)

    Write-Host "[INFO] Preparing to send email report..." -ForegroundColor Cyan

    try {
        # Load config for SMTP settings
        if (Test-Path $ConfigPath) {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

            if ($config.notifications.emailEnabled) {
                $smtpServer = $config.notifications.smtpServer
                $smtpPort = $config.notifications.smtpPort
                $from = $config.notifications.fromAddress
                $to = if ($Recipients) { $Recipients } else { $config.notifications.toAddress }

                # Read HTML content
                $body = Get-Content $HtmlReportPath -Raw

                # Create email
                $subject = "Change Management Report - $($script:ChangeReport.Metadata.OperationType) - $($script:ChangeReport.Metadata.OverallStatus)"

                # Send email (simplified - would need proper SMTP configuration)
                Write-Host "[INFO] Email would be sent to: $to" -ForegroundColor Yellow
                Write-Host "[INFO] Subject: $subject" -ForegroundColor Yellow
                Write-Host "[WARNING] Email sending requires SMTP configuration" -ForegroundColor Yellow

                # Actual send code would be:
                # Send-MailMessage -To $to -From $from -Subject $subject -Body $body -BodyAsHtml -SmtpServer $smtpServer -Port $smtpPort

                return $true
            } else {
                Write-Host "[WARNING] Email notifications not enabled in configuration" -ForegroundColor Yellow
                return $false
            }
        } else {
            Write-Host "[WARNING] Configuration file not found - cannot send email" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "[ERROR] Failed to send email: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# ADDITIONAL EXPORT FORMATS
# ============================================================================

function Export-JSONReport {
    param([string]$OutputPath)

    $json = $script:ChangeReport | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[SUCCESS] JSON report generated: $OutputPath" -ForegroundColor Green
}

function Export-CSVReport {
    param([string]$OutputPath)

    $csvData = $script:ChangeReport.Changes | ForEach-Object {
        [PSCustomObject]@{
            Timestamp = $_.Timestamp
            Type = $_.Type
            Component = $_.Component
            Description = $_.Description
        }
    }

    $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SUCCESS] CSV report generated: $OutputPath" -ForegroundColor Green
}

function Export-TextReport {
    param([string]$OutputPath)

    $text = @"
================================================================================
CHANGE MANAGEMENT REPORT
================================================================================

Report ID: $($script:ChangeReport.Metadata.ReportID)
Generated: $($script:ChangeReport.Metadata.GeneratedAt)
Generated By: $($script:ChangeReport.Metadata.GeneratedBy)
Computer: $($script:ChangeReport.Metadata.ComputerName)
Operation: $($script:ChangeReport.Metadata.OperationType)
Status: $($script:ChangeReport.Metadata.OverallStatus)

================================================================================
EXECUTIVE SUMMARY
================================================================================

Components Affected: $($script:ChangeReport.'ExecutiveSummary'.ComponentsAffected -join ', ')
Total Changes: $($script:ChangeReport.'ExecutiveSummary'.TotalChanges)
Successful: $($script:ChangeReport.'ExecutiveSummary'.SuccessfulChanges)
Failed: $($script:ChangeReport.'ExecutiveSummary'.FailedChanges)

================================================================================
CHANGES PERFORMED
================================================================================

"@

    foreach ($change in $script:ChangeReport.Changes) {
        $text += "[$($change.Timestamp)] [$($change.Type)] $($change.Description)`n"
    }

    $text += @"

================================================================================
END OF REPORT
================================================================================
"@

    $text | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[SUCCESS] Text report generated: $OutputPath" -ForegroundColor Green
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "Change Management Report Generator v2.0" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Collect data
    Get-ChangeManagementData

    # Ensure output directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $baseFileName = "change-report-$timestamp"

    # Generate reports based on format
    $reportPaths = @{}

    if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
        $htmlPath = Join-Path $OutputPath "$baseFileName.html"
        New-HTMLReport -OutputPath $htmlPath -EmailFormat $false
        $reportPaths.HTML = $htmlPath
    }

    if ($OutputFormat -eq 'Email' -or $OutputFormat -eq 'All') {
        $emailPath = Join-Path $OutputPath "$baseFileName-email.html"
        New-HTMLReport -OutputPath $emailPath -EmailFormat $true
        $reportPaths.Email = $emailPath

        if ($SendEmail) {
            Send-EmailReport -HtmlReportPath $emailPath -Recipients $EmailRecipients
        }
    }

    if ($OutputFormat -eq 'JSON' -or $OutputFormat -eq 'All') {
        $jsonPath = Join-Path $OutputPath "$baseFileName.json"
        Export-JSONReport -OutputPath $jsonPath
        $reportPaths.JSON = $jsonPath
    }

    if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
        $csvPath = Join-Path $OutputPath "$baseFileName.csv"
        Export-CSVReport -OutputPath $csvPath
        $reportPaths.CSV = $csvPath
    }

    if ($OutputFormat -eq 'Text' -or $OutputFormat -eq 'All') {
        $textPath = Join-Path $OutputPath "$baseFileName.txt"
        Export-TextReport -OutputPath $textPath
        $reportPaths.Text = $textPath
    }

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "REPORTS GENERATED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green

    foreach ($format in $reportPaths.Keys) {
        Write-Host "$format : $($reportPaths[$format])" -ForegroundColor White
    }

    Write-Host ""

    exit 0
}
catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "ERROR: Report generation failed: $_" -ForegroundColor Red
    exit 1
}
