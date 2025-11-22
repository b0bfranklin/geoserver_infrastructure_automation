# Testing Procedures and Baseline Management

## Overview

This document describes the comprehensive testing framework for GeoServer infrastructure upgrades, including baseline testing, automated verification, and manual testing procedures.

## Table of Contents

1. [Baseline Testing](#baseline-testing)
2. [Automated Tests](#automated-tests)
3. [Custom Test Creation](#custom-test-creation)
4. [Manual Testing Checklist](#manual-testing-checklist)
5. [Email Reporting](#email-reporting)
6. [Integration with Upgrades](#integration-with-upgrades)

---

## Baseline Testing

### What is a Baseline?

A baseline is a "known-good" snapshot of your GeoServer infrastructure's test results. By comparing current test results against the baseline, you can immediately identify what changed after an upgrade or configuration change.

### Creating a Baseline

**When to create**:
- After fresh installation
- After verifying all functionality works
- Before any major changes

**How to create**:
```powershell
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode SaveBaseline `
    -BaselineName "production-baseline" `
    -TestProfile Comprehensive
```

**Output**: Baseline file saved in `test-baselines/production-baseline.json`

### Comparing Against Baseline

**When to compare**:
- After upgrades
- After configuration changes
- During troubleshooting
- As part of scheduled health checks

**How to compare**:
```powershell
.\scripts\utilities\Invoke-BaselineTests.ps1 `
    -Mode CompareBaseline `
    -BaselineName "production-baseline" `
    -TestProfile Comprehensive
```

**Interpretation of Results**:

| Status | Meaning | Action |
|--------|---------|--------|
| **Identical** | Test result matches baseline exactly | ✅ Good - no action needed |
| **PASS** | Test passed (no baseline comparison) | ✅ Good |
| **FAIL** | Test failed | 🔴 Investigate immediately |
| **CHANGED** | Result different from baseline | ⚠️ Verify change is expected |
| **NEW** | Test not in baseline | ℹ️ Normal for new tests |
| **MISSING** | Baseline test not run | ⚠️ Test may have been removed |

### Managing Multiple Baselines

You can maintain different baselines for different purposes:

```powershell
# Pre-upgrade baseline
.\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName "pre-upgrade-2.25"

# Post-upgrade baseline (becomes new production baseline)
.\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName "post-upgrade-2.25"

# Staging environment baseline
.\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName "staging-baseline"
```

**Best Practice**: Date your baselines
```powershell
$baselineName = "production-$(Get-Date -Format 'yyyyMMdd')"
.\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName $baselineName
```

---

## Automated Tests

### Standard Test Suites

The testing framework includes these standard tests:

#### Service Tests
- Tomcat service status
- PostgreSQL service status
- Service health verification

#### Web Interface Tests
- GeoServer web admin accessibility
- Login functionality
- Admin console responsiveness

#### OGC Service Tests
- WMS GetCapabilities
- WMS GetMap
- WFS GetCapabilities
- WFS GetFeature
- WCS GetCapabilities (Comprehensive profile)
- WPS GetCapabilities (Comprehensive profile)

#### Database Tests
- PostgreSQL connection
- Database query execution
- PostGIS availability

#### Performance Tests
- Response time monitoring
- Memory usage checks
- Service availability

#### API Tests
- REST API accessibility
- GeoWebCache status
- Version information retrieval

### Test Profiles

#### Quick Profile (30 seconds)
- Service status checks only
- Basic connectivity tests
- Critical functionality verification

```powershell
.\Invoke-BaselineTests.ps1 -TestProfile Quick
```

**Use when**: Quick health checks, automated monitoring

#### Standard Profile (2-3 minutes)
- All service tests
- Core OGC services
- Database connectivity
- Basic performance checks

```powershell
.\Invoke-BaselineTests.ps1 -TestProfile Standard
```

**Use when**: Regular testing, post-upgrade verification

#### Comprehensive Profile (5-10 minutes)
- All Standard tests
- Extended OGC services (WCS, WPS)
- Performance profiling
- Memory usage analysis
- Extension functionality

```powershell
.\Invoke-BaselineTests.ps1 -TestProfile Comprehensive
```

**Use when**: Major upgrades, detailed analysis, troubleshooting

---

## Custom Test Creation

### Why Create Custom Tests?

Standard tests cover GeoServer core functionality, but your environment likely has:
- Custom layers and services
- Specific WMS/WFS endpoints
- Integration with other applications
- Performance requirements
- Compliance needs

### Creating Custom Tests

1. **Copy the template**:
```powershell
Copy-Item config\custom-tests.json.template config\custom-tests.json
```

2. **Edit the file**:
```powershell
notepad config\custom-tests.json
```

3. **Add your tests** (see examples below)

4. **Run with custom tests**:
```powershell
.\Invoke-BaselineTests.ps1 -CustomTestsPath "config\custom-tests.json"
```

### Custom Test Types

#### HTTP Test
Test any HTTP endpoint:

```json
{
  "name": "My Custom WMS Layer",
  "category": "Custom-Layers",
  "type": "HTTP",
  "url": "http://localhost:8080/geoserver/myworkspace/wms?service=WMS&version=1.3.0&request=GetMap&layers=myworkspace:roads&styles=&bbox=-180,-90,180,90&width=768&height=384&srs=EPSG:4326&format=image/png",
  "expectedStatusCode": 200,
  "expectedContent": "PNG",
  "critical": true,
  "description": "Test custom roads layer rendering"
}
```

#### REST API Test
Test REST API endpoints:

```json
{
  "name": "My Workspace List",
  "category": "Custom-API",
  "type": "REST",
  "url": "http://localhost:8080/geoserver/rest/workspaces.json",
  "method": "GET",
  "expectedStatusCode": 200,
  "critical": false,
  "credentials": {
    "username": "admin",
    "password": "geoserver"
  }
}
```

#### Response Time Test
Ensure performance SLAs are met:

```json
{
  "name": "Large Dataset Performance",
  "category": "Performance",
  "type": "ResponseTime",
  "url": "http://localhost:8080/geoserver/wfs?service=WFS&version=2.0.0&request=GetFeature&typeName=mydata:large_dataset&maxFeatures=1000",
  "maxResponseTimeMs": 5000,
  "critical": false,
  "description": "Ensure large dataset queries complete under 5 seconds"
}
```

#### Application Integration Test
Test your custom applications:

```json
{
  "name": "Public Web Map Application",
  "category": "Integration",
  "type": "HTTP",
  "url": "https://maps.example.com/viewer",
  "expectedStatusCode": 200,
  "expectedContent": "Map Viewer",
  "critical": true,
  "description": "Verify public-facing map application loads"
}
```

#### Path Check Test
Verify file system requirements:

```json
{
  "name": "Custom Data Directory",
  "category": "FileSystem",
  "type": "PathCheck",
  "target": "S:\\GIS\\CustomData",
  "critical": true,
  "description": "Verify custom data directory is accessible"
}
```

#### Database Test
Test custom database objects:

```json
{
  "name": "Custom Database View",
  "category": "Database",
  "type": "Database",
  "target": "PostgreSQL",
  "query": "SELECT COUNT(*) FROM gis_schema.parcels;",
  "expectedResult": "> 0",
  "critical": false,
  "description": "Verify parcel view exists and has data"
}
```

### Custom Test Best Practices

1. **Use descriptive names**: "Production WMS - Parcels Layer" vs "Test 1"
2. **Set criticality appropriately**: Only mark truly critical services as `"critical": true`
3. **Add descriptions**: Helps future maintainers understand the test
4. **Include authentication**: For secured services
5. **Test at multiple levels**: Service, data, application integration
6. **Version control**: Keep `custom-tests.json` in source control

---

## Manual Testing Checklist

### Why Manual Testing?

Automated tests verify technical functionality, but manual testing validates:
- User experience
- Visual quality
- Complex workflows
- Business processes
- Compliance requirements

### Built-in Manual Checklists

The testing framework includes pre-defined manual verification categories:

1. **Visual Verification**
   - Web interfaces load correctly
   - Maps render properly
   - No visual corruption

2. **Data Publishing**
   - Can create/modify/delete resources
   - Configuration changes persist
   - Data integrity maintained

3. **OGC Services**
   - Correct data returned
   - Format compliance
   - Error handling

4. **Performance**
   - Acceptable response times
   - No degradation under load
   - Resource usage normal

5. **Data Integrity**
   - Layer counts match
   - Feature data correct
   - Spatial accuracy preserved

6. **Integration**
   - External apps function
   - Authentication works
   - APIs accessible

### Adding Custom Manual Tests

Edit `custom-tests.json`:

```json
{
  "manual_verification_steps": [
    {
      "category": "Emergency Services Integration",
      "items": [
        "911 dispatch system can query address locations",
        "Fire department can print emergency maps",
        "Police can view incident locations in real-time",
        "Emergency route planning works correctly"
      ]
    },
    {
      "category": "Public Portal",
      "items": [
        "Citizens can search property information",
        "Zoning queries return correct data",
        "Permit applications display properly",
        "Print function generates readable PDFs"
      ]
    }
  ]
}
```

---

## Email Reporting

### Automated Checklist Distribution

Send testing checklists to your team via email:

```powershell
.\Invoke-BaselineTests.ps1 `
    -GenerateChecklist `
    -EmailRecipients "gis-team@example.com,qa-team@example.com"
```

### Email Content

The email includes:

1. **Automated Test Summary**
   - Total tests run
   - Pass/fail counts
   - Changed items (if comparing to baseline)

2. **Detailed Test Results Table**
   - Each test with status
   - Error messages
   - Response times

3. **Manual Verification Checklist**
   - Standard categories
   - Custom categories (from custom-tests.json)
   - Checkbox format for easy completion

4. **Instructions**
   - How to complete the checklist
   - What to report
   - Who to contact

### Configuring Email Settings

In `custom-tests.json`:

```json
{
  "email_settings": {
    "default_recipients": [
      "gis-team@example.com",
      "operations@example.com"
    ],
    "cc_recipients": [
      "manager@example.com"
    ],
    "subject_prefix": "[GeoServer Testing]",
    "include_screenshots": false
  }
}
```

Then run without specifying recipients:
```powershell
.\Invoke-BaselineTests.ps1 -GenerateChecklist  # Uses default recipients
```

### Team Workflow

1. **After upgrade, automation runs tests**
2. **Email sent to GIS team with results**
3. **Team members complete manual verification**
4. **Team replies to email with completed checklist**
5. **Lead verifies all items checked**
6. **Upgrade approved or rolled back**

---

## Integration with Upgrades

### Pre-Upgrade Workflow

```powershell
# 1. Save baseline of current working system
.\Invoke-BaselineTests.ps1 `
    -Mode SaveBaseline `
    -BaselineName "pre-upgrade-$(Get-Date -Format 'yyyyMMdd')" `
    -TestProfile Comprehensive

# 2. Perform upgrade
.\Invoke-SafeUpgrade.ps1 -TargetGeoServerVersion "2.25.0"

# 3. Compare post-upgrade results
.\Invoke-BaselineTests.ps1 `
    -Mode CompareBaseline `
    -BaselineName "pre-upgrade-$(Get-Date -Format 'yyyyMMdd')" `
    -GenerateChecklist `
    -EmailRecipients "team@example.com"
```

### Automated Safe Upgrade

The `Invoke-SafeUpgrade.ps1` script automatically:

1. Runs configuration analysis
2. Saves pre-upgrade baseline
3. Executes upgrade
4. Compares post-upgrade to baseline
5. Generates and emails checklist

```powershell
.\scripts\core\Invoke-SafeUpgrade.ps1 `
    -TargetGeoServerVersion "2.25.0" `
    -EmailRecipients "team@example.com"
```

### Rollback Decision Tree

```
Post-Upgrade Tests
├── All CRITICAL tests pass?
│   ├── YES → Continue to manual verification
│   └── NO → IMMEDIATE ROLLBACK
├── More than 3 HIGH tests fail?
│   ├── YES → Evaluate for rollback
│   └── NO → Continue
├── Changes from baseline expected?
│   ├── YES → Document and continue
│   └── NO → Investigate before proceeding
└── Manual verification passed?
    ├── YES → Upgrade successful
    └── NO → Rollback
```

### Scheduled Testing

Set up automated baseline comparisons:

```powershell
.\Register-ScheduledMaintenance.ps1 -RegisterTask BaselineTest -ScheduleType Monthly
```

This will:
- Run monthly baseline comparison
- Email results to configured recipients
- Alert on unexpected changes
- Track system health over time

---

## Troubleshooting

### Issue: Tests Fail After Upgrade

**Steps**:
1. Check service status: `Get-Service Tomcat*, postgresql*`
2. Review logs: `Get-Content C:\GeoServerLogs\catalina.out -Tail 100`
3. Test basic connectivity: `Invoke-WebRequest http://localhost:8080/geoserver/web/`
4. Compare to baseline to see what changed
5. Review upgrade logs for errors

### Issue: Baseline Comparison Shows Many Changes

**Expected Changes**:
- Version numbers different
- New features available
- Performance improvements

**Unexpected Changes**:
- Services not responding
- Errors where none existed
- Data missing
- Configuration lost

**Action**: If unexpected changes, investigate before approving upgrade

### Issue: Email Not Sending

**Check**:
1. SMTP server configured: Check `config/upgrade-config.json`
2. Credentials correct
3. Network connectivity to SMTP server
4. Firewall allows SMTP traffic

---

## Best Practices

### 1. Baseline Management
- Create baseline after confirming system works perfectly
- Update baseline after successful major changes
- Keep dated baselines for historical reference
- Document what each baseline represents

### 2. Test Organization
- Group tests by criticality
- Use consistent naming conventions
- Document expected results
- Review and update tests regularly

### 3. Team Communication
- Email checklists to entire team
- Require confirmation from multiple team members
- Document test completion
- Store completed checklists for audit

### 4. Continuous Monitoring
- Schedule regular baseline comparisons
- Monitor for configuration drift
- Alert on unexpected changes
- Track trends over time

### 5. Documentation
- Keep test definitions in source control
- Document custom tests
- Explain why tests exist
- Update tests when requirements change

---

## Quick Reference

### Save Baseline
```powershell
.\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName "production-baseline"
```

### Compare to Baseline
```powershell
.\Invoke-BaselineTests.ps1 -Mode CompareBaseline -BaselineName "production-baseline"
```

### Run Tests Only (No Baseline)
```powershell
.\Invoke-BaselineTests.ps1 -Mode TestOnly -TestProfile Standard
```

### Generate Email Checklist
```powershell
.\Invoke-BaselineTests.ps1 -GenerateChecklist -EmailRecipients "team@example.com"
```

### Custom Tests
```powershell
.\Invoke-BaselineTests.ps1 -CustomTestsPath "config\custom-tests.json"
```

### Full Pre/Post Upgrade
```powershell
# Before
.\Invoke-BaselineTests.ps1 -Mode SaveBaseline -BaselineName "pre-upgrade"

# After
.\Invoke-BaselineTests.ps1 -Mode CompareBaseline -BaselineName "pre-upgrade" -GenerateChecklist -EmailRecipients "team@example.com"
```

---

*Last Updated: 2024-01-15*
*Version: 1.0.0*
