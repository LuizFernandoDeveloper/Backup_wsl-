<p align="center">
  <img src="assets/mega-backup-wsl-banner.svg" alt="Mega Backup WSL" width="100%">
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2bd8ff?style=for-the-badge"></a>
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1+-244b7a?style=for-the-badge&logo=powershell">
  <img alt="WSL 2" src="https://img.shields.io/badge/WSL-2-0f172a?style=for-the-badge&logo=linux">
  <img alt="Backup resumable" src="https://img.shields.io/badge/resume-enabled-16a34a?style=for-the-badge">
</p>

<h1 align="center">Mega Backup WSL</h1>

<p align="center">
  Backup profissional para WSL no Windows: distros como templates, VHDX extra, retomada automatica, health gates e validacao SHA-256.
</p>

## Por Que Existe

O Mega Backup WSL foi criado para resolver um problema bem pratico: manter distros WSL grandes e importantes com backup confiavel, restauravel e reutilizavel como template.

Ele nao apenas copia arquivos. Ele prepara, diagnostica, valida, publica somente quando esta tudo consistente e evita repetir horas de exportacao quando uma execucao falha no meio.

## Destaques

| Recurso | O que entrega |
| --- | --- |
| Backup completo | Exporta distros WSL e copia `WSL_Drives.vhdx` |
| Modos selecionaveis | `All`, `Distros` ou `Vhdx` |
| Templates saudaveis | `QualityGate Template` purifica e bloqueia distros ruins |
| Diagnostico pesado | Procura read-only, erro de diretorio, falha de escrita, sockets e sinais de filesystem |
| Retomada automatica | Reaproveita TAR/VHDX ja validos em `_staging` |
| Integridade | SHA-256, manifesto JSON, checksums e guia de restauracao |
| Seguranca operacional | Lock de execucao, staging, retencao e logs detalhados |

## Inicio Rapido

Use o menu:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Escolher_Backup_WSL.cmd
```

Ou rode direto:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All
```

Validar e purificar distros para template sem exportar backup:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

Gerar backup completo com nivel de template:

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

## Mapa Da Documentacao

| Topico | Documento |
| --- | --- |
| Instalar, testar e executar | [docs/QUICKSTART.md](docs/QUICKSTART.md) |
| Modos de backup e parametros | [docs/USAGE.md](docs/USAGE.md) |
| Health gates, templates e purificacao | [docs/HEALTH_GATES.md](docs/HEALTH_GATES.md) |
| Restaurar distros e criar clones | [docs/RESTORE.md](docs/RESTORE.md) |
| Arquitetura, staging e retomada | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Erros comuns e diagnostico | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

## Arquivos Principais

| Arquivo | Funcao |
| --- | --- |
| `Mega_Backup_WSL.ps1` | Motor principal do backup |
| `Escolher_Backup_WSL.cmd` | Menu interativo |
| `Executar_Mega_Backup_WSL.cmd` | Atalho para backup geral |
| `Executar_Backup_WSL_Drives_VHDX.cmd` | Atalho para backup somente do VHDX extra |
| `README.md` | Visao geral do projeto |
| `docs/` | Documentacao por topico |

## Resultado Esperado

Um backup publicado fica assim:

```text
F:\Backup\WSl_backup
|-- LATEST.txt
|-- logs
|   `-- Mega_Backup_WSL_RUN_ID.log
`-- Runs
    `-- RUN_ID
        |-- checksums.sha256
        |-- manifest.json
        |-- RESTORE_GUIDE.txt
        |-- resume_state.json
        |-- distros
        |   |-- Ubuntu.tar
        |   `-- kali-linux.tar
        `-- workspace
            `-- WSL_Drives.vhdx
```

## Fontes E Referencias

Este projeto segue os fluxos oficiais de `wsl.exe --export`, `wsl.exe --import`, `wsl.exe --shutdown` e manejo de disco WSL descritos pela Microsoft:

- [Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [FAQ about WSL](https://learn.microsoft.com/en-us/windows/wsl/faq)
- [How to manage WSL disk space](https://learn.microsoft.com/en-us/windows/wsl/disk-space)
- [Troubleshooting WSL](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting)

A escolha de licenca segue o padrao MIT visto no repositorio de referencia [LuizFernandoDeveloper/LandpageDisneyPlus](https://github.com/LuizFernandoDeveloper/LandpageDisneyPlus).

## Licenca

Distribuido sob a licenca MIT. Veja [LICENSE](LICENSE).
