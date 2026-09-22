# Spec-Driven Development (SDD) — guia do repo

Workflow: ESPECIFICAR → revisar spec → implementar com TDD → review.

## Estrutura de specs

    .planning/<feature>/
    ├── README.md          # índice: problema, solução, ordem
    └── specs/TASK-xxx.md  # 1 spec = 1 task = 1 PR

## TASK template (contrato executável)

- **Status:** Draft | Ready | In Progress | Review | Done
- **O QUE É** (1 frase)
- **EXECUTION MODE:** YOLO (bug óbvio) | Interactive (checkpoint em decisões) | Pre-flight (só spec, humano aprova)
- **PRE-CONDITIONS:** verificadas contra o repo real
- **O QUE CRIAR:** arquivo(s) + descrição
- **RF-IDs cobertos** (rastreabilidade com a SPEC)
- **TESTES DERIVADOS:** dado/quando/então — existem ANTES do código
- **CRITÉRIO DE ACEITE:** max 5 itens testáveis
- **ARMADILHAS** conhecidas

## Regras

- Spec divergiu do real? Atualiza a spec NO MESMO COMMIT.
- Antes de implementar: grep pra não duplicar coisa existente.
- RF-ID propaga: spec → task → teste → commit → PR body.
