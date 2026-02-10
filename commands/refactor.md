# Refactor: port legacy yn-be controller to yn-be-v2 (TypeScript)

Refactor a legacy yn-be controller to yn-be-v2.

**Inputs:**
- `${newFile}`: path to new v2 controller (e.g. `src/controllers/addressbook.controller.ts`)
- `${legacyFile}`: path to legacy controller in yn-be (e.g. `src/controllers/addressbook-controller.ts`)
- `${method}`: (optional) specific method/API to implement (e.g. `"getById"`, `"POST /users/:id"`). If provided, implement only this method; otherwise implement the entire class

**Goals:**
- Port routes and logic from `${legacyFile}` to `${newFile}`
- If `${method}` is provided, implement only that specific method/API; otherwise port all routes and logic
- Use **TypeScript**, `PgClientManager` (`env.pgConnection`), and shared utils
- Enforce ExpressMiddlewares for pagination and path params

**Do not write tests in this step.** The refactor command produces only implementation code. After correcting the refactor result, write or update tests using the **test** command (`commands/test.md`).

---

## 1) Controller skeleton

- Extend `Abstract_Controller`; call `super(env, "<scope>")`
- Register routes in constructor: `this.router.<verb>(path, middlewares..., this.<handler>.bind(this))`
- **Method names:** Use **private** method names **without** a `__` prefix (e.g. `getNations`, `login`). Tests will call them via `(controller as any).getNations(...)`.
- Always add ExpressMiddlewares:
  - `validIntegerPathParam('<param>')` for numeric `:params` (middleware sets `res.locals[param]`, not always `res.locals.id`)
  - `parsePaginationParams(required=true|false)` for list endpoints (offset is `(page - 1) * limit`)
  - `validIntegerQueryParam('<param>', required?)` when needed

---

## 2) Handlers

- Each handler: `try/catch` → validate → call `env.pgConnection` / `env.pgModels` → shape response
- Read parsed values from `res.locals` (e.g. `res.locals.id`, `res.locals.testParam`, `res.locals.limit`, `res.locals.offset`)
- Use `HttpResponseStatus` constants (no numeric literals)
- **Transactions:** `const t = await env.pgConnection.startTransaction()`; then `commit(t)` / `rollback(t)` explicitly. Use **`transactionClient: t`** (not `transaction`) when passing to `query` / `insert` / `updateByKey`.
- **Validation:** Use `_.isNil(variable)` for null/undefined; use `_.isArray(x)` when a value must be an array (e.g. `if (_.isNil(numbers) || !_.isArray(numbers) || numbers.length === 0)`). For IDs, validate with `Number.isInteger(id) && id > 0` (e.g. `idCustomer`, path params) so strings like `'invalid'` return 400, not 404.
- **Model methods:** Apply the same `_.isNil()` and type checks in model methods; return `result?.rows ?? []` or throw when query result is null/undefined where appropriate.
- **Cookies:** When setting session cookie, pass an **options object** (e.g. `{ maxAge, ... }` or `{}`), never `null`, so tests can assert on the third argument.

---

## 3) SQL & filtering

- Replace Sequelize with SQL via `env.pgConnection.{query, queryReturnFirst, queryPaged}`
- Use **queryReturnFirst** for single-row checks (e.g. folder count, existing record); use **query** for multi-row or when the controller expects `{ rows }`. Tests must stub and assert on the method the controller actually uses.
- Preserve legacy behavior (filters, sorting, response shape)
- For lists: deterministic ordering and envelope `{ total, data }`
- **Read-only queries:** Use `isSlave: true` for COUNT and read-only SELECT. Never use `isSlave: true` for INSERT/UPDATE/DELETE.
- **Avoid duplicate queries:** Extract repeated or similar queries into model methods (in classes extending `Abstract_PgModel`). Register new models in `src/model/postgres/pg-models.ts`. Use `this.env.pgModels.<model>.<method>()` in controllers.
- **Query result shape — flat row, no wrapper:** Type the query result as the **exact row shape** returned by the SELECT. Do **not** wrap the whole row in an outer `SELECT row_to_json(q) AS question FROM (...) q`. Return columns directly so each row has a flat structure. Example type: `query<{ id_tq: number; mandatory: boolean; type: string; choices: ITicketQuestionChoiceRecord[]; tree: ITicketCustomizedTreesRecord }>`.
- **row_to_json for joined/related data:**
  - **Single related record:** Use `row_to_json(alias) AS column_name` (e.g. `row_to_json(tct) AS tree`) so the row has one column with the full record. Type it with the model interface (e.g. `tree: ITicketCustomizedTreesRecord`).
  - **Array of related records:** Use `COALESCE((SELECT json_agg(row_to_json(alias)) FROM table alias WHERE ...), '[]'::json) AS column_name` so the row has one column with an array of full records. Type it with the record array (e.g. `choices: ITicketQuestionChoiceRecord[]`).
  - Do **not** return only IDs when you need full records; use `json_agg(row_to_json(...))` for arrays and `row_to_json(...)` for the single record. Define and use `I*Record` interfaces for each table involved.
