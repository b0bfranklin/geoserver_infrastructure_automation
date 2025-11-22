# GeoServer Infrastructure Automation Suite - Beginner's Guide

## 📋 Table of Contents

1. [Introduction](#introduction)
2. [Before You Start - Critical Safety Steps](#before-you-start---critical-safety-steps)
3. [Understanding Your Environment](#understanding-your-environment)
4. [Component Overview](#component-overview)
5. [Step-by-Step: Your First Upgrade](#step-by-step-your-first-upgrade)
6. [Testing and Verification](#testing-and-verification)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Introduction

Welcome to the GeoServer Infrastructure Automation Suite! This guide will walk you through using this automation toolkit safely and effectively, even if you're new to GeoServer administration or PowerShell scripting.

### What This Tool Does

This suite automates the complex process of:
- Upgrading GeoServer, Tomcat, Java, and related components
- Analyzing configurations for compatibility issues
- Creating backups and restore points
- Testing infrastructure health
- Rolling back failed upgrades

### Who Should Use This Guide

- System administrators new to GeoServer
- GIS administrators performing their first upgrade
- Anyone who wants a safety-first approach to automation
- Teams who need standardized procedures

### What You'll Need

- **Time**: 2-4 hours for first upgrade (including reading this guide)
- **Access**: Administrator access to the server
- **Backup**: External storage for backups (~10GB+ recommended)
- **Testing**: Ability to test GeoServer after changes
- **Support**: Contact info for your GIS applications team

---

## Before You Start - Critical Safety Steps

⚠️ **READ THIS SECTION COMPLETELY BEFORE PROCEEDING** ⚠️

### 🛑 STOP! Take These Safety Steps First

#### Step 1: Create a VM Snapshot (If Using Virtual Machine)

**⚠️ CRITICAL - DO THIS NOW!**

If your GeoServer runs in a virtual machine (VMware, Hyper-V, VirtualBox, etc.):

```
✅ Create VM snapshot with name: "Pre-Upgrade-$(Get-Date -Format 'yyyyMMdd')"
✅ Document snapshot name and location
✅ Verify snapshot completed successfully
✅ Test snapshot restore process on test VM (if available)
```

**Why**: VM snapshots allow instant rollback of entire system if something goes wrong.

**How**:
- **VMware**: Right-click VM → Snapshots → Take Snapshot
- **Hyper-V**: Hyper-V Manager → Checkpoint
- **VirtualBox**: Machine → Take Snapshot

#### Step 2: Backup Configuration Files

**⚠️ MANDATORY - DO NOT SKIP!**

Copy these directories to external storage **RIGHT NOW**:

```powershell
# Create backup directory
$backupRoot = "E:\GeoServer-Backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -Path $backupRoot -ItemType Directory -Force

# Backup Tomcat configuration
Copy-Item "C:\Apache\Tomcat\conf" -Destination "$backupRoot\tomcat-conf" -Recurse

# Backup GeoServer data directory
Copy-Item "E:\GeoServerData" -Destination "$backupRoot\geoserver-data" -Recurse

# Backup Apache configuration (if applicable)
Copy-Item "C:\Apache\httpd\conf" -Destination "$backupRoot\apache-conf" -Recurse

# Backup PostgreSQL data (if using PostgreSQL)
# Option 1: File system copy (requires PostgreSQL stopped)
Copy-Item "C:\PostgreSQL\data" -Destination "$backupRoot\postgresql-data" -Recurse

# Option 2: Database dump (preferred - doesn't require stopping service)
& "C:\PostgreSQL\bin\pg_dumpall.exe" -U postgres > "$backupRoot\postgres-dump.sql"

# Document what was backed up
@"
Backup created: $(Get-Date)
Tomcat Config: $backupRoot\tomcat-conf
GeoServer Data: $backupRoot\geoserver-data
Apache Config: $backupRoot\apache-conf
PostgreSQL: $backupRoot\postgresql-data
"@ | Set-Content "$backupRoot\BACKUP-MANIFEST.txt"

Write-Host "✓ Backups saved to: $backupRoot" -ForegroundColor Green
```

**Verify Backups**:
```powershell
# Check backup size
Get-ChildItem $backupRoot -Recurse | Measure-Object -Property Length -Sum |
    Select-Object @{Name="SizeMB";Expression={[math]::Round($_.Sum/1MB,2)}}

# Verify key files exist
Test-Path "$backupRoot\tomcat-conf\server.xml"  # Should be True
Test-Path "$backupRoot\geoserver-data\global.xml"  # Should be True
```

#### Step 3: Document Current State

Create a "known good" baseline:

```powershell
# Document current versions
$manifest = @{
    Date = Get-Date
    GeoServerVersion = "Run: http://localhost:8080/geoserver/web/ and check version"
    TomcatVersion = "Check: C:\Apache\Tomcat\bin\version.bat"
    JavaVersion = java -version 2>&1 | Select-Object -First 1
    ServiceStatus = @{
        Tomcat = (Get-Service -Name Tomcat*).Status
        PostgreSQL = (Get-Service -Name postgresql*).Status
    }
}

$manifest | ConvertTo-Json | Set-Content "$backupRoot\SYSTEM-MANIFEST.json"
```

#### Step 4: Verify Application Access

Test that everything works **before** starting:

```powershell
# Test GeoServer web interface
Start-Process "http://localhost:8080/geoserver/web/"

# Test WMS service
Start-Process "http://localhost:8080/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities"

# Create checklist
@"
VERIFY THESE WORK NOW (before upgrade):
☐ GeoServer web admin loads
☐ Can login to admin interface
☐ Layer preview shows maps
☐ Your custom application works
☐ Map tiles load in client apps
☐ No errors in Tomcat logs
"@ | Set-Content "$backupRoot\PRE-UPGRADE-CHECKLIST.txt"

notepad "$backupRoot\PRE-UPGRADE-CHECKLIST.txt"
```

**✅ CHECK**: Go through this checklist and verify everything works!

#### Step 5: Schedule Downtime

⚠️ **DO NOT upgrade production during business hours!**

Recommended maintenance window:
- **Duration**: 4-6 hours minimum
- **Timing**: Weekend or evening
- **Notifications**: Email all users 48 hours in advance
- **Rollback time**: Reserve last 1-2 hours for rollback if needed

---

## Understanding Your Environment

### What Components Do You Have?

Run this script to understand your environment:

```powershell
# Environment discovery script
Write-Host "🔍 Discovering GeoServer Environment..." -ForegroundColor Cyan

# Check Java
Write-Host "`n📦 Java:" -ForegroundColor Yellow
java -version 2>&1 | Select-Object -First 3

# Check Tomcat
Write-Host "`n🐈 Tomcat:" -ForegroundColor Yellow
$tomcatService = Get-Service -Name Tomcat* -ErrorAction SilentlyContinue
if ($tomcatService) {
    Write-Host "  Service: $($tomcatService.Name) - Status: $($tomcatService.Status)"
    $tomcatPath = "C:\Apache\Tomcat"  # Adjust if different
    if (Test-Path "$tomcatPath\bin\version.bat") {
        & "$tomcatPath\bin\version.bat"
    }
} else {
    Write-Host "  ⚠️ Tomcat service not found" -ForegroundColor Red
}

# Check PostgreSQL
Write-Host "`n🐘 PostgreSQL:" -ForegroundColor Yellow
$pgService = Get-Service -Name postgresql* -ErrorAction SilentlyContinue
if ($pgService) {
    Write-Host "  Service: $($pgService.Name) - Status: $($pgService.Status)"
} else {
    Write-Host "  ⚠️ PostgreSQL not found (may not be installed locally)" -ForegroundColor Gray
}

# Check GeoServer
Write-Host "`n🗺️ GeoServer:" -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8080/geoserver/rest/about/version.json" -UseBasicParsing -TimeoutSec 5
    Write-Host "  Version detected from REST API"
} catch {
    Write-Host "  ⚠️ GeoServer not responding (may be stopped)" -ForegroundColor Yellow
}

Write-Host "`n✓ Discovery complete" -ForegroundColor Green
```

### File Locations to Know

Common installation paths (yours may differ):

| Component | Common Path | Configuration Files |
|-----------|-------------|---------------------|
| **Tomcat** | `C:\Apache\Tomcat` | `conf\server.xml`, `conf\web.xml` |
| **GeoServer Data** | `E:\GeoServerData` or `C:\ProgramData\GeoServer\Data` | `global.xml`, `logging.xml` |
| **Java** | `C:\Program Files\Java\jdk-11` | (none - binary only) |
| **PostgreSQL** | `C:\Program Files\PostgreSQL\14` | `data\postgresql.conf` |
| **Logs** | `C:\GeoServerLogs` or `C:\Apache\Tomcat\logs` | `catalina.out`, `geoserver.log` |

---

## Component Overview

### Main Scripts - What They Do

#### 1. **Invoke-ConfigurationAnalysis.ps1** 📊
**What it does**: Analyzes your current setup and tells you what will break during upgrade.

**When to use**: **ALWAYS run this FIRST** before any upgrade.

**Example**:
```powershell
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 `
    -TargetGeoServerVersion "2.25.0" `
    -AnalysisDepth Standard `
    -OutputFormat All
```

**Output**: HTML report showing:
- ✅ Things that will work
- ⚠️ Things that might break
- 🔴 Things that WILL break
- 💡 How to fix each issue

#### 2. **Backup-GeoServerEnvironment.ps1** 💾
**What it does**: Creates complete backup of GeoServer, Tomcat configs, and data.

**When to use**: Before every upgrade (automated by upgrade script).

**Example**:
```powershell
.\scripts\core\Backup-GeoServerEnvironment.ps1 `
    -BackupName "pre-upgrade-2.25" `
    -Compress
```

**Output**: ZIP file with everything needed to restore.

#### 3. **Invoke-GeoServerUpgrade.ps1** 🚀
**What it does**: Performs the actual upgrade with safety checks.

**When to use**: After analysis, after backups, during maintenance window.

**Example**:
```powershell
.\scripts\core\Invoke-GeoServerUpgrade.ps1 `
    -Component All `
    -AutoRollback
```

**Output**: Upgraded system (or rolled back if failed).

#### 4. **Invoke-BaselineTests.ps1** ✅
**What it does**: Tests that everything still works after upgrade.

**When to use**:
- Before upgrade (save baseline)
- After upgrade (compare to baseline)

**Example**:
```powershell
# Before upgrade
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode SaveBaseline `
    -BaselineName "pre-upgrade-2.25"

# After upgrade
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode CompareBaseline `
    -BaselineName "pre-upgrade-2.25" `
    -GenerateChecklist `
    -EmailRecipients "team@example.com"
```

**Output**: Test report + email checklist for manual verification.

#### 5. **Restore-GeoServerEnvironment.ps1** ⏮️
**What it does**: Rolls back to previous version if upgrade fails.

**When to use**: Only if upgrade fails and you need to go back.

**Example**:
```powershell
.\scripts\core\Restore-GeoServerEnvironment.ps1 `
    -BackupPath "E:\Backups\pre-upgrade-2.25.zip"
```

**Output**: System restored to pre-upgrade state.

---

## Step-by-Step: Your First Upgrade

### Phase 1: Preparation (Day 1-2)

#### 1. Read Documentation

```powershell
# Open all relevant docs
explorer docs\BEGINNERS-GUIDE.md
explorer docs\CONFIGURATION-ANALYSIS.md
explorer docs\TESTING-PROCEDURES.md
```

**Time**: 1-2 hours
**Goal**: Understand what will happen

#### 2. Configure the Tool

```powershell
# Copy template to actual config
Copy-Item config\upgrade-config.json.template config\upgrade-config.json

# Edit configuration file
notepad config\upgrade-config.json
```

**Update these settings**:
```json
{
  "components": {
    "geoserver": {
      "installPath": "C:\\Apache\\Tomcat",  // ← YOUR path
      "dataDirectory": "E:\\GeoServerData",  // ← YOUR path
      "port": 8080  // ← YOUR port
    },
    "tomcat": {
      "installPath": "C:\\Apache\\Tomcat",  // ← YOUR path
      "serviceName": "Tomcat9"  // ← YOUR service name
    }
  },
  "notifications": {
    "email": {
      "enabled": true,
      "recipients": ["you@example.com"],  // ← YOUR email
      "smtpServer": "smtp.example.com"  // ← YOUR SMTP server
    }
  }
}
```

**Verify**:
```powershell
# Test configuration loads
Get-Content config\upgrade-config.json | ConvertFrom-Json
```

#### 3. Run Initial Analysis

```powershell
# Analyze current setup
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 `
    -TargetGeoServerVersion "2.25.0" `
    -AnalysisDepth Deep `
    -CheckSecurity `
    -CheckPerformance `
    -OutputFormat All
```

**Review the HTML report**:
```powershell
# Open latest analysis report
explorer reports\configuration-analysis-*.html
```

**What to look for**:
- 🔴 **CRITICAL** issues - Must fix before upgrading
- ⚠️ **HIGH** issues - Should fix before upgrading
- 💡 **MEDIUM/LOW** - Can fix after

#### 4. Fix Critical Issues

If analysis found Java version problems:
```powershell
# Upgrade Java first
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion "11.0.20"
```

If analysis found config problems:
```powershell
# Generate automated fixes
.\scripts\utilities\New-AutomatedFixScript.ps1

# Review generated scripts
explorer generated-fixes\

# Run each fix script manually
.\generated-fixes\Fix-TomcatDeprecatedConnectors.ps1
```

#### 5. Create Test Environment (Highly Recommended)

If possible, test on non-production first:

```powershell
# Clone VM or restore to test server
# Run through entire upgrade on test
# Verify everything works
# Document any issues
# Fix issues in test
# Then do production
```

### Phase 2: Pre-Upgrade Day (Day of Upgrade - Before Maintenance Window)

#### 6. Final Verification

```powershell
# Verify all services running
Get-Service -Name Tomcat*, postgresql* | Format-Table Name, Status

# Verify GeoServer accessible
Start-Process "http://localhost:8080/geoserver/web/"

# Save baseline tests
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode SaveBaseline `
    -BaselineName "production-$(Get-Date -Format 'yyyyMMdd')" `
    -TestProfile Comprehensive
```

#### 7. Create Backups

⚠️ **CRITICAL CHECKPOINT**

```powershell
# Create comprehensive backup
.\scripts\core\Backup-GeoServerEnvironment.ps1 `
    -BackupName "pre-upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
    -IncludeLogs `
    -Compress

# VERIFY backup created successfully
$backup = Get-ChildItem E:\Backups | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Latest backup: $($backup.Name) - Size: $([math]::Round($backup.Length/1MB,2))MB"

# Test backup integrity
if ($backup.Extension -eq '.zip') {
    Expand-Archive -Path $backup.FullName -DestinationPath "C:\Temp\backup-test" -Force
    Write-Host "✓ Backup integrity verified" -ForegroundColor Green
}
```

**STOP! Verify**:
- ☐ Backup file exists
- ☐ Backup file size reasonable (>100MB typically)
- ☐ Backup can be extracted
- ☐ Key files present in backup (server.xml, global.xml)

#### 8. Notify Users

```powershell
# Send notification email
.\scripts\utilities\Send-EmailNotification.ps1 `
    -To "all-users@example.com" `
    -Subject "GeoServer Maintenance Starting in 1 Hour" `
    -Body "GeoServer will be offline from 10 PM to 2 AM for scheduled upgrade."
```

### Phase 3: Upgrade Execution (During Maintenance Window)

⏰ **Time Check**: Start of maintenance window

#### 9. Stop Services

```powershell
# Stop in correct order
Write-Host "Stopping services..." -ForegroundColor Yellow

# Stop Tomcat (includes GeoServer)
Stop-Service -Name Tomcat9
Start-Sleep -Seconds 30

# Verify stopped
Get-Service -Name Tomcat9
```

#### 10. Execute Upgrade

```powershell
# Run upgrade with auto-rollback
.\scripts\core\Invoke-GeoServerUpgrade.ps1 `
    -Component All `
    -AutoRollback `
    -WhatIf:$false  # Remove WhatIf to actually execute
```

**Watch for**:
- Each component upgrade status
- Any errors (highlighted in red)
- Backup confirmation
- Service restart confirmation

**Expected duration**: 30-60 minutes

#### 11. Monitor Upgrade

The script shows progress:
```
[INFO] Backing up current installation...
[SUCCESS] Backup created: E:\Backups\...
[INFO] Downloading GeoServer 2.25.0...
[INFO] Stopping Tomcat service...
[SUCCESS] Service stopped
[INFO] Upgrading GeoServer...
[INFO] Upgrading Tomcat...
[INFO] Starting services...
[SUCCESS] Services started
[INFO] Running health checks...
```

**If errors occur**: Script will automatically rollback if AutoRollback is enabled.

### Phase 4: Post-Upgrade Verification (Still in Maintenance Window)

#### 12. Run Health Checks

```powershell
# Comprehensive health check
.\scripts\core\Get-GeoServerHealth.ps1 `
    -OutputFormat All `
    -SendEmail
```

**Check output**:
- ✅ All services running
- ✅ GeoServer web admin accessible
- ✅ No errors in logs

#### 13. Run Baseline Comparison

```powershell
# Compare to pre-upgrade baseline
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode CompareBaseline `
    -BaselineName "production-$(Get-Date -Format 'yyyyMMdd')" `
    -TestProfile Comprehensive `
    -GenerateChecklist `
    -EmailRecipients "gis-team@example.com"
```

**Review comparison**:
- Identical: Good!
- Changed: Review what changed - is it expected?
- Failed: Investigate why

#### 14. Manual Verification

Open the email checklist and go through each item:

**Critical Checks**:
```
☐ GeoServer web admin loads
☐ Login works with existing credentials
☐ Layer list shows all layers
☐ Layer preview displays maps correctly
☐ WMS GetMap returns images
☐ WFS GetFeature returns data
☐ Your custom application works
☐ No errors in logs (check C:\GeoServerLogs\catalina.out)
```

**Test Each Item**:

1. **Web Admin**:
   ```
   Navigate to: http://localhost:8080/geoserver/web/
   Login with admin credentials
   Click "Layer Preview"
   Click "OpenLayers" on a layer
   Verify map displays
   ```

2. **WMS Test**:
   ```
   Browser: http://localhost:8080/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities
   Verify XML response
   No errors
   ```

3. **Your App**:
   ```
   Open your GIS application
   Refresh map layers
   Verify tiles load
   Test all map operations
   ```

#### 15. Check Logs

```powershell
# View recent errors
Get-Content C:\GeoServerLogs\catalina.out -Tail 100 | Select-String -Pattern "ERROR|SEVERE|Exception"

# If no errors, good!
# If errors found, investigate
```

### Phase 5: Go-Live or Rollback Decision

⚠️ **DECISION POINT**

**If everything passes**: Proceed to Phase 6 (Go-Live)

**If failures found**:

```powershell
# ROLLBACK!
.\scripts\core\Restore-GeoServerEnvironment.ps1 `
    -BackupPath "E:\Backups\pre-upgrade-*.zip"

# Verify rollback worked
.\scripts\utilities\Invoke-BaselineTests.ps1 -Mode TestOnly

# Notify users
.\scripts\utilities\Send-EmailNotification.ps1 `
    -To "all-users@example.com" `
    -Subject "GeoServer Maintenance Rolled Back" `
    -Body "Upgrade encountered issues. Rolled back to previous version. Service restored."
```

### Phase 6: Go-Live (If Successful)

#### 16. Enable Production Access

```powershell
# Final verification
Get-Service Tomcat9 | Format-List Name, Status
Invoke-WebRequest "http://localhost:8080/geoserver/web/" -UseBasicParsing

# Notify users
.\scripts\utilities\Send-EmailNotification.ps1 `
    -To "all-users@example.com" `
    -Subject "GeoServer Maintenance Complete" `
    -Body "GeoServer upgrade successful. Service is now available."
```

#### 17. Monitor for 24 Hours

```powershell
# Check logs periodically
Get-Content C:\GeoServerLogs\catalina.out -Wait

# Monitor errors
Get-EventLog -LogName Application -Source Tomcat* -EntryType Error -Newest 50
```

#### 18. Document Upgrade

```powershell
$upgradeReport = @"
=== GeoServer Upgrade Report ===
Date: $(Get-Date)
Upgraded From: [Previous version]
Upgraded To: GeoServer 2.25.0

Components Upgraded:
- GeoServer: 2.24.2 → 2.25.0
- Tomcat: 9.0.65 → 9.0.80
- Java: 8 → 11

Issues Encountered:
[List any issues]

Resolution:
[How they were resolved]

Testing Results:
- Automated tests: PASS
- Manual verification: PASS
- User acceptance: PENDING

Performed by: [Your name]
"@

$upgradeReport | Set-Content "E:\Backups\UPGRADE-REPORT-$(Get-Date -Format 'yyyyMMdd').txt"
```

---

## Testing and Verification

### Automated Tests

The baseline testing system provides comprehensive automated testing:

#### Save Known-Good Baseline

**When**: After initial installation or after verifying current system works perfectly.

```powershell
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode SaveBaseline `
    -BaselineName "known-good-production" `
    -TestProfile Comprehensive
```

This creates a baseline file in `test-baselines/` directory.

#### Compare After Changes

**When**: After any upgrade, configuration change, or troubleshooting.

```powershell
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode CompareBaseline `
    -BaselineName "known-good-production" `
    -TestProfile Comprehensive
```

**Interpretation**:
- **Identical**: Test result matches baseline - Good!
- **Changed**: Result different from baseline - Investigate why
- **Failed**: Test that passed before now fails - Problem!
- **New**: Test added since baseline - Normal

#### Custom Tests

Create your own tests for your specific environment:

```powershell
# Copy template
Copy-Item config\custom-tests.json.template config\custom-tests.json

# Edit with your tests
notepad config\custom-tests.json
```

**Example custom test**:
```json
{
  "name": "My Custom WMS Layer",
  "category": "Custom-Layers",
  "type": "HTTP",
  "url": "http://localhost:8080/geoserver/myworkspace/wms?service=WMS&version=1.3.0&request=GetMap&layers=myworkspace:mylayer&...",
  "expectedStatusCode": 200,
  "critical": true
}
```

**Run with custom tests**:
```powershell
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -CustomTestsPath "config\custom-tests.json" `
    -Mode TestOnly
```

### Manual Testing Checklist

#### Web Interface Tests

1. **Admin Console**
   ```
   URL: http://localhost:8080/geoserver/web/

   ☐ Page loads (no errors)
   ☐ Login works
   ☐ Dashboard shows server status
   ☐ Layers page lists all layers
   ☐ Stores page shows datastores
   ☐ Workspaces page accessible
   ☐ Security settings accessible
   ☐ No JavaScript errors (press F12, check Console)
   ```

2. **Layer Preview**
   ```
   Navigate: Layer Preview page

   ☐ Layer list populates
   ☐ Click "OpenLayers" on sample layer
   ☐ Map displays correctly
   ☐ Can zoom in/out
   ☐ Can pan
   ☐ Feature info works (click on map)
   ```

3. **Layer Configuration**
   ```
   ☐ Can edit layer settings
   ☐ Can modify styles
   ☐ Can save changes
   ☐ Changes persist after refresh
   ```

#### OGC Service Tests

**WMS (Web Map Service)**:
```
GetCapabilities:
http://localhost:8080/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities

☐ Returns XML document
☐ Lists all layers
☐ No error messages

GetMap:
http://localhost:8080/geoserver/wms?service=WMS&version=1.3.0&request=GetMap&layers=topp:states&styles=&bbox=-124.73142200000001,24.955967,-66.969849,49.371735&width=768&height=330&srs=EPSG:4326&format=image/png

☐ Returns PNG image
☐ Image displays map correctly
☐ No visual corruption
```

**WFS (Web Feature Service)**:
```
GetCapabilities:
http://localhost:8080/geoserver/wfs?service=WFS&version=2.0.0&request=GetCapabilities

☐ Returns XML document
☐ Lists feature types
☐ No errors

GetFeature:
http://localhost:8080/geoserver/wfs?service=WFS&version=2.0.0&request=GetFeature&typeName=topp:states&maxFeatures=10&outputFormat=application/json

☐ Returns JSON/GML
☐ Contains feature data
☐ Attributes present and correct
```

#### Application Integration Tests

Test your custom applications that use GeoServer:

```
☐ Application connects to GeoServer
☐ Map layers load
☐ User interactions work (zoom, pan, identify)
☐ Search/query functions work
☐ Data editing works (if applicable)
☐ Printing/export works
☐ No JavaScript console errors
☐ Performance acceptable
```

#### Performance Tests

```powershell
# Response time test
Measure-Command {
    Invoke-WebRequest "http://localhost:8080/geoserver/wms?service=WMS&version=1.3.0&request=GetMap&..." -UseBasicParsing
}

# Should be under 5 seconds for most maps
```

Manual checks:
```
☐ Web admin loads in < 2 seconds
☐ Layer preview loads in < 3 seconds
☐ Map tiles load quickly (< 1 second)
☐ WFS queries return in reasonable time
☐ No timeouts under normal load
```

#### Data Integrity Tests

```
☐ Layer count matches pre-upgrade
☐ Feature counts match pre-upgrade
☐ Attribute values unchanged
☐ Spatial extents correct
☐ Styles render identically
☐ Symbolization unchanged
☐ Labels display correctly
```

**Verify layer count**:
```powershell
# Get layer count via REST API
$response = Invoke-RestMethod "http://localhost:8080/geoserver/rest/layers.json" -Headers @{Authorization=("Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:geoserver")))}
$response.layers.layer.Count

# Compare to your documented count
```

#### Security Tests

```
☐ Authentication works
☐ LDAP integration functional (if used)
☐ Role-based access works
☐ Layer security enforced
☐ Service security enforced
☐ REST API requires authentication
☐ Unauthorized access properly denied
```

### Email Checklist Feature

Generate and email checklist to your team:

```powershell
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -GenerateChecklist `
    -EmailRecipients "gis-team@example.com,qa-team@example.com,manager@example.com" `
    -TestProfile Comprehensive
```

**Email contains**:
- Automated test results summary
- Detailed test results table
- Manual verification checklist
- Instructions for completion
- Space for notes and issues

**Team members should**:
1. Review automated results
2. Perform manual checks
3. Mark each item as completed
4. Reply to email with results and any issues

---

## Troubleshooting

### Common Issues and Solutions

#### Issue: "Configuration file not found"

**Symptom**:
```
Configuration file not found: C:\...\config\upgrade-config.json
```

**Solution**:
```powershell
# Copy template to config
Copy-Item config\upgrade-config.json.template config\upgrade-config.json

# Edit paths for your environment
notepad config\upgrade-config.json
```

#### Issue: Upgrade fails with "Service did not start"

**Symptom**:
```
[ERROR] Tomcat service failed to start
```

**Solution**:
```powershell
# Check Tomcat logs for actual error
Get-Content C:\Apache\Tomcat\logs\catalina.out -Tail 50

# Common causes:
# 1. Port already in use
Get-NetTCPConnection -LocalPort 8080  # Check if port 8080 in use

# 2. Java version mismatch
java -version  # Verify Java version matches requirement

# 3. Configuration syntax error
# Check server.xml for XML syntax errors

# 4. Permissions
# Verify Tomcat service account has read/write to install directory
```

#### Issue: "Tests failing after upgrade"

**Symptom**:
```
[FAIL] WMS GetCapabilities - HTTP 500 Internal Server Error
```

**Investigation**:
```powershell
# 1. Check service status
Get-Service Tomcat9

# 2. Check logs
Get-Content C:\GeoServerLogs\geoserver.log -Tail 100 | Select-String "ERROR"

# 3. Check GeoServer admin
# Navigate to: http://localhost:8080/geoserver/web/
# Look for error messages

# 4. Test basic connectivity
Invoke-WebRequest "http://localhost:8080/geoserver/web/" -UseBasicParsing

# 5. Check data directory
Test-Path E:\GeoServerData\global.xml  # Should exist
```

#### Issue: Rollback needed

**When**: Something went wrong, need to go back

**Solution**:
```powershell
# List available backups
Get-ChildItem E:\Backups | Sort-Object LastWriteTime -Descending

# Restore from most recent backup
.\scripts\core\Restore-GeoServerEnvironment.ps1 `
    -BackupPath "E:\Backups\pre-upgrade-20240115-120000.zip" `
    -RestoreComponents All

# Verify restoration
.\scripts\utilities\Invoke-BaselineTests.ps1 -Mode TestOnly

# If still problems, check VM snapshot
# Revert VM to snapshot taken before upgrade
```

#### Issue: "Slow performance after upgrade"

**Symptoms**:
- Maps load slowly
- WFS queries timeout
- High memory usage

**Solutions**:

1. **Check JVM settings**:
```powershell
# Edit setenv.bat/sh to optimize JVM
notepad C:\Apache\Tomcat\bin\setenv.bat
```

Add:
```batch
set CATALINA_OPTS=-Xms2G -Xmx4G -XX:+UseG1GC -XX:MaxGCPauseMillis=200
```

2. **Check GeoWebCache**:
```
Navigate to: http://localhost:8080/geoserver/gwc/
Verify tile cache is enabled
Clear cache and regenerate tiles
```

3. **Check Tomcat connector**:
```powershell
# Edit server.xml
notepad C:\Apache\Tomcat\conf\server.xml
```

Verify connector has:
```xml
<Connector port="8080"
           maxThreads="200"
           minSpareThreads="25"
           connectionTimeout="20000" />
```

4. **Run performance analysis**:
```powershell
.\scripts\utilities\Invoke-ConfigurationAnalysis.ps1 `
    -CheckPerformance `
    -OutputFormat HTML
```

Review performance recommendations in report.

---

## Best Practices

### 1. Test in Non-Production First

**Always** test upgrades on a test/staging environment before production:

```
Test Environment → Staging → Production
```

### 2. Backup Rotation

Keep multiple backups:

```powershell
# Weekly backups
Register-ScheduledTask -TaskName "GeoServer-WeeklyBackup" `
    -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am) `
    -Action (New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File C:\...\Backup-GeoServerEnvironment.ps1")

# Retention: Keep 4 weeks of backups
# Manually: Delete backups older than 30 days
Get-ChildItem E:\Backups -Filter "*.zip" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item
```

### 3. Document Everything

Keep a maintenance log:

```
Date: 2024-01-15
Action: Upgraded GeoServer 2.24 → 2.25
Performed by: John Smith
Duration: 2 hours
Issues: None
Testing: All passed
Notes: Smooth upgrade, no problems
```

### 4. Regular Health Checks

Schedule automated health checks:

```powershell
# Daily health check
.\scripts\core\Get-GeoServerHealth.ps1 `
    -OutputFormat HTML `
    -SendEmail

# Weekly baseline comparison
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode CompareBaseline `
    -BaselineName "known-good" `
    -EmailRecipients "monitoring@example.com"
```

### 5. Stay Informed

Monitor for updates:

```powershell
# Check for version updates weekly
.\scripts\utilities\Test-VersionUpdates.ps1 `
    -OutputFormat HTML `
    -SendEmail
```

Subscribe to:
- GeoServer mailing list
- Security advisory feeds
- Tomcat security announcements

### 6. Maintenance Windows

Establish regular maintenance windows:

```
Monthly: First Sunday, 10 PM - 2 AM
- Apply non-critical updates
- Performance optimization
- Log review

Quarterly: Last Sunday, 10 PM - 6 AM
- Major version upgrades
- OS patches
- Comprehensive testing
```

### 7. Change Management

For production systems:

```
1. Submit change request (1 week before)
2. Get approval from stakeholders
3. Schedule maintenance window
4. Notify users (48 hours before)
5. Execute change
6. Document results
7. Post-implementation review
```

### 8. Disaster Recovery Plan

Document recovery procedures:

```markdown
# Disaster Recovery Plan

## Scenario: Complete GeoServer Failure

### Recovery Steps:
1. Restore VM from snapshot (15 min)
2. Or: Reinstall Tomcat (30 min)
3. Restore from backup (45 min)
4. Verify services (30 min)
5. Run baseline tests (15 min)

Total RTO: 2 hours 15 minutes

### Contacts:
- Primary: [Name] [Phone]
- Backup: [Name] [Phone]
- Vendor Support: [Number]
```

---

## Quick Reference

### Pre-Upgrade Checklist

```
☐ Read this guide completely
☐ Create VM snapshot
☐ Backup configuration files
☐ Backup data directory
☐ Document current versions
☐ Test current functionality
☐ Schedule maintenance window
☐ Notify users
☐ Run configuration analysis
☐ Fix critical issues
☐ Save baseline tests
☐ Review upgrade plan
☐ Have rollback plan ready
```

### Upgrade Day Checklist

```
☐ Verify backups current
☐ Stop services
☐ Run upgrade script
☐ Monitor upgrade progress
☐ Check for errors
☐ Start services
☐ Run health checks
☐ Run baseline comparison
☐ Manual verification
☐ Check logs
☐ Test applications
☐ Make go/no-go decision
☐ Notify users (success or rollback)
☐ Monitor for 24 hours
☐ Document results
```

### Emergency Rollback

```
1. Stop services
   Stop-Service Tomcat9

2. Restore backup
   .\scripts\core\Restore-GeoServerEnvironment.ps1 -BackupPath "..."

3. Verify restoration
   .\scripts\utilities\Invoke-BaselineTests.ps1 -Mode TestOnly

4. Notify users

5. Document issues

6. Plan re-attempt
```

---

## Getting Help

### Before Contacting Support

Gather this information:

```powershell
# System info
Get-ComputerInfo | Select-Object WindowsVersion, OsHardwareAbstractionLayer

# Java version
java -version

# Service status
Get-Service Tomcat*, postgresql*

# Recent errors
Get-Content C:\GeoServerLogs\catalina.out -Tail 100 | Select-String "ERROR"

# Recent event logs
Get-EventLog -LogName Application -EntryType Error -Newest 20

# Test results
Get-Content reports\test-results-*.json | ConvertFrom-Json
```

### Support Channels

1. **GeoServer Community**
   - Mailing list: geoserver-users@lists.sourceforge.net
   - Issue tracker: https://github.com/geoserver/geoserver/issues

2. **Tomcat Support**
   - User list: users@tomcat.apache.org
   - Docs: https://tomcat.apache.org/

3. **Commercial Support**
   - OSGeo: https://www.osgeo.org/service-providers/
   - Various GIS vendors

4. **This Tool**
   - Repository issues: [Your repo URL]
   - Documentation: docs/ directory

---

## Conclusion

You're now ready to safely upgrade your GeoServer infrastructure!

**Remember**:
- ✅ Always backup first
- ✅ Test in non-production
- ✅ Have a rollback plan
- ✅ Document everything
- ✅ Take your time

**Key Takeaways**:
1. Safety first - multiple backups
2. Analysis before action
3. Test, test, test
4. Monitor after changes
5. Document for next time

Good luck with your upgrade! 🚀

---

*Last Updated: 2024-01-15*
*Guide Version: 1.0.0*
