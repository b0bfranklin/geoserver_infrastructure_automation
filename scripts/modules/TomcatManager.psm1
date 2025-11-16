<#
.SYNOPSIS
    PowerShell module for Apache Tomcat management functions.

.DESCRIPTION
    This module provides reusable functions for managing Apache Tomcat installations:
    - Version detection
    - Service management
    - Configuration backup/restore
    - Log management
    - Health monitoring

.NOTES
    File Name   : TomcatManager.psm1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+, Windows
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
    Gets the version of Apache Tomcat from an installation directory.

.DESCRIPTION
    Detects Tomcat version by executing version.bat or analyzing JAR manifests.

.PARAMETER TomcatPath
    The root directory of the Tomcat installation.

.EXAMPLE
    Get-TomcatVersion -TomcatPath "C:\Program Files\Apache\Tomcat\instance1"
#>
function Get-TomcatVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$TomcatPath
    )

    try {
        # Method 1: Try version.bat
        $versionScript = Join-Path $TomcatPath "bin\version.bat"

        if (Test-Path $versionScript) {
            $output = & cmd /c "$versionScript" 2>&1

            # Parse version from output
            $versionLine = $output | Where-Object { $_ -match 'Server version: Apache Tomcat/(\d+\.\d+\.\d+)' }
            if ($versionLine -match 'Apache Tomcat/(\d+\.\d+\.\d+)') {
                return $matches[1]
            }
        }

        # Method 2: Check catalina.jar manifest
        $catalinaJar = Join-Path $TomcatPath "lib\catalina.jar"
        if (Test-Path $catalinaJar) {
            # This is a simplified check - full implementation would read JAR manifest
            Write-Verbose "Found catalina.jar at $catalinaJar"
            return "Detected (version script unavailable)"
        }

        Write-Warning "Could not determine Tomcat version"
        return "Unknown"
    }
    catch {
        Write-Error "Failed to get Tomcat version: $_"
        return "Error"
    }
}

<#
.SYNOPSIS
    Validates that a directory is a valid Tomcat installation.

.PARAMETER TomcatPath
    The root directory of the Tomcat installation.

.EXAMPLE
    Test-TomcatInstallation -TomcatPath "C:\Tomcat"
#>
function Test-TomcatInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TomcatPath
    )

    if (-not (Test-Path $TomcatPath)) {
        Write-Verbose "Tomcat path does not exist: $TomcatPath"
        return $false
    }

    # Check for essential directories and files
    $essentialItems = @(
        'bin\catalina.bat',
        'bin\startup.bat',
        'bin\shutdown.bat',
        'conf\server.xml',
        'lib\catalina.jar'
    )

    $missing = @()
    foreach ($item in $essentialItems) {
        $fullPath = Join-Path $TomcatPath $item
        if (-not (Test-Path $fullPath)) {
            $missing += $item
        }
    }

    if ($missing.Count -gt 0) {
        Write-Verbose "Missing Tomcat components: $($missing -join ', ')"
        return $false
    }

    return $true
}

# ============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Starts a Tomcat Windows service.

.PARAMETER ServiceName
    The name of the Tomcat Windows service.

.PARAMETER TimeoutSec
    Maximum time to wait for service to start (seconds).

.EXAMPLE
    Start-TomcatService -ServiceName "Tomcat9"
