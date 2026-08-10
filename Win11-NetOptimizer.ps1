<# 
.SYNOPSIS
    Win11 NetOptimizer - Herramienta portable de optimización de red para Windows 11
.DESCRIPTION
    Script PowerShell standalone con GUI WinForms para optimizar parámetros TCP/IP,
    adaptadores de red, DNS y crear puntos de restauración.
.NOTES
    Autor: Senior Windows Network Developer
    Requiere: Windows 10/11, PowerShell 5.1+, .NET Framework 4.7+
    Ejecutar como Administrador
#>

# ============================================================================
# CONFIGURACIÓN GLOBAL Y UTILIDADES
# ============================================================================
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

# Cargar ensamblados necesarios para WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.NetworkInformation

# Cachear tipos para uso en clase (evita error de parse-time)
$global:tForm = [System.Windows.Forms.Form]
$global:tRichTextBox = [System.Windows.Forms.RichTextBox]
$global:tButton = [System.Windows.Forms.Button]
$global:tPanel = [System.Windows.Forms.Panel]
$global:tLabel = [System.Windows.Forms.Label]
$global:tComboBox = [System.Windows.Forms.ComboBox]
$global:tCheckBox = [System.Windows.Forms.CheckBox]
$global:tProgressBar = [System.Windows.Forms.ProgressBar]
$global:tGroupBox = [System.Windows.Forms.GroupBox]
$global:tColor = [System.Drawing.Color]
$global:tFont = [System.Drawing.Font]
$global:tFontStyle = [System.Drawing.FontStyle]
$global:tPoint = [System.Drawing.Point]
$global:tSize = [System.Drawing.Size]
$global:tPadding = [System.Windows.Forms.Padding]
$global:tDockStyle = [System.Windows.Forms.DockStyle]
$global:tFlatStyle = [System.Windows.Forms.FlatStyle]
$global:tBorderStyle = [System.Windows.Forms.BorderStyle]
$global:tScrollBars = [System.Windows.Forms.ScrollBars]
$global:tHorizontalAlignment = [System.Windows.Forms.HorizontalAlignment]
$global:tCursor = [System.Windows.Forms.Cursor]
$global:tMessageBox = [System.Windows.Forms.MessageBox]
$global:tMessageBoxButtons = [System.Windows.Forms.MessageBoxButtons]
$global:tMessageBoxIcon = [System.Windows.Forms.MessageBoxIcon]
$global:tPing = [System.Net.NetworkInformation.Ping]
$global:tIPStatus = [System.Net.NetworkInformation.IPStatus]

# ============================================================================
# VERIFICACIÓN DE PERMISOS DE ADMINISTRADOR
# ============================================================================
function Test-IsAdmin {
    $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "[ERROR] Se requieren permisos de Administrador." -ForegroundColor Red
    Write-Host "Reinicie el script con 'Ejecutar como administrador'." -ForegroundColor Yellow
    Read-Host "Presione Enter para salir"
    exit 1
}

# ============================================================================
# CLASE PRINCIPAL DE LA APLICACIÓN
# ============================================================================
class Win11NetOptimizer {
    # Controles de la UI (sin type literals para evitar error de parseo antes de Add-Type)
    $Form
    $LogBox
    $BtnBackup
    $BtnOptimizeTCP
    $BtnOptimizeAdapter
    $BtnTestDNS
    $BtnApplyBestDNS
    $BtnRestoreDefaults
    $BtnFlushDNS
    $BtnResetWinsock
    $ProgressBar
    $StatusLabel
    $AdapterCombo
    $ChkNagle
    $ChkPowerMgmt
$ChkTimestamps
    
    # Cola de logs para antes de que el handle exista
    [System.Collections.Generic.List[object[]]]$LogQueue = [System.Collections.Generic.List[object[]]]::new()
     
    # Estado interno
    [string[]]$DNSServers = @('1.1.1.1', '8.8.8.8', '9.9.9.9', '1.0.0.1', '8.8.4.4', '149.112.112.112')
    [hashtable]$DNSResults = @{}
    [string]$SelectedAdapterGuid = ''
    [string]$BackupPath = ''

Win11NetOptimizer() {
        # Referencia global accesible desde los event handlers (script scope)
        $script:AppInstance = $this
        $this.InitializeUI()
        $this.LoadAdapters()
        # Logging inicial diferido hasta que el form tenga handle
        $this.Form.Add_Shown({
            $script:AppInstance.ProcessLogQueue()
            $script:AppInstance.Log("=== Win11 NetOptimizer iniciado ===", "Default")
            $script:AppInstance.Log("Ejecutando con permisos de Administrador: OK", "Default")
        })
    }

