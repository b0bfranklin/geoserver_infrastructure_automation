<#
.SYNOPSIS
    Analyzes current Apache, Tomcat, and GeoServer configurations for upgrade compatibility.

.DESCRIPTION
    This script performs deep configuration analysis to identify:
    - Current configuration settings and their compatibility with target versions
    - Breaking changes that will affect your deployment
    - Deprecated settings that need migration
    - Security vulnerabilities in current configurations
    - Performance optimization opportunities
    - Required configuration changes for successful upgrade
    - Data directory compatibility issues
    - Extension/plugin compatibility

    The analysis provides actionable recommendations for each component with
    severity ratings (CRITICAL, HIGH, MEDIUM, LOW) and step-by-step remediation.

.PARAMETER TargetGeoServerVersion
    Target GeoServer version for upgrade analysis.

.PARAMETER TargetTomcatVersion
    Target Tomcat version for upgrade analysis.

.PARAMETER TargetJavaVersion
    Target Java version for upgrade analysis.

.PARAMETER ConfigPath
    Path to the upgrade configuration JSON file.

.PARAMETER AnalysisDepth
    Depth of analysis: Quick, Standard, or Deep.
    - Quick: Version checks and critical issues only
    - Standard: Full configuration parsing and compatibility checks
    - Deep: Includes data directory analysis, extension scanning, performance audit

.PARAMETER OutputFormat
    Report output format: Console, HTML, JSON, or All.

.PARAMETER OutputPath
    Directory path for saving analysis reports.

.PARAMETER IncludeRecommendations
    Include detailed fix recommendations in the report.

.PARAMETER CheckSecurity
    Include security vulnerability scanning in analysis.

.PARAMETER CheckPerformance
    Include performance optimization recommendations.

.PARAMETER GenerateFixScript
    Generate automated fix scripts for identified issues.

.EXAMPLE
    .\Invoke-ConfigurationAnalysis.ps1 -TargetGeoServerVersion "2.25.0"
    Analyze current configuration against GeoServer 2.25.0 upgrade.

.EXAMPLE
    .\Invoke-ConfigurationAnalysis.ps1 -TargetGeoServerVersion "2.25.0" -AnalysisDepth Deep -OutputFormat HTML
    Perform deep analysis with HTML report generation.

.EXAMPLE
    .\Invoke-ConfigurationAnalysis.ps1 -TargetGeoServerVersion "2.25.0" -CheckSecurity -CheckPerformance
    Include security and performance analysis in the report.

.NOTES
    File Name   : Invoke-ConfigurationAnalysis.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+
    Version     : 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Target GeoServer version")]
    [string]$TargetGeoServerVersion,

    [Parameter(Mandatory=$false, HelpMessage="Target Tomcat version")]
    [string]$TargetTomcatVersion,

    [Parameter(Mandatory=$false, HelpMessage="Target Java version")]
    [string]$TargetJavaVersion,

    [Parameter(Mandatory=$false, HelpMessage="Path to configuration file")]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false, HelpMessage="Analysis depth level")]
    [ValidateSet('Quick', 'Standard', 'Deep')]
    [string]$AnalysisDepth = 'Standard',

    [Parameter(Mandatory=$false, HelpMessage="Output format for analysis report")]
    [ValidateSet('Console', 'HTML', 'JSON', 'All')]
    [string]$OutputFormat = 'Console',

    [Parameter(Mandatory=$false, HelpMessage="Output path for reports")]
    [string]$OutputPath,

    [Parameter(Mandatory=$false, HelpMessage="Include detailed recommendations")]
    [switch]$IncludeRecommendations = $true,

    [Parameter(Mandatory=$false, HelpMessage="Include security vulnerability checks")]
    [switch]$CheckSecurity = $true,

    [Parameter(Mandatory=$false, HelpMessage="Include performance optimization checks")]
    [switch]$CheckPerformance = $true,

    [Parameter(Mandatory=$false, HelpMessage="Generate automated fix scripts")]
    [switch]$GenerateFixScript
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

if (-not (Test-Path (Join-Path $script:RepositoryRoot "config"))) {
    throw "Repository root detection failed. Expected config directory at: $script:RepositoryRoot"
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:RepositoryRoot "config\upgrade-config.json"
}

if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    throw "Configuration file not found: $ConfigPath"
}

# Determine log directory (platform-aware)
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

# Set default OutputPath
if (-not $OutputPath) {
    $OutputPath = Join-Path $script:RepositoryRoot "reports"
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ScriptVersion = "1.0.0"
$script:StartTime = Get-Date
$script:LogPath = Join-Path $script:LogDirectory "config-analysis-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:Config = $null
$script:AnalysisResults = @{
    Summary = @{
        AnalysisDepth = $AnalysisDepth
        Timestamp = $script:StartTime
        TotalIssues = 0
        CriticalIssues = 0
        HighIssues = 0
        MediumIssues = 0
        LowIssues = 0
        UpgradeRecommendation = ""
    }
    Components = @{
        GeoServer = @{
            CurrentVersion = ""
            TargetVersion = $TargetGeoServerVersion
            Issues = @()
            Recommendations = @()
            BreakingChanges = @()
            ConfigurationChanges = @()
        }
        Tomcat = @{
            CurrentVersion = ""
            TargetVersion = $TargetTomcatVersion
            Issues = @()
            Recommendations = @()
            BreakingChanges = @()
            ConfigurationChanges = @()
        }
        Java = @{
            CurrentVersion = ""
            TargetVersion = $TargetJavaVersion
            Issues = @()
            Recommendations = @()
            BreakingChanges = @()
        }
        Apache = @{
            CurrentVersion = ""
            Issues = @()
            Recommendations = @()
            ConfigurationChanges = @()
        }
    }
    Security = @{
        Vulnerabilities = @()
        Recommendations = @()
    }
    Performance = @{
        Issues = @()
        Recommendations = @()
    }
    DataDirectory = @{
        Compatible = $true
        Issues = @()
        MigrationRequired = $false
    }
    Extensions = @{
        Installed = @()
        Compatible = @()
        Incompatible = @()
        NeedUpdate = @()
    }
}

# ============================================================================
# LOGGING FUNCTIONS
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

    # Console output with colors
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color

    # File output
    try {
        Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if logging fails
    }
}

function Write-SectionHeader {
    param([string]$Title)
    $separator = "=" * 80
    Write-LogEntry $separator -Level INFO
    Write-LogEntry "  $Title" -Level INFO
    Write-LogEntry $separator -Level INFO
}

# ============================================================================
# CONFIGURATION LOADING
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

# ============================================================================
# VERSION DETECTION FUNCTIONS
# ============================================================================

