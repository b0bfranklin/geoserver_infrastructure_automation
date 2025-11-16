# Phase 2: Advanced Features Implementation

## Overview

Phase 2 expands the GeoServer Infrastructure Automation Suite with:
- **WPF GUI** for user-friendly management
- **Self-contained package management** (no external dependencies)
- **Component-specific upgrade modules** with rollback
- **Configuration analysis tools**
- **Restore/Rollback capabilities**

---

## New Features

### 1. Graphical User Interface (Start-GeoServerGUI.ps1)

**Technology:** Windows Presentation Foundation (WPF) - built into Windows, no dependencies

**Tabs:**
- **Dashboard**: Real-time health monitoring with HTML export
- **Backup & Restore**: Visual backup creation and restore management
- **Component Upgrades**: Checkbox selection for upgrade components
- **Configuration Analysis**: Migration analysis and comparison
- **Settings**: Path configuration and preferences

**Key Features:**
- Self-contained (no external UI frameworks required)
- Real-time status logging
- Integration with all core scripts
- Color-coded status indicators

**Launch:**
```powershell
.\Start-GeoServerGUI.ps1
```

---

### 2. Self-Contained Package Manager

**File:** `scripts/utilities/Get-ComponentPackage.ps1`

**Purpose:** Download and cache software packages without requiring Python, npm, or other package managers

**Supported Components:**
- ✅ Azul Zulu JRE 17/21
- ✅ Apache Tomcat 9.x / 10.x
- ✅ GeoServer 2.24.x / 2.25.x
- ✅ PostgreSQL 15.x / 16.x
- ✅ PostGIS 3.4.x
- ✅ pgAdmin 4.x
- ✅ QGIS 3.34.x

**Features:**
- Local caching to `.\downloads` directory
- SHA256 integrity verification
- Progress tracking for large downloads
- Automatic package detection
- Offline installation support (once cached)

**Example Usage:**
```powershell
# Download Azul Zulu JRE 17
.\scripts\utilities\Get-ComponentPackage.ps1 -Component "AzulJRE" -Version "17.0.9"

# Download latest Tomcat 10
.\scripts\utilities\Get-ComponentPackage.ps1 -Component "Tomcat"

# Force re-download (ignore cache)
.\scripts\utilities\Get-ComponentPackage.ps1 -Component "GeoServer" -Force
```

---

### 3. Restore & Rollback System

**File:** `scripts/core/Restore-GeoServerEnvironment.ps1`

**Purpose:** Complete rollback capabilities for failed upgrades

**Features:**
- List all available backups with metadata
- Validate backup integrity before restore
- Selective component restore (Tomcat, GeoServer, or All)
- Safety backup before restore (rollback of rollback!)
- Post-restore health verification
- WhatIf mode for preview

**Common Operations:**

```powershell
# List available backups
.\scripts\core\Restore-GeoServerEnvironment.ps1 -ListBackups

# Restore from specific backup
.\scripts\core\Restore-GeoServerEnvironment.ps1 -BackupName "pre-upgrade-2025-11-17"

# Restore only Tomcat configuration
.\scripts\core\Restore-GeoServerEnvironment.ps1 -BackupName "2025-11-17_140530" -RestoreComponents Tomcat

# Preview restore (WhatIf)
.\scripts\core\Restore-GeoServerEnvironment.ps1 -BackupName "latest" -WhatIf

# Force restore without confirmation
.\scripts\core\Restore-GeoServerEnvironment.ps1 -BackupPath "E:\Backups\GeoServer\backup.zip" -Force
```

---

### 4. Component-Specific Upgrade Modules

#### Azul Zulu JRE Upgrade (Java 11 → 17/21)

**File:** `scripts/upgrades/Upgrade-AzulJRE.ps1`

**Features:**
- Automatic detection of current Java version
- Downloads Azul Zulu JRE (not Oracle)
- Backs up current Java installation
- Updates JAVA_HOME and PATH environment variables
- Updates all Tomcat setenv.bat files
- Verifies installation with test execution
- Automatic rollback on failure

**Upgrade Process:**
1. Detect current Java (from JAVA_HOME or PATH)
2. Create backup of current Java directory
3. Download target Azul Zulu version (17 or 21)
4. Extract to `C:\Program Files\Azul\Zulu{version}`
5. Update system environment variables
6. Update Tomcat setenv.bat for all instances
7. Verify Java executable and properties
8. Test basic functionality

**Usage:**
```powershell
# Upgrade to Java 17 (recommended for GeoServer 2.24+)
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion 17

# Upgrade to Java 21 (for GeoServer 2.25+)
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion 21

# Preview upgrade
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion 17 -WhatIf

# Custom install location
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion 17 -InstallPath "D:\Java\Zulu17"
```

**Rollback:**
If upgrade fails verification, automatic rollback restores:
- Original JAVA_HOME environment variable
- Original PATH environment variable
- Original Tomcat setenv configurations

