# Restauracao E Clones

Cada backup publicado gera um `RESTORE_GUIDE.txt` dentro da pasta do `RUN_ID`.

## Conferir Integridade

```powershell
Get-FileHash "F:\Backup\WSl_backup\Runs\RUN_ID\distros\Ubuntu.tar" -Algorithm SHA256
```

Compare com:

```text
F:\Backup\WSl_backup\Runs\RUN_ID\checksums.sha256
```

## Restaurar Com O Mesmo Nome

```bat
wsl.exe --shutdown
wsl.exe --import "Ubuntu" "D:\WSL-Restored\Ubuntu" "F:\Backup\WSl_backup\Runs\RUN_ID\distros\Ubuntu.tar" --version 2
```

Nao importe uma distro com nome ja existente.

## Usar Como Template/Clone

```bat
wsl.exe --shutdown
wsl.exe --import "Ubuntu-lab" "D:\WSL-Restored\Ubuntu-lab" "F:\Backup\WSl_backup\Runs\RUN_ID\distros\Ubuntu.tar" --version 2
```

Esse fluxo cria uma nova distro a partir do mesmo TAR.

## Restaurar VHDX Extra

O arquivo extra fica em:

```text
F:\Backup\WSl_backup\Runs\RUN_ID\workspace\WSL_Drives.vhdx
```

Restaure somente com o WSL desligado:

```bat
wsl.exe --shutdown
```

Voltar ao [indice da documentacao](README.md).
