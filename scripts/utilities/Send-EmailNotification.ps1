<#
.SYNOPSIS
    Enhanced email notification system for GeoServer infrastructure automation.

.DESCRIPTION
    Sends professional HTML email notifications for:
    - Upgrade completion/failure alerts
    - Integration test results
    - New version availability alerts
    - Security advisory notifications
    - Scheduled maintenance reports
    - Configuration change alerts

    Supports SMTP authentication, TLS, attachments, and HTML templates.

.PARAMETER To
    Email recipient(s). Comma-separated for multiple recipients.

.PARAMETER Subject
    Email subject line.

.PARAMETER Body
    Email body text (plain text or HTML).

.PARAMETER BodyFile
    Path to HTML file to use as email body.

.PARAMETER Template
    Pre-defined template: UpgradeSuccess, UpgradeFailed, VersionAlert, SecurityAlert, TestReport

.PARAMETER AttachmentPath
    Path to file attachment (e.g., test reports, logs).

.PARAMETER Priority
    Email priority: Low, Normal, High

.PARAMETER SMTPServer
    SMTP server address (default: from config or localhost).

.PARAMETER SMTPPort
    SMTP port (default: 587 for TLS, 25 for non-TLS).

.PARAMETER UseTLS
    Use TLS encryption (default: true).

.PARAMETER Credential
    PSCredential object for SMTP authentication.

.EXAMPLE
    .\Send-EmailNotification.ps1 -To "admin@company.com" -Subject "Test" -Body "Hello"
    # Send simple email

.EXAMPLE
    .\Send-EmailNotification.ps1 -Template "UpgradeSuccess" -To "team@company.com"
    # Send upgrade success notification using template

.EXAMPLE
    .\Send-EmailNotification.ps1 -Template "TestReport" -AttachmentPath "C:\reports\test.html"
    # Send test report with attachment

.NOTES
    Author: GeoServer Infrastructure Automation Suite
    Version: 2.2.0
    Requires: PowerShell 7.0+
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Recipient email address(es)")]
    [string[]]$To,

    [Parameter(HelpMessage = "Email subject")]
    [string]$Subject,

    [Parameter(HelpMessage = "Email body content")]
    [string]$Body,

    [Parameter(HelpMessage = "Path to HTML file for body")]
    [string]$BodyFile,

    [Parameter(HelpMessage = "Pre-defined email template")]
    [ValidateSet('UpgradeSuccess', 'UpgradeFailed', 'VersionAlert', 'SecurityAlert', 'TestReport', 'MaintenanceScheduled', 'ConfigurationChange')]
    [string]$Template,

    [Parameter(HelpMessage = "Attachment file path")]
    [string]$AttachmentPath,

    [Parameter(HelpMessage = "Email priority")]
    [ValidateSet('Low', 'Normal', 'High')]
    [string]$Priority = 'Normal',

    [Parameter(HelpMessage = "SMTP server address")]
    [string]$SMTPServer,

    [Parameter(HelpMessage = "SMTP port")]
    [int]$SMTPPort = 587,

    [Parameter(HelpMessage = "Use TLS encryption")]
    [switch]$UseTLS = $true,

    [Parameter(HelpMessage = "SMTP credentials")]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(HelpMessage = "Additional template data")]
    [hashtable]$TemplateData = @{}
)

#Requires -Version 7.0

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
$script:LogPath = Join-Path $script:LogDirectory "email-notifications-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
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

#endregion

#region Configuration Loading

function Load-Configuration {
    Write-LogEntry "Loading configuration..." -Level INFO

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

    Write-LogEntry "Configuration file not found, using defaults" -Level WARNING
    return $false
}

#endregion

#region Email Templates