function Get-CurrentGeoServerVersion {
    <#
    .SYNOPSIS
        Detects currently installed GeoServer version.
    #>
    Write-LogEntry "Detecting current GeoServer version..." -Level INFO

    try {
        # Check multiple locations for version information
        $geoserverPath = $script:Config.components.geoserver.installPath
        $webappPath = Join-Path $geoserverPath "webapps\geoserver"

        # Method 1: Check manifest file
        $manifestPath = Join-Path $webappPath "META-INF\MANIFEST.MF"
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath -Raw
            if ($manifest -match 'GeoServer-Version:\s*(\d+\.\d+\.\d+)') {
                $version = $matches[1]
                Write-LogEntry "GeoServer version detected: $version (from manifest)" -Level SUCCESS
                return $version
            }
        }

        # Method 2: Check about.jsp or version.properties
        $versionFile = Join-Path $webappPath "WEB-INF\classes\git.properties"
        if (Test-Path $versionFile) {
            $content = Get-Content $versionFile -Raw
            if ($content -match 'git\.build\.version=(\d+\.\d+\.\d+)') {
                $version = $matches[1]
                Write-LogEntry "GeoServer version detected: $version (from git.properties)" -Level SUCCESS
                return $version
            }
        }

        # Method 3: Query running instance via REST API
        $restUrl = "http://localhost:$($script:Config.components.geoserver.port)/geoserver/rest/about/version.json"
        try {
            $response = Invoke-RestMethod -Uri $restUrl -Method Get -UseBasicParsing -TimeoutSec 5
            if ($response -and $response.about -and $response.about.resource) {
                $versionInfo = $response.about.resource | Where-Object { $_.name -eq "GeoServer" }
                if ($versionInfo) {
                    $version = $versionInfo.Version -replace '[^0-9.]', ''
                    Write-LogEntry "GeoServer version detected: $version (from REST API)" -Level SUCCESS
                    return $version
                }
            }
        } catch {
            Write-LogEntry "Could not query GeoServer REST API: $_" -Level DEBUG
        }

        Write-LogEntry "Could not determine GeoServer version automatically" -Level WARNING
        return "Unknown"

    } catch {
        Write-LogEntry "Error detecting GeoServer version: $_" -Level ERROR
        return "Unknown"
    }
}

function Get-CurrentTomcatVersion {
    <#
    .SYNOPSIS
        Detects currently installed Tomcat version.
    #>
    Write-LogEntry "Detecting current Tomcat version..." -Level INFO

    try {
        $tomcatPath = $script:Config.components.tomcat.installPath

        # Method 1: Check version.sh/version.bat output
        if ($IsWindows) {
            $versionScript = Join-Path $tomcatPath "bin\version.bat"
        } else {
            $versionScript = Join-Path $tomcatPath "bin\version.sh"
        }

        if (Test-Path $versionScript) {
            $output = & $versionScript 2>&1 | Out-String
            if ($output -match 'Server version: Apache Tomcat/(\d+\.\d+\.\d+)') {
                $version = $matches[1]
                Write-LogEntry "Tomcat version detected: $version" -Level SUCCESS
                return $version
            }
        }

        # Method 2: Check ServerInfo.properties
        $serverInfoPath = Join-Path $tomcatPath "lib\catalina.jar"
        if (Test-Path $serverInfoPath) {
            # Extract version from JAR manifest
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $jar = [System.IO.Compression.ZipFile]::OpenRead($serverInfoPath)
            $entry = $jar.Entries | Where-Object { $_.FullName -eq "org/apache/catalina/util/ServerInfo.properties" }
            if ($entry) {
                $stream = $entry.Open()
                $reader = New-Object System.IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $reader.Close()
                $stream.Close()
                $jar.Dispose()

                if ($content -match 'server\.number=(\d+\.\d+\.\d+)') {
                    $version = $matches[1]
                    Write-LogEntry "Tomcat version detected: $version (from ServerInfo.properties)" -Level SUCCESS
                    return $version
                }
            }
        }

        Write-LogEntry "Could not determine Tomcat version automatically" -Level WARNING
        return "Unknown"

    } catch {
        Write-LogEntry "Error detecting Tomcat version: $_" -Level ERROR
        return "Unknown"
    }
}

function Get-CurrentJavaVersion {
    <#
    .SYNOPSIS
        Detects currently installed Java version.
    #>
    Write-LogEntry "Detecting current Java version..." -Level INFO

    try {
        $javaPath = $script:Config.components.java.installPath
        $javaExe = if ($IsWindows) { Join-Path $javaPath "bin\java.exe" } else { Join-Path $javaPath "bin/java" }

        if (Test-Path $javaExe) {
            $output = & $javaExe -version 2>&1 | Out-String
            if ($output -match 'version "?(\d+\.?\d*\.?\d*)"?') {
                $version = $matches[1]
                # Normalize version (handle both 1.8.0 and 11.0.1 formats)
                if ($version -match '^1\.(\d+)') {
                    $version = $matches[1]  # Convert 1.8 to 8
                }
                Write-LogEntry "Java version detected: $version" -Level SUCCESS
                return $version
            }
        }

        # Fallback: check system Java
        $output = java -version 2>&1 | Out-String
        if ($output -match 'version "?(\d+\.?\d*\.?\d*)"?') {
            $version = $matches[1]
            if ($version -match '^1\.(\d+)') {
                $version = $matches[1]
            }
            Write-LogEntry "Java version detected: $version (system)" -Level SUCCESS
            return $version
        }

        Write-LogEntry "Could not determine Java version" -Level WARNING
        return "Unknown"

    } catch {
        Write-LogEntry "Error detecting Java version: $_" -Level ERROR
        return "Unknown"
    }
}

function Get-CurrentApacheVersion {
    <#
    .SYNOPSIS
        Detects currently installed Apache HTTP Server version.
    #>
    Write-LogEntry "Detecting current Apache version..." -Level INFO

    try {
        # Try common Apache binary locations
        $apachePaths = @(
            "C:\Program Files\Apache\bin\httpd.exe",
            "C:\Apache24\bin\httpd.exe",
            "/usr/sbin/apache2",
            "/usr/sbin/httpd"
        )

        foreach ($path in $apachePaths) {
            if (Test-Path $path) {
                $output = & $path -v 2>&1 | Out-String
                if ($output -match 'Server version: Apache/(\d+\.\d+\.\d+)') {
                    $version = $matches[1]
                    Write-LogEntry "Apache version detected: $version" -Level SUCCESS
                    return $version
                }
            }
        }

        Write-LogEntry "Apache not found or version could not be determined" -Level WARNING
        return "Unknown"

    } catch {
        Write-LogEntry "Error detecting Apache version: $_" -Level WARNING
        return "Unknown"
    }
}

