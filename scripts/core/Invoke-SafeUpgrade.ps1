<#
.SYNOPSIS
    Safe upgrade wrapper that runs configuration analysis before upgrading.

.DESCRIPTION
    This script wraps the upgrade process with safety checks:
    1. Runs configuration analysis
    2. Checks for blocking issues
    3. Creates pre-upgrade baseline
    4. Executes upgrade
    5. Compares post-upgrade to baseline
    6. Generates email reports

    This is the RECOMMENDED way to perform upgrades as it includes all
    safety checks and verification steps.

.PARAMETER TargetGeoServerVersion
    Target GeoServer version for upgrade

.PARAMETER TargetTomcatVersion
    Target Tomcat version for upgrade

.PARAMETER TargetJavaVersion
    Target Java version for upgrade

.PARAMETER SkipAnalysis
    Skip configuration analysis (NOT RECOMMENDED)

.PARAMETER SkipBaseline
    Skip baseline testing

.PARAMETER EmailRecipients
    Email addresses to send reports to (comma-separated)

.PARAMETER AutoApprove
    Automatically proceed with upgrade if no critical issues (use with caution)

.EXAMPLE
    .\Invoke-SafeUpgrade.ps1 -TargetGeoServerVersion "2.25.0"

.EXAMPLE
    .\Invoke-SafeUpgrade.ps1 `
        -TargetGeoServerVersion "2.25.0" `
        -EmailRecipients "admin@example.com" `
        -AutoApprove

.NOTES
    File Name   : Invoke-SafeUpgrade.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+, Administrator privileges
    Version     : 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetGeoServerVersion,

    [Parameter(Mandatory=$false)]
    [string]$TargetTomcatVersion,

    [Parameter(Mandatory=$false)]
    [string]$TargetJavaVersion,

    [Parameter(Mandatory=$false)]
    [switch]$SkipAnalysis,

    [Parameter(Mandatory=$false)]
    [switch]$SkipBaseline,

    [Parameter(Mandatory=$false)]
    [string]$EmailRecipients,

    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath
)

#Requires -Version 7.0
#Requires -RunAsAdministrator

# ============================================================================
# INITIALIZATION
# ============================================================================

$script:RepositoryRoot = if ($PSScriptRoot) {
    Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
} else {
    Get-Location | Select-Object -ExpandProperty Path
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:RepositoryRoot "config\upgrade-config.json"
}

$script:AnalysisScript = Join-Path $script:RepositoryRoot "scripts\utilities\Invoke-ConfigurationAnalysis.ps1"
$script:BaselineScript = Join-Path $script:RepositoryRoot "scripts\utilities\Invoke-BaselineTests.ps1"
$script:UpgradeScript = Join-Path $script:RepositoryRoot "scripts\core\Invoke-GeoServerUpgrade.ps1"
$script:EmailScript = Join-Path $script:RepositoryRoot "scripts\utilities\Send-EmailNotification.ps1"

Write-Host "════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  GeoServer Safe Upgrade Workflow" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# PHASE 1: PRE-UPGRADE ANALYSIS
# ============================================================================

if (-not $SkipAnalysis) {
    Write-Host "═══ Phase 1: Configuration Analysis ═══" -ForegroundColor Cyan
    Write-Host ""

    $analysisParams = @{
        ConfigPath = $ConfigPath
        AnalysisDepth = 'Standard'
        CheckSecurity = $true
        CheckPerformance = $true
        OutputFormat = 'All'
    }

    if ($TargetGeoServerVersion) { $analysisParams['TargetGeoServerVersion'] = $TargetGeoServerVersion }
    if ($TargetTomcatVersion) { $analysisParams['TargetTomcatVersion'] = $TargetTomcatVersion }
    if ($TargetJavaVersion) { $analysisParams['TargetJavaVersion'] = $TargetJavaVersion }

    & $script:AnalysisScript @analysisParams
    $analysisExitCode = $LASTEXITCODE

    Write-Host ""
    if ($analysisExitCode -eq 2) {
        Write-Host "🔴 CRITICAL ISSUES DETECTED" -ForegroundColor Red
        Write-Host ""
        Write-Host "Configuration analysis found critical blocking issues that must be fixed" -ForegroundColor Red
        Write-Host "before proceeding with the upgrade." -ForegroundColor Red
        Write-Host ""
        Write-Host "Actions required:" -ForegroundColor Yellow
        Write-Host "  1. Review analysis report in reports/ directory" -ForegroundColor White
        Write-Host "  2. Fix all CRITICAL issues" -ForegroundColor White
        Write-Host "  3. Re-run this script to verify fixes" -ForegroundColor White
        Write-Host ""

        if ($EmailRecipients) {
            & $script:EmailScript -To ($EmailRecipients -split ',') `
                -Subject "GeoServer Upgrade BLOCKED - Critical Issues" `
                -Body "Configuration analysis detected critical issues. Upgrade cannot proceed. Review analysis report."
        }

        exit 2
    } elseif ($analysisExitCode -eq 1) {
        Write-Host "⚠️  HIGH PRIORITY ISSUES DETECTED" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Configuration analysis found high priority issues that should be addressed." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Review the analysis report and decide whether to:" -ForegroundColor White
        Write-Host "  - Fix issues now and re-run upgrade" -ForegroundColor White
        Write-Host "  - Proceed with upgrade (issues may cause problems)" -ForegroundColor White
        Write-Host "  - Document issues to address post-upgrade" -ForegroundColor White
        Write-Host ""

        if (-not $AutoApprove) {
            $response = Read-Host "Proceed with upgrade despite warnings? (yes/no)"
            if ($response -ne 'yes') {
                Write-Host "Upgrade cancelled by user" -ForegroundColor Yellow
                exit 1
            }
        }
    } else {
        Write-Host "✓ Configuration analysis passed - no blocking issues" -ForegroundColor Green
        Write-Host ""
    }
} else {
    Write-Host "⚠️  Skipping configuration analysis (not recommended)" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# PHASE 2: BASELINE CAPTURE
# ============================================================================

if (-not $SkipBaseline) {
    Write-Host "═══ Phase 2: Baseline Testing ═══" -ForegroundColor Cyan
    Write-Host ""

    $baselineName = "pre-upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    $baselineParams = @{
        Mode = 'SaveBaseline'
        BaselineName = $baselineName
        TestProfile = 'Standard'
        ConfigPath = $ConfigPath
    }

    & $script:BaselineScript @baselineParams

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Baseline saved: $baselineName" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "⚠️  Baseline testing encountered errors" -ForegroundColor Yellow
        Write-Host "Continuing with upgrade..." -ForegroundColor Yellow
        Write-Host ""
    }
} else {
    Write-Host "⚠️  Skipping baseline testing" -ForegroundColor Yellow
    Write-Host ""
    $baselineName = $null
}

# ============================================================================
# PHASE 3: CONFIRMATION
# ============================================================================

Write-Host "═══ Phase 3: Pre-Upgrade Confirmation ═══" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ready to upgrade with the following configuration:" -ForegroundColor White
Write-Host ""
if ($TargetGeoServerVersion) { Write-Host "  Target GeoServer Version: $TargetGeoServerVersion" -ForegroundColor Cyan }
if ($TargetTomcatVersion) { Write-Host "  Target Tomcat Version: $TargetTomcatVersion" -ForegroundColor Cyan }
if ($TargetJavaVersion) { Write-Host "  Target Java Version: $TargetJavaVersion" -ForegroundColor Cyan }
if ($baselineName) { Write-Host "  Baseline Saved: $baselineName" -ForegroundColor Cyan }
Write-Host ""

if (-not $AutoApprove) {
    Write-Host "⚠️  FINAL CONFIRMATION REQUIRED" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This will:" -ForegroundColor White
    Write-Host "  - Stop GeoServer and Tomcat services" -ForegroundColor White
    Write-Host "  - Create backup of current installation" -ForegroundColor White
    Write-Host "  - Upgrade components to target versions" -ForegroundColor White
    Write-Host "  - Restart services" -ForegroundColor White
    Write-Host "  - Run health checks" -ForegroundColor White
    Write-Host ""

    $confirmation = Read-Host "Proceed with upgrade? (type 'UPGRADE' to confirm)"

    if ($confirmation -ne 'UPGRADE') {
        Write-Host ""
        Write-Host "Upgrade cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Starting upgrade..." -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 4: EXECUTE UPGRADE
# ============================================================================

Write-Host "═══ Phase 4: Executing Upgrade ═══" -ForegroundColor Cyan
Write-Host ""

$upgradeParams = @{
    Component = 'All'
    AutoRollback = $true
    ConfigPath = $ConfigPath
}

& $script:UpgradeScript @upgradeParams
$upgradeExitCode = $LASTEXITCODE

Write-Host ""

# ============================================================================
# PHASE 5: POST-UPGRADE VERIFICATION
# ============================================================================

if ($upgradeExitCode -eq 0) {
    Write-Host "═══ Phase 5: Post-Upgrade Verification ═══" -ForegroundColor Cyan
    Write-Host ""

    if ($baselineName -and -not $SkipBaseline) {
        Write-Host "Running baseline comparison..." -ForegroundColor Cyan

        $compareParams = @{
            Mode = 'CompareBaseline'
            BaselineName = $baselineName
            TestProfile = 'Standard'
            ConfigPath = $ConfigPath
        }

        if ($EmailRecipients) {
            $compareParams['GenerateChecklist'] = $true
            $compareParams['EmailRecipients'] = $EmailRecipients
        }

        & $script:BaselineScript @compareParams

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Post-upgrade tests passed" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Post-upgrade tests detected changes or failures" -ForegroundColor Yellow
            Write-Host "Review test results and baseline comparison" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ UPGRADE COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Review test results" -ForegroundColor White
    Write-Host "  2. Perform manual verification" -ForegroundColor White
    Write-Host "  3. Monitor logs for errors" -ForegroundColor White
    Write-Host "  4. Notify users that service is available" -ForegroundColor White
    Write-Host ""

    if ($EmailRecipients) {
        & $script:EmailScript -To ($EmailRecipients -split ',') `
            -Subject "GeoServer Upgrade Completed Successfully" `
            -Body "GeoServer upgrade completed. Review test results and perform manual verification."
    }

    exit 0

} else {
    Write-Host "════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ UPGRADE FAILED" -ForegroundColor Red
    Write-Host "════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "The upgrade process failed or was rolled back." -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "  1. Review logs in C:\GeoServerLogs\" -ForegroundColor White
    Write-Host "  2. Check analysis report for missed issues" -ForegroundColor White
    Write-Host "  3. Verify system state with baseline tests" -ForegroundColor White
    Write-Host "  4. Consult BEGINNERS-GUIDE.md troubleshooting section" -ForegroundColor White
    Write-Host ""

    if ($EmailRecipients) {
        & $script:EmailScript -To ($EmailRecipients -split ',') `
            -Subject "GeoServer Upgrade FAILED" `
            -Body "GeoServer upgrade failed or was rolled back. System should be in pre-upgrade state. Review logs."
    }

    exit 1
}
