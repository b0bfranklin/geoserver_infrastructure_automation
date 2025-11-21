# Configuration Analysis Component

## Overview

The Configuration Analysis component provides comprehensive pre-upgrade analysis of your Apache, Tomcat, and GeoServer installations. It identifies potential breaking changes, configuration incompatibilities, security vulnerabilities, and performance optimization opportunities **before** you perform an upgrade.

## Key Features

### 🔍 **Deep Configuration Inspection**
- Parses Tomcat server.xml, web.xml, and context.xml
- Analyzes GeoServer data directory structure
- Examines installed extensions and plugins
- Detects current component versions automatically

### ⚠️ **Breaking Change Detection**
- Database of known breaking changes across versions
- Impact assessment for your specific upgrade path
- Version-specific compatibility checks
- API change notifications

### 🔒 **Security Vulnerability Scanning**
- CVE database integration
- Version-specific vulnerability detection
- CVSS severity scoring
- Remediation recommendations

### ⚡ **Performance Analysis**
- Configuration optimization recommendations
- JVM tuning suggestions
- Connector threading analysis
- Caching strategy recommendations

### 📊 **Multiple Report Formats**
- Console output for quick reviews
- HTML reports with visual severity indicators
- JSON output for automation/CI/CD integration

## Usage

### Basic Analysis

```powershell
# Analyze against default target versions
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1

# Analyze with specific target version
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 -TargetGeoServerVersion "2.25.0"

# Full analysis with all checks
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 `
    -TargetGeoServerVersion "2.25.0" `
    -TargetTomcatVersion "10.1.0" `
    -TargetJavaVersion "17" `
    -AnalysisDepth Deep `
    -CheckSecurity `
    -CheckPerformance
```

### Analysis Depth Levels

#### **Quick** (Fastest - 30 seconds)
- Version detection only
- Critical breaking changes
- Security vulnerabilities
- Best for: Quick pre-flight checks

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -AnalysisDepth Quick
```

#### **Standard** (Recommended - 2-3 minutes)
- Full configuration parsing
- Compatibility analysis
- Deprecated setting detection
- Performance recommendations
- Best for: Regular pre-upgrade assessments

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -AnalysisDepth Standard
```

#### **Deep** (Most Thorough - 5-10 minutes)
- Everything in Standard
- Data directory deep scan
- Extension compatibility checks
- Performance profiling
- Configuration best practices audit
- Best for: Major version upgrades, production deployments

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -AnalysisDepth Deep
```

### Report Formats

#### Console Output
Quick results directly in your terminal:

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -OutputFormat Console
```

#### HTML Report
Beautiful, shareable HTML report with visual indicators:

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -OutputFormat HTML -OutputPath "./reports"
```

#### JSON Output
Machine-readable format for automation:

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -OutputFormat JSON | ConvertFrom-Json
```

#### All Formats
Generate all report types:

```powershell
.\Invoke-ConfigurationAnalysis.ps1 -OutputFormat All
```

## Understanding the Results

### Severity Levels

| Level | Meaning | Action Required |
|-------|---------|-----------------|
| **CRITICAL** | 🔴 Upgrade will fail or cause data loss | Must fix before upgrading |
| **HIGH** | ⚠️ Major functionality will break | Should fix before upgrading |
| **MEDIUM** | ⚡ Minor issues or deprecations | Can fix after upgrading |
| **LOW** | ℹ️ Best practices or optimizations | Optional improvements |

### Upgrade Recommendations

The analysis provides one of these recommendations:

- **CRITICAL ISSUES - Address before upgrading** 🔴
  - One or more critical blockers detected
  - **Action:** Fix all critical issues, then re-run analysis

- **CAUTION - Review and address high priority issues** ⚠️
  - Multiple high-priority issues found
  - **Action:** Review each issue, plan fixes, test in staging

- **PROCEED - Minor issues can be addressed post-upgrade** ✅
  - Only low/medium issues detected
  - **Action:** Document issues, proceed with upgrade, address afterwards

