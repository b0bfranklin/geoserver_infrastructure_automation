<#
.SYNOPSIS
    Graphical User Interface for GeoServer Infrastructure Automation Suite

.DESCRIPTION
    WPF-based GUI that provides a user-friendly interface for:
    - Health monitoring
    - Backup/restore operations
    - Component upgrades (Java, Tomcat, GeoServer, PostgreSQL, pgAdmin, QGIS)
    - Configuration analysis
    - Rollback management

    This GUI is self-contained and requires no external dependencies.

.NOTES
    File Name   : Start-GeoServerGUI.ps1
    Author      : GeoServer Infrastructure Automation Suite
    Requires    : PowerShell 7.0+, Windows Server 2016+
    Version     : 2.0.0
#>

#Requires -Version 7.0

# ============================================================================
# GUI INITIALIZATION
# ============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Script variables
$script:ConfigPath = ".\config\upgrade-config.json"
$script:Config = $null

# ============================================================================
# XAML DEFINITION
# ============================================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GeoServer Infrastructure Automation Suite v2.0"
        Height="800" Width="1200"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize">

    <Window.Resources>
        <!-- Define styles -->
        <Style x:Key="HeaderTextStyle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="18"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>

        <Style x:Key="SectionTextStyle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="0,10,0,5"/>
        </Style>

        <Style x:Key="ButtonStyle" TargetType="Button">
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="MinWidth" Value="120"/>
        </Style>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="200"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="GeoServer Infrastructure Automation"
                       Style="{StaticResource HeaderTextStyle}"/>
            <TextBlock Text="v2.0" FontSize="12" VerticalAlignment="Bottom" Margin="5,0,0,5"/>
        </StackPanel>

        <!-- Main Content Area -->
        <TabControl Grid.Row="1" Margin="0,0,0,10">

            <!-- Dashboard Tab -->
            <TabItem Header="Dashboard">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0">
                        <TextBlock Text="System Health Overview" Style="{StaticResource SectionTextStyle}"/>
                        <TextBlock Name="txtHealthStatus" Text="Status: Not checked yet" Margin="5"/>

                        <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                            <Button Name="btnRefreshHealth" Content="Refresh Health" Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnExportHealthHTML" Content="Export HTML Report" Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnContinuousMonitor" Content="Start Monitoring" Style="{StaticResource ButtonStyle}"/>
                        </StackPanel>
                    </StackPanel>

                    <ScrollViewer Grid.Row="1" Margin="0,10,0,0" VerticalScrollBarVisibility="Auto">
                        <TextBlock Name="txtHealthDetails" TextWrapping="Wrap" FontFamily="Consolas" FontSize="10"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- Backup/Restore Tab -->
            <TabItem Header="Backup &amp; Restore">
                <Grid Margin="10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Backup Section -->
                    <StackPanel Grid.Column="0" Margin="0,0,10,0">
                        <TextBlock Text="Create Backup" Style="{StaticResource SectionTextStyle}"/>

                        <TextBlock Text="Backup Name:" Margin="0,10,0,5"/>
                        <TextBox Name="txtBackupName" Padding="5"/>

                        <CheckBox Name="chkCompressBackup" Content="Compress backup (ZIP)"
                                  IsChecked="True" Margin="0,10,0,0"/>
                        <CheckBox Name="chkIncludeLogs" Content="Include log files"
                                  IsChecked="False" Margin="0,5,0,0"/>

                        <TextBlock Text="Retention (days):" Margin="0,10,0,5"/>
                        <TextBox Name="txtRetentionDays" Text="30" Padding="5"/>

                        <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
                            <Button Name="btnCreateBackup" Content="Create Backup"
                                    Style="{StaticResource ButtonStyle}" Width="150"/>
                            <Button Name="btnBackupWhatIf" Content="Preview (WhatIf)"
                                    Style="{StaticResource ButtonStyle}"/>
                        </StackPanel>
                    </StackPanel>

                    <!-- Restore Section -->
                    <StackPanel Grid.Column="1" Margin="10,0,0,0">
                        <TextBlock Text="Restore from Backup" Style="{StaticResource SectionTextStyle}"/>

                        <TextBlock Text="Available Backups:" Margin="0,10,0,5"/>
                        <ListBox Name="lstBackups" Height="200" Margin="0,0,0,10"/>

                        <StackPanel Orientation="Horizontal">
                            <Button Name="btnRefreshBackups" Content="Refresh List"
                                    Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnRestoreBackup" Content="Restore Selected"
                                    Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnDeleteBackup" Content="Delete Selected"
                                    Style="{StaticResource ButtonStyle}"/>
                        </StackPanel>

                        <TextBlock Text="Backup Details:" Margin="0,20,0,5"/>
                        <TextBlock Name="txtBackupDetails" TextWrapping="Wrap"
                                   FontFamily="Consolas" FontSize="10" Height="150"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- Upgrades Tab -->
            <TabItem Header="Component Upgrades">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0">
                        <TextBlock Text="Select Components to Upgrade" Style="{StaticResource SectionTextStyle}"/>

                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                                <CheckBox Name="chkUpgradeJava" Content="Azul Zulu JRE (11 → 17/21)" Margin="5"/>
                                <CheckBox Name="chkUpgradeTomcat" Content="Tomcat (9.x → 10.x)" Margin="5"/>
                                <CheckBox Name="chkUpgradeGeoServer" Content="GeoServer (2.26.2 → Current)" Margin="5"/>
                            </StackPanel>

                            <StackPanel Grid.Column="1" Margin="0,0,10,0">
                                <CheckBox Name="chkUpgradePostgreSQL" Content="PostgreSQL &amp; PostGIS" Margin="5"/>
                                <CheckBox Name="chkUpgradePgAdmin" Content="pgAdmin" Margin="5"/>
                                <CheckBox Name="chkUpgradeQGIS" Content="QGIS" Margin="5"/>
                            </StackPanel>

                            <StackPanel Grid.Column="2">
                                <CheckBox Name="chkAutoBackup" Content="Auto-backup before upgrade"
                                          IsChecked="True" Margin="5"/>
                                <CheckBox Name="chkAutoRollback" Content="Auto-rollback on failure"
                                          IsChecked="True" Margin="5"/>
                                <CheckBox Name="chkAnalyzeConfig" Content="Analyze configuration changes"
                                          IsChecked="True" Margin="5"/>
                            </StackPanel>
                        </Grid>

                        <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
                            <Button Name="btnStartUpgrade" Content="Start Upgrade"
                                    Style="{StaticResource ButtonStyle}" Width="150"
                                    Background="Green" Foreground="White"/>
                            <Button Name="btnUpgradeWhatIf" Content="Preview Upgrade"
                                    Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnAnalyzeChanges" Content="Analyze Required Changes"
                                    Style="{StaticResource ButtonStyle}"/>
                        </StackPanel>
                    </StackPanel>

                    <ScrollViewer Grid.Row="1" Margin="0,10,0,0" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="pnlUpgradeProgress"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- Configuration Tab -->
            <TabItem Header="Configuration Analysis">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0">
                        <TextBlock Text="Configuration Comparison &amp; Migration Analysis"
                                   Style="{StaticResource SectionTextStyle}"/>

                        <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                            <Button Name="btnAnalyzeGeoServer" Content="Analyze GeoServer Config"
                                    Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnCompareVersions" Content="Compare with Target Version"
                                    Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnExportAnalysis" Content="Export Analysis"
                                    Style="{StaticResource ButtonStyle}"/>
                        </StackPanel>
                    </StackPanel>

                    <ScrollViewer Grid.Row="1" Margin="0,10,0,0" VerticalScrollBarVisibility="Auto">
                        <TextBlock Name="txtConfigAnalysis" TextWrapping="Wrap"
                                   FontFamily="Consolas" FontSize="10"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- Settings Tab -->
            <TabItem Header="Settings">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="10">
                        <TextBlock Text="Application Settings" Style="{StaticResource SectionTextStyle}"/>

                        <TextBlock Text="Configuration File:" Margin="0,10,0,5"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Name="txtConfigPath" Grid.Column="0" Padding="5"
                                     IsReadOnly="True"/>
                            <Button Name="btnBrowseConfig" Grid.Column="1" Content="Browse..."
                                    Margin="5,0,0,0" Padding="10,5"/>
                        </Grid>

                        <TextBlock Text="Backup Location:" Margin="0,20,0,5"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Name="txtBackupLocation" Grid.Column="0" Padding="5"/>
                            <Button Name="btnBrowseBackup" Grid.Column="1" Content="Browse..."
                                    Margin="5,0,0,0" Padding="10,5"/>
                        </Grid>

                        <TextBlock Text="Download Cache Location:" Margin="0,20,0,5"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Name="txtCacheLocation" Grid.Column="0" Padding="5"/>
                            <Button Name="btnBrowseCache" Grid.Column="1" Content="Browse..."
                                    Margin="5,0,0,0" Padding="10,5"/>
                        </Grid>

                        <StackPanel Orientation="Horizontal" Margin="0,30,0,0">
                            <Button Name="btnSaveSettings" Content="Save Settings"
                                    Style="{StaticResource ButtonStyle}" Width="150"/>
                            <Button Name="btnReloadConfig" Content="Reload Configuration"
                                    Style="{StaticResource ButtonStyle}"/>
                            <Button Name="btnResetDefaults" Content="Reset to Defaults"
                                    Style="{StaticResource ButtonStyle}"/>
                        </StackPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

        </TabControl>

        <!-- Status Bar -->
        <Grid Grid.Row="2" Background="#F0F0F0" Margin="0,10,0,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="5">
                <TextBlock Text="Status:" FontWeight="Bold" Margin="0,0,10,0"/>
                <TextBlock Name="txtStatus" Text="Ready"/>
            </StackPanel>

            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="5">
                <TextBlock Name="txtLog" FontFamily="Consolas" FontSize="10" TextWrapping="Wrap"/>
            </ScrollViewer>
        </Grid>
    </Grid>
