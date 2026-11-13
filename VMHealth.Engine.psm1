#Requires -Version 5.1
<#
.SYNOPSIS
    VM Health Check - Motore diagnostico (sola lettura) v1.0
.DESCRIPTION
    Raccoglie in 1-3 minuti lo stato di un PC Windows 10/11 e produce un report HTML (+ JSON) con semaforo
    per ogni controllo. Non modifica nulla sul sistema. Tutti i controlli sono isolati: se uno fallisce,
    gli altri proseguono e il report lo segnala.
    Funziona anche senza privilegi di amministratore (alcuni controlli risulteranno "non disponibili").
.NOTES
    (c) vm technology - uso interno.
#>
Set-StrictMode -Version 2.0
$script:Version = '1.0.1'
$script:LogCallback = $null
$script:ProgCallback = $null

function Initialize-HcCallbacks { param([scriptblock]$OnLog, [scriptblock]$OnProgress) $script:LogCallback = $OnLog; $script:ProgCallback = $OnProgress }
function Write-HcLog { param([string]$Message, [string]$Level = 'INFO') if ($script:LogCallback) { try { & $script:LogCallback $Level $Message } catch {} } }
function Write-HcProgress { param([double]$Percent, [string]$Status) if ($script:ProgCallback) { try { & $script:ProgCallback $Percent $Status } catch {} } }
function Test-HcAdmin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Format-HcBytes { param([double]$B) if ($B -ge 1TB) { '{0:N2} TB' -f ($B/1TB) } elseif ($B -ge 1GB) { '{0:N1} GB' -f ($B/1GB) } elseif ($B -ge 1MB) { '{0:N0} MB' -f ($B/1MB) } else { '{0:N0} KB' -f ($B/1KB) } }

# Risultato di un controllo: Stato = OK | WARN | CRIT | INFO | NA
function New-HcResult {
    param([string]$Id, [string]$Categoria, [string]$Titolo, [ValidateSet('OK','WARN','CRIT','INFO','NA')][string]$Stato, [string]$Messaggio, $Dettagli = $null, [string]$Azione = '')
    [pscustomobject]@{ Id = $Id; Categoria = $Categoria; Titolo = $Titolo; Stato = $Stato; Messaggio = $Messaggio; Dettagli = $Dettagli; Azione = $Azione }
}

# ------------------------------------------------------------------------------
#  CONTROLLI (ognuno ritorna uno o piu' New-HcResult)
# ------------------------------------------------------------------------------
function Test-HcSistema {
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = "$($cv.CurrentBuildNumber).$($cv.UBR)"; $ver = $cv.DisplayVersion; if (-not $ver) { $ver = $cv.ReleaseId }
    $uptime = (Get-Date) - $os.LastBootUpTime
    $r = @()
    $r += New-HcResult 'sys.info' 'Sistema' 'Computer' 'INFO' ("{0} {1} - S/N {2} - BIOS {3} ({4})" -f $cs.Manufacturer, $cs.Model, $bios.SerialNumber, $bios.SMBIOSBIOSVersion, $bios.ReleaseDate.ToString('yyyy-MM-dd')) @{ Nome = $env:COMPUTERNAME; Dominio = $cs.Domain; Utente = "$env:USERDOMAIN\$env:USERNAME" }
    $r += New-HcResult 'sys.os' 'Sistema' 'Windows' 'INFO' ("{0} {1} build {2} ({3}) - installato il {4}" -f $os.Caption, $ver, $build, $os.OSArchitecture, $os.InstallDate.ToString('dd/MM/yyyy'))
    # Fine supporto Windows 10 (14/10/2025) o versioni vecchie di Win11
    if ($os.Caption -like '*Windows 10*') { $r += New-HcResult 'sys.eol' 'Sistema' 'Supporto Windows' 'CRIT' 'Windows 10 e'' fuori supporto dal 14/10/2025: nessun aggiornamento di sicurezza (salvo ESU).' $null 'Aggiornare a Windows 11 o attivare le Extended Security Updates.' }
    elseif ([int]$cv.CurrentBuildNumber -lt 26100) { $r += New-HcResult 'sys.eol' 'Sistema' 'Versione Windows 11' 'WARN' "Versione $ver (build $build) non e'' l''ultima: verificare che sia ancora supportata." $null 'Eseguire l''aggiornamento di versione da Windows Update.' }
    else { $r += New-HcResult 'sys.eol' 'Sistema' 'Versione Windows 11' 'OK' "Versione $ver (build $build) supportata." }
    $r += New-HcResult 'sys.uptime' 'Sistema' 'Tempo dall''ultimo riavvio' $(if ($uptime.TotalDays -gt 14) { 'WARN' } else { 'OK' }) ("{0} giorni, {1} ore" -f [int]$uptime.TotalDays, $uptime.Hours) $null $(if ($uptime.TotalDays -gt 14) { 'Riavviare il PC: l''avvio rapido maschera i riavvii mancati.' } else { '' })
    # Attivazione
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
        $st = switch ([int]$lic.LicenseStatus) { 1 { 'OK' } 0 { 'CRIT' } default { 'WARN' } }
        $txt = switch ([int]$lic.LicenseStatus) { 1 { 'Windows attivato' } 0 { 'Windows NON attivato' } 2 { 'Periodo di prova' } 5 { 'Notifica: attivazione richiesta' } default { "Stato licenza $($lic.LicenseStatus)" } }
        $r += New-HcResult 'sys.act' 'Sistema' 'Attivazione' $st ("{0} ({1})" -f $txt, $lic.Name) $null $(if ($st -ne 'OK') { 'Verificare la licenza in Impostazioni > Sistema > Attivazione.' } else { '' })
    } catch { $r += New-HcResult 'sys.act' 'Sistema' 'Attivazione' 'NA' 'Non rilevabile' }
    # Riavvio in sospeso
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) -ne $null)
    $r += New-HcResult 'sys.reboot' 'Sistema' 'Riavvio in sospeso' $(if ($pending) { 'WARN' } else { 'OK' }) $(if ($pending) { 'Il sistema richiede un riavvio per completare aggiornamenti/installazioni.' } else { 'Nessun riavvio in sospeso.' })
    return $r
}