- **SAFE - No major compatibility issues detected** ✅
  - Clean bill of health
  - **Action:** Proceed with upgrade confidently

## Common Issues and Fixes

### Issue: Java Version Incompatibility

**Detection:**
```
[CRITICAL] Java Version: Minimum Java version raised to 11
Impact: Java 8 installations will fail to start
```

**Resolution:**
```powershell
# Upgrade Java first
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion "11.0.20"

# Re-run analysis
.\Invoke-ConfigurationAnalysis.ps1
```

### Issue: Tomcat Package Namespace Change (9.x → 10.x)

**Detection:**
```
[HIGH] Package Names: Jakarta EE namespace migration (javax.* → jakarta.*)
Impact: Applications using javax.servlet.* will not work
```

**Resolution:**
```
Option 1: Stay on Tomcat 9.x (recommended for most GeoServer deployments)
Option 2: Migrate to Jakarta EE 9+ (requires GeoServer recompilation)

Recommended: Target Tomcat 9.0.80+ instead of 10.x
```

### Issue: Deprecated Tomcat Connector Configuration

**Detection:**
```
[MEDIUM] Deprecated Configuration: Using deprecated HTTP/1.1 protocol class
Location: server.xml - Connector port 8080
```

**Resolution:**
Edit `conf/server.xml`:
```xml
<!-- OLD (deprecated) -->
<Connector port="8080"
           protocol="org.apache.coyote.http11.Http11Protocol" />

<!-- NEW (recommended) -->
<Connector port="8080"
           protocol="HTTP/1.1" />
```

### Issue: GeoServer Custom Authentication

**Detection:**
```
[CRITICAL] Security: Security subsystem refactored - custom auth filters need migration
Impact: Custom authentication providers will not load
```

**Resolution:**
1. Review custom authentication code
2. Consult GeoServer migration guide for version
3. Update auth filters to new API
4. Test authentication in staging environment

## Integration with Upgrade Workflow

### Recommended Workflow

```powershell
# 1. Run analysis
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 `
    -TargetGeoServerVersion "2.25.0" `
    -AnalysisDepth Deep `
    -OutputFormat All

# 2. Review reports
# Check: reports/configuration-analysis-*.html

# 3. Fix critical and high issues
# (Based on report recommendations)

# 4. Re-run analysis to verify fixes
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 -AnalysisDepth Quick

# 5. Proceed with upgrade
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component All
```

### CI/CD Integration

```powershell
# Run in CI pipeline
$exitCode = .\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 `
    -OutputFormat JSON `
    -CheckSecurity

# Exit codes:
#   0 = No critical/high issues (safe to deploy)
#   1 = High priority issues found (review required)
#   2 = Critical issues found (block deployment)
#  99 = Analysis failed

if ($exitCode -eq 0) {
    Write-Host "✅ Configuration analysis passed - proceeding with upgrade"
} elseif ($exitCode -eq 1) {
    Write-Host "⚠️ High priority issues detected - manual review required"
    exit 1
} else {
    Write-Host "🔴 Critical issues detected - blocking upgrade"
    exit 2
}
```

## Extension Compatibility

The analysis detects installed GeoServer extensions and can flag compatibility issues:

### Compatible Extensions
✅ Will work with target version (may need update)

### Incompatible Extensions
❌ Will not work - must be removed or updated

### Common Extension Issues

| Extension | GeoServer 2.24+ | GeoServer 2.25+ | Notes |
|-----------|----------------|----------------|-------|
| WPS | ✅ Compatible | ✅ Compatible | Update recommended |
| CSS Styling | ✅ Compatible | ✅ Compatible | New features available |
| INSPIRE | ✅ Compatible | ⚠️ Update Required | Schema changes |
| Printing | ✅ Compatible | ✅ Compatible | - |
| Importer | ⚠️ Check version | ⚠️ Check version | API changes in 2.24+ |

## Performance Recommendations

The analysis can identify configuration improvements:

### JVM Tuning
```
Recommended JVM Settings:
-Xms2G -Xmx4G
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:+ParallelRefProcEnabled
```

### Tomcat Connector Optimization
```xml
<Connector port="8080"
           protocol="HTTP/1.1"
           maxThreads="200"
           minSpareThreads="25"
           connectionTimeout="20000"
           maxConnections="10000"
           acceptCount="100" />
