#Requires -Version 5.1
<#
.SYNOPSIS  VM Health Check da riga di comando (RMM, attivita' pianificate, chiavetta).
.EXAMPLE   .\VMHealth.CLI.ps1 -Out C:\Report -Cliente "Caffe' Aiello" -Pdf
.EXAMPLE   .\VMHealth.CLI.ps1 -Deep -Json | ConvertFrom-Json   # solo JSON su stdout, nessun file
.NOTES     Codice di uscita: 0 = verde, 1 = giallo, 2 = rosso, 3 = errore.
#>
[CmdletBinding()] param([string]$Out = (Join-Path $env:PUBLIC 'HealthCheck'), [string]$Cliente = '', [string]$Tecnico = $env:USERNAME, [switch]$Deep, [switch]$Pdf, [switch]$Json, [switch]$Quiet)
$root = $PSScriptRoot; if (-not $root) { $root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$t = [System.IO.File]::ReadAllText((Join-Path $root 'VMHealth.Engine.psm1'), [System.Text.Encoding]::UTF8)
Import-Module (New-Module -Name 'VMHealth.Engine' -ScriptBlock ([scriptblock]::Create($t))) -Force
$colors = @{ OK = 'Green'; WARN = 'Yellow'; CRIT = 'Red'; INFO = 'Gray'; NA = 'DarkGray' }
if (-not $Quiet -and -not $Json) { Initialize-HcCallbacks -OnLog { param($l, $m) Write-Host ("[{0,-4}] {1}" -f $l, $m) -ForegroundColor $colors[$l] } -OnProgress { param($p, $s) Write-Progress -Activity 'VM Health Check' -Status $s -PercentComplete $p } }
try {
    $c = Invoke-HcCheck -Deep $Deep.IsPresent
    Write-Progress -Activity 'VM Health Check' -Completed
    if ($Json) { $c | ConvertTo-Json -Depth 6; exit @{ VERDE = 0; GIALLO = 1; ROSSO = 2 }[$c.Semaforo] }
    $logo = ''; $lp = Join-Path $root 'logo.png'; if (Test-Path $lp) { $logo = [Convert]::ToBase64String([IO.File]::ReadAllBytes($lp)) }
    $html = Export-HcReport -Check $c -OutFolder $Out -Tecnico $Tecnico -Cliente $Cliente -LogoBase64 $logo
    $pdfPath = $null; if ($Pdf) { $pdfPath = Export-HcPdf -HtmlPath $html }
    Write-Host ("`nStato: {0} - {1} critici, {2} avvisi, {3} ok`nReport: {4}{5}" -f $c.Semaforo, $c.Critici, $c.Avvisi, $c.Ok, $html, $(if ($pdfPath) { "`nPDF:    $pdfPath" } else { '' })) -ForegroundColor Cyan
    exit @{ VERDE = 0; GIALLO = 1; ROSSO = 2 }[$c.Semaforo]
} catch {
    $msg = @("ERRORE: $($_.Exception.Message)", $_.InvocationInfo.PositionMessage, $_.ScriptStackTrace) -join "`r`n"
    Write-Host $msg -ForegroundColor Red
    foreach ($lf in @((Join-Path $Out 'HealthCheck_errore.log'), (Join-Path $env:TEMP 'vmhc_last.log'))) { try { New-Item -ItemType Directory -Path (Split-Path -Parent $lf) -Force | Out-Null; Set-Content -LiteralPath $lf -Value $msg -Encoding UTF8; Write-Host "Dettagli salvati in: $lf" -ForegroundColor Yellow; break } catch {} }
    exit 3
}