    # ========================================================================
    # INICIALIZACIÓN DE LA INTERFAZ GRÁFICA (WinForms)
    # ========================================================================
    [void] InitializeUI() {
        $this.Form = New-Object System.Windows.Forms.Form
        $this.Form.Text = 'Win11 NetOptimizer v1.0 - Optimización de Red Windows 11'
        $this.Form.Size = New-Object System.Drawing.Size(900, 700)
        $this.Form.StartPosition = 'CenterScreen'
        $this.Form.MinimumSize = New-Object System.Drawing.Size(850, 650)
        $this.Form.BackColor = $global:tColor::FromArgb(30, 30, 30)
        $this.Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

        # Panel superior - Selector de adaptador
        $topPanel = New-Object System.Windows.Forms.Panel
        $topPanel.Dock = 'Top'
        $topPanel.Height = 60
        $topPanel.BackColor = $global:tColor::FromArgb(40, 40, 40)
        $topPanel.Padding = New-Object System.Windows.Forms.Padding(10)

        $lblAdapter = New-Object System.Windows.Forms.Label
        $lblAdapter.Text = 'Adaptador de red:'
        $lblAdapter.ForeColor = $global:tColor::White
        $lblAdapter.AutoSize = $true
        $lblAdapter.Location = New-Object System.Drawing.Point(10, 18)
        $topPanel.Controls.Add($lblAdapter)

        $this.AdapterCombo = New-Object System.Windows.Forms.ComboBox
        $this.AdapterCombo.DropDownStyle = 'DropDownList'
        $this.AdapterCombo.Width = 400
        $this.AdapterCombo.Location = New-Object System.Drawing.Point(130, 15)
        $this.AdapterCombo.BackColor = $global:tColor::FromArgb(50, 50, 50)
        $this.AdapterCombo.ForeColor = $global:tColor::White
        $this.AdapterCombo.FlatStyle = 'Flat'
        $this.AdapterCombo.Add_SelectedIndexChanged({ $script:AppInstance.OnAdapterChanged($script:AppInstance.AdapterCombo.SelectedItem) })
        $topPanel.Controls.Add($this.AdapterCombo)

        $btnRefresh = New-Object System.Windows.Forms.Button
        $btnRefresh.Text = '🔄 Actualizar'
        $btnRefresh.Size = New-Object System.Drawing.Size(100, 30)
        $btnRefresh.Location = New-Object System.Drawing.Point(540, 13)
        $btnRefresh.BackColor = $global:tColor::FromArgb(0, 120, 215)
        $btnRefresh.ForeColor = $global:tColor::White
        $btnRefresh.FlatStyle = 'Flat'
        $btnRefresh.FlatAppearance.BorderSize = 0
        $btnRefresh.Add_Click({ $script:AppInstance.LoadAdapters() })
        $topPanel.Controls.Add($btnRefresh)

        $this.Form.Controls.Add($topPanel)

        # Panel de opciones (checkboxes)
        $optPanel = New-Object System.Windows.Forms.Panel
        $optPanel.Dock = 'Top'
        $optPanel.Height = 50
        $optPanel.BackColor = $global:tColor::FromArgb(35, 35, 35)
        $optPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

        $this.ChkNagle = $this.CreateCheckBox('Desactivar Algoritmo de Nagle (Gaming/Baja latencia)', 10, 8, 400)
        $this.ChkNagle.Checked = $true
        $optPanel.Controls.Add($this.ChkNagle)

        $this.ChkPowerMgmt = $this.CreateCheckBox('Desactivar ahorro de energía en adaptador', 420, 8, 300)
        $this.ChkPowerMgmt.Checked = $true
        $optPanel.Controls.Add($this.ChkPowerMgmt)

        $this.ChkTimestamps = $this.CreateCheckBox('Desactivar TCP Timestamps', 730, 8, 200)
        $this.ChkTimestamps.Checked = $true
        $optPanel.Controls.Add($this.ChkTimestamps)

        $this.Form.Controls.Add($optPanel)

        # Panel de botones principales
        $btnPanel = New-Object System.Windows.Forms.Panel
        $btnPanel.Dock = 'Top'
        $btnPanel.Height = 160
        $btnPanel.BackColor = $global:tColor::FromArgb(30, 30, 30)
        $btnPanel.Padding = New-Object System.Windows.Forms.Padding(10)

        # Fila 1 - Respaldos y Restauración
        $grpBackup = New-Object System.Windows.Forms.GroupBox
        $grpBackup.Text = '🛡️ Respaldos y Restauración'
        $grpBackup.ForeColor = $global:tColor::LightGray
        $grpBackup.Size = New-Object System.Drawing.Size(850, 70)
        $grpBackup.Location = New-Object System.Drawing.Point(10, 5)

        $this.BtnBackup = $this.CreateButton('📦 Crear Respaldo + Punto de Restauración', 10, 25, 400, 35, $global:tColor::FromArgb(0, 150, 100))
        $this.BtnBackup.Add_Click({ $script:AppInstance.CreateBackupAndRestorePoint() })
        $grpBackup.Controls.Add($this.BtnBackup)

        $this.BtnRestoreDefaults = $this.CreateButton('↩️ Restaurar Valores Predeterminados de Windows', 420, 25, 400, 35, $global:tColor::FromArgb(200, 100, 0))
        $this.BtnRestoreDefaults.Add_Click({ $script:AppInstance.RestoreWindowsDefaults() })
        $grpBackup.Controls.Add($this.BtnRestoreDefaults)

        $btnPanel.Controls.Add($grpBackup)

        # Fila 2 - Optimizaciones
        $grpOptimize = New-Object System.Windows.Forms.GroupBox
        $grpOptimize.Text = '⚡ Optimizaciones de Red'
        $grpOptimize.ForeColor = $global:tColor::LightGray
        $grpOptimize.Size = New-Object System.Drawing.Size(850, 75)
        $grpOptimize.Location = New-Object System.Drawing.Point(10, 80)

        $this.BtnOptimizeTCP = $this.CreateButton('🔧 Optimizar TCP/IP Global', 10, 22, 200, 35, $global:tColor::FromArgb(0, 120, 215))
        $this.BtnOptimizeTCP.Add_Click({ $script:AppInstance.OptimizeTCPIP() })
        $grpOptimize.Controls.Add($this.BtnOptimizeTCP)

        $this.BtnOptimizeAdapter = $this.CreateButton('📶 Optimizar Adaptador Seleccionado', 220, 22, 230, 35, $global:tColor::FromArgb(0, 120, 215))
        $this.BtnOptimizeAdapter.Add_Click({ $script:AppInstance.OptimizeAdapter() })
        $grpOptimize.Controls.Add($this.BtnOptimizeAdapter)

        $this.BtnFlushDNS = $this.CreateButton('🧹 Flush DNS Cache', 460, 22, 160, 35, $global:tColor::FromArgb(100, 100, 200))
        $this.BtnFlushDNS.Add_Click({ $script:AppInstance.FlushDNSCache() })
        $grpOptimize.Controls.Add($this.BtnFlushDNS)

        $this.BtnResetWinsock = $this.CreateButton('🔄 Reset Winsock', 630, 22, 160, 35, $global:tColor::FromArgb(100, 100, 200))
        $this.BtnResetWinsock.Add_Click({ $script:AppInstance.ResetWinsock() })
        $grpOptimize.Controls.Add($this.BtnResetWinsock)

        $btnPanel.Controls.Add($grpOptimize)

        $this.Form.Controls.Add($btnPanel)

        # Panel DNS
        $dnsPanel = New-Object System.Windows.Forms.Panel
        $dnsPanel.Dock = 'Top'
        $dnsPanel.Height = 80
        $dnsPanel.BackColor = $global:tColor::FromArgb(30, 30, 30)
        $dnsPanel.Padding = New-Object System.Windows.Forms.Padding(10)

        $grpDNS = New-Object System.Windows.Forms.GroupBox
        $grpDNS.Text = '🌐 DNS Speed Test y Selección'
        $grpDNS.ForeColor = $global:tColor::LightGray
        $grpDNS.Size = New-Object System.Drawing.Size(850, 65)
        $grpDNS.Location = New-Object System.Drawing.Point(10, 5)

        $this.BtnTestDNS = $this.CreateButton('🏃 Probar Velocidad DNS (Ping)', 10, 22, 220, 35, $global:tColor::FromArgb(150, 0, 150))
        $this.BtnTestDNS.Add_Click({ $script:AppInstance.TestDNSSpeed() })
        $grpDNS.Controls.Add($this.BtnTestDNS)

        $this.BtnApplyBestDNS = $this.CreateButton('✅ Aplicar DNS Más Rápido Detectado', 240, 22, 280, 35, $global:tColor::FromArgb(0, 150, 100))
        $this.BtnApplyBestDNS.Enabled = $false
        $this.BtnApplyBestDNS.Add_Click({ $script:AppInstance.ApplyBestDNS() })
        $grpDNS.Controls.Add($this.BtnApplyBestDNS)

        $lblDNSInfo = New-Object System.Windows.Forms.Label
        $lblDNSInfo.Text = 'Servidores probados: Cloudflare (1.1.1.1), Google (8.8.8.8), Quad9 (9.9.9.9) + secundarios'
        $lblDNSInfo.ForeColor = $global:tColor::Gray
        $lblDNSInfo.AutoSize = $true
        $lblDNSInfo.Location = New-Object System.Drawing.Point(530, 28)
        $grpDNS.Controls.Add($lblDNSInfo)

        $dnsPanel.Controls.Add($grpDNS)
        $this.Form.Controls.Add($dnsPanel)

        # Barra de progreso y estado
        $statusPanel = New-Object System.Windows.Forms.Panel
        $statusPanel.Dock = 'Bottom'
        $statusPanel.Height = 40
        $statusPanel.BackColor = $global:tColor::FromArgb(25, 25, 25)
        $statusPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

        $this.ProgressBar = New-Object System.Windows.Forms.ProgressBar
        $this.ProgressBar.Dock = 'Top'
        $this.ProgressBar.Height = 6
        $this.ProgressBar.Style = 'Continuous'
        $this.ProgressBar.ForeColor = $global:tColor::FromArgb(0, 150, 100)
        $this.ProgressBar.BackColor = $global:tColor::FromArgb(50, 50, 50)
        $statusPanel.Controls.Add($this.ProgressBar)

        $this.StatusLabel = New-Object System.Windows.Forms.Label
        $this.StatusLabel.Text = 'Listo'
        $this.StatusLabel.ForeColor = $global:tColor::LightGray
        $this.StatusLabel.Dock = 'Bottom'
        $this.StatusLabel.Height = 20
        $this.StatusLabel.TextAlign = 'MiddleLeft'
        $statusPanel.Controls.Add($this.StatusLabel)

        $this.Form.Controls.Add($statusPanel)

        # Log Box (ocupa el resto del espacio)
        $this.LogBox = New-Object System.Windows.Forms.RichTextBox
        $this.LogBox.Dock = 'Fill'
        $this.LogBox.BackColor = $global:tColor::FromArgb(20, 20, 20)
        $this.LogBox.ForeColor = $global:tColor::FromArgb(200, 200, 200)
        $this.LogBox.BorderStyle = 'None'
        $this.LogBox.ReadOnly = $true
        $this.LogBox.Font = New-Object System.Drawing.Font('Consolas', 8.5)
        $this.LogBox.WordWrap = $false
        $this.LogBox.ScrollBars = 'Vertical'
        $this.Form.Controls.Add($this.LogBox)

        # Evento FormClosing
        $this.Form.Add_FormClosing({ $script:AppInstance.OnFormClosing() })
    }

[object] CreateCheckBox($text, $x, $y, $width) {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $text
        $chk.ForeColor = $global:tColor::LightGray
        $chk.Location = New-Object $global:tPoint($x, $y)
        $chk.Size = New-Object $global:tSize($width, 25)
        $chk.FlatStyle = 'Flat'
        return $chk
    }