```

### GeoServer Caching
- Enable GeoWebCache (integrated tile caching)
- Configure disk quotas
- Set appropriate cache expiration
- Use vector tiles where applicable

## Advanced Usage

### Custom Breaking Changes Database

You can extend the breaking changes detection by modifying the script's internal database or creating a custom JSON file.

### Automated Scheduled Analysis

```powershell
# Weekly configuration health check
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 2am
$action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
    -Argument "-File .\Invoke-ConfigurationAnalysis.ps1 -OutputFormat HTML -OutputPath C:\Reports"

Register-ScheduledTask -TaskName "GeoServer-ConfigAnalysis" `
    -Trigger $trigger `
    -Action $action `
    -Description "Weekly GeoServer configuration analysis"
```

### Pre-Upgrade Safety Check

```powershell
# Add to your upgrade script
$analysisResult = .\Invoke-ConfigurationAnalysis.ps1 `
    -TargetGeoServerVersion $targetVersion `
    -OutputFormat JSON

$issues = ($analysisResult | ConvertFrom-Json).Summary

if ($issues.CriticalIssues -gt 0) {
    Write-Error "Critical issues detected - aborting upgrade"
    exit 1
}

# Proceed with upgrade...
```

## Troubleshooting

### Analysis Fails to Detect Version

**Problem:** "Could not determine GeoServer version automatically"

**Solutions:**
1. Ensure GeoServer is running and accessible
2. Check that REST API is enabled
3. Verify installation paths in config file
4. Check file permissions on installation directory

### Configuration Files Not Found

**Problem:** "server.xml not found"

**Solutions:**
1. Verify `installPath` in `config/upgrade-config.json`
2. Check that Tomcat is installed
3. Ensure paths use correct separators for your OS

### Missing Extensions

**Problem:** Extensions not detected

**Solutions:**
1. Run with `-AnalysisDepth Deep`
2. Check that `webapps/geoserver/WEB-INF/lib` exists
3. Verify extensions are actually installed (JAR files present)

## Output Examples

### Console Output
```
================================================================================
  CONFIGURATION ANALYSIS REPORT
================================================================================

Analysis Summary
  Analysis Depth: Standard
  Timestamp: 2024-01-15 14:30:22
  Total Issues: 5
    - Critical: 1
    - High: 2
    - Medium: 1
    - Low: 1

  Recommendation: CAUTION - Review and address high priority issues

Current vs Target Versions
  GeoServer: 2.23.2 → 2.25.0
  Tomcat: 9.0.65 → 9.0.80
  Java: 8 → 11

GeoServer Breaking Changes
  [CRITICAL] Java Version: Minimum Java version raised to 11
    Impact: Java 8 installations will fail to start
    Fix: Upgrade Java to version 11 or higher before upgrading GeoServer

  [HIGH] Security: Security subsystem refactored - custom auth filters need migration
    Impact: Custom authentication providers will not load
    Fix: Migrate custom auth filters to new security API
```

### HTML Report Preview

The HTML report includes:
- 📊 Visual dashboard with statistics
- 🎨 Color-coded severity indicators
- 📋 Detailed issue breakdown
- ✅ Step-by-step remediation guidance
- 📦 Extension compatibility matrix
- ⚡ Performance recommendations

## Related Documentation

- [Upgrade Procedures](./UPGRADE-PROCEDURES.md)
- [Rollback Procedures](./ROLLBACK-PROCEDURES.md)
- [Testing Strategy](./TESTING-STRATEGY.md)
- [Configuration Management](./CONFIGURATION-MANAGEMENT.md)

## Support

For issues or questions:
1. Check this documentation
2. Review analysis report recommendations
3. Consult GeoServer/Tomcat official migration guides
4. Review repository issues