- **No unnecessary variables:** Do not introduce intermediate variables when the value is used only once. Inline the call in place (e.g. use `${filterTree.getWhere(false)}` directly in the SQL template literal instead of `const treeWhere = filterTree.getWhere(false)`).
- **PgFilter (common-mjs):** Use `addEqual`, `addIn`, `addCondition`, `addPagination`, `getWhere()`, `getPagination()`, and **always** `getParameterPlaceHolder(value)` for custom conditions (never manual `$1`, `$2`). For ranges: `addGreaterThan(col, val, true)` = `>=`, `addLessThan(col, val, true)` = `<=`; third param is `orEqual` (boolean), not type.

---

## 4) Types and interfaces (TypeScript)

- **One model file per table:** Each table has exactly one model file (e.g. `scheduled_phone_settings_sp` → `scheduled-phone-settings.model.ts`, `scheduled_phone_setting_fails_sf` → `scheduled-phone-setting-fails.model.ts`). The file name mirrors the table name (without suffix).
- **One interface per table:** Define exactly **one** `I<TableName>Record` interface per table with **all** columns. No subset interfaces (e.g. no `IRetryRow`, `IListItem`), no duplicate interfaces. The interface name reflects the table: `scheduled_phone_settings_sp` → `IScheduledPhoneSettingsRecord`, `scheduled_phone_setting_fails_sf` → `IScheduledPhoneSettingFailRecord`.
- **Single source of truth:** Define shared interfaces in **one** model file; import elsewhere. Do not duplicate interface definitions across files.
- **Use model interfaces:** When a table has an interface, **always use that interface**. Do **not** define custom interfaces in controllers or lib for the same shape. Import the `*Record` interface from the model and use it for parameters, return types, and query results.
- **Record vs extended:** Prefer a base interface for DB columns only (e.g. `IUserRecord` with only `_us` fields, including e.g. `status_us` when from table or always present) and an extended interface for computed/joined data (e.g. `IUserExtended` with `fullname`, `departmentFullname`, `pbx`, `plan`). Have model methods return the extended type when the query includes joined/computed fields.
- **Object properties in \*Record interfaces:** Properties that are object types (e.g. JSONB columns) must be typed with **`| string`** in the Record interface, because on insert/update they are passed to the database as serialized strings (e.g. `JSON.stringify(...)`). Example: `automatic_data_pm?: IAutomaticDataPm | string`.
- **Split model interfaces:** For models that return both “record-only” and “with relations” shapes, use e.g. `IWorkingPlanRecord` (table columns only) and `IWorkingPlanExtended extends IWorkingPlanRecord` (adds `users?`). Use optional chaining in controllers when reading optional relations (e.g. `workingPlan.users?.map(...) ?? []`).
- **Typing callbacks:** When mapping over arrays with mixed types (e.g. `type: string | number`), type the callback parameter to accept the source type and coerce in the return. Use `Buffer | string` when a value can be either (e.g. export output).

---

## 5) AuthZ

- Mirror legacy grants/ownership checks using `request.session.grants`, `idCustomer`, `idUser`.

---

## 6) Output and file layout

- Overwrite `${newFile}`; ensure imports resolve inside yn-be-v2.
- **Paths:** Source lives under **`src/`** (e.g. `src/controllers/`, `src/model/postgres/`, `src/lib/`). Use **`.ts`** extension; no `.mjs`.
- No Sequelize or legacy TS patterns; ESM-compatible TypeScript only.

---

## 7) Code completeness

- If `${method}` is provided: implement only that method/API from `${legacyFile}`.
- If not: replicate **all** routes and logic from `${legacyFile}` in `${newFile}`.
- Do not drop functionality; for unimplemented dependencies add a `// TODO: ...` and keep the structure.

---

## 8) Tests (Mocha + tsx) — reference only for test.md

This section describes patterns that **test.md** will use when you run the test command after the refactor. **Do not generate test code as part of the refactor.** Use **test.md** once the refactor output has been corrected.

