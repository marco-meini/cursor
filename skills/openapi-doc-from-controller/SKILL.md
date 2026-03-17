---
name: openapi-doc-from-controller
description: Creates or updates one OpenAPI YAML fragment from a single controller method. Use when documenting API endpoints, adding OpenAPI path items from Express routes, or when the user asks to document an endpoint or update docs from controller code.
---

# OpenAPI doc from controller method

This skill defines how to create or update **exactly one** OpenAPI path item in the project `docs/` folder, derived from a single controller method in the codebase.

## Input parameters

Supply these as ordered lines (one per line, no prefixes):

1. **Controller method name** (e.g. `getAssociations`) — the real method name that implements the endpoint (no `__` prefix). Use as `${method}`.
2. **Target YAML path under docs/** (e.g. `associations.yaml`). Use as `${file}`.
3. **(Optional)** Repo-relative path to the controller file (e.g. `src/controllers/associations.controller.ts`) for context. Source lives under **`src/`**; use **`.ts`** extension.

Example:

```
getAssociations
associations.yaml
src/controllers/associations.controller.ts
```

## Goal

Insert or update the OpenAPI path item for the Express route that invokes `${method}`. Do not change unrelated paths. Preserve formatting and ordering used in existing YAMLs. Implementation lives under **src/** (TypeScript, `.ts`); use the controller’s real method name when locating the route.

---

## Locating the route from `${method}`

1. Find the controller class that defines `${method}`. Pattern: `export class <Something>Controller extends Abstract_Controller`. Controllers use **private** method names **without** a `__` prefix (e.g. `getAssociations`, `login`).
2. In its constructor, find `super(env, "<scope>")`. The second argument is the scope/tag name used in YAML (replicate the exact case already used for tags in `docs/`, or capitalize if creating a new file).
3. In the constructor, find the router registration for `${method}`. Example:
   - `this.router.get("/", ..., this.getAssociations.bind(this));`
   - HTTP verb = router method (`get` | `post` | `put` | `patch` | `delete` | `head` | `options`).
   - Path segment (e.g. `"/"`, `"/:id"`, `"/:associationId/members/:customerId"`) is joined to the controller mount base.
4. Base mount path = scope (string passed to `super`) prefixed with `'/'`. If router path is `'/'`, full path is `'/<scope>'`. Otherwise: `'/<scope>' + routerPath`.
5. Convert Express path params `:paramName` to OpenAPI `{paramName}`.

---

## OpenAPI file creation (when `${file}` does not exist or is empty)

Create this skeleton exactly (2 spaces, no tabs). Replace placeholders with **project-specific** values (API title, description, contact, server URL, security scheme name/cookie name). Reuse existing root YAML in the repo as reference for `info`, `servers`, `security`, and `components.securitySchemes`.

```yaml
openapi: 3.0.3
info:
  title: <Project API Title>
  description: <Project API description>
  contact:
    email: <contact email>
  version: <version>
servers:
  - url: <base URL e.g. https://api.example.com/v1>
    description: <server description>
security:
  - <securitySchemeName>: []

tags:
  - name: <ScopeName>

paths:
  # (insert the new path item here)

components:
  securitySchemes:
    <securitySchemeName>:
      type: apiKey
      in: cookie
      name: <session-cookie-name>
```

Use `<ScopeName>` = scope string from `super(env, "scope")` (exact raw string). If multiple endpoints will live in this file, define only one tag entry here.

---

## OpenAPI file update (when `${file}` already exists)

1. Do **not** re-add header, servers, security or components if already present.
2. Ensure the top-level `tags:` list contains the scope tag. If missing, append it (keep alphabetical order if the list has more than one entry). No duplicates.
3. Under `paths:` add or merge the path item:
   - If the path key does not exist, insert it with 2-space indentation and alphabetical path key order.
   - If the path exists but the HTTP verb does not, add only that operation.
   - If the same verb exists, update only summary, description, parameters, requestBody, and responses if incomplete; otherwise leave unchanged (idempotent).
4. Keep this order inside each path item: tags, summary, description, parameters, requestBody, responses, security (if any). Do not add `operationId`.
5. Never remove existing responses or schemas.
6. Every operation must have a `tags:` array containing exactly the scope tag.

---

## Deriving operation metadata

- **Summary:** Short imperative phrase (≤6 words), e.g. "List Associations", "Update Member Association".
- **Description:** Use JSDoc above `${method}` if present; otherwise one concise sentence (present tense). No internal details (SQL, internal model names).
- **Parameters:** For each path variable `{var}`: `name`, `in: path`, `required: true`, `schema.type`: integer if variable ends with `Id` or is clearly numeric, else string. One-line description. Do not duplicate existing parameters.
- **Request body:** Only for methods that read `request.body.*` (e.g. PATCH/POST/PUT). Media type `application/json`. Schema: object with properties used in the method (e.g. `request.body.isAdmin` → type from usage: `_.isBoolean` → boolean, string usage → string).
- **Responses:**
  - Always include 200 (or 204 if the controller sends an empty body and semantics are delete/update without content).
  - For every non-200 status (4xx, 5xx, 201, 204, etc.), use `$ref` to common components when a matching name exists in **`docs/common-components.yaml`** (e.g. Ok, NoContent, BadRequest, Unauthorized, Forbidden, Blocked, NotFound). Format: `$ref: "./common-components.yaml#/components/responses/<Name>"`. Do not write inline description when a reusable component exists; use inline only when no component exists.
  - Map controller usages: NOT_FOUND → 404 NotFound; NOT_AUTHORIZED → 401 Unauthorized (or 403 Forbidden if permission denied); MISSING_PARAMS → 400 BadRequest; empty successful delete/update → 200 Ok or 204 NoContent (mirror existing scope style).
  - For 200 with JSON body: if the schema would exceed ~25 lines or has nested arrays/objects with ≥8 properties, put it under `components.schemas` and reference with `$ref: '#/components/schemas/<SchemaName>'`. Use a PascalCase name from the resource (e.g. ContractServices, CustomerBills). When adding a new schema, do not overwrite existing ones; reuse if structure matches.
  - Response status order: ascending (200 first, then others).
  - Optional `examples:` block only if short (≤15 lines); otherwise a reduced subset.
  - If the controller can return an empty array, document the array schema; no separate 204 unless the code uses `sendStatus(204)`.
- **Security:** If the root already defines security, do not add per-operation security unless the file has local overrides.

---

## Schemas policy

1. Reuse existing schemas in the same YAML when structure matches.
2. Add new component schemas when the 200 response is large (see threshold above) or the structure is (or will be) reused.
3. New schemas under `components.schemas`; create `schemas:` if missing. Keep schema names alphabetically ordered; place above `securitySchemes` if following typical file order.
4. Property order: identifiers first (id/ids), then key attributes, then nested arrays/objects, metadata/timestamps last.
5. Types: integer, number, string, boolean. For epoch milliseconds use integer with a description.
6. Avoid heavy example duplication; prefer examples at path level; in shared schemas use `example` sparingly.

---

## Validation and style

- Indentation: 2 spaces, no tabs, no trailing spaces.
- Paths: keep `paths` keys alphabetically sorted. Inside each operation, keep the order described above.
- YAML: double quotes only when needed (e.g. numeric-looking strings). Quote response status codes per project style (e.g. `"200"`).
- Idempotence: same inputs and unchanged implementation must not produce semantic diffs.

---

## Output

Write the result with the **write** tool to **`docs/${file}`**.

- Content = full updated (or new) YAML. No markdown fences or commentary around the file.
- If `${file}` already had content, write that content with **only** the minimal changes for the single endpoint from `${method}`.
- If `${file}` was new/empty, write the full skeleton with the single path under `paths:`.

Always use the write tool; do not only display content.

---

## Documentation index updates (when `${file}` is new or first endpoint in file)

When creating a new YAML file or adding the first endpoint to an empty file, update the doc index if the project has one:

1. **docs/index.js** (or equivalent): Add the route mapping, e.g. `'/<ScopeName>': "${file}"`, in alphabetical order. Use the scope from `super(env, "scope")`.
2. **docs/index.html** (or equivalent): Add a navigation item (e.g. `<li class="nav-item">` / `<a href="#/<ScopeName>">...</a>`) in alphabetical order; same scope capitalization.
3. If the project uses a version query on the script (e.g. `index.js?v=1.17`), increment the version so browsers load the updated bundle.

Skip these steps if the project has no such index files.

---

## Success criteria (self-check before output)

- [ ] Path and HTTP verb match the router registration for `${method}`.
- [ ] Tag matches controller scope and is present on the operation.
- [ ] Summary and description are concise and aligned with method JSDoc.
- [ ] Path params are complete and not duplicated.
- [ ] Request body only when the method uses a body.
- [ ] Responses cover all status codes implied by the controller.
- [ ] Schemas reused or added consistently with existing patterns.
- [ ] No unrelated sections changed.
- [ ] YAML valid, 2-space indentation.
- [ ] If `${file}` was new: index files (index.js, index.html, version) updated when they exist.

END OF SKILL.
