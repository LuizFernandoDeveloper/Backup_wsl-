<p align="center">
  <img src="assets/mega-backup-wsl-banner.svg" alt="Mega Backup WSL" width="100%">
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2bd8ff?style=for-the-badge"></a>
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1+-244b7a?style=for-the-badge&logo=powershell">
  <img alt="WSL 2" src="https://img.shields.io/badge/WSL-2-0f172a?style=for-the-badge&logo=linux">
  <img alt="SHA-256" src="https://img.shields.io/badge/SHA--256-validated-16a34a?style=for-the-badge">
  <img alt="Resume enabled" src="https://img.shields.io/badge/resume-enabled-0ea5e9?style=for-the-badge">
</p>

<h1 align="center">Mega Backup WSL</h1>

<p align="center">
  Backup profissional para WSL no Windows, com distros tratadas como templates, VHDX extra, retomada automatica, health gates e publicacao segura.
</p>

<p align="center">
  <a href="#inicio-rapido">Inicio rapido</a> ·
  <a href="#comandos-principais">Comandos</a> ·
  <a href="#documentacao">Documentacao</a> ·
  <a href="#estrutura-do-backup">Estrutura</a> ·
  <a href="#licenca">Licenca</a>
</p>

---

## Visao Geral

| Area | Entrega |
| --- | --- |
| **Backup completo** | Exporta distros WSL e copia `WSL_Drives.vhdx` |
| **Templates saudaveis** | Purifica, diagnostica e bloqueia distros ruins antes de exportar |
| **Retomada automatica** | Continua a partir de `_staging` quando uma execucao falha |
| **Integridade** | Valida TAR/VHDX com SHA-256 e gera manifesto |
| **Operacao segura** | Usa lock, staging, logs, retencao e publicacao atomica |

> [!IMPORTANT]
> O script executa `wsl.exe --shutdown` durante backups reais. Feche terminais, editores e servicos dentro das distros antes de iniciar.

## Inicio Rapido

### <img src="https://img.shields.io/badge/recomendado-menu-2bd8ff?style=for-the-badge" alt="Menu">

Abra o menu interativo e escolha o tipo de backup.

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Escolher_Backup_WSL.cmd
```

### <img src="https://img.shields.io/badge/seguro-teste-64748b?style=for-the-badge" alt="DryRun">

Valide tudo sem exportar distros nem copiar o VHDX.

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -DryRun
```

### <img src="https://img.shields.io/badge/template-purificar-16a34a?style=for-the-badge" alt="Purify template">

Limpe e valide as distros como base de clones, sem publicar backup.

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

### <img src="https://img.shields.io/badge/backup-completo-0ea5e9?style=for-the-badge" alt="Backup completo">

Gere backup de distros + `WSL_Drives.vhdx` com exigencia de template.

```bat
D:\config_wsl\backup_distro_wsl\backup_all\Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

## Comandos Principais

| Objetivo | Comando |
| --- | --- |
| <img src="https://img.shields.io/badge/menu-interativo-2bd8ff" alt="menu"> | `Escolher_Backup_WSL.cmd` |
| <img src="https://img.shields.io/badge/backup-all-0ea5e9" alt="all"> | `Executar_Mega_Backup_WSL.cmd -BackupMode All` |
| <img src="https://img.shields.io/badge/backup-distros-6366f1" alt="distros"> | `Executar_Mega_Backup_WSL.cmd -BackupMode Distros` |
| <img src="https://img.shields.io/badge/backup-vhdx-f59e0b" alt="vhdx"> | `Executar_Backup_WSL_Drives_VHDX.cmd` |
| <img src="https://img.shields.io/badge/saude-leve-22c55e" alt="health"> | `Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly` |
| <img src="https://img.shields.io/badge/diagnostico-pesado-ef4444" alt="deep health"> | `Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly -DeepHealth` |
| <img src="https://img.shields.io/badge/template-gate-16a34a" alt="template"> | `Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template` |
| <img src="https://img.shields.io/badge/retomar-staging-64748b" alt="resume"> | `Executar_Mega_Backup_WSL.cmd -BackupMode All -ResumeRunId RUN_ID` |

> [!TIP]
> Use `-PurifyOnly -QualityGate Template` antes de criar uma distro-template importante. Ele remove sockets temporarios, tenta limpar journal antigo, roda diagnostico pesado e para sem exportar.

## Modos E Gates

### Modos De Backup

| Modo | Quando usar | Resultado |
| --- | --- | --- |
| `All` | Backup completo | Distros + `WSL_Drives.vhdx` |
| `Distros` | Templates ou restauracao de distros | Somente arquivos `.tar` |
| `Vhdx` | Copia rapida do disco extra | Somente `WSL_Drives.vhdx` |

### Quality Gates

| Gate | Perfil | Bloqueia |
| --- | --- | --- |
| `Basic` | Emergencia | Quase nada; prioriza gerar backup |
| `Standard` | Uso normal | Problemas criticos de filesystem, escrita ou montagem |
| `Template` | Base para clones | Sockets, read-only, erro de diretorio, falha de escrita e sinais fortes de filesystem ruim |

## Documentacao

| Topico | Link |
| --- | --- |
| Primeira execucao | [docs/QUICKSTART.md](docs/QUICKSTART.md) |
| Parametros e exemplos | [docs/USAGE.md](docs/USAGE.md) |
| Health gates e templates | [docs/HEALTH_GATES.md](docs/HEALTH_GATES.md) |
| Restauracao e clones | [docs/RESTORE.md](docs/RESTORE.md) |
| Arquitetura e retomada | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Erros comuns | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

## Estrutura Do Backup

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

## Arquivos Do Projeto

| Arquivo | Funcao |
| --- | --- |
| `Mega_Backup_WSL.ps1` | Motor principal |
| `Escolher_Backup_WSL.cmd` | Menu interativo |
| `Executar_Mega_Backup_WSL.cmd` | Atalho geral |
| `Executar_Backup_WSL_Drives_VHDX.cmd` | Atalho para VHDX |
| `docs/` | Guias por topico |
| `assets/` | Imagens do README |

## Referencias

- [Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [FAQ about WSL](https://learn.microsoft.com/en-us/windows/wsl/faq)
- [How to manage WSL disk space](https://learn.microsoft.com/en-us/windows/wsl/disk-space)
- [Troubleshooting WSL](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting)

## Licenca

Distribuido sob a licenca MIT. Veja [LICENSE](LICENSE).
