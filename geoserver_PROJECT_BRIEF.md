# GeoServer Infrastructure Automation Suite

## Project Overview

**Repository:** https://github.com/b0bfranklin/geoserver_infrastructure_automation  
**Platform:** Windows Server 2025  
**Primary Goal:** Create enterprise-grade automation for upgrading, testing, and maintaining GeoServer infrastructure with zero-downtime deployments.

**Business Value:**
- Reduce manual upgrade time from days to hours
- Eliminate human error in complex upgrades
- Enable repeatable, tested upgrade procedures
- Provide automated rollback capabilities
- Comprehensive testing framework for validation

## Target Environment

### Current Infrastructure
- **OS:** Windows Server 2025
- **Java:** OpenJDK/Corretto (version detection required)
- **Application Server:** Apache Tomcat 9.x (multiple instances)
- **GeoServer:** Version to be detected (target: latest stable)
- **Load Balancer:** Apache HTTP Server OR NGINX (dual support)
- **Databases:** 
  - PostgreSQL with PostGIS
  - Microsoft SQL Server
- **Architecture:** Clustered GeoServer instances with shared data directory

### Existing Documentation
The user has comprehensive existing documentation from February 2025 conversations covering:
- Complete installation procedures
- Testing methodologies  
- Verification scripts
- Security configurations
- Performance tuning guidelines

## Core Objectives

### 1. Automated Upgrade System
Create intelligent scripts that:
- Detect current versions of all components
- Determine upgrade paths
- Download appropriate versions
- Backup configurations automatically
- Execute upgrades with validation
- Rollback on failure

### 2. Comprehensive Testing Framework
Build testing suite that validates:
- WMS/WFS service functionality
- Layer rendering correctness
- Database connectivity (PostgreSQL/MSSQL)
- Performance benchmarks
- Security configurations
- Load balancer health

### 3. Safety & Reliability
Implement features for:
- Pre-upgrade system snapshots
- Configuration backups
- Automated rollback procedures
- Health checks at each stage
- Detailed logging
- Email notifications

### 4. Monitoring & Validation
Create tools for:
- Service health monitoring
- Performance baseline comparisons
- Resource utilization tracking
- Error detection and alerting

## Technical Requirements

### Programming Languages
- **Primary:** PowerShell 7.x (cross-platform compatible)
- **Secondary:** Python 3.11+ (for complex data processing)
- **Scripts:** Batch files for legacy compatibility
- **Configuration:** JSON, YAML for settings

### Key Dependencies
```powershell
# PowerShell Modules (install if missing)
- PSWindowsUpdate
- SqlServer (for MSSQL integration)
- Posh-SSH (for remote operations)

# Python Libraries (requirements.txt)
- requests (HTTP operations)
- psycopg2 (PostgreSQL connectivity)
- pyodbc (MSSQL connectivity)
- lxml (XML parsing for GeoServer configs)
- pyyaml (configuration management)
```

### External Tools Integration
- **JMeter:** Performance testing automation
- **cURL:** HTTP endpoint testing
- **Git:** Version control for configurations
- **7-Zip:** Archive management

## Detailed Feature Specifications

### Feature 1: Upgrade Orchestrator

**File:** `Invoke-GeoServerUpgrade.ps1`

**Capabilities:**
- Interactive and unattended modes
- Component detection (Java, Tomcat, GeoServer versions)
- Upgrade path determination
- Dependency checking
- Pre-upgrade validation
- Automated backup creation
- Step-by-step upgrade execution
- Post-upgrade verification
- Rollback on failure

**Parameters:**
```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Java','Tomcat','GeoServer','All')]
    [string]$Component = 'All',
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup,
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoRollback,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\config\upgrade-config.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)
```

**Configuration File:** `config/upgrade-config.json`
```json
{
  "environment": {
    "serverName": "GeoServer-Prod",
    "tomcatInstances": [
      {"name": "instance1", "port": 8080, "shutdownPort": 8005},
      {"name": "instance2", "port": 8081, "shutdownPort": 8006}
    ],
    "geoserverDataDir": "D:\\GeoServer\\data",
    "backupLocation": "E:\\Backups\\GeoServer"
  },
  "versions": {
    "targetJavaVersion": "17.0.9",
    "targetTomcatVersion": "9.0.85",
    "targetGeoServerVersion": "2.24.2"
  },
  "upgrade": {
    "enableAutoBackup": true,
    "enableAutoRollback": true,
    "maxRollbackAttempts": 3,
    "healthCheckRetries": 5,
    "healthCheckInterval": 30
  },
  "notifications": {
    "emailEnabled": true,
    "smtpServer": "smtp.example.com",
    "fromAddress": "geoserver-automation@example.com",
    "toAddress": "admin@example.com"
  }
}
```

