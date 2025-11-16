<#
.SYNOPSIS
    PowerShell module for GeoServer management functions.

.DESCRIPTION
    This module provides reusable functions for managing GeoServer installations:
    - Version detection
    - Configuration management
    - REST API interactions
    - Health checks
    - Workspace and layer management

.NOTES
    File Name   : GeoServer.psm1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+
    Version     : 1.0.0
#>

# ============================================================================
# MODULE VARIABLES
# ============================================================================

$script:ModuleVersion = "1.0.0"

# ============================================================================
# VERSION DETECTION FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Gets the version of GeoServer from a running instance.

.DESCRIPTION
    Attempts to determine the GeoServer version by querying the about API endpoint.

.PARAMETER BaseUrl
    The base URL of the GeoServer instance (e.g., http://localhost:8080/geoserver)

.PARAMETER Credential
    Optional credentials for accessing GeoServer REST API.

.EXAMPLE
    Get-GeoServerVersion -BaseUrl "http://localhost:8080/geoserver"
#>
function Get-GeoServerVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,

        [Parameter(Mandatory=$false)]
        [PSCredential]$Credential
    )

    try {
        # Try to get version from REST API
        $aboutUrl = "$BaseUrl/rest/about/version.json"

        $params = @{
            Uri = $aboutUrl
            Method = 'GET'
            ContentType = 'application/json'
            TimeoutSec = 30
            ErrorAction = 'Stop'
        }

        if ($Credential) {
            $params.Credential = $Credential
        }

        $response = Invoke-RestMethod @params

        if ($response.'about'.'resource') {
            $versionInfo = $response.'about'.'resource' | Where-Object { $_.name -eq 'GeoServer' }
            if ($versionInfo) {
                return $versionInfo.'Build-Timestamp'
            }
        }

        return "Unknown (API accessible)"
    }
    catch {
        Write-Verbose "Failed to get GeoServer version: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Tests if a GeoServer instance is accessible and responding.

.PARAMETER BaseUrl
    The base URL of the GeoServer instance.

.PARAMETER TimeoutSec
    Timeout in seconds for the connection test.

.EXAMPLE
    Test-GeoServerConnection -BaseUrl "http://localhost:8080/geoserver"
#>
function Test-GeoServerConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSec = 30
    )

    try {
        $webUrl = "$BaseUrl/web/"
        $response = Invoke-WebRequest -Uri $webUrl -TimeoutSec $TimeoutSec -ErrorAction Stop

        return @{
            Success = ($response.StatusCode -eq 200)
            StatusCode = $response.StatusCode
            ResponseTime = 0  # Would need stopwatch for accurate timing
        }
    }
    catch {
        return @{
            Success = $false
            StatusCode = 0
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# REST API FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Gets a list of workspaces from GeoServer.

.PARAMETER BaseUrl
    The base URL of the GeoServer instance.

.PARAMETER Credential
    Credentials for GeoServer REST API access.

.EXAMPLE
    Get-GeoServerWorkspaces -BaseUrl "http://localhost:8080/geoserver" -Credential $cred
#>
function Get-GeoServerWorkspaces {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,

        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential
    )

    try {
        $url = "$BaseUrl/rest/workspaces.json"

        $response = Invoke-RestMethod -Uri $url -Method GET -Credential $Credential -ContentType 'application/json' -ErrorAction Stop

        if ($response.workspaces.workspace) {
            return $response.workspaces.workspace
        }

        return @()
    }
    catch {
        Write-Error "Failed to get workspaces: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Gets a list of layers from a GeoServer workspace.

.PARAMETER BaseUrl
    The base URL of the GeoServer instance.

.PARAMETER Workspace
    The workspace name.

.PARAMETER Credential
    Credentials for GeoServer REST API access.

.EXAMPLE
    Get-GeoServerLayers -BaseUrl "http://localhost:8080/geoserver" -Workspace "myworkspace" -Credential $cred
#>
function Get-GeoServerLayers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$Workspace,

        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential
    )

    try {
        $url = "$BaseUrl/rest/workspaces/$Workspace/layers.json"

        $response = Invoke-RestMethod -Uri $url -Method GET -Credential $Credential -ContentType 'application/json' -ErrorAction Stop

        if ($response.layers.layer) {
            return $response.layers.layer
        }

        return @()
    }
    catch {
        Write-Error "Failed to get layers for workspace $Workspace: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Tests WMS GetCapabilities endpoint.

.PARAMETER BaseUrl
    The base URL of the GeoServer instance.

.EXAMPLE
    Test-GeoServerWMS -BaseUrl "http://localhost:8080/geoserver"
#>
function Test-GeoServerWMS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )

    try {
        $url = "$BaseUrl/wms?service=WMS&version=1.3.0&request=GetCapabilities"
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 30 -ErrorAction Stop

        $isValid = ($response.StatusCode -eq 200) -and ($response.Content -match 'WMS_Capabilities')

        return @{
            Success = $isValid
            StatusCode = $response.StatusCode
            ContentLength = $response.Content.Length
        }
    }
    catch {
        return @{
            Success = $false
            StatusCode = 0
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Tests WFS GetCapabilities endpoint.

.PARAMETER BaseUrl
    The base URL of the GeoServer instance.

.EXAMPLE
    Test-GeoServerWFS -BaseUrl "http://localhost:8080/geoserver"
#>
function Test-GeoServerWFS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )

    try {
        $url = "$BaseUrl/wfs?service=WFS&version=2.0.0&request=GetCapabilities"
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 30 -ErrorAction Stop

        $isValid = ($response.StatusCode -eq 200) -and ($response.Content -match 'WFS_Capabilities')

        return @{
            Success = $isValid
            StatusCode = $response.StatusCode
            ContentLength = $response.Content.Length
        }
    }
    catch {
        return @{
            Success = $false
            StatusCode = 0
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Backs up GeoServer configuration files.

.PARAMETER DataDirectory
    Path to the GeoServer data directory.

.PARAMETER BackupPath
    Destination path for the backup.

.EXAMPLE
    Backup-GeoServerConfiguration -DataDirectory "D:\GeoServer\data" -BackupPath "E:\Backups\geoserver-config"
#>
function Backup-GeoServerConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataDirectory,

        [Parameter(Mandatory=$true)]
        [string]$BackupPath
    )

    try {
        if (-not (Test-Path $DataDirectory)) {
            throw "GeoServer data directory not found: $DataDirectory"
        }

        # Create backup directory
        if (-not (Test-Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }

        # Critical files and directories to backup
        $criticalItems = @(
            'global.xml',
            'logging.xml',
            'wms.xml',
            'wfs.xml',
            'wcs.xml',
            'security',
            'workspaces',
            'styles'
        )

        foreach ($item in $criticalItems) {
            $source = Join-Path $DataDirectory $item
            $dest = Join-Path $BackupPath $item

            if (Test-Path $source) {
                if ((Get-Item $source).PSIsContainer) {
                    Copy-Item -Path $source -Destination $dest -Recurse -Force
                } else {
                    Copy-Item -Path $source -Destination $dest -Force
                }
                Write-Verbose "Backed up: $item"
            }
        }

        return $true
    }
    catch {
        Write-Error "Failed to backup GeoServer configuration: $_"
        return $false
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Validates GeoServer data directory structure.

.PARAMETER DataDirectory
    Path to the GeoServer data directory.

.EXAMPLE
    Test-GeoServerDataDirectory -DataDirectory "D:\GeoServer\data"
#>
function Test-GeoServerDataDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataDirectory
    )

    if (-not (Test-Path $DataDirectory)) {
        Write-Error "Data directory not found: $DataDirectory"
        return $false
    }

    # Check for essential files
    $essentialFiles = @('global.xml')
    $missingFiles = @()

    foreach ($file in $essentialFiles) {
        $filePath = Join-Path $DataDirectory $file
        if (-not (Test-Path $filePath)) {
            $missingFiles += $file
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-Warning "Missing essential files: $($missingFiles -join ', ')"
        return $false
    }

    return $true
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

Export-ModuleMember -Function @(
    'Get-GeoServerVersion',
    'Test-GeoServerConnection',
    'Get-GeoServerWorkspaces',
    'Get-GeoServerLayers',
    'Test-GeoServerWMS',
    'Test-GeoServerWFS',
    'Backup-GeoServerConfiguration',
    'Test-GeoServerDataDirectory'
)