- **Run tests:** Use `npm test` or `npm run test:all`. Scripts must use **`--require tsx/cjs`** (not `tsx/register`; from tsx v4 the register subpath is not exported) so Mocha can load `.ts` files.
- **Controller methods:** Controllers expose **private** methods **without** `__` (e.g. `getNations`, `login`). In tests (when written via test.md):
  - Call them via `(controller as any).methodName(...)`.
  - Use `describe('methodName', ...)` (not `describe('__methodName', ...)`).
- **Stubs:** Stub the real method name (e.g. `sinon.stub(controller as any, 'sendRequest')`), not `__sendRequest`. Same for lib/helpers: e.g. Bridge uses `sendRequest`, PunchingExportsHelper uses `parsePaddingTemplate`, `parseDateFormat`, `parseBoolean`.
- **Assertions:**
  - `pgConnection`: use **`transactionClient`** in `calledWith` / `calledOnceWith` (not `transaction`). For `query`, assert the shape the controller passes (e.g. `{ sql, replacements }` or `{ sql, replacements, transactionClient }`).
  - `pgConnection.startTransaction`: stub with **`.resolves(t)`** (not `.returns(t)`) so the controller receives the same transaction reference for `commit(t)` / `rollback(t)`.
  - `updateByKey`: keys are passed as an **array** (e.g. `["id_us"]`, `['id_up']`), not a string; payload may include `id_last_updater_up` from `request.session.idUser`.
  - Session/cookie: assert on the third argument of `response.cookie` (options object); use `sinon.match.object` or check for `expires` when testing persistent sessions.
- **Mock env (do not change production to satisfy tests):**
  - Use **`documentsConnection`** (not `ynDbConnection`) when the controller uses `env.documentsConnection`; assert on `documentsConnection.query` where relevant.
  - For code that builds `NotificationsManager` (hence `PubSubV2`), provide **`config.pubSubOptions`** with `topicId` and `authentication: { projectId, credentials }` so the constructor does not throw. Add `mockNotificationManager.store.resolves()` and `mockNotificationManager.publish.resolves()` where needed. Do **not** add factories or hooks in production code to inject mocks.
  - Provide **`config.getstream`** (e.g. `apiKey`), **`config.sms`** (e.g. `fakeSms`), and any other config keys the controller or its dependencies read (e.g. `SmsGatewaySkebby`, `sessionManager.set`).
  - For helpers/models that need env but not full config, use a **minimal fake env** (e.g. `pgConnection`, `pgModels.*` stubs) instead of `new Environment()` when the real config is missing or incomplete.
- **Import paths:** From `test/` use **`../../src/...`** (two levels to project root). From **`test/lib/notifications/`** use **`../../../src/...`** and **`../../../config/...`** (three levels). Using `../../` from `test/lib/notifications/` resolves to `test/`, so modules under `src/` would not be found.
- **Dynamic imports in tests:** Prefer static imports for source modules. If you must load a module in a hook, `require('../../src/lib/...')` (with tsx/cjs) resolves correctly; dynamic `import('../../src/...')` from `test/lib/` can fail resolution.
- **Rollback behavior:** If the controller does **not** wrap `rollback` in try/catch, when `rollback` rejects, `next` is called with the **rollback error**, not the original error. Tests should assert `next(rollbackError)` and must **not** expect `logger.error` for rollback in that case.
- **Logger:** If the controller calls `this.env.logger.warning`, the mock env must provide `logger.warning` (not only `logger.warn`); assert on `logger.warning` in tests.
- **query vs queryReturnFirst:** Stub the method the controller actually uses (e.g. folder existence check via `queryReturnFirst`); fix error-propagation tests to reject on that same method.

---

## 9) Lib and integration tests

- **Bridge:** Constructor accepts a **single** argument (options object with `protocol`, `host`, `path`, etc.). Private method is `sendRequest`, not `__sendRequest`.
- **Getstream:** Constructor expects four arguments: `(pgConnection, mongoClient, config, logger)`. `getUser()` uses `pgConnection.queryReturnFirst`, not model methods; stub `pgConnection.queryReturnFirst` for token/user tests.
- **Model tests:** Stub return shapes to match actual API: e.g. `queryPaged` returns `{ totalRowCount, rows }` or `{ total, rows }`; `query` returns `{ rows }`. Use aliased column names in mock rows when the SQL uses `AS` (e.g. `id`, `user`, `day`, `minutes` for getExtraWotkingTime).

---

## References

- `src/controllers/fax.controller.ts` (pagination & SQL patterns)
- `src/lib/express-middlewares.ts` (param parsing: `res.locals[param]`, offset `(page - 1) * limit`)
- `src/model/postgres/pg-models.ts` (model registration)
- `.github/prompts/refactor.prompt.md` (general playbook)