**Workflow:**
1. Load configuration
2. Validate prerequisites
3. Detect current versions
4. Determine upgrade necessity
5. Create system snapshot
6. Backup configurations
7. Stop services gracefully
8. Execute upgrades
9. Update configurations
10. Start services
11. Run health checks
12. Validate functionality
13. Send notification
14. Generate report

### Feature 2: Testing Framework

**File:** `Invoke-GeoServerTests.ps1`

**Test Categories:**

#### A. Service Availability Tests
```powershell
# Test HTTP endpoints
Test-GeoServerEndpoint -Url "http://localhost:8080/geoserver"
Test-WMSCapabilities -Url "http://localhost:8080/geoserver/wms?request=GetCapabilities"
Test-WFSCapabilities -Url "http://localhost:8080/geoserver/wfs?request=GetCapabilities"
```

#### B. Database Connectivity Tests
```powershell
Test-PostgreSQLConnection -Server "db-server" -Database "gis_data"
Test-MSSQLConnection -Server "sql-server" -Database "geoserver_db"
Test-PostGISExtension -Server "db-server" -Database "gis_data"
```

#### C. Performance Tests
```powershell
# JMeter integration
Invoke-JMeterTest -TestPlan ".\tests\performance\load-test.jmx" -Threads 50 -Duration 300
```

#### D. Rendering Tests
```powershell
# Validate map rendering
Test-LayerRendering -Workspace "workspace1" -Layer "countries" -Format "image/png"
Test-StyleApplication -Workspace "workspace1" -Layer "roads" -Style "default_roads"
```

**JMeter Test Plans to Create:**
1. `tests/performance/baseline-load.jmx` - Normal load simulation
2. `tests/performance/stress-test.jmx` - High load stress testing
3. `tests/performance/endurance-test.jmx` - Long-duration stability

### Feature 3: Backup & Rollback System

**File:** `Backup-GeoServerEnvironment.ps1`

**Backup Components:**
- Tomcat configuration files (server.xml, web.xml, context.xml)
- GeoServer data directory
- GeoServer configuration (global.xml, security configs)
- Custom styles and fonts
- Database connection configurations
- SSL certificates
- Environment variables

**Backup Structure:**
```
E:\Backups\GeoServer\
├── 2025-11-17_140530\
│   ├── metadata.json
│   ├── tomcat\
│   │   ├── instance1\
│   │   └── instance2\
│   ├── geoserver\
│   │   ├── config\
│   │   └── data\
│   ├── databases\
│   │   └── connection-configs\
│   └── logs\
```

**Rollback File:** `Restore-GeoServerEnvironment.ps1`

**Rollback Capabilities:**
- List available backups
- Validate backup integrity
- Preview rollback changes
- Execute full or partial rollback
- Verify post-rollback health
- Generate rollback report

### Feature 4: Health Monitoring Dashboard

**File:** `Get-GeoServerHealth.ps1`

**Monitoring Metrics:**
- Service status (running/stopped)
- Port availability
- HTTP response codes
- Response times
- Memory usage
- CPU usage
- Disk space
- Database connections
- Active sessions
- Cache hit rates
- Error rates

**Output Formats:**
- Console (real-time)
- HTML report (detailed)
- JSON (for integration)
- Email summary

**Example HTML Report Layout:**
```html
<!DOCTYPE html>
<html>
<head>
    <title>GeoServer Health Report</title>
    <style>
        /* Bootstrap-like styling */
        .status-ok { color: green; }
        .status-warning { color: orange; }
        .status-error { color: red; }
    </style>
</head>
<body>
    <h1>GeoServer Infrastructure Health</h1>
    <section id="services">...</section>
    <section id="performance">...</section>
    <section id="resources">...</section>
</body>
</html>
```

### Feature 5: Configuration Manager

**File:** `Manage-GeoServerConfig.ps1`

**Capabilities:**
- Compare configurations across instances
- Detect configuration drift
- Synchronize configurations
- Validate XML/JSON configs
- Apply configuration templates
- Track configuration changes

## Project Structure

