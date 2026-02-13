# Refactor: port legacy yn-be controller to yn-be-v2 (TypeScript)

Refactor a legacy yn-be controller to yn-be-v2.

## Mandatory rule source

For coding conventions, SQL rules, typing, validation, transactions, testing patterns, and project structure, **do not duplicate rules in this command**.

Use this skill as the single source of truth (path relative to the user's home directory, valid on any OS):
- **macOS/Linux:** `$HOME/.agents/skills/yn-be-developer-ts/SKILL.md`
- **Windows:** `%USERPROFILE%\.agents\skills\yn-be-developer-ts\SKILL.md`

## Inputs

- `${newFile}`: path to new v2 controller (example: `src/controllers/addressbook.controller.ts`)
- `${legacyFile}`: path to legacy controller in yn-be (example: `src/controllers/addressbook-controller.ts`)
- `${method}` (optional): specific method/API to implement (example: `"getById"`, `"POST /users/:id"`). If provided, implement only this method; otherwise implement the entire class.

## Refactor scope

- Port routes and logic from `${legacyFile}` to `${newFile}`.
- If `${method}` is provided, implement only that method/API.
- If `${method}` is not provided, port all routes and logic from the legacy controller.
- Preserve legacy behavior (authorization checks, filters, sorting, and response semantics).
- Overwrite `${newFile}` and keep imports resolved inside yn-be-v2.
- Do not drop functionality; if a dependency cannot be ported immediately, keep structure and add a focused `// TODO: ...`.

## Out of scope

- Do not write tests in this step.
- After implementation is corrected, use `commands/test.md` to create or update tests.

## References

- Skill at `$HOME/.agents/skills/yn-be-developer-ts/SKILL.md` (all conventions and technical directives; on Windows use `%USERPROFILE%\.agents\skills\yn-be-developer-ts\SKILL.md`)
- `commands/test.md` (test creation/update flow)
