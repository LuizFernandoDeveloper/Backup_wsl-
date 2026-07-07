# Interface WPF

A interface grafica pronta fica em:

```text
dist\MegaBackupWsl.exe
```

O projeto completo em C#/.NET WPF fica em:

```text
src\MegaBackupWsl.App
```

A versao rapida compilada pelo `csc.exe` do Windows fica em:

```text
src\MegaBackupWsl.FastWpf
```

Ela nao substitui o script principal. O app chama:

```text
scripts\Mega_Backup_WSL.ps1
```

## Abrir

```bat
dist\MegaBackupWsl.exe
```

Ou use o launcher:

```bat
launchers\Abrir_Interface_WPF.cmd
```

Se o `.exe` em `dist` existir, o launcher abre ele direto.

## Abas

| Aba | Conteudo |
| --- | --- |
| Saude | Graficos por distro para uso do disco, uso de inodes e risco de template |
| Log | Saida completa do PowerShell em tempo real |

## Requisito Para Compilar

O `.exe` rapido em `dist` nao exige o .NET 8 SDK para abrir.

Para compilar o projeto completo `src\MegaBackupWsl.App`, o Windows precisa do .NET 8 SDK. Apenas o runtime nao compila projetos.

Verifique com:

```bat
dotnet --list-sdks
```

Para regenerar o `.exe` rapido sem SDK:

```bat
powershell.exe -ExecutionPolicy RemoteSigned -File scripts\Build-MegaBackupWslFastExe.ps1
```

## Acoes Da Tela

| Acao | Comando equivalente |
| --- | --- |
| Simular Organizacao | `-OrganizeRuns -DryRun` |
| Organizar Diretorios | `-OrganizeRuns` |
| DryRun Completo | `-BackupMode MODO -QualityGate GATE -DryRun` |
| Saude Das Distros | `-BackupMode Distros -HealthOnly`, preenchendo a aba Saude |
| Full Template | `-BackupMode Distros -PurifyOnly -QualityGate Template` e depois `-BackupMode All -QualityGate Template` |

## Segurança

`Organizar Diretorios` nao exporta distros, nao copia VHDX e nao desliga o WSL.

`Full Template` pode desligar o WSL durante o backup real. Feche terminais, editores e servicos dentro das distros antes de confirmar.

Voltar ao [indice da documentacao](README.md).
