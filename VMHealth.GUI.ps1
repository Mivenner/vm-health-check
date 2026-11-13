#Requires -Version 5.1
<# VM Health Check - interfaccia WPF. Richiede VMHealth.Engine.psm1, GUI.xaml, logo.png nella stessa cartella. #>
[CmdletBinding()] param()
$script:Root = $PSScriptRoot
if (-not $script:Root) { try { $script:Root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {} }
if (-not $script:Root) { $script:Root = [AppDomain]::CurrentDomain.BaseDirectory }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
function Show-FatalError([string]$Message, $Err) {
    $d = $Message; if ($Err) { $d += "`n" + $Err.ScriptStackTrace }
    foreach ($lp in (Join-Path $script:Root 'vmhc_error.log'), (Join-Path $env:TEMP 'vmhc_error.log')) { try { Add-Content -LiteralPath $lp -Value ("{0} {1}" -f (Get-Date -Format s), $d); break } catch {} }
    try { [System.Windows.MessageBox]::Show($Message, 'VM Health Check', 'OK', 'Error') | Out-Null } catch {}
}
try {
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}
$EnginePath = Join-Path $script:Root 'VMHealth.Engine.psm1'; $XamlPath = Join-Path $script:Root 'GUI.xaml'
foreach ($f in $EnginePath, $XamlPath) { if (-not (Test-Path -LiteralPath $f)) { Show-FatalError "File mancante: $f"; return } }
$EngineText = [System.IO.File]::ReadAllText($EnginePath, [System.Text.Encoding]::UTF8)
Import-Module (New-Module -Name 'VMHealth.Engine' -ScriptBlock ([scriptblock]::Create($EngineText))) -Force
[xml]$xaml = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
$Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}; $xaml.SelectNodes('//*[@Name]') | ForEach-Object { $ui[$_.Name] = $Window.FindName($_.Name) }
$LogoB64 = ''
try { $logo = Join-Path $script:Root 'logo.png'; if (Test-Path -LiteralPath $logo) { $bmp = New-Object System.Windows.Media.Imaging.BitmapImage; $bmp.BeginInit(); $bmp.UriSource = New-Object System.Uri($logo); $bmp.CacheOption = 'OnLoad'; $bmp.EndInit(); $ui.imgLogo.Source = $bmp; $Window.Icon = $bmp; $LogoB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($logo)) } } catch {}
$ui.lblComputer.Text = $env:COMPUTERNAME
$ui.lblAdmin.Text = $(if (Test-HcAdmin) { 'Amministratore: si'' (tutti i controlli)' } else { 'Amministratore: no (alcuni controlli non disponibili)' })
$ui.txtOut.Text = Join-Path ([Environment]::GetFolderPath('Desktop')) 'HealthCheck'
$ui.txtTecnico.Text = $env:USERNAME

