# Mappehistorik

PowerShell-script der tager daglige snapshots af en mappestruktur (2 niveauer) og gemmer dem i en interaktiv HTML-fil med kalenderpicker og diff-visning.

## Opsætning

1. Placer `snapshot.ps1` i en undermappe (f.eks. `_historik`) af den mappe du vil tracke.
2. Kør scriptet manuelt eller som scheduled task:

```powershell
# Manuelt
powershell -ExecutionPolicy Bypass -File "_historik\snapshot.ps1"

# Som daglig scheduled task (kl. 08:00)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -WindowStyle Hidden -File "STI\_historik\snapshot.ps1"'
$trigger = New-ScheduledTaskTrigger -Daily -At '08:00'
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'Mappehistorik_Snapshot' -Action $action -Trigger $trigger -Settings $settings
```

## Brug

Abn `mappehistorik.html` i en browser. Brug kalenderpicker eller pile til at skifte mellem datoer. Nye mapper vises med gron, fjernede med rod.

## Filer

- `snapshot.ps1` — scriptet (laeg paa GitHub)
- `mappehistorik.html` — genereret HTML med data (kun lokalt)