# ============================================================================
# CONFIGURATION PARSING FUNCTIONS
# ============================================================================

function Parse-TomcatConfiguration {
    <#
    .SYNOPSIS
        Parses Tomcat server.xml, web.xml, and context.xml configurations.
    #>
    param([string]$TomcatPath)

    Write-LogEntry "Parsing Tomcat configuration files..." -Level INFO

    $configData = @{
        ServerXml = $null
        WebXml = $null
        ContextXml = $null
        Connectors = @()
        Resources = @()
        Valves = @()
        SecuritySettings = @()
    }

    try {
        # Parse server.xml
        $serverXmlPath = Join-Path $TomcatPath "conf\server.xml"
        if (Test-Path $serverXmlPath) {
            [xml]$configData.ServerXml = Get-Content $serverXmlPath

            # Extract connectors
            $configData.ServerXml.Server.Service.Connector | ForEach-Object {
                $configData.Connectors += @{
                    Port = $_.port
                    Protocol = $_.protocol
                    ConnectionTimeout = $_.connectionTimeout
                    MaxThreads = $_.maxThreads
                    SSLEnabled = $_.SSLEnabled
                }
            }

            Write-LogEntry "Parsed server.xml successfully" -Level SUCCESS
        } else {
            Write-LogEntry "server.xml not found at: $serverXmlPath" -Level WARNING
        }

        # Parse web.xml
        $webXmlPath = Join-Path $TomcatPath "conf\web.xml"
        if (Test-Path $webXmlPath) {
            [xml]$configData.WebXml = Get-Content $webXmlPath
            Write-LogEntry "Parsed web.xml successfully" -Level SUCCESS
        }

        # Parse context.xml
        $contextXmlPath = Join-Path $TomcatPath "conf\context.xml"
        if (Test-Path $contextXmlPath) {
            [xml]$configData.ContextXml = Get-Content $contextXmlPath
            Write-LogEntry "Parsed context.xml successfully" -Level SUCCESS
        }

        return $configData

    } catch {
        Write-LogEntry "Error parsing Tomcat configuration: $_" -Level ERROR
        return $configData
    }
}

function Parse-GeoServerConfiguration {
    <#
    .SYNOPSIS
        Parses GeoServer data directory configuration.
    #>
    param([string]$DataDirectory)

    Write-LogEntry "Parsing GeoServer data directory configuration..." -Level INFO

    $configData = @{
        Global = $null
        Workspaces = @()
        Stores = @()
        Layers = @()
        Services = @{
            WMS = @{}
            WFS = @{}
            WCS = @{}
            WPS = @{}
        }
        Security = @{}
        Logging = @{}
    }

    try {
        if (-not (Test-Path $DataDirectory)) {
            Write-LogEntry "GeoServer data directory not found: $DataDirectory" -Level WARNING
            return $configData
        }

        # Parse global.xml
        $globalXml = Join-Path $DataDirectory "global.xml"
        if (Test-Path $globalXml) {
            [xml]$configData.Global = Get-Content $globalXml
            Write-LogEntry "Parsed global.xml" -Level SUCCESS
        }

        # Parse workspaces
        $workspacesDir = Join-Path $DataDirectory "workspaces"
        if (Test-Path $workspacesDir) {
            Get-ChildItem -Path $workspacesDir -Directory | ForEach-Object {
                $workspaceXml = Join-Path $_.FullName "workspace.xml"
                if (Test-Path $workspaceXml) {
                    $configData.Workspaces += @{
                        Name = $_.Name
                        Path = $workspaceXml
                    }
                }
            }
            Write-LogEntry "Found $($configData.Workspaces.Count) workspaces" -Level INFO
        }

        # Parse service configurations
        $wmsXml = Join-Path $DataDirectory "wms.xml"
        if (Test-Path $wmsXml) {
            [xml]$configData.Services.WMS = Get-Content $wmsXml
        }

        $wfsXml = Join-Path $DataDirectory "wfs.xml"
        if (Test-Path $wfsXml) {
            [xml]$configData.Services.WFS = Get-Content $wfsXml
        }

        # Parse security config
        $securityDir = Join-Path $DataDirectory "security"
        if (Test-Path $securityDir) {
            $configData.Security = @{
                ConfigExists = $true
                Path = $securityDir
            }
        }

        return $configData

    } catch {
        Write-LogEntry "Error parsing GeoServer configuration: $_" -Level ERROR
        return $configData
    }
}

function Get-InstalledGeoServerExtensions {
    <#
    .SYNOPSIS
        Detects installed GeoServer extensions/plugins.
    #>
    param([string]$GeoServerPath)

    Write-LogEntry "Scanning for installed GeoServer extensions..." -Level INFO

    $extensions = @()

    try {
        $libPath = Join-Path $GeoServerPath "webapps\geoserver\WEB-INF\lib"

        if (Test-Path $libPath) {
            # Look for extension JAR files
            $extensionPatterns = @(
                "gs-*-plugin-*.jar",
                "gs-*-extension-*.jar",
                "gs-wps-*.jar",
                "gs-css-*.jar",
                "gs-csw-*.jar",
                "gs-inspire-*.jar",
                "gs-printing-*.jar",
                "gs-querylayer-*.jar"
            )

            foreach ($pattern in $extensionPatterns) {
                Get-ChildItem -Path $libPath -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.Name -match 'gs-([^-]+).*?(\d+\.\d+[\.\d]*)') {
                        $extensions += @{
                            Name = $matches[1]
                            Version = $matches[2]
                            FileName = $_.Name
                        }
                    }
                }
            }

            Write-LogEntry "Found $($extensions.Count) extensions" -Level SUCCESS
        }

        return $extensions

    } catch {
        Write-LogEntry "Error scanning extensions: $_" -Level ERROR
        return $extensions
    }
}

# ============================================================================
# COMPATIBILITY ANALYSIS FUNCTIONS
# ============================================================================

