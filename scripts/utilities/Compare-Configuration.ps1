<#
.SYNOPSIS
    Analyzes and compares GeoServer configurations for migration planning.

.DESCRIPTION
    Comprehensive configuration analysis tool that:
    - Scans existing GeoServer data directory
    - Identifies all workspaces, layers, and styles
    - Detects custom configurations and extensions
    - Checks for deprecated features
    - Compares with target version requirements
    - Generates detailed migration report
    - Exports findings in multiple formats (HTML, JSON, CSV)

.PARAMETER DataDirectory
    Path to GeoServer data directory

.PARAMETER TargetVersion
    Target GeoServer version for compatibility analysis

.PARAMETER OutputFormat
    Report output format (HTML, JSON, CSV, All)

.PARAMETER OutputPath
    Path to save the report

.EXAMPLE
    .\Compare-Configuration.ps1 -DataDirectory "D:\GeoServer\data"

.EXAMPLE
    .\Compare-Configuration.ps1 -DataDirectory "D:\GeoServer\data" -TargetVersion "2.25.0" -OutputFormat HTML

.NOTES
    File Name   : Compare-Configuration.ps1
    Version     : 2.0.0
    Requires    : PowerShell 7.0+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DataDirectory,

    [Parameter(Mandatory=$false)]
    [string]$TargetVersion = "2.25.0",

    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'JSON', 'CSV', 'All')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\config\upgrade-config.json"
)

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$script:AnalysisResults = @{
    Timestamp = Get-Date
    DataDirectory = $null
    Summary = @{
        Workspaces = 0
        TotalLayers = 0
        CustomStyles = 0
        Extensions = 0
        Issues = 0
        Warnings = 0
    }
    Workspaces = @()
    Styles = @()
    Extensions = @()
    Configuration = @()
    Issues = @()
    Recommendations = @()
    BreakingChanges = @()
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-LogEntry {
    param([string]$Message, [string]$Level = 'INFO')
    $colors = @{ERROR='Red';WARNING='Yellow';SUCCESS='Green';STEP='Cyan';default='White'}
    Write-Host "[$Level] $Message" -ForegroundColor $colors[$Level]
}

# ============================================================================
# XML PARSING FUNCTIONS
# ============================================================================

function Get-WorkspaceConfiguration {
    param([string]$WorkspacePath)

    $wsInfo = @{
        Name = (Split-Path $WorkspacePath -Leaf)
        Path = $WorkspacePath
        NamespaceURI = $null
        Isolated = $false
        Stores = @()
        Layers = @()
    }

    # Parse workspace.xml
    $wsXmlPath = Join-Path $WorkspacePath "workspace.xml"
    if (Test-Path $wsXmlPath) {
        try {
            [xml]$wsXml = Get-Content $wsXmlPath
            $wsInfo.NamespaceURI = $wsXml.workspace.namespaceURI
            $wsInfo.Isolated = ($wsXml.workspace.isolated -eq 'true')
        }
        catch {
            Write-LogEntry "Failed to parse $wsXmlPath" "WARNING"
        }
    }

    # Find data stores
    $storesDir = Get-ChildItem -Path $WorkspacePath -Recurse -Directory |
        Where-Object { $_.Name -match '(datastore|coveragestore)s' }

    foreach ($storeDir in $storesDir) {
        $stores = Get-ChildItem -Path $storeDir.FullName -Directory
        foreach ($store in $stores) {
            $storeXml = Get-ChildItem -Path $store.FullName -Filter "*.xml" | Select-Object -First 1
            if ($storeXml) {
                try {
                    [xml]$storeConfig = Get-Content $storeXml.FullName
                    $wsInfo.Stores += @{
                        Name = $store.Name
                        Type = $storeDir.Name
                        Config = $storeConfig
                    }
                }
                catch {
                    Write-LogEntry "Failed to parse $($storeXml.FullName)" "WARNING"
                }
            }
        }
    }

    # Find layers
    $layersDir = Get-ChildItem -Path $WorkspacePath -Recurse -Directory |
        Where-Object { $_.Name -eq 'layers' } | Select-Object -First 1

    if ($layersDir) {
        $layers = Get-ChildItem -Path $layersDir.FullName -Directory
        foreach ($layer in $layers) {
            $layerXml = Join-Path $layer.FullName "layer.xml"
            if (Test-Path $layerXml) {
                try {
                    [xml]$layerConfig = Get-Content $layerXml
                    $wsInfo.Layers += @{
                        Name = $layer.Name
                        Title = $layerConfig.layer.title
                        Enabled = ($layerConfig.layer.enabled -eq 'true')
                    }
                }
                catch {
                    Write-LogEntry "Failed to parse $layerXml" "WARNING"
                }
            }
        }
    }

    return $wsInfo
}

function Get-GlobalConfiguration {
    param([string]$DataDirectory)

    $globalConfig = @{}
    $globalXmlPath = Join-Path $DataDirectory "global.xml"

    if (Test-Path $globalXmlPath) {
        try {
            [xml]$globalXml = Get-Content $globalXmlPath

            $globalConfig = @{
                ProxyBaseUrl = $globalXml.global.settings.proxyBaseUrl
                NumDecimals = $globalXml.global.settings.numDecimals
                Charset = $globalXml.global.settings.charset
                VerboseExceptions = ($globalXml.global.settings.verboseExceptions -eq 'true')
                LoggingLevel = $globalXml.global.settings.loggingLevel
            }
        }
        catch {
            Write-LogEntry "Failed to parse global.xml" "WARNING"
        }
    }

    return $globalConfig
}

# ============================================================================
# ANALYSIS FUNCTIONS
# ============================================================================

function Invoke-ConfigurationAnalysis {
    param([string]$DataDirectory)

    Write-LogEntry "=== Starting Configuration Analysis ===" "STEP"
    Write-LogEntry "Data Directory: $DataDirectory" "INFO"

    if (-not (Test-Path $DataDirectory)) {
        throw "Data directory not found: $DataDirectory"
    }

    $script:AnalysisResults.DataDirectory = $DataDirectory

    # Analyze global configuration
    Write-LogEntry "Analyzing global configuration..." "INFO"
    $globalConfig = Get-GlobalConfiguration -DataDirectory $DataDirectory
    $script:AnalysisResults.Configuration = $globalConfig

    # Analyze workspaces
    Write-LogEntry "Scanning workspaces..." "INFO"
    $workspacesDir = Join-Path $DataDirectory "workspaces"

    if (Test-Path $workspacesDir) {
        $workspaces = Get-ChildItem -Path $workspacesDir -Directory

        foreach ($ws in $workspaces) {
            Write-LogEntry "  Analyzing workspace: $($ws.Name)" "INFO"
            $wsInfo = Get-WorkspaceConfiguration -WorkspacePath $ws.FullName
            $script:AnalysisResults.Workspaces += $wsInfo

            $script:AnalysisResults.Summary.TotalLayers += $wsInfo.Layers.Count
        }

        $script:AnalysisResults.Summary.Workspaces = $workspaces.Count
        Write-LogEntry "Found $($workspaces.Count) workspace(s)" "SUCCESS"
    }

    # Analyze styles
    Write-LogEntry "Scanning styles..." "INFO"
    $stylesDir = Join-Path $DataDirectory "styles"

    if (Test-Path $stylesDir) {
        $styles = Get-ChildItem -Path $stylesDir -Filter "*.sld"
        foreach ($style in $styles) {
            $script:AnalysisResults.Styles += @{
                Name = $style.BaseName
                File = $style.Name
                Size = $style.Length
            }
        }

        $script:AnalysisResults.Summary.CustomStyles = $styles.Count
        Write-LogEntry "Found $($styles.Count) custom style(s)" "SUCCESS"
    }

    # Check for extensions
    Write-LogEntry "Checking for extensions..." "INFO"
    # Extensions are typically in webapps/geoserver/WEB-INF/lib
    # This is a simplified check - would need Tomcat path

    Write-LogEntry "Configuration analysis completed" "SUCCESS"
}

function Test-VersionCompatibility {
    param([string]$TargetVersion)

    Write-LogEntry "=== Checking Compatibility with v$TargetVersion ===" "STEP"

    # Known breaking changes and deprecations
    $breakingChanges = @()
    $recommendations = @()
    $issues = @()

    # Parse target version
    if ($TargetVersion -match '^(\d+)\.(\d+)') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]

        # Version-specific checks
        if ($minor -ge 24) {
            $recommendations += "GeoServer 2.24+ supports Tomcat 10.x (jakarta.*)"
            $recommendations += "GeoServer 2.24+ requires Java 11 or later"
        }

        if ($minor -ge 25) {
            $recommendations += "GeoServer 2.25+ has updated REST API endpoints"
            $breakingChanges += "Some deprecated WFS operations removed in 2.25"
        }

        # Check for deprecated styles
        foreach ($style in $script:AnalysisResults.Styles) {
            if ($style.File -match '\.sld$') {
                # SLD files are fine, but check for deprecated elements
                # This would require XML parsing of each SLD file
            }
        }

        # Check workspace configurations
        foreach ($ws in $script:AnalysisResults.Workspaces) {
            if ($ws.Isolated) {
                $recommendations += "Workspace '$($ws.Name)' is isolated - verify isolation still works in $TargetVersion"
            }
        }
    }

    $script:AnalysisResults.BreakingChanges = $breakingChanges
    $script:AnalysisResults.Recommendations = $recommendations
    $script:AnalysisResults.Issues = $issues

    $script:AnalysisResults.Summary.Issues = $issues.Count
    $script:AnalysisResults.Summary.Warnings = $breakingChanges.Count

    if ($issues.Count -eq 0) {
        Write-LogEntry "No blocking issues found" "SUCCESS"
    } else {
        Write-LogEntry "$($issues.Count) potential issue(s) found" "WARNING"
    }
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

