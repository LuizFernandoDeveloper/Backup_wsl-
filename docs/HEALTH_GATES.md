# Health Gates E Templates

As distros exportadas em `.tar` podem funcionar como templates. Isso significa que o mesmo TAR pode restaurar a distro original ou criar clones com outros nomes.

Por isso, o script mede a saude da distro antes de exportar.

## Saude Leve

Verifica:

- se a distro responde via `sh`;
- uso de disco em `/`;
- uso de inodes;
- tamanho do `ext4.vhdx` no Windows;
- sockets temporarios em `/tmp`, `/var/tmp` e agentes SSH.

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly
```

## Diagnostico Pesado

Verifica tambem:

- sockets no filesystem inteiro;
- links quebrados;
- escrita em `/tmp`;
- escrita no `$HOME`;
- se `/` parece `read-only`;
- erros ao varrer diretorios;
- sinais fortes no `dmesg`, como `I/O error`, `EXT4-fs error`, `read-only file system` e `Structure needs cleaning`;
- maiores diretorios e caches.

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -HealthOnly -DeepHealth
```

## Niveis De Exigencia

| Nivel | Uso | Regra |
| --- | --- | --- |
| `Basic` | Emergencia | Relata quase tudo sem bloquear |
| `Standard` | Backup comum | Bloqueia problemas criticos |
| `Template` | Base para clones | Purifica, diagnostica pesado e bloqueia qualquer sujeira relevante |

## Purificacao De Template

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode Distros -PurifyOnly -QualityGate Template
```

Esse modo:

- remove sockets temporarios em `/tmp`, `/var/tmp` e agentes SSH;
- tenta rotacionar e reduzir journald para 7 dias;
- executa `sync`;
- roda diagnostico pesado;
- reprova se ainda houver algo grave.

## Backup Com Gate De Template

```bat
launchers\Executar_Mega_Backup_WSL.cmd -BackupMode All -QualityGate Template
```

Nesse modo, o backup real so exporta se a purificacao e o diagnostico passarem.

Voltar ao [indice da documentacao](README.md).