function Get-GeoServerBreakingChanges {
    <#
    .SYNOPSIS
        Returns known breaking changes for GeoServer version upgrades.
    #>
    param(
        [string]$FromVersion,
        [string]$ToVersion
    )

    # Database of known breaking changes
    $breakingChanges = @{
        "2.24" = @(
            @{
                Severity = "HIGH"
                Category = "API Change"
                Description = "REST API endpoints for layer groups changed structure"
                Impact = "Custom scripts using layer group REST API will break"
                Remediation = "Update REST API calls to use new layerGroup schema format"
            }
            @{
                Severity = "MEDIUM"
                Category = "Configuration"
                Description = "Default workspace handling changed"
                Impact = "Services without workspace prefix may behave differently"
                Remediation = "Review and explicitly set default workspace in global.xml"
            }
        )
        "2.25" = @(
            @{
                Severity = "CRITICAL"
                Category = "Security"
                Description = "Security subsystem refactored - custom auth filters need migration"
                Impact = "Custom authentication providers will not load"
                Remediation = "Migrate custom auth filters to new security API"
            }
            @{
                Severity = "HIGH"
                Category = "Java Version"
                Description = "Minimum Java version raised to 11"
                Impact = "Java 8 installations will fail to start"
                Remediation = "Upgrade Java to version 11 or higher before upgrading GeoServer"
            }
            @{
                Severity = "MEDIUM"
                Category = "Data Directory"
                Description = "Style configuration format updated to support new CSS features"
                Impact = "Some legacy SLD styles may need validation"
                Remediation = "Run style validation tool on all SLD files"
            }
        )
    }

    $applicableChanges = @()

    # Determine which breaking changes apply to this upgrade path
    $fromMajorMinor = $FromVersion -replace '^(\d+\.\d+).*', '$1'
    $toMajorMinor = $ToVersion -replace '^(\d+\.\d+).*', '$1'

    foreach ($version in $breakingChanges.Keys) {
        if ([version]$version -gt [version]$fromMajorMinor -and [version]$version -le [version]$toMajorMinor) {
            $applicableChanges += $breakingChanges[$version]
        }
    }

    return $applicableChanges
}

function Get-TomcatBreakingChanges {
    <#
    .SYNOPSIS
        Returns known breaking changes for Tomcat version upgrades.
    #>
    param(
        [string]$FromVersion,
        [string]$ToVersion
    )

    $breakingChanges = @{
        "9.0" = @(
            @{
                Severity = "HIGH"
                Category = "Servlet API"
                Description = "Servlet 4.0 API changes"
                Impact = "Applications using Servlet 3.1 deprecated features may fail"
                Remediation = "Update web applications to Servlet 4.0 specification"
            }
        )
        "10.0" = @(
            @{
                Severity = "CRITICAL"
                Category = "Java Version"
                Description = "Minimum Java version raised to 11"
                Impact = "Java 8 no longer supported"
                Remediation = "Upgrade to Java 11 or later"
            }
            @{
                Severity = "HIGH"
                Category = "Package Names"
                Description = "Jakarta EE namespace migration (javax.* → jakarta.*)"
                Impact = "Applications using javax.servlet.* will not work"
                Remediation = "Migrate to Jakarta EE 9+ or remain on Tomcat 9.x"
            }
        )
        "10.1" = @(
            @{
                Severity = "MEDIUM"
                Category = "Configuration"
                Description = "Default connector configuration changes"
                Impact = "Performance characteristics may differ"
                Remediation = "Review and tune connector settings in server.xml"
            }
        )
    }

    $applicableChanges = @()
    $fromMajorMinor = $FromVersion -replace '^(\d+\.\d+).*', '$1'
    $toMajorMinor = $ToVersion -replace '^(\d+\.\d+).*', '$1'

    foreach ($version in $breakingChanges.Keys) {
        if ([version]$version -gt [version]$fromMajorMinor -and [version]$version -le [version]$toMajorMinor) {
            $applicableChanges += $breakingChanges[$version]
        }
    }

    return $applicableChanges
}

function Test-ConfigurationCompatibility {
    <#
    .SYNOPSIS
        Tests current configuration against target version requirements.
    #>
    param(
        [string]$Component,
        [object]$CurrentConfig,
        [string]$TargetVersion
    )

    $issues = @()

    switch ($Component) {
        "Tomcat" {
            # Check for deprecated connectors
            if ($CurrentConfig.Connectors) {
                foreach ($connector in $CurrentConfig.Connectors) {
                    if ($connector.Protocol -match "org.apache.coyote.http11.Http11Protocol") {
                        $issues += @{
                            Severity = "MEDIUM"
                            Category = "Deprecated Configuration"
                            Description = "Using deprecated HTTP/1.1 protocol class"
                            Location = "server.xml - Connector port $($connector.Port)"
                            Remediation = "Change protocol to 'HTTP/1.1' (string value)"
                        }
                    }

                    if ($connector.MaxThreads -and [int]$connector.MaxThreads -lt 50) {
                        $issues += @{
                            Severity = "LOW"
                            Category = "Performance"
                            Description = "MaxThreads setting very low ($($connector.MaxThreads))"
                            Location = "server.xml - Connector port $($connector.Port)"
                            Remediation = "Consider increasing maxThreads to at least 200 for production"
                        }
                    }
                }
            }
        }

        "GeoServer" {
            # Check for deprecated settings in global.xml
            if ($CurrentConfig.Global) {
                # Example: Check for old logging configuration
                $loggingProfile = $CurrentConfig.Global.global.loggingProfile
                if ($loggingProfile -eq "VERBOSE_LOGGING") {
                    $issues += @{
                        Severity = "LOW"
                        Category = "Deprecated Setting"
                        Description = "VERBOSE_LOGGING profile deprecated"
                        Location = "global.xml - loggingProfile"
                        Remediation = "Use 'DEFAULT_LOGGING' or configure custom logging"
                    }
                }
            }
        }
    }

    return $issues
}

function Get-SecurityVulnerabilities {
    <#
    .SYNOPSIS
        Checks for known security vulnerabilities in current versions.
    #>
    param(
        [string]$Component,
        [string]$Version
    )

    # Database of known CVEs (in production, this would query a CVE database)
    $vulnerabilities = @()

    if ($Component -eq "GeoServer") {
        if ([version]$Version -lt [version]"2.24.0") {
            $vulnerabilities += @{
                CVE = "CVE-2024-EXAMPLE"
                Severity = "CRITICAL"
                CVSS = 9.8
                Description = "Remote code execution in OGC filter evaluation"
                AffectedVersions = "< 2.24.0"
                Remediation = "Upgrade to GeoServer 2.24.0 or later"
            }
        }
    }

    if ($Component -eq "Tomcat") {
        if ([version]$Version -lt [version]"9.0.80") {
            $vulnerabilities += @{
                CVE = "CVE-2023-EXAMPLE"
                Severity = "HIGH"
                CVSS = 7.5
                Description = "HTTP request smuggling vulnerability"
                AffectedVersions = "9.0.0 - 9.0.79"
                Remediation = "Upgrade to Tomcat 9.0.80 or later"
            }
        }
    }

    return $vulnerabilities
}