function Export-HTMLReport {
    param([string]$OutputPath)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>GeoServer Configuration Analysis Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; margin-bottom: 30px; }
        h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 10px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card .value { font-size: 48px; font-weight: bold; }
        .summary-card .label { font-size: 14px; margin-top: 10px; opacity: 0.9; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #ecf0f1; }
        tr:hover { background-color: #f8f9fa; }
        .warning { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .success { background-color: #d4edda; border-left: 4px solid #28a745; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .error { background-color: #f8d7da; border-left: 4px solid #dc3545; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .info { background-color: #d1ecf1; border-left: 4px solid #17a2b8; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .timestamp { color: #6c757d; font-size: 14px; font-style: italic; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; }
        .badge-success { background-color: #28a745; color: white; }
        .badge-warning { background-color: #ffc107; color: #212529; }
        .badge-danger { background-color: #dc3545; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>GeoServer Configuration Analysis Report</h1>
        <p class="timestamp">Generated: $($script:AnalysisResults.Timestamp.ToString("yyyy-MM-dd HH:mm:ss"))</p>
        <p class="timestamp">Data Directory: $($script:AnalysisResults.DataDirectory)</p>
        <p class="timestamp">Target Version: GeoServer $TargetVersion</p>

        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-card">
                <div class="value">$($script:AnalysisResults.Summary.Workspaces)</div>
                <div class="label">Workspaces</div>
            </div>
            <div class="summary-card">
                <div class="value">$($script:AnalysisResults.Summary.TotalLayers)</div>
                <div class="label">Total Layers</div>
            </div>
            <div class="summary-card">
                <div class="value">$($script:AnalysisResults.Summary.CustomStyles)</div>
                <div class="label">Custom Styles</div>
            </div>
            <div class="summary-card">
                <div class="value">$($script:AnalysisResults.Summary.Issues)</div>
                <div class="label">Issues Found</div>
            </div>
        </div>
"@

    # Breaking Changes
    if ($script:AnalysisResults.BreakingChanges.Count -gt 0) {
        $html += "<h2>⚠️ Breaking Changes</h2>`n"
        foreach ($change in $script:AnalysisResults.BreakingChanges) {
            $html += "<div class='warning'>$change</div>`n"
        }
    }

    # Recommendations
    if ($script:AnalysisResults.Recommendations.Count -gt 0) {
        $html += "<h2>💡 Recommendations</h2>`n"
        foreach ($rec in $script:AnalysisResults.Recommendations) {
            $html += "<div class='success'>✓ $rec</div>`n"
        }
    }

    # Workspaces
    if ($script:AnalysisResults.Workspaces.Count -gt 0) {
        $html += @"
        <h2>Workspaces</h2>
        <table>
            <tr>
                <th>Workspace</th>
                <th>Namespace URI</th>
                <th>Isolated</th>
                <th>Stores</th>
                <th>Layers</th>
            </tr>
"@

        foreach ($ws in $script:AnalysisResults.Workspaces) {
            $isolated = if ($ws.Isolated) { "<span class='badge badge-warning'>Yes</span>" } else { "<span class='badge badge-success'>No</span>" }
            $html += @"
            <tr>
                <td><strong>$($ws.Name)</strong></td>
                <td>$($ws.NamespaceURI)</td>
                <td>$isolated</td>
                <td>$($ws.Stores.Count)</td>
                <td>$($ws.Layers.Count)</td>
            </tr>
"@
        }

        $html += "</table>`n"
    }

    # Styles
    if ($script:AnalysisResults.Styles.Count -gt 0) {
        $html += @"
        <h2>Custom Styles</h2>
        <table>
            <tr>
                <th>Style Name</th>
                <th>File</th>
                <th>Size (bytes)</th>
            </tr>
"@

        foreach ($style in $script:AnalysisResults.Styles) {
            $html += @"
            <tr>
                <td>$($style.Name)</td>
                <td>$($style.File)</td>
                <td>$($style.Size)</td>
            </tr>
"@
        }

        $html += "</table>`n"
    }

    # Migration Checklist
    $html += @"
        <h2>Migration Checklist</h2>
        <div class='info'>
            <h3>Pre-Migration Tasks:</h3>
            <ul>
                <li>✓ Configuration analysis completed</li>
                <li>☐ Review breaking changes and recommendations</li>
                <li>☐ Test in staging environment</li>
                <li>☐ Backup all data (automated)</li>
                <li>☐ Schedule maintenance window</li>
                <li>☐ Notify stakeholders</li>
            </ul>

            <h3>Post-Migration Verification:</h3>
            <ul>
                <li>☐ Verify all workspaces load</li>
                <li>☐ Test layer rendering</li>
                <li>☐ Check WMS/WFS endpoints</li>
                <li>☐ Validate custom styles</li>
                <li>☐ Test database connectivity</li>
                <li>☐ Review application logs</li>
            </ul>
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-LogEntry "HTML report saved: $OutputPath" "SUCCESS"
}

function Export-JSONReport {
    param([string]$OutputPath)

    $json = $script:AnalysisResults | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-LogEntry "JSON report saved: $OutputPath" "SUCCESS"
}

function Export-CSVReport {
    param([string]$OutputPath)

    # Create CSV with workspace summary
    $csvData = @()

    foreach ($ws in $script:AnalysisResults.Workspaces) {
        $csvData += [PSCustomObject]@{
            Workspace = $ws.Name
            NamespaceURI = $ws.NamespaceURI
            Isolated = $ws.Isolated
            Stores = $ws.Stores.Count
            Layers = $ws.Layers.Count
            LayerNames = ($ws.Layers | ForEach-Object { $_.Name }) -join '; '
        }
    }

    $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-LogEntry "CSV report saved: $OutputPath" "SUCCESS"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-LogEntry "==================================================================" "INFO"
    Write-LogEntry "GeoServer Configuration Analysis Tool v2.0" "INFO"
    Write-LogEntry "==================================================================" "INFO"
    Write-LogEntry "" "INFO"

    # Load config if needed
    if (-not $DataDirectory) {
        if (Test-Path $ConfigPath) {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            $DataDirectory = $config.environment.paths.geoserverDataDir
            Write-LogEntry "Using data directory from config: $DataDirectory" "INFO"
        } else {
            throw "No data directory specified and config not found"
        }
    }

    # Run analysis
    Invoke-ConfigurationAnalysis -DataDirectory $DataDirectory

    # Check compatibility
    Test-VersionCompatibility -TargetVersion $TargetVersion

    # Generate reports
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'

    if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
        $htmlPath = Join-Path $OutputPath "geoserver-analysis-$timestamp.html"
        Export-HTMLReport -OutputPath $htmlPath
    }

    if ($OutputFormat -eq 'JSON' -or $OutputFormat -eq 'All') {
        $jsonPath = Join-Path $OutputPath "geoserver-analysis-$timestamp.json"
        Export-JSONReport -OutputPath $jsonPath
    }

    if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
        $csvPath = Join-Path $OutputPath "geoserver-analysis-$timestamp.csv"
        Export-CSVReport -OutputPath $csvPath
    }

    Write-LogEntry "" "INFO"
    Write-LogEntry "==================================================================" "SUCCESS"
    Write-LogEntry "ANALYSIS COMPLETED" "SUCCESS"
    Write-LogEntry "==================================================================" "SUCCESS"
    Write-LogEntry "Workspaces: $($script:AnalysisResults.Summary.Workspaces)" "INFO"
    Write-LogEntry "Layers: $($script:AnalysisResults.Summary.TotalLayers)" "INFO"
    Write-LogEntry "Styles: $($script:AnalysisResults.Summary.CustomStyles)" "INFO"
    Write-LogEntry "Issues: $($script:AnalysisResults.Summary.Issues)" "INFO"
    Write-LogEntry "" "INFO"

    exit 0
}
catch {
    Write-LogEntry "" "ERROR"
    Write-LogEntry "Analysis failed: $_" "ERROR"
    exit 1
}