function Test-HcHardware {
    $r = @()
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cs = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem
    $ramTot = $cs.TotalPhysicalMemory; $ramFree = $os.FreePhysicalMemory * 1KB; $ramPct = [math]::Round((1 - $ramFree / $ramTot) * 100)
    $r += New-HcResult 'hw.cpu' 'Hardware' 'Processore' 'INFO' ("{0} - {1} core / {2} thread - carico attuale {3}%" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $cpu.LoadPercentage)
    $ramSt = if ($ramTot -lt 7.5GB) { 'WARN' } elseif ($ramPct -gt 90) { 'WARN' } else { 'OK' }
    $r += New-HcResult 'hw.ram' 'Hardware' 'Memoria RAM' $ramSt ("{0} totali, {1}% in uso" -f (Format-HcBytes $ramTot), $ramPct) $null $(if ($ramTot -lt 7.5GB) { 'Meno di 8 GB: PC lento con Office + browser; valutare upgrade.' } elseif ($ramPct -gt 90) { 'Memoria quasi esaurita: chiudere programmi o aggiungere RAM.' } else { '' })
    # TPM / Secure Boot
    try { $tpm = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop; $r += New-HcResult 'hw.tpm' 'Hardware' 'TPM' $(if ($tpm.IsEnabled_InitialValue -and $tpm.SpecVersion -like '2.0*') { 'OK' } else { 'WARN' }) ("TPM {0}, abilitato: {1}" -f ($tpm.SpecVersion -split ',')[0], $tpm.IsEnabled_InitialValue) } catch { $r += New-HcResult 'hw.tpm' 'Hardware' 'TPM' 'NA' 'Non rilevabile (servono privilegi di amministratore)' }
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; $r += New-HcResult 'hw.sb' 'Hardware' 'Secure Boot' $(if ($sb) { 'OK' } else { 'WARN' }) $(if ($sb) { 'Attivo' } else { 'Disattivato' }) } catch { $r += New-HcResult 'hw.sb' 'Hardware' 'Secure Boot' 'NA' 'Non rilevabile (BIOS legacy o permessi insufficienti)' }
    # Batteria
    try {
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if ($bat) {
            $full = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
            $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1).DesignedCapacity
            $health = if ($full -and $design) { [math]::Round($full / $design * 100) } else { $null }
            $st = if ($health -and $health -lt 60) { 'WARN' } else { 'OK' }
            $r += New-HcResult 'hw.bat' 'Hardware' 'Batteria' $st ("Carica {0}% - salute {1}" -f $bat.EstimatedChargeRemaining, $(if ($health) { "$health% della capacita' originale" } else { 'n/d' })) $null $(if ($st -eq 'WARN') { 'Batteria usurata: autonomia ridotta, valutare sostituzione.' } else { '' })
        }
    } catch {}
    # Driver con problemi
    try {
        $bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 })
        $r += New-HcResult 'hw.drv' 'Hardware' 'Dispositivi con errori' $(if ($bad.Count -gt 0) { 'WARN' } else { 'OK' }) $(if ($bad.Count -gt 0) { "$($bad.Count) dispositivi con errore in Gestione dispositivi" } else { 'Nessun dispositivo in errore' }) @($bad | Select-Object -First 10 | ForEach-Object { "{0} (codice {1})" -f $_.Name, $_.ConfigManagerErrorCode }) $(if ($bad.Count -gt 0) { 'Installare i driver mancanti dal sito del produttore.' } else { '' })
    } catch {}
    # Temperatura (spesso non esposta)
    try { $t = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1; if ($t) { $c = [math]::Round(($t.CurrentTemperature / 10) - 273.15); $r += New-HcResult 'hw.temp' 'Hardware' 'Temperatura (zona termica)' $(if ($c -gt 85) { 'WARN' } else { 'OK' }) "$c C" } } catch {}
    return $r
}

