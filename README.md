# GeoServer Infrastructure Automation Suite

Enterprise-grade automation for upgrading, testing, and maintaining GeoServer infrastructure with zero-downtime deployments.

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows%20Server-lightgrey.svg)](https://www.microsoft.com/windows-server)
[![License](https://img.shields.io/badge/License-TBD-yellow.svg)](LICENSE)

## Overview

This automation suite provides comprehensive tooling for managing GeoServer deployments on Windows Server environments. It handles the complete lifecycle of infrastructure upgrades with built-in safety mechanisms, automated testing, and rollback capabilities.

### Key Features

- **Automated Upgrades**: Orchestrated upgrades for Java, Tomcat, and GeoServer with version detection
- **Safety First**: Automatic backups before any changes, with rollback capabilities
- **Health Monitoring**: Real-time health checks with console, HTML, and JSON output
- **Comprehensive Testing**: WMS/WFS validation, database connectivity, performance benchmarks
- **Production Ready**: Detailed logging, error handling, and notifications
- **Well Documented**: Extensive inline comments for sysadmins

## Quick Start

### Prerequisites

- **Operating System**: Windows Server 2016+ (designed for 2025)
- **PowerShell**: Version 7.0 or higher
- **Python**: 3.11+ (optional, for advanced features)
- **Permissions**: Administrative privileges required
- **Existing Setup**: Apache Tomcat 9.x with GeoServer deployed

### Installation

1. **Clone the repository**
   ```powershell
   git clone https://github.com/b0bfranklin/geoserver_infrastructure_automation.git
   cd geoserver_infrastructure_automation
   ```

2. **Create your configuration file**
   ```powershell
   # Copy the template and customize with your settings
   Copy-Item config\upgrade-config.json.template config\upgrade-config.json

   # Edit the configuration file with your actual paths and settings
   notepad config\upgrade-config.json
   ```

3. **Install Python dependencies (optional)**
   ```powershell
   pip install -r requirements.txt
   ```

### Using the GUI (New in v2.0!)

Launch the graphical interface for point-and-click management:

```powershell
.\Start-GeoServerGUI.ps1
```

The GUI provides:
- **Dashboard**: Real-time health monitoring
- **Backup & Restore**: Visual backup creation and restore management
- **Component Upgrades**: Select Java, Tomcat, GeoServer, PostgreSQL, pgAdmin, or QGIS
- **Configuration Analysis**: Migration analysis and comparison
- **Settings**: Configure paths and preferences

### Command-Line Usage

#### 1. Health Check (Safe to run anytime)

```powershell
# Quick console health check
.\scripts\core\Get-GeoServerHealth.ps1

# Generate HTML report
.\scripts\core\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath ".\reports\health.html"

# Continuous monitoring (refreshes every 60 seconds)
.\scripts\core\Get-GeoServerHealth.ps1 -Continuous -RefreshInterval 60
```

#### 2. Backup Your Environment (Safety First!)

```powershell
# Create a full backup before any maintenance
.\scripts\core\Backup-GeoServerEnvironment.ps1

# Create a backup with custom name
.\scripts\core\Backup-GeoServerEnvironment.ps1 -BackupName "pre-upgrade-2025-11-17"

# Preview what would be backed up (WhatIf mode)
.\scripts\core\Backup-GeoServerEnvironment.ps1 -WhatIf
```

#### 3. Upgrade Components

```powershell
# Preview upgrade without making changes
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component All -WhatIf

# Upgrade only Tomcat
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component Tomcat

# Upgrade all components with auto-rollback on failure
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component All -AutoRollback

# Upgrade GeoServer only (skip backup - not recommended)
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component GeoServer -SkipBackup
```

#### 4. Individual Component Upgrades (New in v2.2!)

```powershell
# Upgrade pgAdmin while preserving PostgreSQL server configurations
.\scripts\upgrades\Upgrade-pgAdmin.ps1 -TargetVersion "8.2" -TestConnections

# Upgrade QGIS while preserving PostGIS connections and plugins
.\scripts\upgrades\Upgrade-QGIS.ps1 -TargetVersion "3.34" -PreservePlugins

# Upgrade PostgreSQL/PostGIS with data migration
.\scripts\upgrades\Upgrade-PostgreSQL.ps1 -TargetVersion "15.0" -UpgradePostGIS

# Upgrade Tomcat with automatic javax→jakarta migration
.\scripts\upgrades\Upgrade-Tomcat.ps1 -TargetVersion "10.1"

# Upgrade Azul Java JRE from 11 to 17
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion "17"

# Analyze GeoServer configuration for migration planning
.\scripts\utilities\Compare-Configuration.ps1 -OutputFormat HTML
```

#### 5. Testing & Automation (New in v3.0!)

```powershell
# Run comprehensive integration tests
.\tests\integration\Invoke-IntegrationTests.ps1 -TestSuite All -GenerateReport

# Check for component version updates and security advisories
.\scripts\utilities\Test-VersionUpdates.ps1 -EmailNotification

# Set up scheduled maintenance tasks
.\scripts\utilities\Register-ScheduledMaintenance.ps1 -TaskType All

# Run unattended upgrades with automated testing (scheduled)
.\scripts\utilities\Invoke-UnattendedUpgrade.ps1 -EmailReport

# Send email notification
.\scripts\utilities\Send-EmailNotification.ps1 -Template "UpgradeSuccess" -To "admin@company.com"

# Start local web dashboard
.\Start-WebDashboard.ps1 -Port 8080 -OpenBrowser
```

## Configuration

The `config/upgrade-config.json` file is the central configuration for all scripts. Key sections:

### Environment Paths
```json
{
  "environment": {
    "paths": {
      "tomcatBase": "C:\\Program Files\\Apache\\Tomcat",
      "geoserverDataDir": "D:\\GeoServer\\data",
      "backupLocation": "E:\\Backups\\GeoServer"
    }
  }
}
```

### Tomcat Instances
```json
{
  "tomcatInstances": [
    {
      "name": "instance1",
      "path": "C:\\Program Files\\Apache\\Tomcat\\instance1",
      "port": 8080,
      "serviceName": "Tomcat9-Instance1"
    }
  ]
}
```

### Target Versions
```json
{
  "versions": {
    "targetJavaVersion": "17.0.9",
    "targetTomcatVersion": "9.0.85",
    "targetGeoServerVersion": "2.24.2"
  }
}
```

See `config/upgrade-config.json.template` for complete configuration options.

## Project Structure

```
geoserver_infrastructure_automation/
├── config/                          # Configuration files
│   ├── upgrade-config.json.template # Configuration template
│   └── templates/                   # Config file templates
│
├── scripts/
│   ├── core/                        # Main automation scripts
│   │   ├── Backup-GeoServerEnvironment.ps1    # Backup system
│   │   ├── Invoke-GeoServerUpgrade.ps1        # Upgrade orchestrator
│   │   └── Get-GeoServerHealth.ps1            # Health monitoring
│   │
│   ├── modules/                     # Reusable PowerShell modules
│   │   ├── GeoServer.psm1          # GeoServer management functions
│   │   └── TomcatManager.psm1      # Tomcat management functions
│   │
│   └── utilities/                   # Helper scripts
│
├── tests/                           # Testing framework (Phase 2)
│   ├── integration/                # Integration tests
│   └── performance/                # JMeter test plans
│
├── docs/                           # Documentation
├── logs/                           # Log files
└── examples/                       # Example usage scripts
```

## Core Scripts Reference

### Backup-GeoServerEnvironment.ps1

Creates comprehensive backups of your GeoServer environment.

**What it backs up:**
- Tomcat configuration files (server.xml, web.xml, etc.)
- GeoServer data directory
- Custom styles and fonts
- Database connection configs
- SSL certificates

**Key Parameters:**
- `-BackupPath`: Destination for backups
- `-BackupName`: Custom backup name (default: timestamp)
- `-Compress`: Create ZIP archive (default: enabled)
- `-IncludeLogs`: Include log files in backup
- `-RetentionDays`: Auto-delete backups older than N days

### Invoke-GeoServerUpgrade.ps1

Orchestrates component upgrades with safety checks and rollback.

**Upgrade Workflow:**
1. Detect current versions
2. Validate prerequisites
3. Create automatic backup
4. Stop services gracefully
5. Execute upgrades
6. Start services
7. Run health checks
8. Rollback if health checks fail (optional)

**Key Parameters:**
- `-Component`: What to upgrade (Java, Tomcat, GeoServer, All)
- `-AutoRollback`: Enable automatic rollback on failure
- `-SkipBackup`: Skip backup step (not recommended)
- `-WhatIf`: Preview changes without executing

### Get-GeoServerHealth.ps1

Monitors infrastructure health with multiple output formats.

**Health Checks:**
- Service status (running/stopped)
- HTTP endpoint availability
- Response times
- CPU and memory usage
- Disk space
- Database connectivity
- Port availability

**Key Parameters:**
- `-OutputFormat`: Console, HTML, JSON, or All
- `-OutputPath`: Where to save reports
- `-Continuous`: Enable continuous monitoring
- `-RefreshInterval`: Refresh rate for continuous mode

## Safety Features

### Automatic Backups
All scripts that make changes create automatic backups unless explicitly skipped. Backups include:
- Timestamped directories for easy identification
- Metadata files with backup details
- Automatic cleanup of old backups based on retention policy

### Validation at Every Step
- Prerequisites checked before starting
- Disk space validation
- Service status verification
- Configuration file validation
- Post-upgrade health checks

### Rollback Capability
If upgrades fail health checks:
- Automatic rollback available (with `-AutoRollback`)
- Manual rollback using backup files
- Detailed logs for troubleshooting

### Comprehensive Logging
- Timestamped log entries
- Multiple log levels (DEBUG, INFO, WARNING, ERROR, SUCCESS)
- Logs saved to files for audit trails
- Color-coded console output

## Common Use Cases

### Scenario 1: Monthly Maintenance Window

```powershell
# 1. Check current health
.\scripts\core\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath ".\reports\pre-maintenance.html"

# 2. Create backup
.\scripts\core\Backup-GeoServerEnvironment.ps1 -BackupName "monthly-maintenance-2025-11"

# 3. Upgrade components
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component All -AutoRollback

# 4. Verify post-upgrade health
.\scripts\core\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath ".\reports\post-maintenance.html"
```

### Scenario 2: Emergency Security Patch

```powershell
# Quick Tomcat upgrade with automatic safety features
.\scripts\core\Invoke-GeoServerUpgrade.ps1 -Component Tomcat -AutoRollback
```

### Scenario 3: Regular Health Monitoring

```powershell
# Schedule this to run daily via Task Scheduler
.\scripts\core\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath "C:\Reports\daily-health.html"
```

## Troubleshooting

### Script Requires Administrative Privileges

Ensure you're running PowerShell as Administrator:
```powershell
# Right-click PowerShell and select "Run as Administrator"
```

### Configuration File Not Found

Make sure you've created the config file from the template:
```powershell
Copy-Item config\upgrade-config.json.template config\upgrade-config.json
```

### Service Won't Stop

If Tomcat services won't stop gracefully:
```powershell
# Use Force parameter in the script (advanced)
# Or manually stop services before running upgrade
Stop-Service -Name "Tomcat9" -Force
```

### Check Logs for Details

All scripts generate detailed logs:
```powershell
# View recent logs
Get-Content .\logs\*.log -Tail 50
```

## Development Status

### Phase 1: Core Functionality ✅ COMPLETE
- [x] Project structure
- [x] Backup/restore scripts
- [x] Upgrade orchestrator
- [x] Health monitoring
- [x] PowerShell modules
- [x] Configuration templates

### Phase 2: Advanced Features ✅ COMPLETE
- [x] WPF GUI for user-friendly management
- [x] Self-contained package manager (no Python/external deps)
- [x] Restore/rollback functionality
- [x] Azul Zulu JRE upgrade module (11 → 17/21)
- [x] Tomcat upgrade module (9.x → 10.x with javax → jakarta)
- [x] GeoServer migration (2.26.2 → current with config analysis)
- [x] PostgreSQL/PostGIS upgrade (with pg_upgrade)
- [x] Configuration analysis tool (standalone utility)
- [x] Change management reporting system
- [x] pgAdmin upgrade module with server config preservation
- [x] QGIS upgrade module with PostgreSQL/PostGIS integration

### Phase 3: Testing & Automation ✅ COMPLETE
- [x] Integration testing suite (comprehensive test coverage)
- [x] Enhanced email notifications (SMTP with HTML templates)
- [x] Scheduled maintenance via Task Scheduler
- [x] Unattended upgrade system with automated testing
- [x] Version checking with security advisory monitoring
- [x] Local web dashboard for historical monitoring
- [x] GUI and web interface samples/documentation

## Requirements

### Software Requirements
- Windows Server 2016+ (optimized for 2025)
- PowerShell 7.2+
- Java JDK 17+
- Apache Tomcat 9.0+
- GeoServer 2.24+
- Git 2.40+

### Optional Software
- Python 3.11+ (for advanced features)
- Apache JMeter 5.6+ (for performance testing)
- PostgreSQL 15+ with PostGIS
- Microsoft SQL Server 2022+

### Network Requirements
- Internet access for downloads (or configured local mirror)
- Access to database servers
- Administrative access to target servers

## Best Practices

1. **Always Test First**: Use `-WhatIf` parameter to preview changes
2. **Never Skip Backups**: Unless you're absolutely certain and in a test environment
3. **Monitor Logs**: Check log files after operations for warnings or errors
4. **Test Restores**: Periodically verify that backups can be restored
5. **Document Changes**: Keep notes on configuration changes
6. **Schedule Maintenance**: Plan upgrades during low-traffic periods

## Support & Contributing

- **Issues**: Report issues at [GitHub Issues](https://github.com/b0bfranklin/geoserver_infrastructure_automation/issues)
- **Documentation**: See the `docs/` directory for detailed guides
- **Contact**: Repository owner - b0bfranklin

## License

To be determined by repository owner.

## Acknowledgments

Built for enterprise GeoServer deployments with a focus on:
- Production reliability
- Safety and rollback capabilities
- Sysadmin-friendly automation
- Clear documentation for non-developers

---

**Version**: 3.0.0 (Phase 3 Complete)
**Last Updated**: November 17, 2025
**Status**: Enterprise Ready - Complete automation suite with testing, monitoring, and scheduled maintenance