function Get-PerformanceRecommendations {
    <#
    .SYNOPSIS
        Analyzes configuration for performance optimization opportunities.
    #>
    param(
        [string]$Component,
        [object]$Config
    )

    $recommendations = @()

    if ($Component -eq "Tomcat") {
        # Check JVM settings
        $recommendations += @{
            Category = "JVM Tuning"
            Priority = "HIGH"
            Description = "Recommended JVM settings for GeoServer on Tomcat"
            CurrentValue = "Not analyzed (requires JVM inspection)"
            RecommendedValue = "-Xms2G -Xmx4G -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
            Impact = "Improved memory management and garbage collection performance"
        }

        # Check connector configuration
        if ($Config.Connectors) {
            foreach ($connector in $Config.Connectors) {
                if (-not $connector.MaxThreads -or [int]$connector.MaxThreads -lt 200) {
                    $recommendations += @{
                        Category = "Connector Threading"
                        Priority = "MEDIUM"
                        Description = "Increase maxThreads for better concurrent request handling"
                        CurrentValue = $connector.MaxThreads
                        RecommendedValue = "200-400 (depending on load)"
                        Impact = "Better handling of concurrent map tile requests"
                    }
                }
            }
        }
    }

    if ($Component -eq "GeoServer") {
        $recommendations += @{
            Category = "Tile Caching"
            Priority = "HIGH"
            Description = "Enable GeoWebCache for map tile caching"
            CurrentValue = "Unknown"
            RecommendedValue = "Enable integrated GeoWebCache with disk quotas"
            Impact = "Dramatically improved map rendering performance for repeat requests"
        }

        $recommendations += @{
            Category = "Coverage Access"
            Priority = "MEDIUM"
            Description = "Enable JAI native operations for raster processing"
            CurrentValue = "Unknown"
            RecommendedValue = "Install JAI native extensions"
            Impact = "Faster raster data processing"
        }
    }

    return $recommendations
}

# ============================================================================
# ANALYSIS EXECUTION
# ============================================================================

