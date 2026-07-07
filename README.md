# Mega Backup WSL

Backup versionado e validado de distribuicoes WSL no Windows, com suporte a um VHDX extra de laboratorio.

## Arquivos

- `Mega_Backup_WSL.ps1`: script principal do backup.
- `Executar_Mega_Backup_WSL.cmd`: atalho para executar o script pelo Prompt/duplo clique.

## O que o backup faz

- Desliga o WSL antes de exportar, para melhorar a consistencia.
- Exporta as distros WSL para arquivos `.tar`.
- Ignora `docker-desktop` e `docker-desktop-data` por padrao.
- Copia o VHDX extra configurado em `D:\disk-removivel-wsl2\WSL_Drives.vhdx`.
- Gera SHA-256 dos arquivos exportados/copiedos.
- Gera `manifest.json`, `checksums.sha256` e `RESTORE_GUIDE.txt`.
- Usa staging e so publica o backup se todas as etapas passarem.
- Mantem os ultimos backups conforme a retencao configurada.
- Usa lock para evitar duas execucoes ao mesmo tempo.

## Configuracao padrao

Destino:

```text
F:\Backup\WSl_backup
```

VHDX extra:

```text
D:\disk-removivel-wsl2\WSL_Drives.vhdx
```

Retencao:

```text
3 backups completos
```

Reserva minima:

```text
25 GB livres alem da estimativa do backup
```

## Testar sem copiar nada

Use o modo de teste antes do primeiro backup real:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -DryRun
```

Esse modo valida comandos, destino, espaco livre, distros encontradas e VHDX extra, mas nao exporta nem copia arquivos grandes.

## Executar backup real

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd
```

Durante o backup, o script executa `wsl.exe --shutdown`. Feche trabalhos abertos nas distros WSL antes de iniciar.

## Opcoes uteis

Incluir distros do Docker:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -IncludeDocker
```

Fazer backup somente das distros WSL, sem o VHDX extra:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -SkipVhdx
```

Alterar destino do backup:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupRoot "E:\Backups\WSL"
```

Alterar o VHDX extra:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -SourceVhdx "D:\outro\arquivo.vhdx"
```

Validar o rotulo da unidade de destino:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -ExpectedVolumeLabel "WSL_BACKUP"
```

Alterar retencao e reserva minima:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -KeepLastRuns 5 -MinimumFreeSpaceGB 50
```

## Estrutura gerada

Depois de um backup concluido, a pasta de destino fica parecida com:

```text
F:\Backup\WSl_backup
|-- LATEST.txt
|-- logs
|   `-- Mega_Backup_WSL_YYYYMMDD_HHMMSS_fff.log
`-- Runs
    `-- YYYYMMDD_HHMMSS_fff
        |-- checksums.sha256
        |-- manifest.json
        |-- RESTORE_GUIDE.txt
        |-- distros
        |   |-- Ubuntu.tar
        |   `-- outra-distro.tar
        `-- workspace
            `-- WSL_Drives.vhdx
```

## Restauracao

Cada backup concluido gera um `RESTORE_GUIDE.txt` dentro da pasta da execucao. Ele contem os comandos `wsl.exe --import` ja apontando para os arquivos `.tar` daquele backup.

Fluxo geral:

```bat
wsl.exe --shutdown
wsl.exe --import "NomeDaDistro" "D:\WSL-Restored\NomeDaDistro" "F:\Backup\WSl_backup\Runs\RUN_ID\distros\NomeDaDistro.tar" --version 2
```

Antes de restaurar, confira os hashes em `checksums.sha256`.

## Logs e diagnostico

Logs ficam em:

```text
F:\Backup\WSl_backup\logs
```

Se o backup falhar, o script nao apaga backups antigos e preserva a pasta de staging com um `FAILED.json` para diagnostico.

## Observacoes importantes

- O backup real pode demorar bastante, especialmente em distros grandes.
- A unidade `F:` precisa continuar conectada durante toda a execucao.
- Por padrao, Docker nao entra no backup.
- O `.cmd` executa o PowerShell com `RemoteSigned` apenas naquele processo, sem alterar a politica permanente do Windows.
- O script nao usa `ExecutionPolicy Bypass`.