```
geoserver_infrastructure_automation/
├── README.md
├── PROJECT_BRIEF.md (this file)
├── LICENSE
├── .gitignore
├── requirements.txt (Python dependencies)
│
├── config/
│   ├── upgrade-config.json
│   ├── test-config.json
│   ├── notification-config.json
│   └── templates/
│       ├── server.xml.template
│       └── web.xml.template
│
├── scripts/
│   ├── core/
│   │   ├── Invoke-GeoServerUpgrade.ps1
│   │   ├── Backup-GeoServerEnvironment.ps1
│   │   ├── Restore-GeoServerEnvironment.ps1
│   │   └── Get-GeoServerHealth.ps1
│   │
│   ├── modules/
│   │   ├── GeoServer.psm1 (PowerShell module)
│   │   ├── TomcatManager.psm1
│   │   ├── DatabaseValidator.psm1
│   │   └── NotificationManager.psm1
│   │
│   ├── utilities/
│   │   ├── Download-Component.ps1
│   │   ├── Verify-Prerequisites.ps1
│   │   └── Send-EmailNotification.ps1
│   │
│   └── python/
│       ├── geoserver_api.py
│       ├── config_validator.py
│       └── performance_analyzer.py
│
├── tests/
│   ├── unit/
│   │   ├── Test-UpgradeScripts.ps1
│   │   └── Test-BackupRestore.ps1
│   │
│   ├── integration/
│   │   ├── Invoke-GeoServerTests.ps1
│   │   ├── Test-DatabaseConnectivity.ps1
│   │   └── Test-LoadBalancer.ps1
│   │
│   └── performance/
│       ├── baseline-load.jmx
│       ├── stress-test.jmx
│       └── endurance-test.jmx
│
├── docs/
│   ├── INSTALLATION.md
│   ├── USAGE.md
│   ├── TROUBLESHOOTING.md
│   ├── ARCHITECTURE.md
│   └── API_REFERENCE.md
│
├── logs/
│   └── .gitkeep
│
└── examples/
    ├── simple-upgrade.ps1
    ├── automated-testing.ps1
    └── scheduled-maintenance.ps1
```

## Success Criteria

### Must Have (MVP)
✅ Automated Tomcat upgrade with rollback  
✅ Automated GeoServer deployment  
✅ Configuration backup/restore  
✅ Basic health checks (HTTP, DB connectivity)  
✅ Service start/stop automation  
✅ Basic error logging  
✅ Installation documentation  

### Should Have (Polish)
✅ JMeter performance testing integration  
✅ HTML health report generation  
✅ Email notifications  
✅ Configuration drift detection  
✅ Multi-instance support  
✅ Comprehensive error handling  
✅ Detailed usage documentation  

### Nice to Have (Future)
⭐ GUI dashboard (optional web interface)  
⭐ Scheduled maintenance windows  
⭐ Automatic version checking  
⭐ Integration with monitoring systems (Prometheus/Grafana)  
⭐ Remote execution capabilities  

## Testing Requirements

### Unit Tests
- Each PowerShell function should have Pester tests
- Python functions should have pytest tests
- Minimum 70% code coverage

### Integration Tests
- Full upgrade cycle test (with rollback)
- Multi-instance deployment test
- Database connectivity validation
- Load balancer health check validation

### User Acceptance Tests
1. **Scenario 1:** Fresh Tomcat installation
2. **Scenario 2:** Upgrade existing Tomcat 9.0.65 → 9.0.85
3. **Scenario 3:** GeoServer deployment with existing data directory
4. **Scenario 4:** Failed upgrade with automatic rollback
5. **Scenario 5:** Performance testing suite execution
6. **Scenario 6:** Health monitoring report generation

## Documentation Requirements

### README.md
- Project overview
- Quick start guide
- Prerequisites
- Installation steps
- Basic usage examples
- Links to detailed docs

### INSTALLATION.md
- Detailed prerequisites
- Step-by-step installation
- Configuration file setup
- Dependency installation
- Verification steps

### USAGE.md
- Common use cases
- Command examples
- Parameter explanations
- Configuration options
- Best practices

### TROUBLESHOOTING.md
- Common errors and solutions
- Log file locations
- Debug mode instructions
- Recovery procedures
- Support contacts

### ARCHITECTURE.md
- System design overview
- Component interactions
- Workflow diagrams
- Extension points
- Security considerations

### API_REFERENCE.md
- Function documentation
- Parameter specifications
- Return values
- Usage examples
- Module exports

## Security Considerations

### Credentials Management
- Never hardcode credentials
- Support Windows Credential Manager
- Environment variable support
- Encrypted configuration files (optional)

### Logging
- Sanitize sensitive data in logs
- Separate error logs from audit logs
- Log rotation policies
- Secure log storage

### Network Security
- Support HTTPS for GeoServer connections
- Validate SSL certificates
- Configurable timeout values
- Support for proxy configurations

## Performance Targets

- **Upgrade time:** < 30 minutes for full stack
- **Backup time:** < 10 minutes for typical configuration
- **Rollback time:** < 15 minutes
- **Health check:** < 60 seconds
- **Test suite:** < 10 minutes for basic tests

## Error Handling Standards

### Logging Levels
```powershell
Write-LogEntry -Level "DEBUG" -Message "Detailed diagnostic information"
Write-LogEntry -Level "INFO" -Message "General informational messages"
Write-LogEntry -Level "WARNING" -Message "Warning messages for attention"
Write-LogEntry -Level "ERROR" -Message "Error messages"
Write-LogEntry -Level "CRITICAL" -Message "Critical failure messages"
```

