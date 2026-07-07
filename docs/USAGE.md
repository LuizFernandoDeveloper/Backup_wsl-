# Uso E Parametros

## Modos De Backup

| Modo | O que faz |
| --- | --- |
| `All` | Exporta distros WSL e copia `WSL_Drives.vhdx` |
| `Distros` | Exporta somente as distros WSL |
| `Vhdx` | Copia somente o VHDX extra |

Exemplos:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode All
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode Distros
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode Vhdx
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
| `-OrganizeRuns` | sem valor | Organiza backups ja publicados por qualidade, sem refazer backup |
| `-BackupRoot` | `"E:\Backups\WSL"` | Altera destino |
| `-SourceVhdx` | `"D:\x\WSL_Drives.vhdx"` | Altera VHDX extra |
| `-KeepLastRuns` | `5` | Altera retencao |
| `-MinimumFreeSpaceGB` | `50` | Altera reserva minima |

## Organizacao Por Qualidade

Backups publicados ficam separados pelo `QualityGate` usado na execucao:

```text
Runs\Basic\Basic-RUN_ID
Runs\Standard\Standard-RUN_ID
Runs\Template\Template-RUN_ID
```

Isso evita misturar backups emergenciais, normais e templates. A retencao de `-KeepLastRuns` tambem passa a valer dentro da qualidade atual, entao backups `Template` nao apagam backups `Standard`.

Para organizar backups antigos ja publicados sem executar backup novo:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -OrganizeRuns
```

Para simular antes de mover:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -OrganizeRuns -DryRun
```

## Exemplos Prontos

Backup completo normal:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Standard
```

Backup completo como template:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

Somente VHDX extra:

```bat
launchers\Executar_Backup_WSL_Drives_VHDX.cmd
```

Retomar uma execucao:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode All -ResumeRunId 20260707_130726_771
```

Incluir Docker:

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode All -IncludeDocker
```

Voltar ao [indice da documentacao](README.md).
