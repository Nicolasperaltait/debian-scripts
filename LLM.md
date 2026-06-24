# LLM.md — Adaptador universal de arranque

Adaptador de arranque para cualquier LLM (Codex, Claude, modelos locales, Cursor, Continue u otros). [AGENTS.md](./AGENTS.md) es la autoridad de este repositorio; este documento no la reemplaza ni la relaja.

## Orden de arranque

1. [README.md](./README.md)
2. [AGENTS.md](./AGENTS.md) (raíz)
3. AGENTS.md local del módulo, si existe
4. [CLAUDE.md](./CLAUDE.md) y la documentación de área en [docs/](./docs/)
5. `git status --short` antes de cualquier cambio

Puede existir un [CLAUDE.md](./CLAUDE.md) con notas específicas para Claude; sus reglas nunca prevalecen sobre AGENTS.md.

Restricciones de seguridad, privacidad, trazabilidad y no invención de datos no se relajan por ningún documento de menor prioridad que AGENTS.md. En particular, este repositorio es público: ningún archivo versionado debe contener secretos, nombres personales ni IPs privadas, y `tests/public-safety.sh` lo verifica.