Manual rollback:
```powershell
# Backups stored in: .\backups\java\java_YYYY-MM-DD_HHMMSS
# Restore by reversing environment variables from backup\environment.json
```

---

#### Apache Tomcat Upgrade (9.x → 10.x)

**Status:** Framework ready - implementation pending

**Planned Features:**
- Detect Tomcat 9.x installations
- Download Tomcat 10.1.x (latest stable)
- Backup existing Tomcat directory
- Migrate configuration files (server.xml, web.xml, context.xml)
- Handle breaking changes (javax → jakarta package rename)
- Deploy GeoServer WAR to new Tomcat
- Verify deployment and health

**Migration Challenges:**
- **Package rename**: Tomcat 10 uses `jakarta.*` instead of `javax.*`
- **GeoServer compatibility**: Requires GeoServer 2.24.2+ for Tomcat 10
- **Configuration migration**: Some settings need adjustment

---

#### GeoServer Migration (2.26.2 → Current)

**Status:** Framework ready - implementation pending

**Current Version Detection:**
The user has GeoServer **2.26.2** installed. This is actually NEWER than the project brief suggested (2.24.2).

**Migration Path:**
- 2.26.2 → 2.26.x (patch updates)
- 2.26.x → 2.27.x (minor updates)
- 2.27.x → 2.28.x (latest stable)

**Planned Features:**
1. **Configuration Analysis**
   - Scan existing data directory
   - Identify custom configurations
   - Detect extensions and plugins
   - Analyze workspace configurations
   - Check for deprecated features

2. **Migration Process**
   - Download target GeoServer WAR
   - Backup current installation
   - Stop Tomcat services
   - Deploy new WAR
   - Migrate data directory (if needed)
   - Update configuration files
   - Restart services
   - Validate all workspaces and layers

3. **Rollback Points**
   - Pre-migration backup
   - WAR deployment checkpoint
   - Configuration update checkpoint
   - Post-verification checkpoint

---

#### PostgreSQL & PostGIS Upgrade

**Status:** Framework ready - implementation pending

**Upgrade Scenarios:**
- PostgreSQL 12/13/14 → 15 or 16
- PostGIS 2.x/3.x → 3.4.x

**Planned Features:**
- Detect current PostgreSQL version
- Backup all databases (pg_dump)
- Download PostgreSQL installer
- Install new version (side-by-side)
- Migrate data using pg_upgrade
- Install PostGIS extension
- Verify spatial functionality
- Update connection strings

**Rollback Strategy:**
- Keep old PostgreSQL installation until verified
- Database backups for restoration
- Connection string rollback

---

#### pgAdmin Upgrade

**Status:** Framework ready - implementation pending

**Features:**
- Detect current pgAdmin version
- Download latest pgAdmin installer
- Backup pgAdmin configuration
- Silent install of new version
- Migrate server connections
- Verify connectivity

---

#### QGIS Upgrade

**Status:** Framework ready - implementation pending

**Features:**
- Detect current QGIS version
- Download QGIS LTR (Long Term Release)
- Backup QGIS profiles and settings
- Silent install
- Migrate plugins and connections
- Verify PostGIS connectivity

---

## Configuration Analysis Tool

**Purpose:** Analyze existing configurations and identify required changes for upgrades

**Planned Features:**

1. **GeoServer Configuration Scanner**
   - Parse XML configuration files
   - Identify custom styles
   - List all workspaces and layers
   - Detect deprecated features
   - Check for incompatibilities with target version

2. **Comparison Tool**
   - Compare current config with target version requirements
   - Generate migration checklist
   - Highlight breaking changes
   - Suggest configuration updates

3. **Export Options**
   - HTML report with findings
   - JSON for automation
   - CSV for spreadsheet analysis

---

## Architecture Improvements

### Modular Design

```
scripts/
├── core/                           # Core functionality
│   ├── Backup-GeoServerEnvironment.ps1
│   ├── Restore-GeoServerEnvironment.ps1 (NEW)
│   ├── Invoke-GeoServerUpgrade.ps1
│   └── Get-GeoServerHealth.ps1
│
├── modules/                        # Reusable modules
│   ├── GeoServer.psm1
│   └── TomcatManager.psm1
│
├── upgrades/                       # Component upgrade modules (NEW)
│   ├── Upgrade-AzulJRE.ps1
│   ├── Upgrade-Tomcat.ps1          (planned)
│   ├── Upgrade-GeoServer.ps1       (planned)
│   ├── Upgrade-PostgreSQL.ps1      (planned)
│   ├── Upgrade-PgAdmin.ps1         (planned)
│   └── Upgrade-QGIS.ps1            (planned)
│
├── utilities/                      # Helper scripts (NEW)
│   ├── Get-ComponentPackage.ps1    (NEW - Package manager)
│   └── Compare-Configuration.ps1   (planned)
│
└── Start-GeoServerGUI.ps1          # GUI launcher (NEW)
```