function Test-HcDischi {
    $r = @()
    # Spazio
    foreach ($v in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        if (-not $v.Size) { continue }
        $pct = [math]::Round($v.FreeSpace / $v.Size * 100)
        $st = if ($pct -lt 10 -or $v.FreeSpace -lt 10GB) { 'CRIT' } elseif ($pct -lt 20) { 'WARN' } else { 'OK' }
        $r += New-HcResult "disk.space.$($v.DeviceID[0])" 'Dischi' "Spazio su $($v.DeviceID)" $st ("{0} liberi su {1} ({2}%)" -f (Format-HcBytes $v.FreeSpace), (Format-HcBytes $v.Size), $pct) $null $(if ($st -ne 'OK') { 'Liberare spazio: Pulizia disco, Download, cestino, vecchi aggiornamenti (DISM /StartComponentCleanup).' } else { '' })
    }
    # Salute fisica (SMART via Storage API)
    try {
        foreach ($pd in Get-PhysicalDisk -ErrorAction Stop) {
            $rel = $null; try { $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
            $st = switch ([string]$pd.HealthStatus) { 'Healthy' { 'OK' } 'Warning' { 'WARN' } 'Unhealthy' { 'CRIT' } default { 'INFO' } }
            $det = @{ Tipo = [string]$pd.MediaType; Bus = [string]$pd.BusType; Dimensione = (Format-HcBytes $pd.Size); Stato = [string]$pd.HealthStatus; Operativo = ([string]$pd.OperationalStatus) }
            $msg = "{0} {1} {2} - stato {3}" -f $pd.FriendlyName, [string]$pd.MediaType, (Format-HcBytes $pd.Size), $pd.HealthStatus
            if ($rel) {
                $det.Temperatura = $rel.Temperature; $det.OreAccensione = $rel.PowerOnHours; $det.Usura = $rel.Wear; $det.ErroriLetturaNonCorretti = $rel.ReadErrorsUncorrected; $det.ErroriScritturaNonCorretti = $rel.WriteErrorsUncorrected
                if ($rel.Wear -and $rel.Wear -gt 80) { $st = 'WARN' }
                if (($rel.ReadErrorsUncorrected -gt 0) -or ($rel.WriteErrorsUncorrected -gt 0)) { $st = 'WARN' }
                if ($rel.Temperature -and $rel.Temperature -gt 60) { if ($st -eq 'OK') { $st = 'WARN' } }
                $msg += (" - {0}C, {1} h, usura {2}%" -f $rel.Temperature, $rel.PowerOnHours, $rel.Wear)
            }
            $r += New-HcResult "disk.smart.$($pd.DeviceId)" 'Dischi' "Salute disco $($pd.DeviceId)" $st $msg $det $(if ($st -ne 'OK') { 'Fare subito un backup completo e pianificare la sostituzione del disco.' } else { '' })
        }
    } catch { $r += New-HcResult 'disk.smart' 'Dischi' 'Salute dischi (SMART)' 'NA' "Non disponibile: $($_.Exception.Message)" }
    # Predizione guasto WMI (vecchio ma utile sui SATA)
    try { $fp = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Where-Object PredictFailure); if ($fp.Count -gt 0) { $r += New-HcResult 'disk.predict' 'Dischi' 'Predizione guasto SMART' 'CRIT' "$($fp.Count) disco/i segnalano guasto imminente" $null 'Backup immediato e sostituzione.' } } catch {}
    # Dirty bit / errori file system ed eventi disco
    foreach ($v in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        $o = & fsutil.exe dirty query $v.DeviceID 2>&1
        if ("$o" -match 'is Dirty|e'' danneggiato|E'' DIRTY|DIRTY') { $r += New-HcResult "disk.dirty.$($v.DeviceID[0])" 'Dischi' "File system $($v.DeviceID)" 'WARN' 'Volume marcato "dirty": serve chkdsk al riavvio.' $null "Eseguire: chkdsk $($v.DeviceID) /f" }
    }
    try {
        $since = (Get-Date).AddDays(-7)
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Id = @(7, 11, 51, 55, 98, 129, 153, 157) } -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'disk|ntfs|storahci|stornvme|iaStor|volmgr' })
        $r += New-HcResult 'disk.events' 'Dischi' 'Errori disco negli ultimi 7 giorni' $(if ($ev.Count -gt 20) { 'CRIT' } elseif ($ev.Count -gt 0) { 'WARN' } else { 'OK' }) $(if ($ev.Count -gt 0) { "$($ev.Count) eventi disco/NTFS (ID 7/11/51/55/98/129/153/157)" } else { 'Nessun errore disco registrato' }) @($ev | Group-Object Id | ForEach-Object { "ID {0}: {1} volte" -f $_.Name, $_.Count }) $(if ($ev.Count -gt 0) { 'Controllare cavi/disco; eseguire chkdsk e un backup.' } else { '' })
    } catch {}
    return $r
}

function Test-HcEventi {
    $r = @()
    try {
        $since = (Get-Date).AddDays(-7)
        $crit = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = @(1, 2); StartTime = $since } -ErrorAction SilentlyContinue)
        $top = $crit | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
        $r += New-HcResult 'ev.sys' 'Eventi' 'Errori registro Sistema (7 giorni)' $(if ($crit.Count -gt 100) { 'WARN' } elseif ($crit.Count -gt 0) { 'INFO' } else { 'OK' }) "$($crit.Count) errori/critici" @($top)
        $kp = @($crit | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41 })
        $bug = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue)
        $r += New-HcResult 'ev.crash' 'Eventi' 'Spegnimenti anomali / schermate blu' $(if ($bug.Count -gt 0) { 'CRIT' } elseif ($kp.Count -gt 2) { 'WARN' } elseif ($kp.Count -gt 0) { 'INFO' } else { 'OK' }) ("{0} spegnimenti improvvisi (Kernel-Power 41) in 7 giorni, {1} BSOD in 30 giorni" -f $kp.Count, $bug.Count) @($bug | Select-Object -First 5 | ForEach-Object { $_.TimeCreated.ToString('dd/MM HH:mm') + ' ' + ($_.Message -split "`n")[0] }) $(if ($bug.Count -gt 0) { 'Analizzare i minidump (C:\Windows\Minidump) con WinDbg/BlueScreenView; spesso driver o RAM.' } elseif ($kp.Count -gt 2) { 'Verificare alimentazione, surriscaldamento e che il PC non venga spento a forza.' } else { '' })
        $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -ErrorAction SilentlyContinue)
        if ($whea.Count -gt 0) { $r += New-HcResult 'ev.whea' 'Eventi' 'Errori hardware (WHEA)' 'WARN' "$($whea.Count) errori hardware corretti/non corretti" $null 'Possibile problema CPU/RAM/PCIe: eseguire test memoria (mdsched) e aggiornare BIOS.' }
        $app = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 2; StartTime = $since; ProviderName = 'Application Error' } -ErrorAction SilentlyContinue)
        $topApp = $app | ForEach-Object { if ($_.Message -match 'Nome dell''applicazione.*?: (.+?),|Faulting application name: (.+?),') { $(if ($Matches[1]) { $Matches[1] } else { $Matches[2] }) } } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "{0}: {1} crash" -f $_.Name, $_.Count }
        $r += New-HcResult 'ev.app' 'Eventi' 'Crash applicazioni (7 giorni)' $(if ($app.Count -gt 10) { 'WARN' } elseif ($app.Count -gt 0) { 'INFO' } else { 'OK' }) "$($app.Count) crash applicativi" @($topApp)
    } catch { $r += New-HcResult 'ev.sys' 'Eventi' 'Registro eventi' 'NA' $_.Exception.Message }
    return $r
}

