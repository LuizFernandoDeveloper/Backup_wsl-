# Interface WPF

A interface grafica fica em:

```text
src\MegaBackupWsl.App
```

Ela nao substitui o script principal. O app chama:

```text
scripts\Mega_Backup_WSL.ps1
```

## Abrir

```bat
launchers\Abrir_Interface_WPF.cmd
```

Se o `.exe` ainda nao existir, o launcher tenta compilar o projeto.

## Requisito Para Compilar

O Windows precisa do .NET 8 SDK. Apenas o runtime nao compila projetos.

Verifique com:

```bat
dotnet --list-sdks
```

## Acoes Da Tela

| Acao | Comando equivalente |
| --- | --- |
| Simular Organizacao | `-OrganizeRuns -DryRun` |
| Organizar Diretorios | `-OrganizeRuns` |
| DryRun Completo | `-BackupMode MODO -QualityGate GATE -DryRun` |
| Saude Das Distros | `-BackupMode Distros -HealthOnly` |
| Full Template | `-BackupMode Distros -PurifyOnly -QualityGate Template` e depois `-BackupMode All -QualityGate Template` |

## Segurança

`Organizar Diretorios` nao exporta distros, nao copia VHDX e nao desliga o WSL.

`Full Template` pode desligar o WSL durante o backup real. Feche terminais, editores e servicos dentro das distros antes de confirmar.

Voltar ao [indice da documentacao](README.md).
