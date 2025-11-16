<#
.SYNOPSIS
    Self-contained package manager for downloading and caching infrastructure components.

.DESCRIPTION
    Downloads and manages component packages without requiring external package managers.
    Supports:
    - Azul Zulu JRE
    - Apache Tomcat
    - GeoServer
    - PostgreSQL & PostGIS
    - pgAdmin
    - QGIS

    All downloads are cached locally for offline installations.

.PARAMETER Component
    The component to download.

.PARAMETER Version
    Specific version to download (optional - uses latest if not specified).

.PARAMETER CacheDirectory
    Directory to cache downloaded files. Default: .\downloads

.PARAMETER Force
    Force re-download even if cached version exists.

.EXAMPLE
    .\Get-ComponentPackage.ps1 -Component "AzulJRE" -Version "17.0.9"

.EXAMPLE
    .\Get-ComponentPackage.ps1 -Component "Tomcat" -Version "10.1.17"

.NOTES
    File Name   : Get-ComponentPackage.ps1
    Version     : 2.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('AzulJRE', 'Tomcat', 'GeoServer', 'PostgreSQL', 'PostGIS', 'PgAdmin', 'QGIS')]
    [string]$Component,

    [Parameter(Mandatory=$false)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$CacheDirectory = ".\downloads",

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# COMPONENT VERSION DATABASE
# ============================================================================

$ComponentDatabase = @{
    AzulJRE = @{
        Name = "Azul Zulu JRE"
        Versions = @{
            '17.0.9' = @{
                URL = "https://cdn.azul.com/zulu/bin/zulu17.46.19-ca-jre17.0.9-win_x64.zip"
                SHA256 = ""  # Add actual SHA256 hash
                FileName = "zulu17.46.19-ca-jre17.0.9-win_x64.zip"
            }
            '21.0.1' = @{
                URL = "https://cdn.azul.com/zulu/bin/zulu21.30.15-ca-jre21.0.1-win_x64.zip"
                SHA256 = ""
                FileName = "zulu21.30.15-ca-jre21.0.1-win_x64.zip"
            }
        }
        Latest = '21.0.1'
    }

    Tomcat = @{
        Name = "Apache Tomcat"
        Versions = @{
            '9.0.85' = @{
                URL = "https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.85/bin/apache-tomcat-9.0.85-windows-x64.zip"
                SHA256 = ""
                FileName = "apache-tomcat-9.0.85-windows-x64.zip"
            }
            '10.1.17' = @{
                URL = "https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.17/bin/apache-tomcat-10.1.17-windows-x64.zip"
                SHA256 = ""
                FileName = "apache-tomcat-10.1.17-windows-x64.zip"
            }
        }
        Latest = '10.1.17'
    }

    GeoServer = @{
        Name = "GeoServer"
        Versions = @{
            '2.24.2' = @{
                URL = "https://sourceforge.net/projects/geoserver/files/GeoServer/2.24.2/geoserver-2.24.2-war.zip/download"
                SHA256 = ""
                FileName = "geoserver-2.24.2-war.zip"
            }
            '2.25.0' = @{
                URL = "https://sourceforge.net/projects/geoserver/files/GeoServer/2.25.0/geoserver-2.25.0-war.zip/download"
                SHA256 = ""
                FileName = "geoserver-2.25.0-war.zip"
            }
        }
        Latest = '2.25.0'
    }

    PostgreSQL = @{
        Name = "PostgreSQL"
        Versions = @{
            '15.5' = @{
                URL = "https://get.enterprisedb.com/postgresql/postgresql-15.5-1-windows-x64.exe"
                SHA256 = ""
                FileName = "postgresql-15.5-1-windows-x64.exe"
            }
            '16.1' = @{
                URL = "https://get.enterprisedb.com/postgresql/postgresql-16.1-1-windows-x64.exe"
                SHA256 = ""
                FileName = "postgresql-16.1-1-windows-x64.exe"
            }
        }
        Latest = '16.1'
    }

    PostGIS = @{
        Name = "PostGIS"
        Versions = @{
            '3.4.1' = @{
                URL = "https://download.osgeo.org/postgis/windows/pg15/postgis-bundle-pg15-3.4.1x64.zip"
                SHA256 = ""
                FileName = "postgis-bundle-pg15-3.4.1x64.zip"
            }
        }
        Latest = '3.4.1'
    }

    PgAdmin = @{
        Name = "pgAdmin 4"
        Versions = @{
            '8.0' = @{
                URL = "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v8.0/windows/pgadmin4-8.0-x64.exe"
                SHA256 = ""
                FileName = "pgadmin4-8.0-x64.exe"
            }
        }
        Latest = '8.0'
    }

    QGIS = @{
        Name = "QGIS"
        Versions = @{
            '3.34.2' = @{
                URL = "https://qgis.org/downloads/QGIS-OSGeo4W-3.34.2-1.msi"
                SHA256 = ""
                FileName = "QGIS-OSGeo4W-3.34.2-1.msi"
            }
        }
        Latest = '3.34.2'
    }
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-LogEntry {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage -ForegroundColor White }
    }
}