function Get-EmailTemplate {
    <#
    .SYNOPSIS
        Returns HTML email template based on notification type.
    #>
    param(
        [string]$TemplateName,
        [hashtable]$Data
    )

    $baseStyle = @"
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background: #f5f5f5; }
    .container { max-width: 600px; margin: 20px auto; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 24px; }
    .content { padding: 30px; }
    .content h2 { color: #2c3e50; margin-top: 0; }
    .content p { color: #34495e; line-height: 1.6; }
    .alert { padding: 15px; border-radius: 5px; margin: 20px 0; }
    .alert-success { background: #d4edda; border-left: 4px solid #28a745; color: #155724; }
    .alert-danger { background: #f8d7da; border-left: 4px solid #dc3545; color: #721c24; }
    .alert-warning { background: #fff3cd; border-left: 4px solid #ffc107; color: #856404; }
    .alert-info { background: #d1ecf1; border-left: 4px solid #17a2b8; color: #0c5460; }
    .details { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
    .details-item { margin: 10px 0; }
    .details-label { font-weight: bold; color: #495057; }
    .details-value { color: #6c757d; }
    .button { display: inline-block; padding: 12px 24px; background: #667eea; color: white; text-decoration: none; border-radius: 5px; margin: 10px 0; }
    .button:hover { background: #5568d3; }
    .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #6c757d; font-size: 12px; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th { background: #e9ecef; padding: 10px; text-align: left; font-weight: bold; }
    td { padding: 10px; border-bottom: 1px solid #dee2e6; }
</style>
"@

    switch ($TemplateName) {
        'UpgradeSuccess' {
            $component = if ($Data.Component) { $Data.Component } else { "Component" }
            $version = if ($Data.Version) { $Data.Version } else { "N/A" }
            $duration = if ($Data.Duration) { $Data.Duration } else { "N/A" }

            return @"
<!DOCTYPE html>
<html>
<head>$baseStyle</head>
<body>
    <div class="container">
        <div class="header" style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);">
            <h1>✅ Upgrade Successful</h1>
        </div>
        <div class="content">
            <h2>$component Upgrade Completed</h2>
            <div class="alert alert-success">
                <strong>Success!</strong> The $component upgrade has been completed successfully.
            </div>
            <div class="details">
                <div class="details-item">
                    <span class="details-label">Component:</span>
                    <span class="details-value">$component</span>
                </div>
                <div class="details-item">
                    <span class="details-label">New Version:</span>
                    <span class="details-value">$version</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Duration:</span>
                    <span class="details-value">$duration</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Timestamp:</span>
                    <span class="details-value">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span>
                </div>
            </div>
            <p><strong>Post-upgrade actions:</strong></p>
            <ul>
                <li>All services have been restarted</li>
                <li>Health checks passed successfully</li>
                <li>Configuration has been backed up</li>
                <li>Rollback point created</li>
            </ul>
        </div>
        <div class="footer">
            <p>GeoServer Infrastructure Automation Suite v2.2.0</p>
            <p>This is an automated notification - please do not reply</p>
        </div>
    </div>
</body>
</html>
"@
        }

        'UpgradeFailed' {
            $component = if ($Data.Component) { $Data.Component } else { "Component" }
            $error = if ($Data.Error) { $Data.Error } else { "Unknown error" }

            return @"
<!DOCTYPE html>
<html>
<head>$baseStyle</head>
<body>
    <div class="container">
        <div class="header" style="background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);">
            <h1>❌ Upgrade Failed</h1>
        </div>
        <div class="content">
            <h2>$component Upgrade Failed</h2>
            <div class="alert alert-danger">
                <strong>Error!</strong> The $component upgrade encountered an error and has been rolled back.
            </div>
            <div class="details">
                <div class="details-item">
                    <span class="details-label">Component:</span>
                    <span class="details-value">$component</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Error:</span>
                    <span class="details-value">$error</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Timestamp:</span>
                    <span class="details-value">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span>
                </div>
            </div>
            <p><strong>Actions taken:</strong></p>
            <ul>
                <li>Upgrade process halted</li>
                <li>System rolled back to previous state</li>
                <li>Services restored to working condition</li>
                <li>Error logs captured for analysis</li>
            </ul>
            <p><strong>Next steps:</strong></p>
            <ul>
                <li>Review error logs in the configured log directory</li>
                <li>Verify system health</li>
                <li>Contact support if issue persists</li>
            </ul>
        </div>
        <div class="footer">
            <p>GeoServer Infrastructure Automation Suite v2.2.0</p>
            <p>This is an automated notification - please do not reply</p>
        </div>
    </div>
</body>
</html>
"@
        }

        'VersionAlert' {
            $component = if ($Data.Component) { $Data.Component } else { "Component" }
            $currentVersion = if ($Data.CurrentVersion) { $Data.CurrentVersion } else { "Unknown" }
            $latestVersion = if ($Data.LatestVersion) { $Data.LatestVersion } else { "Unknown" }
            $releaseNotes = if ($Data.ReleaseNotes) { $Data.ReleaseNotes } else { "See vendor website for release notes" }
            $configImpact = if ($Data.ConfigImpact) { $Data.ConfigImpact } else { "No configuration changes required" }

            return @"
<!DOCTYPE html>
<html>
<head>$baseStyle</head>
<body>
    <div class="container">
        <div class="header" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
            <h1>🔔 New Version Available</h1>
        </div>
        <div class="content">
            <h2>$component Update Available</h2>
            <div class="alert alert-info">
                <strong>New version detected!</strong> A newer version of $component is available for installation.
            </div>
            <div class="details">
                <div class="details-item">
                    <span class="details-label">Component:</span>
                    <span class="details-value">$component</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Current Version:</span>
                    <span class="details-value">$currentVersion</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Latest Version:</span>
                    <span class="details-value">$latestVersion</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Configuration Impact:</span>
                    <span class="details-value">$configImpact</span>
                </div>
            </div>
            <p><strong>Release Notes:</strong></p>
            <div class="details">
                <p>$releaseNotes</p>
            </div>
            <p><strong>Recommended Action:</strong></p>
            <ul>
                <li>Review the release notes above</li>
                <li>Schedule maintenance window for upgrade</li>
                <li>Test upgrade in staging environment first</li>
                <li>Use automation suite for seamless upgrade</li>
            </ul>
        </div>
        <div class="footer">
            <p>GeoServer Infrastructure Automation Suite v2.2.0</p>
            <p>This is an automated notification - please do not reply</p>
        </div>
    </div>
</body>
</html>
"@
        }

        'SecurityAlert' {
            $component = if ($Data.Component) { $Data.Component } else { "Component" }
            $cve = if ($Data.CVE) { $Data.CVE } else { "N/A" }
            $severity = if ($Data.Severity) { $Data.Severity } else { "Unknown" }
            $description = if ($Data.Description) { $Data.Description } else { "Security vulnerability detected" }
            $recommendation = if ($Data.Recommendation) { $Data.Recommendation } else { "Upgrade to latest version" }

            return @"
<!DOCTYPE html>
<html>
<head>$baseStyle</head>
<body>
    <div class="container">
        <div class="header" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);">
            <h1>🔒 Security Advisory</h1>
        </div>
        <div class="content">
            <h2>Security Vulnerability Detected</h2>
            <div class="alert alert-warning">
                <strong>Security Alert!</strong> A security vulnerability has been identified in your infrastructure.
            </div>
            <div class="details">
                <div class="details-item">
                    <span class="details-label">Affected Component:</span>
                    <span class="details-value">$component</span>
                </div>
                <div class="details-item">
                    <span class="details-label">CVE ID:</span>
                    <span class="details-value">$cve</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Severity:</span>
                    <span class="details-value" style="color: #dc3545; font-weight: bold;">$severity</span>
                </div>
            </div>
            <p><strong>Description:</strong></p>
            <div class="details">
                <p>$description</p>
            </div>
            <p><strong>Recommendation:</strong></p>
            <div class="alert alert-danger">
                $recommendation
            </div>
            <p><strong>Immediate Actions:</strong></p>
            <ul>
                <li>Assess your exposure to this vulnerability</li>
                <li>Review mitigation options</li>
                <li>Schedule emergency maintenance if critical</li>
                <li>Monitor for exploitation attempts</li>
            </ul>
        </div>
        <div class="footer">
            <p>GeoServer Infrastructure Automation Suite v2.2.0</p>
            <p>This is an automated notification - please do not reply</p>
        </div>
    </div>
</body>
</html>
"@
        }

        'TestReport' {
            $total = if ($Data.TotalTests) { $Data.TotalTests } else { 0 }
            $passed = if ($Data.PassedTests) { $Data.PassedTests } else { 0 }
            $failed = if ($Data.FailedTests) { $Data.FailedTests } else { 0 }
            $passRate = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 2) } else { 0 }

            return @"
<!DOCTYPE html>
<html>
<head>$baseStyle</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Integration Test Report</h1>
        </div>
        <div class="content">
            <h2>Test Execution Summary</h2>
            <div class="details">
                <div class="details-item">
                    <span class="details-label">Total Tests:</span>
                    <span class="details-value">$total</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Passed:</span>
                    <span class="details-value" style="color: #28a745; font-weight: bold;">$passed</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Failed:</span>
                    <span class="details-value" style="color: #dc3545; font-weight: bold;">$failed</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Pass Rate:</span>
                    <span class="details-value" style="font-weight: bold;">$passRate%</span>
                </div>
                <div class="details-item">
                    <span class="details-label">Execution Time:</span>
                    <span class="details-value">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span>
                </div>
            </div>
            <p>Detailed test results are attached to this email.</p>
            <p><strong>Test Coverage:</strong></p>
            <ul>
                <li>Service availability tests</li>
                <li>GeoServer endpoint tests (WMS, WFS, REST)</li>
                <li>PostgreSQL connectivity tests</li>
                <li>Backup/restore functionality tests</li>
                <li>Performance baseline tests</li>
            </ul>
        </div>
        <div class="footer">
            <p>GeoServer Infrastructure Automation Suite v2.2.0</p>
            <p>This is an automated notification - please do not reply</p>
        </div>
    </div>
</body>
</html>
"@
        }

        default {
            return @"
<!DOCTYPE html>
<html>
<head>$baseStyle</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📧 Notification</h1>
        </div>
        <div class="content">
            <p>$($Data.Message)</p>
        </div>
        <div class="footer">
            <p>GeoServer Infrastructure Automation Suite v2.2.0</p>
        </div>
    </div>
</body>
</html>
"@
        }
    }
}

#endregion

#region Email Sending

function Send-Email {
    <#
    .SYNOPSIS
        Sends email using SMTP.
    #>
    param(
        [string[]]$Recipients,
        [string]$Subject,
        [string]$BodyContent,
        [string]$AttachmentFile,
        [string]$Priority,
        [string]$Server,
        [int]$Port,
        [bool]$TLS,
        [System.Management.Automation.PSCredential]$SMTPCredential
    )

    Write-LogEntry "Preparing to send email..." -Level INFO
    Write-LogEntry "Recipients: $($Recipients -join ', ')" -Level DEBUG
    Write-LogEntry "Subject: $Subject" -Level DEBUG

    try {
        # Build email message
        $mailParams = @{
            To = $Recipients
            Subject = $Subject
            Body = $BodyContent
            BodyAsHtml = $true
            SmtpServer = $Server
            Port = $Port
            Priority = $Priority
        }

        # Add sender (from configuration or default)
        $fromAddress = $null
        if ($script:Config -and
            $script:Config.PSObject.Properties['notifications'] -and
            $script:Config.notifications.PSObject.Properties['email'] -and
            $script:Config.notifications.email.PSObject.Properties['from']) {
            $fromAddress = $script:Config.notifications.email.from
        }

        if ($fromAddress) {
            $mailParams['From'] = $fromAddress
        } else {
            $mailParams['From'] = "geoserver-automation@$env:COMPUTERNAME"
        }

        # Add credentials if provided
        if ($SMTPCredential) {
            $mailParams['Credential'] = $SMTPCredential
        }

        # Add TLS if requested
        if ($TLS) {
            $mailParams['UseSsl'] = $true
        }

        # Add attachment if provided
        if ($AttachmentFile -and (Test-Path $AttachmentFile)) {
            $mailParams['Attachments'] = $AttachmentFile
            Write-LogEntry "Attachment: $AttachmentFile" -Level DEBUG
        }

        # Send email
        Send-MailMessage @mailParams

        Write-LogEntry "Email sent successfully" -Level SUCCESS
        return $true

    } catch {
        Write-LogEntry "Failed to send email: $_" -Level ERROR
        return $false
    }
}

#endregion

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-LogEntry "Email notification service starting" -Level INFO

    # Load configuration
    Load-Configuration

    # Determine recipients
    $recipients = $To
    if (-not $recipients) {
        if ($script:Config -and
            $script:Config.PSObject.Properties['notifications'] -and
            $script:Config.notifications.PSObject.Properties['email'] -and
            $script:Config.notifications.email.PSObject.Properties['recipients']) {
            $recipients = $script:Config.notifications.email.recipients
        }
    }

    if (-not $recipients) {
        Write-LogEntry "No recipients specified and none configured in config file" -Level ERROR
        Write-LogEntry "Specify recipients via -To parameter or configure in notifications.email.recipients" -Level ERROR
        exit 1
    }

    # Determine SMTP settings
    $smtpServer = $SMTPServer
    if (-not $smtpServer) {
        if ($script:Config -and
            $script:Config.PSObject.Properties['notifications'] -and
            $script:Config.notifications.PSObject.Properties['email'] -and
            $script:Config.notifications.email.PSObject.Properties['smtpServer']) {
            $smtpServer = $script:Config.notifications.email.smtpServer
        }
    }
    if (-not $smtpServer) {
        $smtpServer = "localhost"
        Write-LogEntry "No SMTP server specified, using default: localhost" -Level WARNING
    }

    # Determine body content
    $bodyContent = $Body
    if ($Template) {
        Write-LogEntry "Using template: $Template" -Level INFO
        $bodyContent = Get-EmailTemplate -TemplateName $Template -Data $TemplateData
    } elseif ($BodyFile -and (Test-Path $BodyFile)) {
        Write-LogEntry "Loading body from file: $BodyFile" -Level INFO
        $bodyContent = Get-Content -Path $BodyFile -Raw
    }

    if (-not $bodyContent) {
        Write-LogEntry "No email body content provided" -Level ERROR
        exit 1
    }

    # Determine subject
    $emailSubject = $Subject
    if (-not $emailSubject) {
        $emailSubject = switch ($Template) {
            'UpgradeSuccess' { "GeoServer Upgrade Successful" }
            'UpgradeFailed' { "GeoServer Upgrade Failed - Action Required" }
            'VersionAlert' { "New Version Available" }
            'SecurityAlert' { "Security Advisory - Action Required" }
            'TestReport' { "Integration Test Report" }
            default { "GeoServer Infrastructure Notification" }
        }
    }

    # Send email
    $success = Send-Email -Recipients $recipients `
                          -Subject $emailSubject `
                          -BodyContent $bodyContent `
                          -AttachmentFile $AttachmentPath `
                          -Priority $Priority `
                          -Server $smtpServer `
                          -Port $SMTPPort `
                          -TLS $UseTLS `
                          -SMTPCredential $Credential

    if ($success) {
        Write-LogEntry "Email notification completed successfully" -Level SUCCESS
        exit 0
    } else {
        Write-LogEntry "Email notification failed" -Level ERROR
        exit 1
    }

} catch {
    Write-LogEntry "Critical error: $_" -Level ERROR
    Write-LogEntry $_.ScriptStackTrace -Level DEBUG
    exit 1
}
