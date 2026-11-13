# VM Health Check 1.0

Diagnostica rapida (1-3 minuti) di un PC Windows 10/11 con report HTML/PDF in italiano e semaforo VERDE/GIALLO/ROSSO. **Sola lettura**: non modifica nulla. Funziona da chiavetta.

- GUI: `VMHealthCheck.exe` (o `Avvia-GUI.cmd`) → cliente, tecnico, cartella, *Avvia diagnostica* → *Apri report / PDF*.
- CLI: `Avvia-CLI.cmd -Pdf -Cliente "Nome" [-Deep] [-Json]`. Codice di uscita 0 verde, 1 giallo, 2 rosso, 3 errore → usabile da RMM/attività pianificata.
- Report: `HealthCheck_<PC>_<data>.html` + `.json` (+ `.pdf` via Edge headless).

## Controlli
Sistema (modello, S/N, versione e supporto Windows, attivazione, uptime, riavvio in sospeso) · Hardware (CPU, RAM, TPM, Secure Boot, batteria, dispositivi con errori, temperatura) · Dischi (spazio, SMART/usura/temperatura, predizione guasto, dirty bit, eventi disco) · Eventi (errori di sistema, spegnimenti anomali, BSOD, WHEA, crash applicazioni) · Avvio (tempo di avvio, programmi in esecuzione automatica) · Aggiornamenti (ultimo installato, in attesa, servizio) · Sicurezza (Defender/antivirus, firewall, BitLocker, UAC, SMB1, RDP, amministratori, account senza password, autologon) · Rete (schede, gateway, Internet/DNS, orario) · Stampanti e servizi (spooler, code, servizi fermi, punti di ripristino, temporanei) · Integrità (SFC/DISM con *Analisi approfondita*).

Ogni voce ha stato, dettaglio e **azione consigliata**; il report è pensato per essere lasciato al cliente.

## Build
`.\Build.ps1` oppure push su GitHub (workflow incluso: exe, zip portable, Setup, release `latest`).