# ============================================================================
# DOWNLOAD FUNCTIONS
# ============================================================================

function Get-PackageInfo {
    param(
        [string]$Component,
        [string]$Version
    )

    if (-not $ComponentDatabase.ContainsKey($Component)) {
        throw "Unknown component: $Component"
    }

    $componentInfo = $ComponentDatabase[$Component]

    # Use latest version if not specified
    if (-not $Version) {
        $Version = $componentInfo.Latest
        Write-LogEntry "No version specified, using latest: $Version" "INFO"
    }

    if (-not $componentInfo.Versions.ContainsKey($Version)) {
        throw "Version $Version not found for component $Component"
    }

    return @{
        Component = $Component
        Version = $Version
        Name = $componentInfo.Name
        Info = $componentInfo.Versions[$Version]
    }
}

function Test-CachedPackage {
    param(
        [string]$CacheDirectory,
        [string]$FileName,
        [string]$SHA256Hash
    )

    $cachePath = Join-Path $CacheDirectory $FileName

    if (-not (Test-Path $cachePath)) {
        return $false
    }

    Write-LogEntry "Found cached package: $FileName" "INFO"

    # Verify SHA256 hash if provided
    if ($SHA256Hash) {
        Write-LogEntry "Verifying cached package integrity..." "INFO"
        try {
            $fileHash = Get-FileHash -Path $cachePath -Algorithm SHA256
            if ($fileHash.Hash -eq $SHA256Hash) {
                Write-LogEntry "Package integrity verified" "SUCCESS"
                return $true
            } else {
                Write-LogEntry "Package integrity check failed - will re-download" "WARNING"
                return $false
            }
        }
        catch {
            Write-LogEntry "Failed to verify package: $_" "WARNING"
            return $false
        }
    }

    return $true
}

function Get-DownloadWithProgress {
    param(
        [string]$URL,
        [string]$OutputPath
    )

    try {
        Write-LogEntry "Downloading from: $URL" "INFO"
        Write-LogEntry "Saving to: $OutputPath" "INFO"

        # Use .NET WebClient for progress tracking
        $webClient = New-Object System.Net.WebClient

        # Register progress event
        $progressHandler = {
            param($sender, $e)
            $percentComplete = $e.ProgressPercentage
            $receivedBytes = $e.BytesReceived
            $totalBytes = $e.TotalBytesToReceive

            if ($totalBytes -gt 0) {
                $receivedMB = [math]::Round($receivedBytes / 1MB, 2)
                $totalMB = [math]::Round($totalBytes / 1MB, 2)
                Write-Progress -Activity "Downloading Package" `
                    -Status "Downloaded ${receivedMB}MB of ${totalMB}MB" `
                    -PercentComplete $percentComplete
            }
        }

        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged `
            -SourceIdentifier WebClient.ProgressChanged -Action $progressHandler | Out-Null

        # Start download
        $completed = $false
        $completionHandler = {
            param($sender, $e)
            $script:completed = $true
        }

        Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted `
            -SourceIdentifier WebClient.DownloadComplete -Action $completionHandler | Out-Null

        $webClient.DownloadFileAsync($URL, $OutputPath)

        # Wait for completion
        while (-not $completed) {
            Start-Sleep -Milliseconds 100
        }

        # Cleanup
        Unregister-Event -SourceIdentifier WebClient.ProgressChanged -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier WebClient.DownloadComplete -ErrorAction SilentlyContinue
        $webClient.Dispose()

        Write-Progress -Activity "Downloading Package" -Completed
        Write-LogEntry "Download completed successfully" "SUCCESS"

        return $true
    }
    catch {
        Write-LogEntry "Download failed: $_" "ERROR"
        return $false
    }
}