function Test-HcAvvio {
    $r = @()
    try {
        $boot = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 10 -ErrorAction SilentlyContinue)
        if ($boot.Count -gt 0) {
            $ms = $boot | ForEach-Object { [int]([xml]$_.ToXml()).Event.EventData.Data[0].'#text' } | Measure-Object -Average
            $sec = [math]::Round($ms.Average / 1000)
            $r += New-HcResult 'boot.time' 'Avvio' 'Tempo di avvio medio (ultimi 10)' $(if ($sec -gt 120) { 'WARN' } elseif ($sec -gt 60) { 'INFO' } else { 'OK' }) "$sec secondi" $null $(if ($sec -gt 120) { 'Avvio lento: ridurre i programmi in esecuzione automatica, verificare disco (SSD?) e antivirus.' } else { '' })
        }
    } catch {}
    $items = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $items += "{0} = {1}" -f $_.Name, $_.Value } }
    }
    foreach ($d in "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp") { Get-ChildItem -LiteralPath $d -ErrorAction SilentlyContinue | ForEach-Object { $items += "Cartella Esecuzione automatica: $($_.Name)" } }
    try { Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }) } | ForEach-Object { $items += "Attivita' pianificata all'avvio/accesso: $($_.TaskName)" } } catch {}
    $r += New-HcResult 'boot.startup' 'Avvio' 'Programmi in esecuzione automatica' $(if ($items.Count -gt 15) { 'WARN' } elseif ($items.Count -gt 8) { 'INFO' } else { 'OK' }) "$($items.Count) elementi" @($items) $(if ($items.Count -gt 15) { 'Disattivare il superfluo da Gestione attivita'' > Avvio.' } else { '' })
    return $r
}

function Test-HcAggiornamenti {
    $r = @()
    try {
        $hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
        $days = if ($hf) { [int]((Get-Date) - $hf.InstalledOn).TotalDays } else { 999 }
        $r += New-HcResult 'wu.last' 'Aggiornamenti' 'Ultimo aggiornamento installato' $(if ($days -gt 60) { 'CRIT' } elseif ($days -gt 35) { 'WARN' } else { 'OK' }) $(if ($hf) { "{0} il {1} ({2} giorni fa)" -f $hf.HotFixID, $hf.InstalledOn.ToString('dd/MM/yyyy'), $days } else { 'Nessun aggiornamento trovato' }) $null $(if ($days -gt 35) { 'Eseguire Windows Update e verificare che non sia bloccato (servizio wuauserv, spazio disco, criteri).' } else { '' })
    } catch {}
    try {
        $s = New-Object -ComObject Microsoft.Update.Session; $searcher = $s.CreateUpdateSearcher(); $searcher.Online = $false
        $res = $searcher.Search('IsInstalled=0 and IsHidden=0')
        $n = $res.Updates.Count
        $sec = @(0..($n - 1) | ForEach-Object { $res.Updates.Item($_) } | Where-Object { $_.MsrcSeverity -in 'Critical','Important' }).Count
        $r += New-HcResult 'wu.pending' 'Aggiornamenti' 'Aggiornamenti in attesa (cache locale)' $(if ($sec -gt 0) { 'WARN' } elseif ($n -gt 5) { 'INFO' } else { 'OK' }) "$n aggiornamenti non installati, di cui $sec di sicurezza critici/importanti" @(0..([math]::Min($n, 8) - 1) | Where-Object { $n -gt 0 } | ForEach-Object { $res.Updates.Item($_).Title })
    } catch { $r += New-HcResult 'wu.pending' 'Aggiornamenti' 'Aggiornamenti in attesa' 'NA' 'Non rilevabile (Windows Update non raggiungibile o servizio fermo)' }
    try { $svc = Get-Service wuauserv -ErrorAction Stop; if ($svc.StartType -eq 'Disabled') { $r += New-HcResult 'wu.svc' 'Aggiornamenti' 'Servizio Windows Update' 'CRIT' 'Il servizio Windows Update e'' disabilitato.' $null 'Riabilitare il servizio wuauserv (avvio manuale).' } } catch {}
    return $r
}

