# Arquitetura

## Fluxo Geral

```mermaid
flowchart TD
    A["Inventario"] --> B["Health check"]
    B --> C{"Quality gate"}
    C -->|"aprovado"| D["Staging"]
    C -->|"reprovado"| E["Falha segura"]
    D --> F["Exportar distros"]
    D --> G["Copiar VHDX"]
    F --> H["Validar TAR e SHA-256"]
    G --> I["Validar VHDX e SHA-256"]
    H --> J["Manifesto e checksums"]
    I --> J
    J --> K["Publicar em Runs"]
    K --> L["Atualizar LATEST.txt"]
```

## Staging

Tudo acontece primeiro em:

```text
F:\Backup\WSl_backup\_staging\RUN_ID.partial
```

O backup so vira oficial quando todas as validacoes passam.

## Publicacao

Depois da validacao:

```text
F:\Backup\WSl_backup\Runs\RUN_ID
```

## Retomada

Se falhar, o staging fica preservado. Na proxima execucao, o script:

- valida TARs ja existentes;
- recalcula hashes;
- reaproveita VHDX se bater com a origem;
- refaz apenas o item ausente ou invalido.

## Lock

O arquivo `.backup.lock` impede duas execucoes simultaneas no mesmo destino.

Voltar ao [indice da documentacao](README.md).