### Exception Handling
- All public functions must have try-catch blocks
- Provide meaningful error messages
- Include remediation suggestions
- Preserve stack traces for debugging
- Log all exceptions

### Validation
- Validate all user inputs
- Check file existence before operations
- Verify network connectivity
- Validate configuration files
- Confirm service states

## Deployment Strategy

### Phase 1: Core Functionality (Week 1)
- Backup/restore scripts
- Service management
- Basic upgrade automation
- Health checks

### Phase 2: Testing Framework (Week 1)
- Integration tests
- Performance testing setup
- Validation scripts

### Phase 3: Polish & Documentation (Week 1)
- Error handling refinement
- Comprehensive documentation
- Example scripts
- User testing

## Dependencies & Prerequisites

### Required Software
- Windows Server 2019+ (tested on 2025)
- PowerShell 7.2+
- Python 3.11+
- Java JDK 17+
- Apache Tomcat 9.0+
- GeoServer 2.24+
- Git 2.40+

### Optional Software
- Apache JMeter 5.6+ (for performance testing)
- PostgreSQL 15+ with PostGIS
- Microsoft SQL Server 2022+
- NGINX or Apache HTTP Server

### Network Requirements
- Internet access for downloads (or local mirror)
- Access to database servers
- Administrative privileges on target servers

## Notes for Claude Code

### Code Style Preferences
- **PowerShell:** Follow Microsoft PowerShell Best Practices
- **Python:** Follow PEP 8 guidelines
- **Comments:** Inline for complex logic, function headers for all functions
- **Naming:** Verb-Noun for PowerShell, snake_case for Python

### Implementation Priorities
1. **Safety First:** Always implement backup before destructive operations
2. **Logging:** Comprehensive logging at all stages
3. **Validation:** Check inputs and state before proceeding
4. **User Experience:** Clear prompts and informative messages
5. **Idempotency:** Scripts should be safe to run multiple times

### Testing Approach
- Write functions to be testable (no hidden dependencies)
- Mock external dependencies in unit tests
- Provide sample data for testing
- Include both positive and negative test cases

### User Context
- User is experienced systems administrator
- Advanced cybersecurity knowledge
- Not a programmer but comfortable with scripts
- Prefers clear documentation over complexity
- Values reliability and safety over features

## Example Usage Scenarios

### Scenario 1: Simple Upgrade
```powershell
# Upgrade all components with defaults
.\Invoke-GeoServerUpgrade.ps1 -Component All

# Upgrade only Tomcat
.\Invoke-GeoServerUpgrade.ps1 -Component Tomcat

# Test upgrade without making changes
.\Invoke-GeoServerUpgrade.ps1 -Component All -WhatIf
```

### Scenario 2: Backup Before Maintenance
```powershell
# Create full backup
.\Backup-GeoServerEnvironment.ps1 -BackupPath "E:\Backups\GeoServer"

# Create backup with custom name
.\Backup-GeoServerEnvironment.ps1 -BackupName "pre-upgrade-2025-11-17"
```

### Scenario 3: Health Monitoring
```powershell
# Quick health check
.\Get-GeoServerHealth.ps1

# Detailed HTML report
.\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath ".\reports\health-$(Get-Date -Format 'yyyy-MM-dd').html"

# Email report to admin
.\Get-GeoServerHealth.ps1 -SendEmail -EmailConfig ".\config\notification-config.json"
```

### Scenario 4: Run Test Suite
```powershell
# Run all integration tests
.\tests\integration\Invoke-GeoServerTests.ps1 -TestSuite All

# Run only database tests
.\tests\integration\Test-DatabaseConnectivity.ps1

# Performance baseline
.\tests\performance\Invoke-JMeterTest.ps1 -TestPlan "baseline-load.jmx"
```

### Scenario 5: Emergency Rollback
```powershell
# List available backups
.\Restore-GeoServerEnvironment.ps1 -ListBackups

# Restore specific backup
.\Restore-GeoServerEnvironment.ps1 -BackupName "2025-11-17_140530" -Confirm:$false
```

## Additional Resources

### Reference Documentation
- [GeoServer Documentation](https://docs.geoserver.org/)
- [Apache Tomcat Documentation](https://tomcat.apache.org/tomcat-9.0-doc/)
- [PostGIS Documentation](https://postgis.net/documentation/)
- [PowerShell Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/cmdlet-development-guidelines)

### User's Existing Documentation
The user has comprehensive documentation from February 2025 covering:
- Complete installation guide
- Testing methodologies
- Security implementation
- Performance tuning
- Database integration
- Load balancer configuration

## Contact & Support

**Repository Owner:** b0bfranklin  
**Project Location:** Central Victoria, Australia  
**Timezone:** AEST (UTC+10/+11)

## License

To be determined by repository owner.

---

**Last Updated:** November 17, 2025  
**Document Version:** 1.0  
**Status:** Ready for Claude Code Development