function Test-HcSicurezza {
    $r = @()
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $sigAge = [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
        $st = if (-not $mp.RealTimeProtectionEnabled -or -not $mp.AntivirusEnabled) { 'CRIT' } elseif ($sigAge -gt 7) { 'WARN' } else { 'OK' }
        $r += New-HcResult 'sec.av' 'Sicurezza' 'Antivirus (Microsoft Defender)' $st ("Protezione in tempo reale: {0} - firme aggiornate {1} giorni fa - ultima scansione rapida: {2}" -f $mp.RealTimeProtectionEnabled, $sigAge, $(if ($mp.QuickScanEndTime) { $mp.QuickScanEndTime.ToString('dd/MM/yyyy') } else { 'mai' })) $null $(if ($st -ne 'OK') { 'Attivare la protezione in tempo reale o aggiornare le firme. Se c''e'' un altro antivirus, verificarne lo stato.' } else { '' })
    } catch {
        $av = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
        if ($av) { $r += New-HcResult 'sec.av' 'Sicurezza' 'Antivirus' 'INFO' ("Antivirus di terze parti: {0}" -f (($av | ForEach-Object { $_.displayName }) -join ', ')) } else { $r += New-HcResult 'sec.av' 'Sicurezza' 'Antivirus' 'NA' 'Stato non rilevabile' }
    }
    try { $fw = Get-NetFirewallProfile -ErrorAction Stop; $off = @($fw | Where-Object { -not $_.Enabled }); $r += New-HcResult 'sec.fw' 'Sicurezza' 'Firewall di Windows' $(if ($off.Count -gt 0) { 'WARN' } else { 'OK' }) $(if ($off.Count -gt 0) { "Disattivato per i profili: " + (($off | ForEach-Object { $_.Name }) -join ', ') } else { 'Attivo su tutti i profili' }) } catch {}
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $r += New-HcResult 'sec.bl' 'Sicurezza' 'Crittografia disco (BitLocker)' $(if ($bl.ProtectionStatus -eq 'On') { 'OK' } else { 'WARN' }) ("Disco di sistema: {0} ({1}% cifrato)" -f $bl.ProtectionStatus, $bl.EncryptionPercentage) $null $(if ($bl.ProtectionStatus -ne 'On') { 'Per PC portatili e dati aziendali attivare BitLocker e salvare la chiave di ripristino.' } else { '' })
    } catch { $r += New-HcResult 'sec.bl' 'Sicurezza' 'Crittografia disco (BitLocker)' 'NA' 'Non rilevabile (edizione Home o permessi insufficienti)' }
    try { $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA; $r += New-HcResult 'sec.uac' 'Sicurezza' 'Controllo account utente (UAC)' $(if ($uac -eq 1) { 'OK' } else { 'CRIT' }) $(if ($uac -eq 1) { 'Attivo' } else { 'DISATTIVATO' }) $null $(if ($uac -ne 1) { 'Riattivare UAC.' } else { '' }) } catch {}
    try { $smb1 = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop).State; $r += New-HcResult 'sec.smb1' 'Sicurezza' 'Protocollo SMBv1' $(if ($smb1 -eq 'Enabled') { 'WARN' } else { 'OK' }) $(if ($smb1 -eq 'Enabled') { 'Abilitato (obsoleto e insicuro)' } else { 'Disabilitato' }) $null $(if ($smb1 -eq 'Enabled') { 'Disabilitare SMB1 salvo dispositivi legacy (vecchie multifunzione/NAS).' } else { '' }) } catch {}
    try { $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections; $r += New-HcResult 'sec.rdp' 'Sicurezza' 'Desktop remoto' 'INFO' $(if ($rdp -eq 0) { 'Abilitato' } else { 'Disabilitato' }) } catch {}
    try {
        $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { $_.Name })
        $r += New-HcResult 'sec.admins' 'Sicurezza' 'Amministratori locali' $(if ($admins.Count -gt 3) { 'WARN' } else { 'INFO' }) ($admins -join ', ') $null $(if ($admins.Count -gt 3) { 'Ridurre gli account amministratore: gli utenti normali dovrebbero essere Users.' } else { '' })
        $noPwd = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and -not $_.PasswordRequired })
        if ($noPwd.Count -gt 0) { $r += New-HcResult 'sec.nopwd' 'Sicurezza' 'Account senza password' 'CRIT' (($noPwd | ForEach-Object { $_.Name }) -join ', ') $null 'Impostare una password per tutti gli account attivi.' }
        $auto = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
        if ($auto.AutoAdminLogon -eq '1') { $r += New-HcResult 'sec.autologon' 'Sicurezza' 'Accesso automatico' 'WARN' "Accesso automatico attivo per $($auto.DefaultUserName)" $null 'Disattivare l''accesso automatico (netplwiz) sui PC con dati aziendali.' }
    } catch {}
    return $r
}

