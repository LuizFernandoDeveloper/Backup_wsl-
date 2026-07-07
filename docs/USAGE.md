# Uso E Parametros

## Modos De Backup

| Modo | O que faz |
| --- | --- |
| `All` | Exporta distros WSL e copia `WSL_Drives.vhdx` |
| `Distros` | Exporta somente as distros WSL |
| `Vhdx` | Copia somente o VHDX extra |

Exemplos:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All
Executar_Mega_Backup_WSL.cmd -BackupMode Distros
Executar_Mega_Backup_WSL.cmd -BackupMode Vhdx
```

## Parametros Mais Usados

| Parametro | Exemplo | Descricao |
| --- | --- | --- |
| `-BackupMode` | `All` | Escolhe o tipo de backup |
| `-DryRun` | sem valor | Valida sem copiar/exportar |
| `-HealthOnly` | sem valor | Diagnostica sem backup |
| `-DeepHealth` | sem valor | Diagnostico pesado |
| `-QualityGate` | `Standard` | Nivel de exigencia |
| `-PurifyOnly` | sem valor | Purifica e para sem backup |
| `-CleanWslSockets` | sem valor | Remove sockets temporarios antes de exportar |
| `-IncludeDocker` | sem valor | Inclui `docker-desktop` |
| `-ResumeRunId` | `20260707_130726_771` | Retoma um staging especifico |
| `-NoResume` | sem valor | Desativa retomada automatica |
| `-BackupRoot` | `"E:\Backups\WSL"` | Altera destino |
| `-SourceVhdx` | `"D:\x\WSL_Drives.vhdx"` | Altera VHDX extra |
| `-KeepLastRuns` | `5` | Altera retencao |
| `-MinimumFreeSpaceGB` | `50` | Altera reserva minima |

## Exemplos Prontos

Backup completo normal:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Standard
```

Backup completo como template:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

Somente VHDX extra:

```bat
Executar_Backup_WSL_Drives_VHDX.cmd
```

Retomar uma execucao:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -ResumeRunId 20260707_130726_771
```

Incluir Docker:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -IncludeDocker
```

Voltar ao [indice da documentacao](README.md).