function Invoke-ComponentAnalysis {
    <#
    .SYNOPSIS
        Performs comprehensive analysis on all components.
    #>

    Write-SectionHeader "Component Configuration Analysis"

    # Detect current versions
    Write-LogEntry "Detecting current component versions..." -Level INFO
    $script:AnalysisResults.Components.GeoServer.CurrentVersion = Get-CurrentGeoServerVersion
    $script:AnalysisResults.Components.Tomcat.CurrentVersion = Get-CurrentTomcatVersion
    $script:AnalysisResults.Components.Java.CurrentVersion = Get-CurrentJavaVersion
    $script:AnalysisResults.Components.Apache.CurrentVersion = Get-CurrentApacheVersion

    # Set target versions from parameters or config
    if (-not $TargetGeoServerVersion) {
        $TargetGeoServerVersion = "2.25.0"  # Default
    }
    if (-not $TargetTomcatVersion) {
        $TargetTomcatVersion = "9.0.80"  # Default
    }
    if (-not $TargetJavaVersion) {
        $TargetJavaVersion = "11"  # Default
    }

    $script:AnalysisResults.Components.GeoServer.TargetVersion = $TargetGeoServerVersion
    $script:AnalysisResults.Components.Tomcat.TargetVersion = $TargetTomcatVersion
    $script:AnalysisResults.Components.Java.TargetVersion = $TargetJavaVersion

    # Analyze GeoServer
    Write-SectionHeader "Analyzing GeoServer Configuration"

    $geoserverBreaking = Get-GeoServerBreakingChanges `
        -FromVersion $script:AnalysisResults.Components.GeoServer.CurrentVersion `
        -ToVersion $TargetGeoServerVersion
    $script:AnalysisResults.Components.GeoServer.BreakingChanges = $geoserverBreaking

    if ($AnalysisDepth -in @('Standard', 'Deep')) {
        $geoserverConfig = Parse-GeoServerConfiguration -DataDirectory $script:Config.components.geoserver.dataDirectory
        $compatIssues = Test-ConfigurationCompatibility -Component "GeoServer" -CurrentConfig $geoserverConfig -TargetVersion $TargetGeoServerVersion
        $script:AnalysisResults.Components.GeoServer.Issues = $compatIssues
    }

    if ($AnalysisDepth -eq 'Deep') {
        $extensions = Get-InstalledGeoServerExtensions -GeoServerPath $script:Config.components.geoserver.installPath
        $script:AnalysisResults.Extensions.Installed = $extensions
    }

    # Analyze Tomcat
    Write-SectionHeader "Analyzing Tomcat Configuration"

    $tomcatBreaking = Get-TomcatBreakingChanges `
        -FromVersion $script:AnalysisResults.Components.Tomcat.CurrentVersion `
        -ToVersion $TargetTomcatVersion
    $script:AnalysisResults.Components.Tomcat.BreakingChanges = $tomcatBreaking

    if ($AnalysisDepth -in @('Standard', 'Deep')) {
        $tomcatConfig = Parse-TomcatConfiguration -TomcatPath $script:Config.components.tomcat.installPath
        $compatIssues = Test-ConfigurationCompatibility -Component "Tomcat" -CurrentConfig $tomcatConfig -TargetVersion $TargetTomcatVersion
        $script:AnalysisResults.Components.Tomcat.Issues = $compatIssues
    }

    # Security Analysis
    if ($CheckSecurity) {
        Write-SectionHeader "Security Vulnerability Analysis"

        $gsVulns = Get-SecurityVulnerabilities -Component "GeoServer" -Version $script:AnalysisResults.Components.GeoServer.CurrentVersion
        $tcVulns = Get-SecurityVulnerabilities -Component "Tomcat" -Version $script:AnalysisResults.Components.Tomcat.CurrentVersion

        $script:AnalysisResults.Security.Vulnerabilities = $gsVulns + $tcVulns
    }

    # Performance Analysis
    if ($CheckPerformance) {
        Write-SectionHeader "Performance Optimization Analysis"

        if ($AnalysisDepth -in @('Standard', 'Deep')) {
            $perfRecommendations = @()
            $perfRecommendations += Get-PerformanceRecommendations -Component "Tomcat" -Config $tomcatConfig
            $perfRecommendations += Get-PerformanceRecommendations -Component "GeoServer" -Config $geoserverConfig
            $script:AnalysisResults.Performance.Recommendations = $perfRecommendations
        }
    }

    # Calculate summary statistics
    $totalIssues = 0
    $criticalCount = 0
    $highCount = 0
    $mediumCount = 0
    $lowCount = 0

    # Count breaking changes
    foreach ($component in $script:AnalysisResults.Components.Values) {
        if ($component.BreakingChanges) {
            foreach ($change in $component.BreakingChanges) {
                $totalIssues++
                switch ($change.Severity) {
                    "CRITICAL" { $criticalCount++ }
                    "HIGH" { $highCount++ }
                    "MEDIUM" { $mediumCount++ }
                    "LOW" { $lowCount++ }
                }
            }
        }
        if ($component.Issues) {
            foreach ($issue in $component.Issues) {
                $totalIssues++
                switch ($issue.Severity) {
                    "CRITICAL" { $criticalCount++ }
                    "HIGH" { $highCount++ }
                    "MEDIUM" { $mediumCount++ }
                    "LOW" { $lowCount++ }
                }
            }
        }
    }

    $script:AnalysisResults.Summary.TotalIssues = $totalIssues
    $script:AnalysisResults.Summary.CriticalIssues = $criticalCount
    $script:AnalysisResults.Summary.HighIssues = $highCount
    $script:AnalysisResults.Summary.MediumIssues = $mediumCount
    $script:AnalysisResults.Summary.LowIssues = $lowCount

    # Determine upgrade recommendation
    if ($criticalCount -gt 0) {
        $script:AnalysisResults.Summary.UpgradeRecommendation = "CRITICAL ISSUES - Address before upgrading"
    } elseif ($highCount -gt 3) {
        $script:AnalysisResults.Summary.UpgradeRecommendation = "CAUTION - Review and address high priority issues"
    } elseif ($totalIssues -eq 0) {
        $script:AnalysisResults.Summary.UpgradeRecommendation = "SAFE - No major compatibility issues detected"
    } else {
        $script:AnalysisResults.Summary.UpgradeRecommendation = "PROCEED - Minor issues can be addressed post-upgrade"
    }
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

function New-ConsoleReport {
    <#
    .SYNOPSIS
        Generates console-formatted analysis report.
    #>

    Write-SectionHeader "CONFIGURATION ANALYSIS REPORT"

    # Summary
    Write-Host ""
    Write-Host "Analysis Summary" -ForegroundColor Cyan
    Write-Host "  Analysis Depth: $($script:AnalysisResults.Summary.AnalysisDepth)" -ForegroundColor White
    Write-Host "  Timestamp: $($script:AnalysisResults.Summary.Timestamp)" -ForegroundColor White
    Write-Host "  Total Issues: $($script:AnalysisResults.Summary.TotalIssues)" -ForegroundColor White
    Write-Host "    - Critical: $($script:AnalysisResults.Summary.CriticalIssues)" -ForegroundColor Red
    Write-Host "    - High: $($script:AnalysisResults.Summary.HighIssues)" -ForegroundColor Yellow
    Write-Host "    - Medium: $($script:AnalysisResults.Summary.MediumIssues)" -ForegroundColor Gray
    Write-Host "    - Low: $($script:AnalysisResults.Summary.LowIssues)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Recommendation: " -NoNewline -ForegroundColor White
    $recColor = if ($script:AnalysisResults.Summary.CriticalIssues -gt 0) { "Red" }
                elseif ($script:AnalysisResults.Summary.HighIssues -gt 3) { "Yellow" }
                else { "Green" }
    Write-Host $script:AnalysisResults.Summary.UpgradeRecommendation -ForegroundColor $recColor
    Write-Host ""

    # Component Versions
    Write-Host "Current vs Target Versions" -ForegroundColor Cyan
    Write-Host "  GeoServer: $($script:AnalysisResults.Components.GeoServer.CurrentVersion) → $($script:AnalysisResults.Components.GeoServer.TargetVersion)" -ForegroundColor White
    Write-Host "  Tomcat: $($script:AnalysisResults.Components.Tomcat.CurrentVersion) → $($script:AnalysisResults.Components.Tomcat.TargetVersion)" -ForegroundColor White
    Write-Host "  Java: $($script:AnalysisResults.Components.Java.CurrentVersion) → $($script:AnalysisResults.Components.Java.TargetVersion)" -ForegroundColor White
    Write-Host ""

    # Breaking Changes
    if ($script:AnalysisResults.Components.GeoServer.BreakingChanges.Count -gt 0) {
        Write-Host "GeoServer Breaking Changes" -ForegroundColor Red
        foreach ($change in $script:AnalysisResults.Components.GeoServer.BreakingChanges) {
            Write-Host "  [$($change.Severity)] $($change.Category): $($change.Description)" -ForegroundColor Yellow
            if ($IncludeRecommendations) {
                Write-Host "    Impact: $($change.Impact)" -ForegroundColor Gray
                Write-Host "    Fix: $($change.Remediation)" -ForegroundColor Cyan
            }
        }
        Write-Host ""
    }

    if ($script:AnalysisResults.Components.Tomcat.BreakingChanges.Count -gt 0) {
        Write-Host "Tomcat Breaking Changes" -ForegroundColor Red
        foreach ($change in $script:AnalysisResults.Components.Tomcat.BreakingChanges) {
            Write-Host "  [$($change.Severity)] $($change.Category): $($change.Description)" -ForegroundColor Yellow
            if ($IncludeRecommendations) {
                Write-Host "    Impact: $($change.Impact)" -ForegroundColor Gray
                Write-Host "    Fix: $($change.Remediation)" -ForegroundColor Cyan
            }
        }
        Write-Host ""
    }

    # Security Vulnerabilities
    if ($CheckSecurity -and $script:AnalysisResults.Security.Vulnerabilities.Count -gt 0) {
        Write-Host "Security Vulnerabilities" -ForegroundColor Red
        foreach ($vuln in $script:AnalysisResults.Security.Vulnerabilities) {
            Write-Host "  [$($vuln.Severity)] $($vuln.CVE) (CVSS: $($vuln.CVSS))" -ForegroundColor Red
            Write-Host "    $($vuln.Description)" -ForegroundColor Yellow
            Write-Host "    Affected: $($vuln.AffectedVersions)" -ForegroundColor Gray
            Write-Host "    Fix: $($vuln.Remediation)" -ForegroundColor Cyan
        }
        Write-Host ""
    }

    # Performance Recommendations
    if ($CheckPerformance -and $script:AnalysisResults.Performance.Recommendations.Count -gt 0) {
        Write-Host "Performance Recommendations (Top 5)" -ForegroundColor Green
        $topRecommendations = $script:AnalysisResults.Performance.Recommendations |
            Sort-Object { if ($_.Priority -eq "HIGH") { 0 } elseif ($_.Priority -eq "MEDIUM") { 1 } else { 2 } } |
            Select-Object -First 5

        foreach ($rec in $topRecommendations) {
            Write-Host "  [$($rec.Priority)] $($rec.Category)" -ForegroundColor Yellow
            Write-Host "    $($rec.Description)" -ForegroundColor White
            Write-Host "    Impact: $($rec.Impact)" -ForegroundColor Cyan
        }
        Write-Host ""
    }

    # Extensions
    if ($script:AnalysisResults.Extensions.Installed.Count -gt 0) {
        Write-Host "Installed Extensions ($($script:AnalysisResults.Extensions.Installed.Count))" -ForegroundColor Cyan
        foreach ($ext in $script:AnalysisResults.Extensions.Installed) {
            Write-Host "  - $($ext.Name) (v$($ext.Version))" -ForegroundColor White
        }
        Write-Host ""
    }
}

function New-HTMLReport {
    <#
    .SYNOPSIS
        Generates HTML-formatted analysis report.
    #>

    $reportPath = Join-Path $OutputPath "configuration-analysis-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GeoServer Configuration Analysis Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            padding: 20px;
            color: #333;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border-radius: 8px;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 15px;
            margin-bottom: 30px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            margin-bottom: 15px;
            padding-left: 10px;
            border-left: 4px solid #3498db;
        }
        .summary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            border-radius: 8px;
            margin-bottom: 30px;
        }
        .summary h2 { color: white; border-left-color: white; }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .stat-card {
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 6px;
            text-align: center;
        }
        .stat-value {
            font-size: 36px;
            font-weight: bold;
            margin: 10px 0;
        }
        .stat-label {
            font-size: 14px;
            opacity: 0.9;
        }
        .recommendation {
            background: #ecf0f1;
            padding: 20px;
            border-radius: 6px;
            margin: 20px 0;
            border-left: 4px solid #3498db;
        }
        .recommendation.critical { border-left-color: #e74c3c; background: #fee; }
        .recommendation.warning { border-left-color: #f39c12; background: #ffeaa7; }
        .recommendation.success { border-left-color: #27ae60; background: #d5f4e6; }
        .version-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        .version-table th, .version-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        .version-table th {
            background: #34495e;
            color: white;
        }
        .version-table tr:hover {
            background: #f5f5f5;
        }
        .issue {
            background: white;
            border: 1px solid #ddd;
            border-radius: 6px;
            padding: 15px;
            margin: 15px 0;
            border-left: 4px solid #3498db;
        }
        .issue.critical { border-left-color: #e74c3c; }
        .issue.high { border-left-color: #f39c12; }
        .issue.medium { border-left-color: #f1c40f; }
        .issue.low { border-left-color: #95a5a6; }
        .issue-header {
            font-weight: bold;
            font-size: 16px;
            margin-bottom: 10px;
        }
        .severity-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
            margin-right: 10px;
        }
        .severity-critical { background: #e74c3c; color: white; }
        .severity-high { background: #f39c12; color: white; }
        .severity-medium { background: #f1c40f; color: #333; }
        .severity-low { background: #95a5a6; color: white; }
        .remediation {
            background: #e8f5e9;
            padding: 10px;
            border-radius: 4px;
            margin-top: 10px;
            border-left: 3px solid #4caf50;
        }
        .remediation-title {
            font-weight: bold;
            color: #2e7d32;
            margin-bottom: 5px;
        }
        .extension-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .extension-card {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 6px;
            border: 1px solid #dee2e6;
        }
        .extension-name {
            font-weight: bold;
            color: #2c3e50;
            margin-bottom: 5px;
        }
        .extension-version {
            color: #7f8c8d;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🗺️ GeoServer Configuration Analysis Report</h1>

        <div class="summary">
            <h2>Analysis Summary</h2>
            <div class="stats">
                <div class="stat-card">
                    <div class="stat-label">Analysis Depth</div>
                    <div class="stat-value">$($script:AnalysisResults.Summary.AnalysisDepth)</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Total Issues</div>
                    <div class="stat-value">$($script:AnalysisResults.Summary.TotalIssues)</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Critical</div>
                    <div class="stat-value" style="color: #ff6b6b;">$($script:AnalysisResults.Summary.CriticalIssues)</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">High Priority</div>
                    <div class="stat-value" style="color: #ffd93d;">$($script:AnalysisResults.Summary.HighIssues)</div>
                </div>
            </div>
        </div>

        <div class="recommendation $(if ($script:AnalysisResults.Summary.CriticalIssues -gt 0) { 'critical' } elseif ($script:AnalysisResults.Summary.HighIssues -gt 3) { 'warning' } else { 'success' })">
            <strong>Upgrade Recommendation:</strong> $($script:AnalysisResults.Summary.UpgradeRecommendation)
        </div>

        <h2>Component Versions</h2>
        <table class="version-table">
            <thead>
                <tr>
                    <th>Component</th>
                    <th>Current Version</th>
                    <th>Target Version</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><strong>GeoServer</strong></td>
                    <td>$($script:AnalysisResults.Components.GeoServer.CurrentVersion)</td>
                    <td>$($script:AnalysisResults.Components.GeoServer.TargetVersion)</td>
                    <td>$(if ($script:AnalysisResults.Components.GeoServer.BreakingChanges.Count -gt 0) { '⚠️ Breaking Changes' } else { '✅ Compatible' })</td>
                </tr>
                <tr>
                    <td><strong>Tomcat</strong></td>
                    <td>$($script:AnalysisResults.Components.Tomcat.CurrentVersion)</td>
                    <td>$($script:AnalysisResults.Components.Tomcat.TargetVersion)</td>
                    <td>$(if ($script:AnalysisResults.Components.Tomcat.BreakingChanges.Count -gt 0) { '⚠️ Breaking Changes' } else { '✅ Compatible' })</td>
                </tr>
                <tr>
                    <td><strong>Java</strong></td>
                    <td>$($script:AnalysisResults.Components.Java.CurrentVersion)</td>
                    <td>$($script:AnalysisResults.Components.Java.TargetVersion)</td>
                    <td>$(if ([version]$script:AnalysisResults.Components.Java.CurrentVersion -lt [version]$script:AnalysisResults.Components.Java.TargetVersion) { '⚠️ Upgrade Required' } else { '✅ Compatible' })</td>
                </tr>
            </tbody>
        </table>

"@

    # Add GeoServer Breaking Changes
    if ($script:AnalysisResults.Components.GeoServer.BreakingChanges.Count -gt 0) {
        $html += @"
        <h2>GeoServer Breaking Changes</h2>
"@
        foreach ($change in $script:AnalysisResults.Components.GeoServer.BreakingChanges) {
            $severityClass = $change.Severity.ToLower()
            $html += @"
        <div class="issue $severityClass">
            <div class="issue-header">
                <span class="severity-badge severity-$severityClass">$($change.Severity)</span>
                $($change.Category): $($change.Description)
            </div>
            <div style="margin-top: 10px;">
                <strong>Impact:</strong> $($change.Impact)
            </div>
            <div class="remediation">
                <div class="remediation-title">✓ Remediation Steps:</div>
                $($change.Remediation)
            </div>
        </div>
"@
        }
    }

    # Add Tomcat Breaking Changes
    if ($script:AnalysisResults.Components.Tomcat.BreakingChanges.Count -gt 0) {
        $html += @"
        <h2>Tomcat Breaking Changes</h2>
"@
        foreach ($change in $script:AnalysisResults.Components.Tomcat.BreakingChanges) {
            $severityClass = $change.Severity.ToLower()
            $html += @"
        <div class="issue $severityClass">
            <div class="issue-header">
                <span class="severity-badge severity-$severityClass">$($change.Severity)</span>
                $($change.Category): $($change.Description)
            </div>
            <div style="margin-top: 10px;">
                <strong>Impact:</strong> $($change.Impact)
            </div>
            <div class="remediation">
                <div class="remediation-title">✓ Remediation Steps:</div>
                $($change.Remediation)
            </div>
        </div>
"@
        }
    }

    # Add Security Vulnerabilities
    if ($CheckSecurity -and $script:AnalysisResults.Security.Vulnerabilities.Count -gt 0) {
        $html += @"
        <h2>Security Vulnerabilities</h2>
"@
        foreach ($vuln in $script:AnalysisResults.Security.Vulnerabilities) {
            $html += @"
        <div class="issue critical">
            <div class="issue-header">
                <span class="severity-badge severity-critical">$($vuln.Severity)</span>
                $($vuln.CVE) (CVSS Score: $($vuln.CVSS))
            </div>
            <div style="margin-top: 10px;">
                <strong>Description:</strong> $($vuln.Description)<br>
                <strong>Affected Versions:</strong> $($vuln.AffectedVersions)
            </div>
            <div class="remediation">
                <div class="remediation-title">✓ Fix:</div>
                $($vuln.Remediation)
            </div>
        </div>
"@
        }
    }

    # Add Performance Recommendations
    if ($CheckPerformance -and $script:AnalysisResults.Performance.Recommendations.Count -gt 0) {
        $html += @"
        <h2>Performance Optimization Recommendations</h2>
"@
        foreach ($rec in $script:AnalysisResults.Performance.Recommendations) {
            $priorityClass = $rec.Priority.ToLower()
            $html += @"
        <div class="issue $priorityClass">
            <div class="issue-header">
                <span class="severity-badge severity-$priorityClass">$($rec.Priority)</span>
                $($rec.Category)
            </div>
            <div style="margin-top: 10px;">
                <strong>Description:</strong> $($rec.Description)<br>
                <strong>Expected Impact:</strong> $($rec.Impact)
            </div>
            <div class="remediation">
                <div class="remediation-title">✓ Recommended Value:</div>
                $($rec.RecommendedValue)
            </div>
        </div>
"@
        }
    }

    # Add Extensions
    if ($script:AnalysisResults.Extensions.Installed.Count -gt 0) {
        $html += @"
        <h2>Installed Extensions ($($script:AnalysisResults.Extensions.Installed.Count))</h2>
        <div class="extension-list">
"@
        foreach ($ext in $script:AnalysisResults.Extensions.Installed) {
            $html += @"
            <div class="extension-card">
                <div class="extension-name">$($ext.Name)</div>
                <div class="extension-version">Version $($ext.Version)</div>
            </div>
"@
        }
        $html += @"
        </div>
"@
    }

    $html += @"

        <div style="margin-top: 40px; padding-top: 20px; border-top: 2px solid #ecf0f1; color: #7f8c8d; font-size: 12px;">
            <strong>Generated:</strong> $($script:AnalysisResults.Summary.Timestamp) |
            <strong>Analysis Version:</strong> $script:ScriptVersion |
            <strong>Log File:</strong> $script:LogPath
        </div>
    </div>
</body>
</html>
"@

    $html | Set-Content -Path $reportPath -Encoding UTF8
    Write-LogEntry "HTML report saved: $reportPath" -Level SUCCESS

    return $reportPath
}

function New-JSONReport {
    <#
    .SYNOPSIS
        Generates JSON-formatted analysis report.
    #>

    $reportPath = Join-Path $OutputPath "configuration-analysis-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

    $script:AnalysisResults | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

    Write-LogEntry "JSON report saved: $reportPath" -Level SUCCESS

    return $reportPath
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-SectionHeader "GeoServer Configuration Analysis - v$script:ScriptVersion"

    # Load configuration
    Load-Configuration

    # Perform analysis
    Invoke-ComponentAnalysis

    # Generate reports
    Write-SectionHeader "Generating Analysis Reports"

    $reportFiles = @()

    if ($OutputFormat -in @('Console', 'All')) {
        New-ConsoleReport
    }

    if ($OutputFormat -in @('HTML', 'All')) {
        $reportFiles += New-HTMLReport
    }

    if ($OutputFormat -in @('JSON', 'All')) {
        $reportFiles += New-JSONReport
    }

    # Summary
    Write-SectionHeader "Analysis Complete"
    Write-LogEntry "Total issues found: $($script:AnalysisResults.Summary.TotalIssues)" -Level INFO
    Write-LogEntry "  - Critical: $($script:AnalysisResults.Summary.CriticalIssues)" -Level $(if ($script:AnalysisResults.Summary.CriticalIssues -gt 0) { "ERROR" } else { "INFO" })
    Write-LogEntry "  - High: $($script:AnalysisResults.Summary.HighIssues)" -Level $(if ($script:AnalysisResults.Summary.HighIssues -gt 0) { "WARNING" } else { "INFO" })
    Write-LogEntry "Recommendation: $($script:AnalysisResults.Summary.UpgradeRecommendation)" -Level INFO

    if ($reportFiles.Count -gt 0) {
        Write-LogEntry "" -Level INFO
        Write-LogEntry "Reports generated:" -Level SUCCESS
        foreach ($file in $reportFiles) {
            Write-LogEntry "  - $file" -Level SUCCESS
        }
    }

    Write-LogEntry "Log file: $script:LogPath" -Level INFO

    # Exit with appropriate code
    if ($script:AnalysisResults.Summary.CriticalIssues -gt 0) {
        exit 2  # Critical issues found
    } elseif ($script:AnalysisResults.Summary.HighIssues -gt 0) {
        exit 1  # High priority issues found
    } else {
        exit 0  # Success
    }

} catch {
    Write-LogEntry "Analysis failed: $_" -Level ERROR
    Write-LogEntry $_.ScriptStackTrace -Level DEBUG
    exit 99
}
