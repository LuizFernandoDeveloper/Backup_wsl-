# Troubleshooting

## `pax format cannot archive sockets`

Motivo: a distro tinha sockets temporarios, geralmente em `/tmp` ou agente SSH.

Solucao recomendada:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

Depois rode o backup novamente.

## Backup Falhou No Meio

O staging e preservado:

```text
F:\Backup\WSl_backup\_staging\RUN_ID.partial
```

Retome:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -ResumeRunId RUN_ID
```

## Distro Reprovou Como Template

Rode:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

Se ainda reprovar, leia o log em:

```text
F:\Backup\WSl_backup\logs
```

Procure por:

- read-only;
- erro de escrita em `/tmp` ou `$HOME`;
- erro de varredura de diretorio;
- `EXT4-fs error`;
- `I/O error`;
- `Structure needs cleaning`.

## Espaco Insuficiente

Altere destino ou reserva minima:

```bat
Executar_Mega_Backup_WSL.cmd -BackupRoot "E:\Backups\WSL" -MinimumFreeSpaceGB 50
```

## ExecutionPolicy

O `.cmd` usa `RemoteSigned` apenas no processo atual. O script nao usa `ExecutionPolicy Bypass`.

Voltar ao [indice da documentacao](README.md).
