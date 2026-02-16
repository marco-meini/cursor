---
name: yn-be-developer-typescript
description: Best practices, coding conventions, and patterns for backend projects using TypeScript. Use when writing code, tests, or new features in TypeScript backends with src/, Express, PostgreSQL/MongoDB, and Mocha+tsx.
---

# Backend TypeScript – Best Practices & Skills

This skill provides guidance for working on TypeScript backend projects that follow this pattern: structure under **src/**, ESM, Express, PostgreSQL/MongoDB, and tests with Mocha + tsx. Align with **refactor.md**, **test.md**, **doc.md**, and **create-project.md** in `commands/` when refactoring, testing, documenting, or creating new projects.

## When to Use

- Writing new controllers, models, or utilities in TypeScript
- Creating or updating tests (`.test.ts`, Mocha + tsx/cjs)
- Implementing features in a codebase that uses `src/`, `env.pgConnection`, `env.pgModels`
- Reviewing or refactoring TypeScript backend code
- Generating OpenAPI docs or new project scaffolds

## Core Technologies

### Runtime & Language
- **Node.js**: ESM (`"type": "module"`), run with **tsx** (or compiled `dist/` with node)
- **TypeScript**: Strict mode, `.ts` only under **src/** (and **config/** if needed)
- **Imports**: Use **.js** extension in import paths for ESM resolution (e.g. `from "./app.js"`); tsx/Node resolve to `.ts` when needed. No `.mjs`.

### Testing
- **Mocha**: Test runner; scripts must use **`--require tsx/cjs`** (not `tsx/register`) so `.test.ts` files load
- **Chai**: Assertions (`expect`, `assert`)
- **Sinon**: Stubs/spies; stub **real method names** (e.g. `sinon.stub(controller as any, 'login')`), not `__methodName`
- **Structure**: Top-level `describe('<ClassName>')`, nested `describe('<methodName>')` with the **real method name** (no `__`)

### Web Framework
- **Express**: Routing and middleware; read parsed values from **`res.locals`** (e.g. `res.locals.id`, `res.locals.limit`, `res.locals.offset`)

## Architecture Patterns

### Project Structure
```
src/
  controllers/   # HTTP layer (extend Abstract_Controller, bind this.methodName)
  lib/           # Utilities, express-middlewares (validIntegerPathParam, parsePaginationParams)
  model/
    postgres/    # PgModels, Abstract_PgModel; register in pg-models.ts
    mongo/       # MongoModels, Abstract_BaseCollection
  cronie/        # Batch entry points (e.g. main-cronie.ts)
config/          # config.ts (or config.json)
docs/            # OpenAPI YAML fragments
test/            # .test.ts mirroring src (test/controllers/, test/lib/, test/lib/notifications/, test/model/...)
```
Source lives under **src/**; no **app/**.

### Controller Pattern
- Extend **Abstract_Controller**; call `super(env, "<scope>")`
- Register routes: `this.router.get("/", ..., this.methodName.bind(this))`
- **Private methods without `__`**: e.g. `login`, `getNations`, `getAssociations`. In tests call via **`(controller as any).methodName(...)`**
- Flow: try/catch → validate (early return with `HttpResponseStatus`) → `env.pgConnection` / `env.pgModels` → shape response
- Use **ExpressMiddlewares**: `validIntegerPathParam('<param>')`, `parsePaginationParams(required)`, `validIntegerQueryParam('<param>', required?)`. Middleware sets **`res.locals[param]`** (not always `res.locals.id`). Pagination offset = **(page - 1) * limit**.

### Data Layer
- **PostgreSQL**: `env.pgConnection` (`query`, `queryReturnFirst`, `queryPaged`, `insert`, `updateByKey`, `startTransaction`, `commit`, `rollback`). Pass **`transactionClient: t`** (not `transaction`) when using a transaction.
- **Models**: Prefer `env.pgModels.<model>.<method>()`; add new models in **src/model/postgres/pg-models.ts** (extend `Abstract_PgModel`). **Lookups by code/name** (e.g. get id by status code, get record by slug) belong in the **model**, not in the controller: expose methods like `getStatusIdByCode(status)`, `getBySlug(slug)` and call them from the controller.
- **Read-only**: Use **`isSlave: true`** for COUNT and read-only SELECT; never for INSERT/UPDATE/DELETE.
- **updateByKey**: Keys are an **array** (e.g. `["id_us"]`, `['id_up']`), not a string. Payload may include `id_last_updater_up` from `request.session.idUser`.
- **MongoDB**: `env.mongoClient`, `env.mongoModels`; same patterns as in JS skill for parameterized access and sanitization.

## TypeScript Conventions

### Types and Interfaces
- **One model file per table**: Each table has exactly one model file (e.g. `scheduled_phone_settings_sp` → `scheduled-phone-settings.model.ts`). File name mirrors the table name (without suffix).
- **One interface per table**: Exactly one `I<TableName>Record` interface per table with **all** columns. No subset interfaces (no `IRetryRow`, `IListItem`, etc.). Interface name reflects table: `scheduled_phone_setting_fails_sf` → `IScheduledPhoneSettingFailRecord`.
- **Single source of truth**: Define interfaces in one model file; import elsewhere. Do not duplicate.
- **Use model interfaces**: Always use the model interface. Do **not** define custom interfaces in controllers or lib for the same shape. Import the `*Record` interface from the model.
- **Record vs extended**: Base interface = DB columns only (e.g. `IUserRecord` with `_us` fields). Extended interface = computed/joined (e.g. `IUserExtended` with `fullname`, `departmentFullname`, `pbx`, `plan`). Model methods return the extended type when the query includes joins.
- **Object properties in \*Record interfaces**: Properties that are object types (e.g. JSONB columns) must be typed with **`| string`** in the Record interface, because on insert/update they are passed to the database as serialized strings (e.g. `JSON.stringify(...)`). Example: `automatic_data_pm?: IAutomaticDataPm | string`.
- **Split model interfaces**: e.g. `IWorkingPlanRecord` (table only) and `IWorkingPlanExtended extends IWorkingPlanRecord` (adds `users?`). In controllers use optional chaining: `workingPlan.users?.map(...) ?? []`.
- **Callbacks**: When mapping over arrays with mixed types, type the callback parameter to accept the source type; use `Buffer | string` when a value can be either.

### Validation (TypeScript)
- Use **`_.isNil(variable)`** for null/undefined; **`_.isArray(x)`** when a value must be an array (e.g. `if (_.isNil(numbers) || !_.isArray(numbers) || numbers.length === 0)`).
- For IDs (path/query/body): **`Number.isInteger(id) && id > 0`** so strings like `'invalid'` return 400, not 404.
- In model methods: same checks; return **`result?.rows ?? []`** or throw when query result is null/undefined where appropriate.

## Code Style & Naming

- **Files**: kebab-case (e.g. `auth.controller.ts`, `express-middlewares.ts`)
- **Classes**: PascalCase (`AuthController`, `ExpressMiddlewares`)
- **Private methods**: Real names, no `__` (e.g. `login`, `getNations`). Use TypeScript **`private`** when appropriate.
- **Constants**: UPPER_SNAKE_CASE; **HttpResponseStatus** constants, never hardcoded numeric codes.
- **Indentation**: 2 spaces; early returns; small, cohesive functions.

## Error Handling & HTTP

- Use **HttpResponseStatus** for all responses; propagate errors via **`next(error)`**.
- **Validation errors (e.g. MISSING_PARAMS):** When returning 400 for missing or invalid parameters, send a **descriptive error code** as plain text with **`.send("ERROR_MESSAGE")`**. Use **UPPER_SNAKE_CASE** codes that describe the specific failure (e.g. `STATUS_REQUIRED`, `CATEGORY_NAME_REQUIRED`, `CHOICE_VALUE_ALREADY_EXISTS`), not a generic `"MISSING_PARAMS"` or `sendStatus` only. This lets clients show a clear message or map codes to i18n. Example: `return response.status(HttpResponseStatus.MISSING_PARAMS).send("QUESTION_LABEL_REQUIRED");`
- Structured errors: `error.status`, optional `error.errors` array; never expose stack or raw DB errors in responses.
- Cookies: When setting session cookie, pass an **options object** (e.g. `{ maxAge, ... }` or `{}`), never `null`.

## SQL & PgFilter

- Use **queryReturnFirst** for single-row checks (e.g. folder count); **query** for multi-row or when expecting `{ rows }`. Tests must stub and assert on the method actually used.
- **Mandatory SQL existence check before delivery:** Validate every SQL statement against the target DB to ensure referenced tables and columns exist.
  - **SELECT:** Execute the query **as-is** (same SQL text, with valid parameters) and verify it runs without relation/column errors.
  - **INSERT / UPDATE:** Do **not** execute the write during validation. Execute a read-only probe `SELECT` on the target table that references the same columns used by the write, to confirm table/column existence.
- **Query result shape — flat row, no wrapper:** Type the query result as the **exact row shape** returned by the SELECT. Do **not** wrap the whole row in an outer `SELECT row_to_json(q) AS question FROM (...) q`. Return columns directly so each row has a flat structure. Example: `query<{ id_tq: number; mandatory: boolean; type: string; choices: ITicketQuestionChoiceRecord[]; tree: ITicketCustomizedTreesRecord }>`.
- **Single query with array_agg for parent + aggregated child data:** When loading parent rows with per-parent arrays of child values (e.g. categories with user/group visibility ids), use **one query** with `LEFT JOIN` + `GROUP BY` and **`array_agg(...) FILTER (WHERE ...)`** (and `COALESCE(..., '{}')::integer[]` for empty arrays) instead of two round-trips (one SELECT parents, one SELECT children by parent ids then merge in code). Example: `SELECT tc.id_tc, tc.name_tc, COALESCE(array_agg(tcv.id_user_tcv) FILTER (WHERE tcv.id_user_tcv IS NOT NULL), '{}')::integer[] AS user_ids, ... FROM ticket_categories_tc tc LEFT JOIN ticket_category_visibilities_tcv tcv ON ... WHERE tc.id_customer_tc = $1 GROUP BY tc.id_tc, tc.name_tc ORDER BY tc.name_tc`.
- **row_to_json for joined/related data:**
  - **Single related record:** Use `row_to_json(alias) AS column_name` (e.g. `row_to_json(tct) AS tree`) so the row has one column with the full record. Type it with the model interface (e.g. `tree: ITicketCustomizedTreesRecord`).
  - **Array of related records:** Use `COALESCE((SELECT json_agg(row_to_json(alias)) FROM table alias WHERE ...), '[]'::json) AS column_name` so the row has one column with an array of full records. Type it (e.g. `choices: ITicketQuestionChoiceRecord[]`). Do **not** return only IDs when you need full records; use `json_agg(row_to_json(...))` for arrays.
  - Define and use `I*Record` interfaces for each table involved.
- **No unnecessary variables:** Do not introduce intermediate variables when the value is used only once (e.g. use `${filterTree.getWhere(false)}` directly in the SQL template, not `const treeWhere = ...`).
- **PgFilter (common-mjs)**: `addEqual`, `addIn`, `addCondition`, and **always** **`getParameterPlaceHolder(value)`** for custom conditions (never manual `$1`, `$2` in the SQL string). Ranges: `addGreaterThan(col, val, true)` = `>=`, `addLessThan(col, val, true)` = `<=` (third param = orEqual). **Pagination:** use **`addPagination(limit, offset)`** and **`getPagination()`** in the SQL (do not build `LIMIT $n OFFSET $m` by hand). **Ordering:** use **`addOrderByCondition(field, direction)`** and **`getOrderBy()`** (do not build `ORDER BY ...` by hand when the filter supports it). **Replacements:** prefer **`new PgFilter(0)`** and have the filter own all placeholders (e.g. call `getParameterPlaceHolder(id)` for any value used in JOIN or SELECT); then use **`replacements = where.replacements`** only, without prepending values that the filter can manage.

## Transactions

- `const t = await env.pgConnection.startTransaction()`; then `commit(t)` / `rollback(t)`.
- Pass **`transactionClient: t`** to `query` / `insert` / `updateByKey`.
- In tests: stub **`startTransaction`** with **`.resolves(t)`** (not `.returns(t)`). If the controller does **not** wrap `rollback` in try/catch, when `rollback` rejects, **`next`** is called with the **rollback error**; tests should assert `next(rollbackError)` and not expect `logger.error` for rollback.

## Testing (Mocha + tsx)

- **Run**: `npm test` or `npm run test:all`; scripts use **`--require tsx/cjs`**.
- **Controller methods**: Call **`(controller as any).methodName(...)`**; **`describe('methodName', ...)`** (not `__methodName`).
- **Stubs**: `sinon.stub(controller as any, 'methodName')` (and same for lib/helpers: e.g. `sendRequest`, `parsePaddingTemplate`).
- **Assertions**: Use **`transactionClient`** in `calledWith`/`calledOnceWith`; **`updateByKey`** keys = array; **`response.cookie`** third arg = options object.
- **Mock env**: Do **not** change production to satisfy tests. Provide **`config.pubSubOptions`** (topicId, authentication) when code builds NotificationsManager/PubSubV2; **`config.getstream`**, **`config.sms`** (e.g. fakeSms) when used. Use **`documentsConnection`** (not `ynDbConnection`) when the controller uses it. For helpers that need env but not full config, use a **minimal fake env** instead of `new Environment()`.
- **Import paths**: From **test/** use **`../../src/...`**; from **test/lib/notifications/** use **`../../../src/...`** and **`../../../config/...`** (three levels).
- **Logger**: If the controller uses **`this.env.logger.warning`**, the mock must provide **`logger.warning`** (not only `logger.warn`).

## Configuration & Environment

- Do not read `process.env` directly in controllers; use Environment/config layer.
- Document defaults in **config/config.ts** (or project equivalent).

## Security, Logging, Batch, Git

- Same as in the Node.js backend skill: no secrets in code/logs; parameterized queries only; hash passwords in model layer; validate/sanitize input; use `env.session.checkAuthentication()` / `checkPermission()`.
- Logging: `env.logger` with appropriate levels; never log sensitive data.
- Batch/cron: under **src/cronie/**; idempotency and clear logging.
- Git: branch names `feature/`, `fix/`, `chore/`, `refactor/`; commits imperative present tense; PRs small and tested.

## Commands Reference

- **refactor.md**: Port legacy controller to TypeScript (src/, no __, transactionClient, types, tests).
- **test.md**: Write/update tests (.test.ts, tsx/cjs, (controller as any).methodName, mock env, no production changes).
- **doc.md**: OpenAPI YAML from controller **method name without __** and route registration.
- **create-project.md**: New TypeScript project (src/, .ts, tsconfig, tsx, private methods without __).

## Instructions Summary

1. **TypeScript only under src/** – .ts, ESM, real method names (no `__`).
2. **Test with Mocha + tsx/cjs** – (controller as any).methodName, transactionClient, correct mock config.
3. **Validate early** – _.isNil, _.isArray, Number.isInteger(id) && id > 0 where needed.
4. **Handle errors** – next(error), HttpResponseStatus constants; for validation (400) use `.send("ERROR_MESSAGE")` with UPPER_SNAKE_CASE codes.
5. **Types** – Single source for interfaces; Record vs Extended; optional chaining for relations.
6. **SQL** – queryReturnFirst vs query; isSlave: true for read-only; getParameterPlaceHolder; transactionClient; validate table/column existence before delivery (SELECT as-is, INSERT/UPDATE via probe SELECT).
7. **No production changes for tests** – complete mock config (pubSubOptions, getstream, sms, etc.) and minimal fake env when appropriate.

When in doubt, prefer the patterns described in **refactor.md** and **test.md** for controllers, handlers, types, and tests.
