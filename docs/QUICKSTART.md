# Quickstart

## 1. Abrir o menu

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Escolher_Backup_WSL.cmd
```

Opcoes principais:

```text
1. Backup completo: distros + WSL_Drives.vhdx
2. Backup completo + limpar sockets temporarios
3. Somente distros WSL
4. Somente WSL_Drives.vhdx
5. Saude leve das distros
6. Diagnostico pesado das distros
7. Validar distros como template
8. Purificar template sem backup
9. Testar completo sem copiar nada
A. Organizar diretorios de backup ja publicados
0. Sair
```

## 2. Testar sem copiar

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -DryRun
```

O `DryRun` valida comandos, destino, espaco livre, distros encontradas e VHDX extra. Ele nao exporta TAR e nao copia VHDX.

## 3. Diagnosticar antes do backup

Saude leve:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly
```

Diagnostico pesado:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly -DeepHealth
```

## 4. Preparar distros para template

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

Esse comando purifica as distros e valida o nivel de template, mas nao exporta backup.

## 5. Full Template em um clique

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Full_Template.cmd
```

Esse atalho purifica as distros como template e so inicia o backup completo se a primeira etapa for aprovada.

## 6. Rodar backup completo

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All
```

Para exigir qualidade de template:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

Voltar ao [indice da documentacao](README.md).