function Test-HcRete {
    $r = @()
    try {
        $ad = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
        $det = @()
        foreach ($a in $ad) { $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress; $det += "{0} ({1}) {2} - {3}" -f $a.Name, $a.InterfaceDescription, $a.LinkSpeed, $ip }
        $r += New-HcResult 'net.adapters' 'Rete' 'Schede di rete attive' $(if ($ad.Count -eq 0) { 'CRIT' } else { 'INFO' }) "$($ad.Count) connesse" @($det)
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        if ($gw) { $p = Test-Connection -ComputerName $gw -Count 2 -Quiet -ErrorAction SilentlyContinue; $r += New-HcResult 'net.gw' 'Rete' "Gateway $gw" $(if ($p) { 'OK' } else { 'CRIT' }) $(if ($p) { 'Raggiungibile' } else { 'Non risponde al ping' }) }
        $dnsOk = $false; try { $null = [System.Net.Dns]::GetHostAddresses('www.microsoft.com'); $dnsOk = $true } catch {}
        $inet = Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet -ErrorAction SilentlyContinue
        $r += New-HcResult 'net.inet' 'Rete' 'Internet e DNS' $(if ($inet -and $dnsOk) { 'OK' } elseif ($inet) { 'WARN' } else { 'CRIT' }) ("Internet (1.1.1.1): {0} - risoluzione DNS: {1}" -f $(if ($inet) { 'ok' } else { 'NO' }), $(if ($dnsOk) { 'ok' } else { 'NO' })) $null $(if (-not $dnsOk -and $inet) { 'Internet c''e'' ma il DNS non risolve: controllare i server DNS della scheda/router.' } elseif (-not $inet) { 'Nessuna connessione Internet.' } else { '' })
        $dnsSrv = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses -join ', '
        $r += New-HcResult 'net.dns' 'Rete' 'Server DNS' 'INFO' $dnsSrv
        $prof = (Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($prof) { $r += New-HcResult 'net.profile' 'Rete' 'Profilo di rete' $(if ($prof.NetworkCategory -eq 'Public' -and $prof.InterfaceAlias -notmatch 'Wi-?Fi') { 'INFO' } else { 'INFO' }) ("{0}: {1}" -f $prof.Name, $prof.NetworkCategory) }
    } catch { $r += New-HcResult 'net.adapters' 'Rete' 'Rete' 'NA' $_.Exception.Message }
    try { $w32 = & w32tm.exe /query /status 2>&1; $src = ($w32 | Select-String 'Origine|Source').ToString(); $r += New-HcResult 'net.time' 'Rete' 'Sincronizzazione orario' $(if ($src -match 'Local CMOS|Orologio CMOS') { 'WARN' } else { 'OK' }) $src.Trim() } catch {}
    return $r
}

function Test-HcStampantiEServizi {
    $r = @()
    try {
        $pr = @(Get-Printer -ErrorAction Stop | Where-Object { $_.PrinterStatus -notin 'Normal', 0 -and $_.Name -notmatch 'PDF|XPS|Fax|OneNote' })
        $spool = Get-Service Spooler -ErrorAction SilentlyContinue
        $jobs = 0; try { $jobs = @(Get-Printer -ErrorAction Stop | Get-PrintJob -ErrorAction SilentlyContinue).Count } catch {}
        $st = if ($spool.Status -ne 'Running') { 'CRIT' } elseif ($pr.Count -gt 0 -or $jobs -gt 5) { 'WARN' } else { 'OK' }
        $r += New-HcResult 'prn' 'Stampanti' 'Stampanti e spooler' $st ("Spooler: {0} - {1} stampanti in stato anomalo - {2} lavori in coda" -f $spool.Status, $pr.Count, $jobs) @($pr | ForEach-Object { "{0}: {1}" -f $_.Name, $_.PrinterStatus }) $(if ($st -ne 'OK') { 'Riavviare lo spooler e svuotare C:\Windows\System32\spool\PRINTERS.' } else { '' })
    } catch {}
    try {
        $svcs = @(Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' -and $_.Name -notmatch '^(sppsvc|RemoteRegistry|MapsBroker|gupdate|edgeupdate|BITS|wuauserv|TrustedInstaller|WbioSrvc|CDPSvc|dmwappushservice|MSDTC|SharedAccess|tiledatamodelsvc|GoogleUpdater|MicrosoftEdgeElevationService)' })
        $r += New-HcResult 'svc.auto' 'Servizi' 'Servizi automatici non in esecuzione' $(if ($svcs.Count -gt 3) { 'WARN' } elseif ($svcs.Count -gt 0) { 'INFO' } else { 'OK' }) "$($svcs.Count) servizi" @($svcs | Select-Object -First 10 | ForEach-Object { "{0} ({1})" -f $_.DisplayName, $_.Name })
    } catch {}
    try { $rp = Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object CreationTime -Descending | Select-Object -First 1; $r += New-HcResult 'svc.restore' 'Servizi' 'Ripristino configurazione di sistema' $(if ($rp) { 'OK' } else { 'INFO' }) $(if ($rp) { "Ultimo punto: $($rp.Description) del $([management.managementDateTimeConverter]::ToDateTime($rp.CreationTime).ToString('dd/MM/yyyy'))" } else { 'Nessun punto di ripristino (protezione sistema disattivata?)' }) } catch {}
    try {
        $temp = (Get-ChildItem -LiteralPath $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $wtemp = (Get-ChildItem -LiteralPath "$env:SystemRoot\Temp" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $tot = [double]$temp + [double]$wtemp
        $r += New-HcResult 'svc.temp' 'Servizi' 'File temporanei' $(if ($tot -gt 5GB) { 'WARN' } else { 'INFO' }) (Format-HcBytes $tot) $null $(if ($tot -gt 5GB) { 'Eseguire Pulizia disco / Impostazioni > Archiviazione.' } else { '' })
    } catch {}
    return $r
}

function Test-HcIntegrita {
    param([bool]$Deep = $false)
    $r = @()
    if (-not $Deep) { $r += New-HcResult 'int.skip' 'Integrita'' sistema' 'SFC / DISM' 'INFO' 'Controllo approfondito non eseguito (opzione "Analisi approfondita").'; return $r }
    if (-not (Test-HcAdmin)) { $r += New-HcResult 'int.sfc' 'Integrita'' sistema' 'SFC / DISM' 'NA' 'Servono privilegi di amministratore.'; return $r }
    try {
        Write-HcProgress -Percent 85 -Status 'DISM: verifica archivio componenti (puo'' richiedere minuti)...'
        $d = & DISM.exe /Online /Cleanup-Image /ScanHealth 2>&1 | Out-String
        $dSt = if ($d -match 'No component store corruption|Nessun danneggiamento') { 'OK' } elseif ($d -match 'repairable|riparabil') { 'WARN' } elseif ($d -match 'not repairable|non riparabil') { 'CRIT' } else { 'INFO' }
        $r += New-HcResult 'int.dism' 'Integrita'' sistema' 'DISM ScanHealth' $dSt (($d -split "`n" | Where-Object { $_ -match 'corruption|danneggiamento|repair|ripar' } | Select-Object -First 2) -join ' ') $null $(if ($dSt -ne 'OK') { 'Eseguire: DISM /Online /Cleanup-Image /RestoreHealth' } else { '' })
        Write-HcProgress -Percent 92 -Status 'SFC: verifica file di sistema...'
        $s = & sfc.exe /verifyonly 2>&1 | Out-String
        $s = ($s -replace "`0", '')
        $sSt = if ($s -match 'did not find any integrity violations|non ha rilevato violazioni') { 'OK' } elseif ($s -match 'found integrity violations|ha rilevato') { 'WARN' } else { 'INFO' }
        $r += New-HcResult 'int.sfc' 'Integrita'' sistema' 'SFC /verifyonly' $sSt (($s -split "`n" | Where-Object { $_ -match 'integrity|integrit' } | Select-Object -First 1) -join ' ') $null $(if ($sSt -ne 'OK') { 'Eseguire: sfc /scannow' } else { '' })
    } catch { $r += New-HcResult 'int.sfc' 'Integrita'' sistema' 'SFC / DISM' 'NA' $_.Exception.Message }
    return $r
}

# ------------------------------------------------------------------------------
#  ESECUZIONE
# ------------------------------------------------------------------------------
function Invoke-HcCheck {
    <# Esegue tutti i controlli. Ritorna oggetto con Risultati, Riepilogo, Durata, Computer. #>
    [CmdletBinding()]
    param([bool]$Deep = $false)
    $started = Get-Date
    $steps = @(
        @{ Nome = 'Sistema';        Fn = { Test-HcSistema } }
        @{ Nome = 'Hardware';       Fn = { Test-HcHardware } }
        @{ Nome = 'Dischi';         Fn = { Test-HcDischi } }
        @{ Nome = 'Eventi';         Fn = { Test-HcEventi } }
        @{ Nome = 'Avvio';          Fn = { Test-HcAvvio } }
        @{ Nome = 'Aggiornamenti';  Fn = { Test-HcAggiornamenti } }
        @{ Nome = 'Sicurezza';      Fn = { Test-HcSicurezza } }
        @{ Nome = 'Rete';           Fn = { Test-HcRete } }
        @{ Nome = 'Stampanti e servizi'; Fn = { Test-HcStampantiEServizi } }
        @{ Nome = 'Integrita'' sistema'; Fn = { Test-HcIntegrita -Deep $Deep } }
    )
    $results = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($s in $steps) {
        $i++
        Write-HcProgress -Percent (($i - 1) / $steps.Count * 100) -Status "Controllo: $($s.Nome)..."
        Write-HcLog "Controllo $($s.Nome)"
        try { foreach ($x in @(& $s.Fn)) { if ($x) { $results.Add($x); Write-HcLog -Level $x.Stato -Message ("{0}: {1}" -f $x.Titolo, $x.Messaggio) } } }
        catch { $results.Add((New-HcResult "err.$i" $s.Nome $s.Nome 'NA' "Controllo fallito: $($_.Exception.Message)")); Write-HcLog -Level 'WARN' -Message "$($s.Nome): $($_.Exception.Message)" }
    }
    Write-HcProgress -Percent 100 -Status 'Completato'
    $crit = 0; $warn = 0; $ok = 0
    foreach ($x in $results) { $stx = [string]$x.Stato; if ($stx -eq 'CRIT') { $crit++ } elseif ($stx -eq 'WARN') { $warn++ } elseif ($stx -eq 'OK') { $ok++ } }
    $sem = 'VERDE'; if ($warn -gt 0) { $sem = 'GIALLO' }; if ($crit -gt 0) { $sem = 'ROSSO' }
    $out = New-Object psobject
    $out | Add-Member NoteProperty Versione $script:Version
    $out | Add-Member NoteProperty Computer $env:COMPUTERNAME
    $out | Add-Member NoteProperty Utente ($env:USERDOMAIN + '\' + $env:USERNAME)
    $out | Add-Member NoteProperty Amministratore (Test-HcAdmin)
    $out | Add-Member NoteProperty Inizio $started
    $out | Add-Member NoteProperty Durata ((Get-Date) - $started)
    $out | Add-Member NoteProperty Semaforo $sem
    $out | Add-Member NoteProperty Critici $crit
    $out | Add-Member NoteProperty Avvisi $warn
    $out | Add-Member NoteProperty Ok $ok
    $out | Add-Member NoteProperty Risultati $results.ToArray()
    return $out
}

function ConvertTo-HcHtml { param($Text) return [System.Net.WebUtility]::HtmlEncode([string]$Text) }

function Export-HcReport {
    <# Scrive report HTML autonomo (stile vm technology) + JSON. Ritorna il percorso HTML. #>
    param([Parameter(Mandatory)]$Check, [Parameter(Mandatory)][string]$OutFolder, [string]$Tecnico = '', [string]$Cliente = '', [string]$LogoBase64 = '')
    if (-not (Test-Path -LiteralPath $OutFolder)) { New-Item -ItemType Directory -Path $OutFolder -Force | Out-Null }
    $inizio = [datetime]$Check.Inizio
    $base = Join-Path $OutFolder ('HealthCheck_' + [string]$Check.Computer + '_' + $inizio.ToString('yyyyMMdd-HHmm'))
    # JSON: non deve mai impedire la creazione del report
    try { $Check | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($base + '.json') -Encoding UTF8 } catch { Write-HcLog -Level 'WARN' -Message ('JSON non scritto: ' + $_.Exception.Message) }

    $color = @{ OK = '#2ecc71'; WARN = '#f1c40f'; CRIT = '#e74c3c'; INFO = '#38d6ff'; NA = '#8fa3c7' }
    $label = @{ OK = 'OK'; WARN = 'Attenzione'; CRIT = 'Critico'; INFO = 'Info'; NA = 'N/D' }
    $rank  = @{ CRIT = 0; WARN = 1; OK = 2; INFO = 3; NA = 4 }
    $semaforo = [string]$Check.Semaforo
    $semColor = '#2ecc71'; $semText = 'Nessun problema rilevante: il PC e'' in buone condizioni.'
    if ($semaforo -eq 'GIALLO') { $semColor = '#f1c40f'; $semText = 'Alcuni punti meritano attenzione: vedere le voci gialle.' }
    if ($semaforo -eq 'ROSSO')  { $semColor = '#e74c3c'; $semText = 'Problemi critici rilevati: intervenire sulle voci rosse prima possibile.' }
    $durata = 0; try { $durata = [int]([timespan]$Check.Durata).TotalSeconds } catch {}
    $sub = (ConvertTo-HcHtml $Check.Computer) + ' - ' + $inizio.ToString('dd/MM/yyyy HH:mm') + ' - durata ' + $durata + ' s'
    if ($Cliente) { $sub += ' - Cliente: ' + (ConvertTo-HcHtml $Cliente) }
    if ($Tecnico) { $sub += ' - Tecnico: ' + (ConvertTo-HcHtml $Tecnico) }
    $logoTag = ''; if ($LogoBase64) { $logoTag = '<img src="data:image/png;base64,' + $LogoBase64 + '" alt="vm technology">' }

    $css = @'
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f4f6fa;color:#1b2740}
.hdr{background:#0a1428;color:#e6f1ff;padding:18px 28px;display:flex;align-items:center;gap:16px}
.hdr img{width:52px;height:52px;border-radius:10px}.hdr h1{margin:0;font-size:20px;color:#38d6ff}.hdr small{color:#8fa3c7}
.wrap{max-width:1000px;margin:20px auto;padding:0 16px}
.sem{display:flex;gap:14px;align-items:center;background:#fff;border-radius:10px;padding:16px 20px;box-shadow:0 1px 4px rgba(0,0,0,.08);margin-bottom:18px}
.dot{width:46px;height:46px;border-radius:50%}
.kpi{display:flex;gap:10px;margin-left:auto}.kpi div{background:#f4f6fa;border-radius:8px;padding:8px 14px;text-align:center;font-size:12px;color:#5a6a8a}.kpi b{display:block;font-size:20px;color:#1b2740}
h2{font-size:15px;margin:22px 0 8px;color:#0a1428;border-bottom:2px solid #dfe6f2;padding-bottom:4px}
.row{background:#fff;border-radius:8px;padding:10px 14px;margin-bottom:6px;display:grid;grid-template-columns:110px 1fr;gap:10px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
.badge{display:inline-block;padding:3px 10px;border-radius:12px;font-size:11px;font-weight:600;color:#0a1428}
.t{font-weight:600}.m{color:#3b4a66;font-size:13px}.d{color:#6b7a95;font-size:12px;margin-top:4px;white-space:pre-wrap}.a{color:#b03a2e;font-size:12px;margin-top:4px}
.foot{color:#8fa3c7;font-size:11px;text-align:center;margin:26px 0}
@media print{.row{break-inside:avoid}body{background:#fff}}
'@
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('<!DOCTYPE html><html lang="it"><head><meta charset="utf-8"><title>Health Check ' + (ConvertTo-HcHtml $Check.Computer) + '</title><style>')
    $lines.Add($css)
    $lines.Add('</style></head><body>')
    $lines.Add('<div class="hdr">' + $logoTag + '<div><h1>VM Health Check - Report diagnostico</h1><small>' + $sub + '</small></div></div>')
    $lines.Add('<div class="wrap"><div class="sem"><div class="dot" style="background:' + $semColor + '"></div><div><div style="font-size:18px;font-weight:700">Stato generale: ' + $semaforo + '</div><div class="m">' + $semText + '</div></div>')
    $lines.Add('<div class="kpi"><div><b style="color:#e74c3c">' + [string]$Check.Critici + '</b>critici</div><div><b style="color:#d4ac0d">' + [string]$Check.Avvisi + '</b>avvisi</div><div><b style="color:#27ae60">' + [string]$Check.Ok + '</b>ok</div></div></div>')

    $all = @($Check.Risultati)
    $cats = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in $all) { $c = [string]$x.Categoria; if (-not $cats.Contains($c)) { $cats.Add($c) } }
    foreach ($cat in $cats) {
        $lines.Add('<h2>' + (ConvertTo-HcHtml $cat) + '</h2>')
        $inCat = @($all | Where-Object { [string]$_.Categoria -eq $cat })
        foreach ($st in 'CRIT', 'WARN', 'OK', 'INFO', 'NA') {
            foreach ($x in $inCat) {
                if ([string]$x.Stato -ne $st) { continue }
                $det = ''
                try {
                    $dv = $x.Dettagli
                    if ($null -ne $dv) {
                        if ($dv -is [System.Collections.IDictionary]) { $parts = @(); foreach ($k in $dv.Keys) { $parts += ([string]$k + ': ' + [string]$dv[$k]) }; $det = $parts -join "`n" }
                        elseif ($dv -is [array]) { $det = (@($dv | ForEach-Object { [string]$_ }) -join "`n") }
                        else { $det = [string]$dv }
                    }
                } catch { $det = '' }
                $row = '<div class="row"><div><span class="badge" style="background:' + $color[$st] + '">' + $label[$st] + '</span></div><div><div class="t">' + (ConvertTo-HcHtml $x.Titolo) + '</div><div class="m">' + (ConvertTo-HcHtml $x.Messaggio) + '</div>'
                if ($det) { $row += '<div class="d">' + (ConvertTo-HcHtml $det) + '</div>' }
                if ($x.Azione) { $row += '<div class="a">&#9654; ' + (ConvertTo-HcHtml $x.Azione) + '</div>' }
                $row += '</div></div>'
                $lines.Add($row)
            }
        }
    }
    $lines.Add('<div class="foot">VM Health Check v' + [string]$Check.Versione + ' - vm technology - report generato automaticamente, sola lettura: nessuna modifica apportata al sistema.</div></div></body></html>')
    $html = $base + '.html'
    [System.IO.File]::WriteAllLines($html, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
    return $html
}

function Export-HcPdf {
    <# Converte l'HTML in PDF con Microsoft Edge headless (presente su ogni Windows 10/11). Ritorna il percorso PDF o $null. #>
    param([Parameter(Mandatory)][string]$HtmlPath)
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $edge) { return $null }
    $pdf = [System.IO.Path]::ChangeExtension($HtmlPath, '.pdf')
    $p = Start-Process -FilePath $edge -ArgumentList @('--headless', '--disable-gpu', '--no-first-run', "--print-to-pdf=`"$pdf`"", '--no-pdf-header-footer', "`"file:///$($HtmlPath.Replace('\', '/'))`"") -Wait -PassThru -WindowStyle Hidden
    if (Test-Path -LiteralPath $pdf) { return $pdf } else { return $null }
}

Export-ModuleMember -Function *-Hc*