$script:Sync = [hashtable]::Synchronized(@{ Log = (New-Object System.Collections.Concurrent.ConcurrentQueue[string]); Percent = 0.0; Status = ''; Done = $false; Error = $null; Html = $null; Pdf = $null; Check = $null })
$script:AllLog = New-Object System.Collections.ArrayList
$Timer = New-Object System.Windows.Threading.DispatcherTimer; $Timer.Interval = [TimeSpan]::FromMilliseconds(250)
$Timer.Add_Tick({
    $line = $null
    while ($script:Sync.Log.TryDequeue([ref]$line)) { [void]$ui.lstLog.Items.Add($line); [void]$script:AllLog.Add($line); $ui.lstLog.ScrollIntoView($line) }
    $ui.progressBar.Value = [double]$script:Sync.Percent; $ui.lblStatus.Text = [string]$script:Sync.Status
    if ($script:Sync.Done) {
        $Timer.Stop(); $ui.btnStart.IsEnabled = $true
        $script:LogPath = $null
        foreach ($lf in @((Join-Path $ui.txtOut.Text.Trim() 'HealthCheck_ultimo.log'), (Join-Path $env:TEMP 'vmhc_last.log'))) { try { New-Item -ItemType Directory -Path (Split-Path -Parent $lf) -Force | Out-Null; Set-Content -LiteralPath $lf -Value $script:AllLog.ToArray() -Encoding UTF8; $script:LogPath = $lf; break } catch {} }
        $ui.btnOpenFolder.IsEnabled = $true
        if ($script:Sync.Error) { $ui.lblResult.Text = 'Errore - log salvato in: ' + $script:LogPath; try { Start-Process notepad.exe -ArgumentList ('"' + $script:LogPath + '"') } catch {}; return }
        $c = $script:Sync.Check
        $ui.lblResult.Text = ("Stato: {0}  -  {1} critici, {2} avvisi, {3} ok" -f $c.Semaforo, $c.Critici, $c.Avvisi, $c.Ok)
        $ui.btnOpenHtml.IsEnabled = [bool]$script:Sync.Html; $ui.btnOpenPdf.IsEnabled = [bool]$script:Sync.Pdf; $ui.btnOpenFolder.IsEnabled = $true
    }
})
$ui.btnStart.Add_Click({
    $ui.lstLog.Items.Clear(); $script:AllLog.Clear(); $ui.lblResult.Text = ''; $ui.btnStart.IsEnabled = $false; $ui.btnOpenHtml.IsEnabled = $false; $ui.btnOpenPdf.IsEnabled = $false
    $script:Sync.Done = $false; $script:Sync.Error = $null; $script:Sync.Html = $null; $script:Sync.Pdf = $null; $script:Sync.Percent = 0
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $script:Sync); $rs.SessionStateProxy.SetVariable('EngineText', $EngineText)
    $rs.SessionStateProxy.SetVariable('Opts', @{ Deep = [bool]$ui.chkDeep.IsChecked; Pdf = [bool]$ui.chkPdf.IsChecked; Out = $ui.txtOut.Text.Trim(); Cliente = $ui.txtCliente.Text.Trim(); Tecnico = $ui.txtTecnico.Text.Trim(); Logo = $LogoB64 })
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        try {
            Import-Module (New-Module -Name 'VMHealth.Engine' -ScriptBlock ([scriptblock]::Create($EngineText))) -Force
            Initialize-HcCallbacks -OnLog { param($l, $m) $Sync.Log.Enqueue(("[{0,-4}] {1}" -f $l, $m)) } -OnProgress { param($p, $s) $Sync.Percent = $p; $Sync.Status = $s }
            $fase = 'controlli'
            $c = Invoke-HcCheck -Deep $Opts.Deep
            $Sync.Check = $c
            $fase = 'scrittura report HTML'; $Sync.Status = 'Scrittura report...'
            $Sync.Html = Export-HcReport -Check $c -OutFolder $Opts.Out -Tecnico $Opts.Tecnico -Cliente $Opts.Cliente -LogoBase64 $Opts.Logo
            $Sync.Log.Enqueue('[OK  ] Report: ' + $Sync.Html)
            if ($Opts.Pdf) { $fase = 'creazione PDF'; $Sync.Status = 'Creazione PDF...'; try { $Sync.Pdf = Export-HcPdf -HtmlPath $Sync.Html } catch { $Sync.Log.Enqueue('[WARN] PDF non creato: ' + $_.Exception.Message) } }
            $Sync.Status = 'Report: ' + $Sync.Html
        } catch {
            $Sync.Error = ('Fase "' + $fase + '": ' + $_.Exception.Message)
            $Sync.Log.Enqueue('[ERR ] ' + $Sync.Error)
            $Sync.Log.Enqueue('[ERR ] ' + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | '))
            $Sync.Log.Enqueue('[ERR ] ' + ($_.ScriptStackTrace -replace "`r?`n", ' | '))
        } finally {
            try { $lf = Join-Path $env:TEMP 'vmhc_last.log'; Set-Content -LiteralPath $lf -Value ($Sync.Log.ToArray()) -Encoding UTF8 } catch {}
            $Sync.Done = $true
        }
    })
    [void]$ps.BeginInvoke(); $Timer.Start()
})
$ui.btnBrowse.Add_Click({ $d = New-Object System.Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $ui.txtOut.Text = $d.SelectedPath } })
$ui.btnOpenHtml.Add_Click({ if ($script:Sync.Html) { Start-Process $script:Sync.Html } })
$ui.btnOpenPdf.Add_Click({ if ($script:Sync.Pdf) { Start-Process $script:Sync.Pdf } })
$ui.btnOpenFolder.Add_Click({ $f = $script:Sync.Html; if (-not $f) { $f = $script:LogPath }; if ($f) { Start-Process explorer.exe -ArgumentList ('/select,"' + $f + '"') } })
[void]$Window.ShowDialog()
} catch { Show-FatalError ("Errore all'avvio: " + $_.Exception.Message) $_ }