function Expand-Package {
    param(
        [string]$PackagePath,
        [string]$ExtractPath
    )

    try {
        Write-LogEntry "Extracting package to: $ExtractPath" "INFO"

        $extension = [System.IO.Path]::GetExtension($PackagePath).ToLower()

        switch ($extension) {
            '.zip' {
                if (-not (Test-Path $ExtractPath)) {
                    New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
                }

                Add-Type -Assembly 'System.IO.Compression.FileSystem'
                [System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $ExtractPath)
                Write-LogEntry "Package extracted successfully" "SUCCESS"
                return $true
            }

            '.exe' {
                Write-LogEntry "Package is an installer (.exe) - extraction not required" "INFO"
                return $true
            }

            '.msi' {
                Write-LogEntry "Package is an MSI installer - extraction not required" "INFO"
                return $true
            }

            default {
                Write-LogEntry "Unknown package format: $extension" "WARNING"
                return $false
            }
        }
    }
    catch {
        Write-LogEntry "Failed to extract package: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-PackageDownload {
    try {
        Write-LogEntry "=== Component Package Manager ===" "INFO"
        Write-LogEntry "" "INFO"

        # Get package information
        $package = Get-PackageInfo -Component $Component -Version $Version

        Write-LogEntry "Component: $($package.Name)" "INFO"
        Write-LogEntry "Version: $($package.Version)" "INFO"
        Write-LogEntry "" "INFO"

        # Ensure cache directory exists
        if (-not (Test-Path $CacheDirectory)) {
            Write-LogEntry "Creating cache directory: $CacheDirectory" "INFO"
            New-Item -Path $CacheDirectory -ItemType Directory -Force | Out-Null
        }

        # Check if already cached
        $cachePath = Join-Path $CacheDirectory $package.Info.FileName

        if (-not $Force) {
            if (Test-CachedPackage -CacheDirectory $CacheDirectory `
                                    -FileName $package.Info.FileName `
                                    -SHA256Hash $package.Info.SHA256) {
                Write-LogEntry "Package already cached and verified" "SUCCESS"
                Write-LogEntry "Cache location: $cachePath" "INFO"

                return @{
                    Success = $true
                    Component = $Component
                    Version = $package.Version
                    PackagePath = $cachePath
                    Cached = $true
                }
            }
        }

        # Download the package
        Write-LogEntry "Downloading $($package.Name) $($package.Version)..." "INFO"

        $downloaded = Get-DownloadWithProgress -URL $package.Info.URL -OutputPath $cachePath

        if (-not $downloaded) {
            throw "Failed to download package"
        }

        # Verify downloaded package
        if ($package.Info.SHA256) {
            Write-LogEntry "Verifying package integrity..." "INFO"
            $fileHash = Get-FileHash -Path $cachePath -Algorithm SHA256

            if ($fileHash.Hash -eq $package.Info.SHA256) {
                Write-LogEntry "Package integrity verified successfully" "SUCCESS"
            } else {
                throw "Package integrity verification failed!"
            }
        }

        # Get file size
        $fileSize = (Get-Item $cachePath).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-LogEntry "Package size: ${fileSizeMB}MB" "INFO"

        Write-LogEntry "" "INFO"
        Write-LogEntry "Package downloaded successfully" "SUCCESS"
        Write-LogEntry "Location: $cachePath" "INFO"

        return @{
            Success = $true
            Component = $Component
            Version = $package.Version
            PackagePath = $cachePath
            Cached = $false
            SizeMB = $fileSizeMB
        }
    }
    catch {
        Write-LogEntry "" "ERROR"
        Write-LogEntry "Package download failed: $_" "ERROR"

        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Execute download
$result = Start-PackageDownload

if ($result.Success) {
    exit 0
} else {
    exit 1
}
