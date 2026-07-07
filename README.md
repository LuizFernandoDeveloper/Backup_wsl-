# Mega Backup WSL

Backup seguro, versionado e retomavel para ambientes WSL no Windows.

Este projeto cria backups das suas distribuicoes WSL e tambem do arquivo extra
`WSL_Drives.vhdx`, com validacao por SHA-256, staging, logs e retomada
automatica quando uma execucao falha no meio.

## Visao geral

| Item | Descricao |
| --- | --- |
| Sistema | Windows + WSL 2 |
| Script principal | `Mega_Backup_WSL.ps1` |
| Menu interativo | `Escolher_Backup_WSL.cmd` |
| Atalho completo | `Executar_Mega_Backup_WSL.cmd` |
| Atalho VHDX | `Executar_Backup_WSL_Drives_VHDX.cmd` |
| Destino padrao | `F:\Backup\WSl_backup` |
| VHDX extra padrao | `D:\disk-removivel-wsl2\WSL_Drives.vhdx` |
| Retencao padrao | 3 execucoes publicadas |
| Reserva padrao | 25 GB livres alem da estimativa |

## Modos de backup

O script principal aceita tres modos:

| Modo | O que faz | Exemplo |
| --- | --- | --- |
| `All` | Backup das distros WSL + `WSL_Drives.vhdx` | backup completo |
| `Distros` | Backup somente das distros WSL | sem VHDX extra |
| `Vhdx` | Backup somente do `WSL_Drives.vhdx` | copia rapida do VHDX |

Por padrao, o modo usado e `All`.

## Como usar

### Opcao recomendada: menu

Execute:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Escolher_Backup_WSL.cmd
```

O menu permite escolher:

```text
1. Backup completo: distros + WSL_Drives.vhdx
2. Somente distros WSL
3. Somente WSL_Drives.vhdx
4. Testar completo sem copiar nada
5. Sair
```

### Backup completo

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd
```

Equivalente a:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All
```

### Somente distros

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros
```

### Somente WSL_Drives.vhdx

Use o atalho direto:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Backup_WSL_Drives_VHDX.cmd
```

Ou chame o script principal:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Vhdx
```

### Testar sem copiar nada

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -DryRun
```

Outros testes:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -DryRun
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Vhdx -DryRun
```

## O que o script faz por seguranca

- Desliga o WSL com `wsl.exe --shutdown` antes de copiar/exportar.
- Exporta distros para `.tar` usando `wsl.exe --export`.
- Valida a estrutura dos `.tar` com `tar.exe -tf`.
- Copia o VHDX extra com `robocopy.exe`.
- Calcula SHA-256 dos `.tar` e do `.vhdx`.
- Usa pasta `_staging` antes de publicar o backup.
- So move para `Runs` depois que relatorios e validacoes passam.
- Cria lock para impedir duas execucoes simultaneas.
- Nunca apaga backups antigos quando a execucao atual falha.
- Mantem os ultimos backups publicados conforme `-KeepLastRuns`.

## Retomada automatica

Se uma execucao falhar, o staging fica preservado em:

```text
F:\Backup\WSl_backup\_staging\RUN_ID.partial
```

Na proxima execucao do mesmo modo, o script procura esse staging e reaproveita
o que ja estiver pronto:

- `.tar` ja exportado: valida o TAR, recalcula SHA-256 e pula a exportacao.
- `WSL_Drives.vhdx` ja copiado: compara tamanho e SHA-256 com a origem.
- Arquivo incompleto ou divergente: refaz somente aquele item.

Isso evita repetir horas de exportacao quando a falha aconteceu no final, como
na etapa de relatorios.

Para desativar retomada:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -NoResume
```

Para retomar um staging especifico:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -ResumeRunId 20260706_220357_630
```

## Estrutura gerada

Backup publicado:

```text
F:\Backup\WSl_backup
|-- LATEST.txt
|-- logs
|   |-- Mega_Backup_WSL_RUN_ID.log
|   `-- Mega_Backup_WSL_RUN_ID_resume_DATA.log
`-- Runs
    `-- RUN_ID
        |-- checksums.sha256
        |-- manifest.json
        |-- RESTORE_GUIDE.txt
        |-- resume_state.json
        |-- distros
        |   |-- Ubuntu.tar
        |   |-- kali-linux.tar
        |   `-- gentoo-current-systemd.tar
        `-- workspace
            `-- WSL_Drives.vhdx
```

Falha preservada para retomada:

```text
F:\Backup\WSl_backup
`-- _staging
    `-- RUN_ID.partial
        |-- FAILED.json
        |-- resume_state.json
        |-- distros
        `-- workspace
```

## Arquivos de relatorio

| Arquivo | Para que serve |
| --- | --- |
| `manifest.json` | Inventario completo da execucao, opcoes, destino e hashes |
| `checksums.sha256` | Lista de hashes SHA-256 para conferir integridade |
| `RESTORE_GUIDE.txt` | Comandos prontos para restaurar as distros |
| `LATEST.txt` | Aponta para o ultimo backup publicado com sucesso |
| `FAILED.json` | Aparece apenas no staging quando uma execucao falha |

## Restauracao

Cada backup publicado gera um `RESTORE_GUIDE.txt` com comandos prontos.

Fluxo geral:

```bat
wsl.exe --shutdown
wsl.exe --import "NomeDaDistro" "D:\WSL-Restored\NomeDaDistro" "F:\Backup\WSl_backup\Runs\RUN_ID\distros\NomeDaDistro.tar" --version 2
```

Antes de restaurar, confira os hashes:

```powershell
Get-FileHash "F:\Backup\WSl_backup\Runs\RUN_ID\distros\Ubuntu.tar" -Algorithm SHA256
```

Compare com o valor em:

```text
F:\Backup\WSl_backup\Runs\RUN_ID\checksums.sha256
```

## Opcoes avancadas

Alterar destino:

```bat
Executar_Mega_Backup_WSL.cmd -BackupRoot "E:\Backups\WSL"
```

Alterar VHDX extra:

```bat
Executar_Mega_Backup_WSL.cmd -SourceVhdx "D:\outro\WSL_Drives.vhdx"
```

Incluir distros do Docker:

```bat
Executar_Mega_Backup_WSL.cmd -IncludeDocker
```

Validar rotulo da unidade:

```bat
Executar_Mega_Backup_WSL.cmd -ExpectedVolumeLabel "WSL_BACKUP"
```

Alterar retencao:

```bat
Executar_Mega_Backup_WSL.cmd -KeepLastRuns 5
```

Alterar reserva minima:

```bat
Executar_Mega_Backup_WSL.cmd -MinimumFreeSpaceGB 50
```

## Observacoes importantes

- O backup real pode demorar bastante em distros grandes.
- Feche terminais e servicos importantes antes de rodar, pois o script desliga o WSL.
- Por padrao, `docker-desktop` e `docker-desktop-data` ficam fora do backup.
- O `.cmd` usa `RemoteSigned` apenas no processo atual do PowerShell.
- O script nao usa `ExecutionPolicy Bypass`.
- Se o Git nao estiver no PATH do Windows, o repositorio ainda pode ser atualizado pelo Git dentro do WSL.