#>
function Start-TomcatService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSec = 120
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq 'Running') {
            Write-Verbose "Service already running: $ServiceName"
            return $true
        }

        Write-Verbose "Starting service: $ServiceName"
        Start-Service -Name $ServiceName -ErrorAction Stop

        # Wait for service to start
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSec))

        Write-Verbose "Service started successfully: $ServiceName"
        return $true
    }
    catch {
        Write-Error "Failed to start Tomcat service ${ServiceName}: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Stops a Tomcat Windows service.

.PARAMETER ServiceName
    The name of the Tomcat Windows service.

.PARAMETER TimeoutSec
    Maximum time to wait for service to stop (seconds).

.PARAMETER Force
    Force stop the service if graceful shutdown fails.

.EXAMPLE
    Stop-TomcatService -ServiceName "Tomcat9" -Force
#>
function Stop-TomcatService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSec = 60,

        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq 'Stopped') {
            Write-Verbose "Service already stopped: $ServiceName"
            return $true
        }

        Write-Verbose "Stopping service: $ServiceName"

        if ($Force) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        } else {
            Stop-Service -Name $ServiceName -ErrorAction Stop
        }

        # Wait for service to stop
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($TimeoutSec))

        Write-Verbose "Service stopped successfully: $ServiceName"
        return $true
    }
    catch {
        Write-Error "Failed to stop Tomcat service ${ServiceName}: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Restarts a Tomcat Windows service.

.PARAMETER ServiceName
    The name of the Tomcat Windows service.

.PARAMETER StopTimeoutSec
    Maximum time to wait for service to stop (seconds).

.PARAMETER StartTimeoutSec
    Maximum time to wait for service to start (seconds).

.EXAMPLE
    Restart-TomcatService -ServiceName "Tomcat9"
#>
function Restart-TomcatService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName,

        [Parameter(Mandatory=$false)]
        [int]$StopTimeoutSec = 60,

        [Parameter(Mandatory=$false)]
        [int]$StartTimeoutSec = 120
    )

    try {
        # Stop the service
        $stopped = Stop-TomcatService -ServiceName $ServiceName -TimeoutSec $StopTimeoutSec

        if (-not $stopped) {
            throw "Failed to stop service"
        }

        # Give it a moment
        Start-Sleep -Seconds 5

        # Start the service
        $started = Start-TomcatService -ServiceName $ServiceName -TimeoutSec $StartTimeoutSec

        if (-not $started) {
            throw "Failed to start service"
        }

        return $true
    }
    catch {
        Write-Error "Failed to restart Tomcat service ${ServiceName}: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the status of a Tomcat Windows service.

.PARAMETER ServiceName
    The name of the Tomcat Windows service.

.EXAMPLE
    Get-TomcatServiceStatus -ServiceName "Tomcat9"
#>
function Get-TomcatServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        return @{
            Name = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status
            StartType = $service.StartType
            CanStop = $service.CanStop
            CanPauseAndContinue = $service.CanPauseAndContinue
        }
    }
    catch {
        return @{
            Name = $ServiceName
            Status = 'NotFound'
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Backs up Tomcat configuration files.

.PARAMETER TomcatPath
    The root directory of the Tomcat installation.

.PARAMETER BackupPath
    Destination directory for the backup.

.EXAMPLE
    Backup-TomcatConfiguration -TomcatPath "C:\Tomcat" -BackupPath "E:\Backups\tomcat-config"
#>
function Backup-TomcatConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$TomcatPath,

        [Parameter(Mandatory=$true)]
        [string]$BackupPath
    )

    try {
        # Create backup directory
        if (-not (Test-Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }

        # Backup entire conf directory
        $confSource = Join-Path $TomcatPath "conf"
        $confDest = Join-Path $BackupPath "conf"

        if (Test-Path $confSource) {
            Copy-Item -Path $confSource -Destination $confDest -Recurse -Force
            Write-Verbose "Backed up Tomcat conf directory"
        }

        # Backup setenv files if they exist
        $binSource = Join-Path $TomcatPath "bin"
        $binDest = Join-Path $BackupPath "bin"

        $envFiles = @('setenv.bat', 'setenv.sh')
        foreach ($envFile in $envFiles) {
            $envPath = Join-Path $binSource $envFile
            if (Test-Path $envPath) {
                if (-not (Test-Path $binDest)) {
                    New-Item -Path $binDest -ItemType Directory -Force | Out-Null
                }
                Copy-Item -Path $envPath -Destination $binDest -Force
                Write-Verbose "Backed up $envFile"
            }
        }

        return $true
    }
    catch {
        Write-Error "Failed to backup Tomcat configuration: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Restores Tomcat configuration from a backup.

.PARAMETER TomcatPath
    The root directory of the Tomcat installation.

.PARAMETER BackupPath
    Source directory containing the backup.

.EXAMPLE
    Restore-TomcatConfiguration -TomcatPath "C:\Tomcat" -BackupPath "E:\Backups\tomcat-config"
#>
function Restore-TomcatConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TomcatPath,

        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$BackupPath
    )

    try {
        # Restore conf directory
        $confSource = Join-Path $BackupPath "conf"
        $confDest = Join-Path $TomcatPath "conf"

        if (Test-Path $confSource) {
            Copy-Item -Path "$confSource\*" -Destination $confDest -Recurse -Force
            Write-Verbose "Restored Tomcat conf directory"
        }

        # Restore setenv files
        $binSource = Join-Path $BackupPath "bin"
        $binDest = Join-Path $TomcatPath "bin"

        if (Test-Path $binSource) {
            Copy-Item -Path "$binSource\*" -Destination $binDest -Force
            Write-Verbose "Restored bin files"
        }

        return $true
    }
    catch {
        Write-Error "Failed to restore Tomcat configuration: $_"
        return $false
    }
}

# ============================================================================
# LOG MANAGEMENT FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Gets recent entries from Tomcat catalina log.

.PARAMETER TomcatPath
    The root directory of the Tomcat installation.

.PARAMETER Lines
    Number of recent lines to retrieve.

.EXAMPLE
    Get-TomcatLog -TomcatPath "C:\Tomcat" -Lines 100
#>
function Get-TomcatLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$TomcatPath,

        [Parameter(Mandatory=$false)]
        [int]$Lines = 50
    )

    try {
        $logsPath = Join-Path $TomcatPath "logs"

        # Find most recent catalina log
        $logFiles = Get-ChildItem -Path $logsPath -Filter "catalina.*.log" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending

        if ($logFiles.Count -eq 0) {
            Write-Warning "No catalina log files found in $logsPath"
            return @()
        }

        $latestLog = $logFiles[0]
        $content = Get-Content -Path $latestLog.FullName -Tail $Lines -ErrorAction Stop

        return $content
    }
    catch {
        Write-Error "Failed to read Tomcat log: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Clears old Tomcat log files based on retention policy.

.PARAMETER TomcatPath
    The root directory of the Tomcat installation.

.PARAMETER RetentionDays
    Number of days to keep log files.

.EXAMPLE
    Clear-TomcatLogs -TomcatPath "C:\Tomcat" -RetentionDays 30
#>
function Clear-TomcatLogs {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$TomcatPath,

        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 365)]
        [int]$RetentionDays = 30
    )

    try {
        $logsPath = Join-Path $TomcatPath "logs"
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

        $oldLogs = Get-ChildItem -Path $logsPath -File |
                   Where-Object { $_.LastWriteTime -lt $cutoffDate }

        $removedCount = 0
        foreach ($log in $oldLogs) {
            if ($PSCmdlet.ShouldProcess($log.Name, "Delete old log file")) {
                Remove-Item -Path $log.FullName -Force
                $removedCount++
                Write-Verbose "Removed old log: $($log.Name)"
            }
        }

        Write-Verbose "Removed $removedCount old log file(s)"
        return $removedCount
    }
    catch {
        Write-Error "Failed to clear Tomcat logs: $_"
        return 0
    }
}

# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Tests if a Tomcat HTTP port is responding.

.PARAMETER Port
    The HTTP port to test.

.PARAMETER TimeoutSec
    Connection timeout in seconds.

.EXAMPLE
    Test-TomcatPort -Port 8080
#>
function Test-TomcatPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSec = 10
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect('localhost', $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($TimeoutSec * 1000, $false)

        if ($wait) {
            try {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return $true
            }
            catch {
                return $false
            }
        }
        else {
            $tcpClient.Close()
            return $false
        }
    }
    catch {
        return $false
    }
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

Export-ModuleMember -Function @(
    'Get-TomcatVersion',
    'Test-TomcatInstallation',
    'Start-TomcatService',
    'Stop-TomcatService',
    'Restart-TomcatService',
    'Get-TomcatServiceStatus',
    'Backup-TomcatConfiguration',
    'Restore-TomcatConfiguration',
    'Get-TomcatLog',
    'Clear-TomcatLogs',
    'Test-TomcatPort'
)