### Self-Contained Design Principles

1. **No External Dependencies**
   - WPF (built into Windows)
   - .NET Framework (built into Windows)
   - PowerShell 7 (only requirement)
   - No Python, Node.js, or other runtimes needed

2. **Package Caching**
   - All downloads stored in `.\downloads`
   - SHA256 verification
   - Offline installation support

3. **Backup Everything**
   - Pre-upgrade backups
   - Safety backups before restore
   - Environment variable snapshots
   - Configuration file versioning

---

## Upgrade Workflow Example

### Complete Infrastructure Upgrade

```powershell
# 1. Start with health check
.\scripts\core\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath ".\reports\pre-upgrade.html"

# 2. Create full backup
.\scripts\core\Backup-GeoServerEnvironment.ps1 -BackupName "pre-major-upgrade"

# 3. Upgrade Java (JRE 11 → 17)
.\scripts\upgrades\Upgrade-AzulJRE.ps1 -TargetVersion 17

# 4. Restart Tomcat to apply Java changes
Restart-Service -Name "Tomcat9"

# 5. Upgrade Tomcat (9.x → 10.x)
.\scripts\upgrades\Upgrade-Tomcat.ps1 -TargetVersion "10.1.17"

# 6. Upgrade GeoServer (2.26.2 → latest)
.\scripts\upgrades\Upgrade-GeoServer.ps1 -AnalyzeConfiguration

# 7. Verify health
.\scripts\core\Get-GeoServerHealth.ps1 -OutputFormat HTML -OutputPath ".\reports\post-upgrade.html"

# 8. If issues occur, rollback
.\scripts\core\Restore-GeoServerEnvironment.ps1 -BackupName "pre-major-upgrade"
```

---

## Testing & Validation

### Recommended Test Environment

Before running in production:

1. **Create VM snapshot** (if using VMware/Hyper-V)
2. **Test in staging** environment first
3. **Verify all backups** can be restored
4. **Document current state** with screenshots
5. **Have rollback plan** ready

### Test Scenarios

1. **Java Upgrade**
   - [ ] Detect current Java version
   - [ ] Download Azul Zulu 17
   - [ ] Install and verify
   - [ ] Test Tomcat startup
   - [ ] Test GeoServer functionality
   - [ ] Rollback if needed

2. **Full Stack Upgrade**
   - [ ] Java 11 → 17
   - [ ] Tomcat 9 → 10
   - [ ] GeoServer 2.26.2 → 2.28.x
   - [ ] Verify all layers render
   - [ ] Test WMS/WFS endpoints
   - [ ] Check database connections

---

## Known Limitations & Future Work

### Current Limitations

1. **GUI** - Event handlers partially implemented (backend integration needed)
2. **Tomcat 10 Migration** - javax → jakarta conversion tool needed
3. **Config Analysis** - XML parsing and comparison logic pending
4. **PostgreSQL Upgrade** - pg_upgrade automation pending
5. **Email Notifications** - SMTP integration pending

### Planned Enhancements

1. **Scheduled Upgrades** - Windows Task Scheduler integration
2. **Remote Management** - PowerShell remoting support
3. **Monitoring Integration** - Prometheus/Grafana exporters
4. **Reporting** - Executive summary reports
5. **Compliance** - Audit trail generation

---

## Security Considerations

### Credentials Management

- Use Windows Credential Manager for database passwords
- Never store passwords in config files
- Support for encrypted configuration files

### Download Verification

- All packages verified with SHA256 hashes
- HTTPS only for downloads
- Package signature validation (where available)

### Backup Security

- Backups may contain sensitive data
- Ensure backup location has proper ACLs
- Consider encryption for backup archives

---

## Support & Troubleshooting

### Common Issues

**Issue:** Java upgrade fails with "Access Denied"
**Solution:** Ensure PowerShell is running as Administrator

**Issue:** Package download fails
**Solution:** Check internet connection, try manual download to `.\downloads`

**Issue:** Restore fails with service errors
**Solution:** Manually stop services before restore

**Issue:** GUI doesn't launch
**Solution:** Ensure PowerShell 7+ is installed, check for XAML syntax errors

### Getting Help

1. Check logs in `.\logs` directory
2. Review backup metadata in `backups\*/metadata.json`
3. Run health check: `.\scripts\core\Get-GeoServerHealth.ps1`
4. Use WhatIf mode to preview operations

---

## Version History

**Version 2.0.0** (Phase 2)
- Added WPF GUI
- Self-contained package manager
- Restore/rollback functionality
- Azul JRE upgrade module
- Framework for remaining upgrade modules

**Version 1.0.0** (Phase 1)
- Core backup script
- Upgrade orchestrator
- Health monitoring
- PowerShell modules

---

**Last Updated:** November 17, 2025
**Status:** Phase 2 In Progress - Core Framework Complete
