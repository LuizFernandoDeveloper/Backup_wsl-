# Mega Backup WSL

Backup seguro, versionado e retomavel para ambientes WSL no Windows.

Este projeto cria backups das suas distribuicoes WSL e tambem do arquivo extra
`WSL_Drives.vhdx`, com diagnostico de saude das distros, validacao por
SHA-256, staging, logs e retomada automatica quando uma execucao falha no meio.

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
2. Backup completo + limpar sockets temporarios
3. Somente distros WSL
4. Somente WSL_Drives.vhdx
5. Saude leve das distros
6. Diagnostico pesado das distros
7. Validar distros como template
8. Purificar template sem backup
9. Testar completo sem copiar nada
0. Sair
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

## Saude das distros/templates

As distros exportadas em `.tar` funcionam como templates: voce pode restaurar
com o mesmo nome ou importar como clone com outro nome. Por isso, antes de
"congelar" uma distro em backup, o script mostra a saude dela.

### Saude leve

Roda por padrao em backups com distros. Verifica:

- se a distro responde via `sh`;
- uso de disco em `/`;
- uso de inodes em `/`;
- tamanho do `ext4.vhdx` visto pelo Windows;
- sockets temporarios em `/tmp`, `/var/tmp` e `~/.ssh/agent`.

Para rodar apenas o diagnostico leve:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly
```

### Diagnostico pesado

Use quando quiser investigar uma distro antes de transforma-la em template.
Ele pode demorar porque varre o filesystem da distro com `find / -xdev`.

Verifica alem da saude leve:

- sockets no filesystem inteiro da distro;
- links quebrados;
- teste de escrita em `/tmp`;
- teste de escrita no `$HOME`;
- se `/` parece montado como read-only;
- erros ao varrer diretorios, ignorando apenas permissoes comuns;
- sinais recentes no `dmesg`, como `I/O error`, `corrupt`,
  `read-only file system` e `Structure needs cleaning`;
- tamanhos de `/tmp`, `/var/tmp`, `/var/cache` e `$HOME/.cache`;
- maiores diretorios no `/`.

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly -DeepHealth
```

O alias em portugues tambem funciona:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly -DiagnosticoPesado
```

### Limpar sockets antes do backup

Sockets temporarios podem gerar avisos do `bsdtar` durante `wsl.exe --export`.
Para preparar as distros antes de exportar, use:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -CleanWslSockets
```

Essa limpeza remove somente arquivos do tipo socket em:

```text
/tmp
/var/tmp
~/.ssh/agent
```

Ela nao apaga chaves SSH, arquivos comuns, projetos ou caches.

## Niveis de exigencia

Use `-QualityGate` para decidir o quanto a saude da distro deve bloquear o
backup.

| Nivel | Uso indicado | Comportamento |
| --- | --- | --- |
| `Basic` | Backup emergencial | Relata problemas, mas quase nao bloqueia |
| `Standard` | Backup normal | Bloqueia problemas criticos, como read-only, falha de escrita ou erro real de filesystem |
| `Template` | Criar base limpa para clones | No backup real, purifica antes; liga `-DeepHealth` automaticamente; bloqueia sockets, read-only, erros de diretorio, pouco espaco e sinais fortes de filesystem ruim |

Backup normal com regra padrao:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Standard
```

Validar se as distros estao boas para virar template:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly -QualityGate Template
```

Gerar backup/template com purificacao automatica:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

Purificar e validar sem exportar backup:

```bat
Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

No modo real de template, o script:

- remove sockets temporarios em `/tmp`, `/var/tmp` e agentes SSH;
- tenta rotacionar e reduzir journald para 7 dias quando `journalctl` existe;
- roda `sync`;
- executa o diagnostico pesado depois da limpeza;
- bloqueia a exportacao se ainda houver problema grave.

`-HealthOnly -QualityGate Template` valida, mas nao publica backup. Para manter o diagnostico como leitura, use esse modo antes do backup real.

## O que o script faz por seguranca

- Desliga o WSL com `wsl.exe --shutdown` antes de copiar/exportar.
- Exporta distros para `.tar` usando `wsl.exe --export`.
- Mostra a saude de cada distro antes de exportar.
- Pode bloquear backups/templates ruins com `-QualityGate`.
- Pode limpar sockets temporarios com `-CleanWslSockets`.
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

Usar o TAR como template/clone:

```bat
wsl.exe --import "NomeDaDistro-clone" "D:\WSL-Restored\NomeDaDistro-clone" "F:\Backup\WSl_backup\Runs\RUN_ID\distros\NomeDaDistro.tar" --version 2
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

## Melhorias pesquisadas para proximas versoes

Estas ideias vieram da documentacao oficial do WSL da Microsoft:

- Exportar distros tambem em formato VHD com `wsl --export <Distro> <Arquivo> --format vhd`.
- Importar VHD diretamente com `wsl --import <Distro> <Local> <Arquivo> --vhd`.
- Mostrar `wsl --list --verbose` no inventario para registrar estado e versao WSL.
- Adicionar rotina opcional de compactacao/otimizacao de VHDX depois de limpeza pesada.
- Criar um comando "template publish" para marcar backups bons como templates recomendados.

Referencias:

- [Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [FAQ about WSL](https://learn.microsoft.com/en-us/windows/wsl/faq)
- [How to manage WSL disk space](https://learn.microsoft.com/en-us/windows/wsl/disk-space)
- [Troubleshooting WSL](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting)

## Observacoes importantes

- O backup real pode demorar bastante em distros grandes.
- O diagnostico pesado tambem pode demorar, porque varre diretorios dentro da distro.
- Feche terminais e servicos importantes antes de rodar, pois o script desliga o WSL.
- Por padrao, `docker-desktop` e `docker-desktop-data` ficam fora do backup.
- O `.cmd` usa `RemoteSigned` apenas no processo atual do PowerShell.
- O script nao usa `ExecutionPolicy Bypass`.
- Se o Git nao estiver no PATH do Windows, o repositorio ainda pode ser atualizado pelo Git dentro do WSL.