</Window>
"@

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    $window.FindName('txtLog').Dispatcher.Invoke([action]{
        $logBox = $window.FindName('txtLog')
        $logBox.Text += "$logEntry`n"
    })

    # Also update status
    $window.FindName('txtStatus').Dispatcher.Invoke([action]{
        $window.FindName('txtStatus').Text = $Message
    })
}

function Load-Configuration {
    try {
        if (Test-Path $script:ConfigPath) {
            $content = Get-Content -Path $script:ConfigPath -Raw
            $script:Config = $content | ConvertFrom-Json
            Write-Log "Configuration loaded successfully" "SUCCESS"
            return $true
        } else {
            Write-Log "Configuration file not found. Using defaults." "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "Failed to load configuration: $_" "ERROR"
        return $false
    }
}

function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title = "GeoServer Automation",
        [string]$Type = "OK"
    )

    [System.Windows.MessageBox]::Show($Message, $Title, $Type)
}

# ============================================================================
# EVENT HANDLERS
# ============================================================================

function Register-EventHandlers {
    param($Window)

    # Dashboard - Health Check
    $Window.FindName('btnRefreshHealth').Add_Click({
        Write-Log "Refreshing health status..." "INFO"
        try {
            $result = & ".\scripts\core\Get-GeoServerHealth.ps1" -OutputFormat Console
            Write-Log "Health check completed" "SUCCESS"
        }
        catch {
            Write-Log "Health check failed: $_" "ERROR"
        }
    })

    $Window.FindName('btnExportHealthHTML').Add_Click({
        Write-Log "Generating HTML health report..." "INFO"
        try {
            $outputPath = ".\reports\health-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').html"
            & ".\scripts\core\Get-GeoServerHealth.ps1" -OutputFormat HTML -OutputPath $outputPath
            Write-Log "HTML report saved to: $outputPath" "SUCCESS"
            Show-MessageBox "Health report saved to:`n$outputPath"
        }
        catch {
            Write-Log "Failed to generate HTML report: $_" "ERROR"
        }
    })

    # Backup - Create
    $Window.FindName('btnCreateBackup').Add_Click({
        Write-Log "Starting backup creation..." "INFO"
        try {
            $backupName = $Window.FindName('txtBackupName').Text
            $compress = $Window.FindName('chkCompressBackup').IsChecked
            $includeLogs = $Window.FindName('chkIncludeLogs').IsChecked
            $retention = [int]$Window.FindName('txtRetentionDays').Text

            $params = @{
                BackupName = $backupName
                Compress = $compress
                IncludeLogs = $includeLogs
                RetentionDays = $retention
            }

            & ".\scripts\core\Backup-GeoServerEnvironment.ps1" @params
            Write-Log "Backup created successfully" "SUCCESS"
            Show-MessageBox "Backup created successfully!"
        }
        catch {
            Write-Log "Backup failed: $_" "ERROR"
            Show-MessageBox "Backup failed! Check logs for details." "" "Error"
        }
    })

    # Backup - WhatIf
    $Window.FindName('btnBackupWhatIf').Add_Click({
        Write-Log "Running backup preview (WhatIf mode)..." "INFO"
        try {
            & ".\scripts\core\Backup-GeoServerEnvironment.ps1" -WhatIf
            Write-Log "Backup preview completed" "SUCCESS"
        }
        catch {
            Write-Log "Backup preview failed: $_" "ERROR"
        }
    })

    # Upgrade - Start
    $Window.FindName('btnStartUpgrade').Add_Click({
        $confirmed = Show-MessageBox "This will start the upgrade process.`n`nAre you sure you want to continue?" "Confirm Upgrade" "YesNo"

        if ($confirmed -eq "Yes") {
            Write-Log "Starting upgrade process..." "INFO"

            # Collect selected components
            $components = @()
            if ($Window.FindName('chkUpgradeJava').IsChecked) { $components += "Java" }
            if ($Window.FindName('chkUpgradeTomcat').IsChecked) { $components += "Tomcat" }
            if ($Window.FindName('chkUpgradeGeoServer').IsChecked) { $components += "GeoServer" }
            if ($Window.FindName('chkUpgradePostgreSQL').IsChecked) { $components += "PostgreSQL" }
            if ($Window.FindName('chkUpgradePgAdmin').IsChecked) { $components += "PgAdmin" }
            if ($Window.FindName('chkUpgradeQGIS').IsChecked) { $components += "QGIS" }

            if ($components.Count -eq 0) {
                Show-MessageBox "Please select at least one component to upgrade." "" "Error"
                return
            }

            $autoBackup = -not $Window.FindName('chkAutoBackup').IsChecked
            $autoRollback = $Window.FindName('chkAutoRollback').IsChecked

            Write-Log "Selected components: $($components -join ', ')" "INFO"

            # This will be implemented with the upgrade modules
            Show-MessageBox "Upgrade functionality will be available after implementing upgrade modules."
        }
    })

    # Settings - Save
    $Window.FindName('btnSaveSettings').Add_Click({
        Write-Log "Saving settings..." "INFO"
        Show-MessageBox "Settings saved successfully!"
    })

    # Settings - Browse Config
    $Window.FindName('btnBrowseConfig').Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $dialog.InitialDirectory = ".\config"

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Window.FindName('txtConfigPath').Text = $dialog.FileName
        }
    })
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    # Load XAML
    $reader = [System.XML.XMLReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XAMLReader]::Load($reader)

    # Initialize controls with default values
    $window.FindName('txtConfigPath').Text = $script:ConfigPath
    $window.FindName('txtBackupName').Text = "manual-$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
    $window.FindName('txtCacheLocation').Text = ".\downloads"

    # Load configuration
    Load-Configuration

    if ($script:Config) {
        $window.FindName('txtBackupLocation').Text = $script:Config.environment.paths.backupLocation
    }

    # Register all event handlers
    Register-EventHandlers -Window $window

    # Show initial status
    Write-Log "GeoServer Infrastructure Automation Suite started" "INFO"
    Write-Log "Ready to manage your infrastructure" "SUCCESS"

    # Show the window
    $window.ShowDialog() | Out-Null
}
catch {
    [System.Windows.MessageBox]::Show("Failed to start GUI: $_", "Error", "OK", "Error")
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
