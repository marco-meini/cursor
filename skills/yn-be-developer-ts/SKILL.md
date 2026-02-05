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
- **Models**: Prefer `env.pgModels.<model>.<method>()`; add new models in **src/model/postgres/pg-models.ts** (extend `Abstract_PgModel`).
- **Read-only**: Use **`isSlave: true`** for COUNT and read-only SELECT; never for INSERT/UPDATE/DELETE.
- **updateByKey**: Keys are an **array** (e.g. `["id_us"]`, `['id_up']`), not a string. Payload may include `id_last_updater_up` from `request.session.idUser`.
- **MongoDB**: `env.mongoClient`, `env.mongoModels`; same patterns as in JS skill for parameterized access and sanitization.

## TypeScript Conventions

### Types and Interfaces
- **Single source of truth**: Define shared interfaces (e.g. `IGrantRecord`, `IUserRecord`) in **one** model file; import elsewhere. Do not duplicate.
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
- Structured errors: `error.status`, optional `error.errors` array; never expose stack or raw DB errors in responses.
- Cookies: When setting session cookie, pass an **options object** (e.g. `{ maxAge, ... }` or `{}`), never `null`.

## SQL & PgFilter

- Use **queryReturnFirst** for single-row checks (e.g. folder count); **query** for multi-row or when expecting `{ rows }`. Tests must stub and assert on the method actually used.
- **PgFilter (common-mjs)**: `addEqual`, `addIn`, `addCondition`, `addPagination`, `getWhere()`, `getPagination()`, and **always** **`getParameterPlaceHolder(value)`** for custom conditions (never manual `$1`, `$2`). Ranges: `addGreaterThan(col, val, true)` = `>=`, `addLessThan(col, val, true)` = `<=` (third param = orEqual boolean).

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
4. **Handle errors** – next(error), HttpResponseStatus constants.
5. **Types** – Single source for interfaces; Record vs Extended; optional chaining for relations.
6. **SQL** – queryReturnFirst vs query; isSlave: true for read-only; getParameterPlaceHolder; transactionClient.
7. **No production changes for tests** – complete mock config (pubSubOptions, getstream, sms, etc.) and minimal fake env when appropriate.

When in doubt, prefer the patterns described in **refactor.md** and **test.md** for controllers, handlers, types, and tests.
