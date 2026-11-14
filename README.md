<!-- header -->
<p align="center"><img src="logo.png" width="96" alt="vm technology"></p>
<h1 align="center">VM Health Check</h1>
<p align="center">Diagnostica rapida di un PC Windows con report HTML/PDF in italiano e semaforo verde/giallo/rosso. Sola lettura.</p>
<p align="center">
  <a href="https://github.com/Mivenner/vm-health-check/actions/workflows/build.yml"><img src="https://github.com/Mivenner/vm-health-check/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4" alt="Windows 10 | 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE" alt="PowerShell 5.1 | 7">
</p>

**Download dell'ultima build:** [File singolo .cmd](https://github.com/Mivenner/vm-health-check/releases/latest/download/VMHealthCheck_Portable.cmd) · [Zip portable](https://github.com/Mivenner/vm-health-check/releases/latest/download/VMHealthCheck_Portable.zip) · [Installer](https://github.com/Mivenner/vm-health-check/releases/latest/download/VMHealthCheck_Setup.exe)

Altri strumenti vm technology: [Migration Suite](https://github.com/Mivenner/vm-migration-suite) · [Health Check](https://github.com/Mivenner/vm-health-check) · [Setup Suite](https://github.com/Mivenner/vm-setup-suite) · [Printer Manager](https://github.com/Mivenner/vm-printer-manager)

---

Diagnostica rapida (1-3 minuti) di un PC Windows 10/11 con report HTML/PDF in italiano e semaforo VERDE/GIALLO/ROSSO. **Sola lettura**: non modifica nulla. Funziona da chiavetta.

- GUI: `VMHealthCheck.exe` (o `Avvia-GUI.cmd`) → cliente, tecnico, cartella, *Avvia diagnostica* → *Apri report / PDF*.
- CLI: `Avvia-CLI.cmd -Pdf -Cliente "Nome" [-Deep] [-Json]`. Codice di uscita 0 verde, 1 giallo, 2 rosso, 3 errore → usabile da RMM/attività pianificata.
- Report: `HealthCheck_<PC>_<data>.html` + `.json` (+ `.pdf` via Edge headless).

## Controlli
Sistema (modello, S/N, versione e supporto Windows, attivazione, uptime, riavvio in sospeso) · Hardware (CPU, RAM, TPM, Secure Boot, batteria, dispositivi con errori, temperatura) · Dischi (spazio, SMART/usura/temperatura, predizione guasto, dirty bit, eventi disco) · Eventi (errori di sistema, spegnimenti anomali, BSOD, WHEA, crash applicazioni) · Avvio (tempo di avvio, programmi in esecuzione automatica) · Aggiornamenti (ultimo installato, in attesa, servizio) · Sicurezza (Defender/antivirus, firewall, BitLocker, UAC, SMB1, RDP, amministratori, account senza password, autologon) · Rete (schede, gateway, Internet/DNS, orario) · Stampanti e servizi (spooler, code, servizi fermi, punti di ripristino, temporanei) · Integrità (SFC/DISM con *Analisi approfondita*).

Ogni voce ha stato, dettaglio e **azione consigliata**; il report è pensato per essere lasciato al cliente.

## Build
`.\Build.ps1` oppure push su GitHub (workflow incluso: exe, zip portable, Setup, release `latest`).