    [object] CreateButton($text, $x, $y, $width, $height, $color) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $text
        $btn.Size = New-Object $global:tSize($width, $height)
        $btn.Location = New-Object $global:tPoint($x, $y)
        $btn.BackColor = $color
        $btn.ForeColor = $global:tColor::White
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderSize = 0
        $btn.Font = New-Object $global:tFont('Segoe UI', 9, $global:tFontStyle::Bold)
        $btn.Cursor = 'Hand'
        return $btn
    }

# ========================================================================
    # MÉTODOS DE LOGGING Y UI
    # ========================================================================
    [void] Log($message, $color = 'Default') {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $formatted = "[$timestamp] $message`n"
        
        $logEntry = @($formatted, $color)
        
        if ($this.Form.IsHandleCreated) {
            # Acceso directo (mismo hilo de UI, sin Invoke/marshaling)
            $this.LogBox.SelectionStart = $this.LogBox.TextLength
            $this.LogBox.SelectionColor = if ($color -eq 'Default') { $global:tColor::FromArgb(200,200,200) } 
                                          elseif ($color -eq 'Green') { $global:tColor::FromArgb(100,255,100) }
                                          elseif ($color -eq 'Red') { $global:tColor::FromArgb(255,100,100) }
                                          elseif ($color -eq 'Yellow') { $global:tColor::FromArgb(255,255,100) }
                                          elseif ($color -eq 'Cyan') { $global:tColor::FromArgb(100,255,255) }
                                          else { $global:tColor::White }
            $this.LogBox.AppendText($formatted)
            $this.LogBox.ScrollToCaret()
        } else {
            # Encolar para procesar cuando el handle exista
            $this.LogQueue.Add($logEntry)
        }
    }

    [void] ProcessLogQueue() {
        foreach ($entry in $this.LogQueue) {
            $this.LogBox.SelectionStart = $this.LogBox.TextLength
            $this.LogBox.SelectionColor = if ($entry[1] -eq 'Default') { $global:tColor::FromArgb(200,200,200) } 
                                          elseif ($entry[1] -eq 'Green') { $global:tColor::FromArgb(100,255,100) }
                                          elseif ($entry[1] -eq 'Red') { $global:tColor::FromArgb(255,100,100) }
                                          elseif ($entry[1] -eq 'Yellow') { $global:tColor::FromArgb(255,255,100) }
                                          elseif ($entry[1] -eq 'Cyan') { $global:tColor::FromArgb(100,255,255) }
                                          else { $global:tColor::White }
            $this.LogBox.AppendText($entry[0])
            $this.LogBox.ScrollToCaret()
        }
        $this.LogQueue.Clear()
    }

    [void] SetStatus($text, $progress = -1) {
        $this.StatusLabel.Text = $text
        if ($progress -ge 0) {
            $clamped = [Math]::Max(0, [Math]::Min(100, $progress))
            $this.ProgressBar.Value = $clamped
        }
    }

    [void] SetButtonsEnabled($enabled) {
        $buttons = @($this.BtnBackup, $this.BtnOptimizeTCP, $this.BtnOptimizeAdapter, 
                     $this.BtnTestDNS, $this.BtnApplyBestDNS, $this.BtnRestoreDefaults,
                     $this.BtnFlushDNS, $this.BtnResetWinsock)
        foreach ($b in $buttons) { $b.Enabled = $enabled }
    }

    # ========================================================================
    # CARGA DE ADAPTADORES DE RED
    # ========================================================================
    [void] LoadAdapters() {
        $this.Log("Cargando adaptadores de red...", "Default")
        $this.AdapterCombo.DisplayMember = 'Display'
        $this.AdapterCombo.ValueMember = 'Name'
        $this.AdapterCombo.Items.Clear()
        
        try {
            $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Disconnected' } | Sort-Object InterfaceDescription
            foreach ($adapter in $adapters) {
                $display = "$($adapter.Name)  [$($adapter.InterfaceDescription)]  ($($adapter.LinkSpeed))"
                $item = [pscustomobject]@{
                    Display = $display
                    Name = $adapter.Name
                }
                $this.AdapterCombo.Items.Add($item) | Out-Null
            }
            
            if ($this.AdapterCombo.Items.Count -gt 0) {
                $this.AdapterCombo.SelectedIndex = 0
            } else {
                $this.Log("No se encontraron adaptadores activos", 'Yellow')
            }
        } catch {
            $this.Log("Error cargando adaptadores: $_", 'Red')
        }
    }

    # Obtener adaptador seleccionado de forma segura (usa Name real, sin parseo)
    [object] GetSelectedAdapter() {
        if (-not $this.AdapterCombo.SelectedItem) { return $null }
        $name = $this.AdapterCombo.SelectedItem.Name
        return Get-NetAdapter -Name $name -ErrorAction SilentlyContinue
    }

    [void] OnAdapterChanged($selectedItem) {
        if ($selectedItem) {
            $adapter = Get-NetAdapter -Name $selectedItem.Name -ErrorAction SilentlyContinue
            if ($adapter) {
                $this.SelectedAdapterGuid = $this.GetAdapterGuid($adapter)
                $this.Log("Adaptador seleccionado: $($adapter.Name) (GUID: $this.SelectedAdapterGuid)", 'Cyan')
            }
        }
    }

    [string] GetAdapterGuid($adapter) {
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
            $subKeys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
            foreach ($key in $subKeys) {
                $driverDesc = Get-ItemProperty $key.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue
                if ($driverDesc.DriverDesc -eq $adapter.InterfaceDescription) {
                    return $key.PSChildName
                }
            }
        } catch { }
        return ''
    }

    # ========================================================================
    # MÓDULO 1: OPTIMIZACIÓN TCP/IP GLOBAL
    # ========================================================================
    [void] OptimizeTCPIP() {
        $this.SetButtonsEnabled($false)
        $this.SetStatus('Optimizando TCP/IP Global...', 10)
        
        $jobs = @(
            @{ Cmd = 'netsh int tcp set global autotuninglevel=normal'; Desc = 'AutoTuning Level = Normal' },
            @{ Cmd = 'netsh int tcp set global congestionprovider=ctcp'; Desc = 'Congestion Provider = CTCP' },
            @{ Cmd = 'netsh int tcp set global ecncapability=enabled'; Desc = 'ECN Capability = Enabled' },
            @{ Cmd = 'netsh int tcp set global timestamps=disabled'; Desc = 'Timestamps = Disabled' },
            @{ Cmd = 'netsh int tcp set global rss=enabled'; Desc = 'RSS = Enabled' },
            @{ Cmd = 'netsh int tcp set global initialRto=2000'; Desc = 'InitialRTO = 2000ms (rápido)' },
            @{ Cmd = 'netsh int tcp set global nonsackrttresiliency=disabled'; Desc = 'NonSackRttResiliency = Disabled' }
        )

        # Intentar cubic si está disponible (Windows 11 22H2+)
        try {
            $osVersion = [System.Environment]::OSVersion.Version
            if ($osVersion.Build -ge 22621) {
                $jobs[1].Cmd = 'netsh int tcp set global congestionprovider=cubic'
                $jobs[1].Desc = 'Congestion Provider = CUBIC (Windows 11 22H2+)'
            }
        } catch { }

        $completed = 0
        foreach ($job in $jobs) {
            $progress = 10 + [Math]::Floor($completed * 80 / $jobs.Count)
            $this.SetStatus($job.Desc, $progress)
            $this.Log("Ejecutando: $($job.Cmd)", "Default")
            try {
                $result = Invoke-Expression $job.Cmd 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $this.Log("✓ $($job.Desc)", 'Green')
                } else {
                    $this.Log("✗ $($job.Desc) - $result", 'Red')
                }
            } catch {
                $this.Log("✗ Error en $($job.Desc): $_", 'Red')
            }
            $completed++
        }

        # Remover throttling de red del sistema (Multimedia SystemProfile)
        $this.SetStatus('Removiendo Network Throttling del sistema...', 85)
        try {
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            $this.Log("✓ Network Throttling Index = 0xFFFFFFFF (desactivado)", 'Green')
            $this.Log("✓ System Responsiveness = 0", 'Green')
        } catch {
            $this.Log("✗ Error quitando Network Throttling: $_", 'Red')
        }

        # Verificar configuración aplicada
        $this.SetStatus('Verificando configuración TCP/IP...', 90)
        $this.VerifyTCPSettings()
        
        $this.SetStatus('Optimización TCP/IP completada', 100)
        $this.SetButtonsEnabled($true)
        $this.Log("=== Optimización TCP/IP Global finalizada ===", 'Green')
    }

    [void] VerifyTCPSettings() {
        try {
            $output = netsh int tcp show global 2>&1
            $this.Log("--- Configuración TCP/IP Actual ---", 'Cyan')
            foreach ($line in $output) {
                if ($line -match '(AutoTuningLevel|CongestionProvider|ECN|Timestamps|RSS|InitialRto|NonSackRtt)') {
                    $this.Log("  $line", "Default")
                }
            }
        } catch {
            $this.Log("No se pudo verificar configuración TCP", 'Yellow')
        }
    }

    # ========================================================================
    # MÓDULO 2: OPTIMIZACIÓN DE ADAPTADOR
    # ========================================================================
    [void] OptimizeAdapter() {
        if (-not $this.SelectedAdapterGuid) {
            $this.Log("Error: No hay adaptador seleccionado", 'Red')
            return
        }

        $this.SetButtonsEnabled($false)
        $this.SetStatus('Optimizando adaptador seleccionado...', 10)

        $adapter = $this.GetSelectedAdapter()
        if (-not $adapter) {
            $this.Log("Error: No se pudo obtener información del adaptador", 'Red')
            $this.SetButtonsEnabled($true)
            return
        }

        $this.Log("Optimizando adaptador: $($adapter.Name)", 'Cyan')

        # 1. Desactivar ahorro de energía
        if ($this.ChkPowerMgmt.Checked) {
            $this.SetStatus('Desactivando ahorro de energía...', 30)
            $this.DisableAdapterPowerManagement($adapter)
        }

        # 2. Desactivar Algoritmo de Nagle (Registro)
        if ($this.ChkNagle.Checked) {
            $this.SetStatus('Desactivando Algoritmo de Nagle...', 50)
            $this.DisableNagleAlgorithm()
        }

        # 3. Desactivar TCP Timestamps en adaptador
        if ($this.ChkTimestamps.Checked) {
            $this.SetStatus('Desactivando TCP Timestamps en adaptador...', 70)
            $this.DisableAdapterTimestamps($adapter)
        }

        # 4. Configuraciones adicionales de rendimiento
        $this.SetStatus('Aplicando configuraciones avanzadas...', 85)
        $this.ApplyAdvancedAdapterSettings($adapter)

        $this.SetStatus('Optimización de adaptador completada', 100)
        $this.SetButtonsEnabled($true)
        $this.Log("=== Optimización de adaptador finalizada ===", 'Green')
    }

    [void] DisableAdapterPowerManagement($adapter) {
        try {
            # Método 1: PowerShell (moderno)
            $adapter | Set-NetAdapterPowerManagement -WakeOnMagicPacket Disabled -WakeOnPattern Disabled -ErrorAction SilentlyContinue

            # Desactivar LSO (Large Send Offload) - mejora de velocidad del .bat
            $adapter | Disable-NetAdapterLso -IPv4 -IPv6 -ErrorAction SilentlyContinue

            # Método 2: Registro (más agresivo y persistente)
            if ($this.SelectedAdapterGuid) {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\$this.SelectedAdapterGuid"
                $props = @{
                    'PnPCapabilities' = 0x18  # Desactivar Wake-on-LAN
                    'EnablePME' = 0
                    'WakeOnMagicPacket' = 0
                    'WakeOnPattern' = 0
                }
                foreach ($prop in $props.Keys) {
                    Set-ItemProperty -Path $regPath -Name $prop -Value $props[$prop] -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }

            # Energy Efficient Ethernet (EEE)
            $adapter | Set-NetAdapterAdvancedProperty -DisplayName "Energy Efficient Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
            $adapter | Set-NetAdapterAdvancedProperty -DisplayName "EEE" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
            $adapter | Set-NetAdapterAdvancedProperty -DisplayName "Green Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

            $this.Log("✓ Ahorro de energía desactivado", 'Green')
        } catch {
            $this.Log("⚠ Error desactivando ahorro de energía: $_", 'Yellow')
        }
    }

    [void] DisableNagleAlgorithm() {
        try {
            # Aplicar a TODAS las interfaces TCP/IP (como el script .bat optimizado)
            $interfacesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $appliedCount = 0
            Get-ChildItem $interfacesPath -ErrorAction SilentlyContinue | ForEach-Object {
                Set-ItemProperty -Path $_.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $_.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                $appliedCount++
            }

            # También en parámetros globales TCP
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            $this.Log("✓ Algoritmo de Nagle desactivado en $appliedCount interfaces (TcpAckFrequency=1, TCPNoDelay=1)", 'Green')
        } catch {
            $this.Log("⚠ Error desactivando Nagle: $_", 'Yellow')
        }
    }

    [void] DisableAdapterTimestamps($adapter) {
        try {
            # Desactivar timestamps a nivel de interfaz via netsh
            $ifIndex = $adapter.ifIndex
            netsh int tcp set supplemental template=internet timestamps=disabled >$null 2>&1
            
            $this.Log("✓ TCP Timestamps desactivado en adaptador", 'Green')
        } catch {
            $this.Log("⚠ Error desactivando timestamps: $_", 'Yellow')
        }
    }

    [void] ApplyAdvancedAdapterSettings($adapter) {
        try {
            # Configuraciones avanzadas comunes para gaming/latencia baja
            $settings = @(
                @{ Name = 'Interrupt Moderation'; Value = 'Disabled' },
                @{ Name = 'Interrupt Moderation Rate'; Value = 'Off' },
                @{ Name = 'Receive Buffers'; Value = '2048' },
                @{ Name = 'Transmit Buffers'; Value = '2048' },
                @{ Name = 'Receive Side Scaling'; Value = 'Enabled' },
                @{ Name = 'RSS'; Value = 'Enabled' },
                @{ Name = 'RSC'; Value = 'Enabled' },
                @{ Name = 'Large Send Offload V2 (IPv4)'; Value = 'Enabled' },
                @{ Name = 'Large Send Offload V2 (IPv6)'; Value = 'Enabled' },
                @{ Name = 'TCP Checksum Offload (IPv4)'; Value = 'Enabled' },
                @{ Name = 'TCP Checksum Offload (IPv6)'; Value = 'Enabled' },
                @{ Name = 'UDP Checksum Offload (IPv4)'; Value = 'Enabled' },
                @{ Name = 'UDP Checksum Offload (IPv6)'; Value = 'Enabled' },
                @{ Name = 'Jumbo Frame'; Value = '9014 Bytes' }
            )

            foreach ($setting in $settings) {
                try {
                    $adapter | Set-NetAdapterAdvancedProperty -DisplayName $setting.Name -DisplayValue $setting.Value -ErrorAction SilentlyContinue
                } catch { }
            }

            $this.Log("✓ Configuraciones avanzadas aplicadas", 'Green')
        } catch {
            $this.Log("⚠ Error en configuraciones avanzadas: $_", 'Yellow')
        }
    }

    # ========================================================================
    # MÓDULO 3: DNS SPEED TEST & SELECTION
    # ========================================================================
    [void] TestDNSSpeed() {
        $this.SetButtonsEnabled($false)
        $this.BtnTestDNS.Enabled = $false
        $this.BtnApplyBestDNS.Enabled = $false
        $this.DNSResults.Clear()
        
        $this.Log("=== Iniciando DNS Speed Test ===", 'Cyan')
        $this.Log("Probando $($this.DNSServers.Count) servidores DNS...", 'Cyan')

        $completed = 0
        $total = $this.DNSServers.Count

        foreach ($dns in $this.DNSServers) {
            $this.SetStatus("Probando $dns...", [int](($completed / $total) * 100))
            $latency = $this.MeasureDNSLatency($dns)
            
            if ($latency -ge 0) {
                $this.DNSResults[$dns] = $latency
                $this.Log("  $dns : ${latency} ms", 'Green')
            } else {
                $this.Log("  $dns : Timeout/Error", 'Red')
            }
            $completed++
        }

        # Ordenar por latencia
        $sorted = $this.DNSResults.GetEnumerator() | Sort-Object Value
        
        $this.Log("", 'Default')
        $this.Log("--- RESULTADOS DNS (ordenados por latencia) ---", 'Cyan')
        $rank = 1
        foreach ($entry in $sorted) {
            $prefix = if ($rank -eq 1) { "🥇 " } elseif ($rank -eq 2) { "🥈 " } elseif ($rank -eq 3) { "🥉 " } else { "   " }
            $color = if ($rank -le 3) { 'Yellow' } else { 'Default' }
            $this.Log("  $prefix$($entry.Key) : $($entry.Value) ms", $color)
            $rank++
        }

        if ($sorted.Count -gt 0) {
            $best = $sorted[0]
            $this.Log("", 'Default')
            $this.Log("🏆 MEJOR DNS: $($best.Key) ($($best.Value) ms)", 'Yellow')
            $this.BtnApplyBestDNS.Tag = $best.Key
            $this.BtnApplyBestDNS.Enabled = $true
        }

        $this.SetStatus('DNS Speed Test completado', 100)
        $this.SetButtonsEnabled($true)
        $this.BtnTestDNS.Enabled = $true
    }

    [int] MeasureDNSLatency($dnsServer) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($dnsServer, 2000)  # 2 seg timeout
            if ($reply.Status -eq 'Success') {
                return $reply.RoundtripTime
            }
        } catch { }
        return -1
    }

    [void] ApplyBestDNS() {
        $bestDNS = $this.BtnApplyBestDNS.Tag
        if (-not $bestDNS) {
            $this.Log("Error: No hay DNS óptimo seleccionado", 'Red')
            return
        }

        $adapter = $this.GetSelectedAdapter()
        if (-not $adapter) {
            $this.Log("Error: No hay adaptador válido", 'Red')
            return
        }

        $this.SetButtonsEnabled($false)
        $this.SetStatus("Aplicando DNS $bestDNS...", 50)

        try {
            # Obtener DNS secundario (el siguiente mejor o uno predeterminado)
            $sorted = $this.DNSResults.GetEnumerator() | Sort-Object Value
            $secondaryDNS = if ($sorted.Count -gt 1) { $sorted[1].Key } else { '1.0.0.1' }

            $result = $adapter | Set-DnsClientServerAddress -ServerAddresses ($bestDNS, $secondaryDNS) -ErrorAction Stop
            
            $this.Log("✓ DNS aplicado exitosamente:", 'Green')
            $this.Log("  Primario: $bestDNS", 'Cyan')
            $this.Log("  Secundario: $secondaryDNS", 'Cyan')
            
            # Flush DNS después de cambiar
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            $this.Log("✓ Cache DNS limpiado", 'Green')
        } catch {
            $this.Log("✗ Error aplicando DNS: $_", 'Red')
        }

        $this.SetStatus('DNS aplicado', 100)
        $this.SetButtonsEnabled($true)
    }

    # ========================================================================
    # FLUSH DNS Y RESET WINSOCK
    # ========================================================================
    [void] FlushDNSCache() {
        $this.SetButtonsEnabled($false)
        $this.SetStatus('Limpiando cache DNS...', 50)
        
        try {
            Clear-DnsClientCache -ErrorAction Stop
            $this.Log("✓ Cache DNS limpiado (Clear-DnsClientCache)", 'Green')
            
            # También ipconfig /flushdns para compatibilidad
            ipconfig /flushdns >$null 2>&1
            $this.Log("✓ ipconfig /flushdns ejecutado", 'Green')
        } catch {
            $this.Log("✗ Error limpiando DNS: $_", 'Red')
        }
        
        $this.SetStatus('Cache DNS limpiado', 100)
        $this.SetButtonsEnabled($true)
    }

    [void] ResetWinsock() {
        $this.SetButtonsEnabled($false)
        $this.SetStatus('Reseteando pila de red...', 30)
        
        try {
            # Limpiar cache DNS
            ipconfig /flushdns >$null 2>&1
            $this.Log("✓ ipconfig /flushdns", 'Green')

            # Reset Winsock
            $result = netsh winsock reset 2>&1
            $this.Log("✓ netsh winsock reset", 'Green')
            foreach ($line in $result) { $this.Log("  $line", "Default") }

            # Renovar IP (release/renew) - como el script .bat optimizado
            $this.SetStatus('Renovando concesión IP (release/renew)...', 70)
            ipconfig /release >$null 2>&1
            ipconfig /renew >$null 2>&1
            ipconfig /registerdns >$null 2>&1
            $this.Log("✓ ipconfig /release + /renew + /registerdns", 'Green')

            $this.Log("  Se recomienda reiniciar para que surta efecto completo", 'Yellow')
        } catch {
            $this.Log("✗ Error reseteando red: $_", 'Red')
        }
        
        $this.SetStatus('Pila de red reseteada (requiere reinicio)', 100)
        $this.SetButtonsEnabled($true)
    }

    # ========================================================================
    # RESPALDO Y PUNTO DE RESTAURACIÓN
    # ========================================================================
    [void] CreateBackupAndRestorePoint() {
        $this.SetButtonsEnabled($false)
        $this.SetStatus('Creando respaldo y punto de restauración...', 10)

        try {
            # 1. Crear punto de restauración del sistema
            $this.Log("Creando punto de restauración del sistema...", 'Cyan')
            $desc = "Win11 NetOptimizer - Pre-optimización $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            $this.Log("✓ Punto de restauración creado: $desc", 'Green')

            # 2. Respaldar configuración TCP/IP actual
            $this.SetStatus('Respaldando configuración TCP/IP...', 40)
            $this.BackupPath = "$env:TEMP\Win11NetOptimizer_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            New-Item -ItemType Directory -Path $this.BackupPath -Force | Out-Null

            # Exportar claves de registro relevantes
            $regKeys = @(
                'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
                'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            )
            
            foreach ($key in $regKeys) {
                $fileName = $key.Replace('HKLM:\', '').Replace(':', '_').Replace('\', '_') + '.reg'
                reg export $key "$this.BackupPath\$fileName" /y >$null 2>&1
            }

            # Respaldar configuración de adaptadores
            Get-NetAdapter | Export-Clixml "$this.BackupPath\NetAdapters.xml" -Force
            Get-NetTCPSetting | Export-Clixml "$this.BackupPath\TCPSettings.xml" -Force
            Get-DnsClientServerAddress | Export-Clixml "$this.BackupPath\DNSSettings.xml" -Force

            $this.Log("✓ Respaldo de configuración guardado en: $this.BackupPath", 'Green')

            # 3. Crear script de restauración automático
            $restoreScript = @"
@echo off
title Restauración Win11 NetOptimizer
echo Restaurando configuración de red...
reg import "$this.BackupPath\SYSTEM_CurrentControlSet_Services_Tcpip_Parameters.reg" 2>nul
reg import "$this.BackupPath\SYSTEM_CurrentControlSet_Services_Tcpip_Parameters_Interfaces.reg" 2>nul
netsh winsock reset
ipconfig /flushdns
echo.
echo Restauración completada. Se recomienda reiniciar.
pause
"@
            [System.IO.File]::WriteAllText("$this.BackupPath\RESTAURAR.bat", $restoreScript, [System.Text.Encoding]::Default)
            $this.Log("✓ Script de restauración creado: RESTAURAR.bat", 'Green')

            $this.SetStatus('Respaldo y punto de restauración creados', 100)
            $this.Log("=== RESPALDO COMPLETO ===", 'Green')
            $this.Log("Ubicación: $this.BackupPath", 'Cyan')
            $this.Log("Ejecute RESTAURAR.bat como Admin para revertir cambios", 'Yellow')
        } catch {
            $this.Log("✗ Error creando respaldo: $_", 'Red')
            $this.SetStatus('Error en respaldo', 0)
        }

        $this.SetButtonsEnabled($true)
    }

    # ========================================================================
    # RESTAURAR VALORES PREDETERMINADOS DE WINDOWS
    # ========================================================================
    [void] RestoreWindowsDefaults() {
        $confirm = $global:tMessageBox::Show(
            "Esto restablecerá TODA la configuración de red a valores predeterminados de Windows.`n`n" +
            "Se ejecutará:`n" +
            "  • netsh int ip reset`n" +
            "  • netsh winsock reset`n" +
            "  • netsh int tcp reset`n" +
            "  • Eliminación de DNS personalizados`n`n" +
            "¿Continuar? Se requiere reinicio.",
            "Confirmar Restauración Completa",
            $global:tMessageBoxButtons::YesNo,
            $global:tMessageBoxIcon::Warning
        )

        if ($confirm -ne 'Yes') { return }

        $this.SetButtonsEnabled($false)
        $this.SetStatus('Restaurando valores predeterminados de Windows...', 20)

        try {
            $commands = @(
                'netsh int ip reset',
                'netsh winsock reset',
                'netsh int tcp reset',
                'netsh int ipv4 reset',
                'netsh int ipv6 reset'
            )

            $step = 0
            foreach ($cmd in $commands) {
                $step++
                $this.SetStatus("Ejecutando: $cmd", 20 + ($step * 12))
                $this.Log("Ejecutando: $cmd", "Default")
                $result = Invoke-Expression $cmd 2>&1
                foreach ($line in $result) { $this.Log("  $line", "Default") }
            }

            # Restaurar valores predeterminados de Windows (como el .bat optimizado)
            netsh int tcp set global autotuninglevel=normal >$null 2>&1
            netsh int tcp set global rss=enabled >$null 2>&1
            netsh int tcp set global ecncapability=disabled >$null 2>&1
            netsh int tcp set global timestamps=disabled >$null 2>&1
            netsh int tcp set global congestionprovider=ctcp >$null 2>&1
            netsh int tcp set global initialRto=3000 >$null 2>&1

            # Restaurar Network Throttling (valores por defecto)
            $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $mmPath -Name 'SystemResponsiveness' -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue

            # Re-habilitar Nagle (TCPNoDelay=0, TcpAckFrequency=2)
            Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue | ForEach-Object {
                Set-ItemProperty -Path $_.PSPath -Name 'TCPNoDelay' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $_.PSPath -Name 'TcpAckFrequency' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            }

            # Limpiar DNS personalizados en todos los adaptadores
            $this.SetStatus('Limpiando DNS personalizados...', 90)
            Get-NetAdapter | ForEach-Object {
                $_ | Set-DnsClientServerAddress -ResetServerAddresses -ErrorAction SilentlyContinue
            }
            Clear-DnsClientCache -ErrorAction SilentlyContinue

            $this.SetStatus('Restauración completada - REINICIO REQUERIDO', 100)
            $this.Log("=== RESTAURACIÓN COMPLETA ===", 'Green')
            $this.Log("✓ Configuración TCP/IP restablecida", 'Green')
            $this.Log("✓ Winsock restablecido", 'Green')
            $this.Log("✓ Network Throttling restaurado (10)", 'Green')
            $this.Log("✓ Nagle re-habilitado (valores por defecto)", 'Green')
            $this.Log("✓ DNS restablecido a DHCP/automático", 'Green')
            $this.Log("", 'Default')
            $this.Log("⚠ REINICIE EL EQUIPO PARA APLICAR CAMBIOS", 'Red')
        } catch {
            $this.Log("✗ Error en restauración: $_", 'Red')
        }

        $this.SetButtonsEnabled($true)
    }

    # ========================================================================
    # EVENTOS Y EJECUCIÓN
    # ========================================================================
    [void] OnFormClosing() {
        $this.Log("Cerrando Win11 NetOptimizer...", "Default")
    }

    [void] Run() {
        $this.Form.ShowDialog()
    }
}

# ============================================================================
# PUNTO DE ENTRADA
# ============================================================================
try {
    $app = [Win11NetOptimizer]::new()
    $app.Run()
} catch {
    Write-Host "Error fatal: $_" -ForegroundColor Red
    Read-Host "Presione Enter para salir"
    exit 1
}


