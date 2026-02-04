## Goal
Model: GPT-5 (desired)
Parameters (required – provided as ordered lines, each separated by a newline):
1. TARGET_NAME → becomes `${targetCode}` in the template; fully qualified target to test (Class or Class.method). Example: `UsersModel.getActiveUsers` or `AuthController.login`. Use the **real method name** (no `__` prefix); controllers expose private methods without `__`.
2. TEST_FILE_PATH → becomes `${testFile}`; repo-relative path to the test file to create/update (must end with `.test.ts`).
When invoking the prompt, supply the parameters in this order, one per line without prefixes, for example:
```
/test
TargetClassOrMethod
test/controllers/target.controller.test.ts
src/controllers/target.controller.ts
```

Output: Markdown fenced TypeScript/JavaScript code for the test content (or delta additions) only.

Audience: project contributors / maintainers.
Given ${targetCode}, ${sourceFile} (if provided) and ${testFile} produce (or update) a Mocha-style test suite (TypeScript `.test.ts`) aligned with project patterns (see existing tests under `test/`). Focus on full logical branch coverage, validation, and error propagation. Source code lives under **`src/`**; tests run with **`npm test`** or **`npm run test:all`** (Mocha + **`--require tsx/cjs`**).

## Context Linking
If ${sourceFile} is supplied:
* Output (before the code block) two plain lines (no clickable links to avoid validation issues):
	* `Implementation: ${sourceFile}`
	* `Test File: ${testFile}`
If it is not supplied, skip these lines; do not guess paths. Relative imports inside code still inferred or derived from provided source path.

## Golden Rules
1. Use TypeScript/ESM: `import ... from '...'`. Test files are `.test.ts`; source under **`src/`** (e.g. `src/controllers/`, `src/lib/`, `src/model/`).
2. Each CLASS gets a top-level `describe('<ClassName>')`.
3. Each METHOD gets its own nested `describe('<methodName>')` — use the **real method name** (e.g. `login`, `getNations`), **not** `__methodName`.
4. Organize inside each method block: optional context `describe('Success')` / `describe('Error')` if branches > 2; else individual `it` cases.
5. Use `sinon` for stubs/spies; prefer `sinon.assert.calledWith` over manual arg inspection.
6. No chai-as-promised; use try/catch for async error assertions.
7. **Controller private methods:** Call them via `(controller as any).methodName(...)`. Stub with `sinon.stub(controller as any, 'methodName')` (real name, no `__`).
8. Never import production secrets or mutate real environment configs.
9. Do NOT reference `test/test-instructions.md` (file will be removed). Integrate its logic here.
10. Do not test raw SQL strings; only assert that the query method was called with objects containing expected shape / replacements. Use **`transactionClient`** in assertions (not `transaction`). Stub **`queryReturnFirst`** when the controller uses it (e.g. folder count); stub **`query`** when it expects `{ rows }`.
11. ALWAYS apply changes directly to ${testFile} in the workspace (create/update the file) rather than only suggesting edits in chat. The chat output must mirror the actual saved file content. (IT: L'agent deve sempre modificare direttamente il file di test e non solo suggerire il codice in chat.)
12. NEVER modify the production implementation file (`${sourceFile}`) while generating tests. Do **not** add factories or hooks in production to inject mocks. Prefer: (a) providing a **complete mock config** (e.g. `config.pubSubOptions`, `config.getstream`, `config.sms`) so constructors do not throw, (b) minimal fake env instead of `new Environment()` when config is missing, (c) local HTTP server / fixtures under `test/` only.
13. After writing tests to ${testFile}, ALWAYS run them using the test runner and iterate until ALL tests pass. Use **`npm test -- ${testFile}`** to run the specific test file (Mocha loads `.ts` via **`--require tsx/cjs`**). Fix any failing tests by adjusting the test code (NOT the production code) until the entire suite is green. (IT: Dopo aver scritto i test, eseguirli SEMPRE e iterare fino a quando tutti i test non passano. Correggere eventuali test falliti modificando SOLO il codice di test, non il codice di produzione.)
14. Do not attempt to stub immutable ES Module default exports. Sinon cannot stub ESM bindings directly. Use HTTP server in test, or indirection in `test/fixtures/` only if that pattern exists (do NOT edit prod code).
15. When encrypt/decrypt or similar static utility calls occur, stub only those static methods (e.g. `Crypt.encryptAES`); never alter the underlying class file.
16. If a required branch is impossible to reach without altering production code (rare), add a `// TODO: unreachable branch without code change` comment rather than changing production.
17. **NotificationsManager / PubSubV2:** Do **not** stub the constructor or add production hooks. Provide in the mock env a **`config.pubSubOptions`** with `topicId` and `authentication: { projectId, credentials }` so `new NotificationsManager(env)` (and thus `new PubSubV2(...)`) does not throw. Add `mockNotificationManager.store.resolves()` and `mockNotificationManager.publish.resolves()` so the async flow completes. For other deps (e.g. Getstream, SmsGatewaySkebby), provide **`config.getstream`**, **`config.sms`** (e.g. `fakeSms`), etc., so constructors do not read `undefined`.
18. **Rollback:** If the controller does **not** wrap `rollback` in try/catch, when `rollback` rejects, `next` is called with the **rollback error**, not the original error. Assert `next(rollbackError)` and do **not** expect `logger.error` for rollback in that case.
19. **Logger:** If the code under test calls `this.env.logger.warning`, the mock env must provide `logger.warning` (not only `logger.warn`).

## Coverage Expectations
Cover: happy path, each conditional branch, invalid parameters, edge values (0, empty array, null, undefined), error propagation (`next(error)` in controllers, thrown errors in models/libs). Validate:
* HTTP status codes & response methods (`send`, `sendStatus`, `json`, `cookie`, `clearCookie`).
* Sequence & arguments of model / DB operations.
* Side-effects: cookie set/cleared, session manager calls, grants updated, transformation of data objects.

## Folder-Specific Directives

### 1. Controllers (`test/controllers/*.test.ts`)
Patterns (see `auth.controller.test.ts`):
* Mock `env` with: `config.sessionCookie`, `config.getstream` (e.g. `apiKey`), `config.sms` (e.g. `fakeSms`), `pgConnection`, `pgModels`, `session` (include `sessionManager` if the controller uses it), `documentsConnection` when the controller uses `env.documentsConnection`.
* For code that builds `NotificationsManager`, provide **`config.pubSubOptions`** with `topicId` and `authentication: { projectId, credentials }` so the constructor does not throw; add `store.resolves()` and `publish.resolves()` on the mock where needed.
* Stub `env.session.checkAuthentication()` to return a pass-through middleware when needed.
* **Call controller methods** via `(controller as any).methodName(request, response, next)` — use the real method name (e.g. `login`), not `__login`.
* For methods that set cookies: assert the **third argument** of `response.cookie` (options object); use `sinon.match.object` or check for `expires` when testing persistent sessions.
* **Transactions:** Stub `pgConnection.startTransaction` with **`.resolves(t)`** so the same `t` is used for `commit(t)` / `rollback(t)`. In assertions use **`transactionClient`** (not `transaction`). For **`updateByKey`**, keys are an **array** (e.g. `["id_us"]`, `['id_up']`); payload may include `id_last_updater_up` from `request.session.idUser`.
* Error path: ensure `next(error)` called with the correct error (original or **rollback error** if rollback rejects and controller does not wrap it in try/catch).
* Avoid leaking implementation details: only assert externally observable behavior (responses + env calls).

Example (controller method error branch):
```ts
it('should propagate DB error', async () => {
  const dbError = new Error('Database failed');
  env.pgModels.users.getUserByUsername.rejects(dbError);
  request.body = { username: 'u', password: 'p', persistent: false };
  await (controller as any).login(request, response, next);
  sinon.assert.calledWith(next, dbError);
  sinon.assert.notCalled(response.send);
});
```

Example (stub private method):
```ts
sinon.stub(controller as any, 'sendRequest').rejects(error);
```

### 2. Lib Utilities (`test/lib/*.test.ts`)
Patterns (see `utils.test.ts`):
* Use Node `assert` or `chai.expect` for pure functions; keep tests exhaustive yet concise.
* Cover boundary: empty input arrays, null/undefined, formatting edge cases.
* For validators: valid value, common invalid formats, null, undefined, empty, malformed.
* No external stubs unless a function internally calls time or randomness—then use `sinon.useFakeTimers()` when needed.
* **Import paths:** From `test/lib/` use **`../../src/...`** (two levels to project root). From **`test/lib/notifications/`** use **`../../../src/...`** and **`../../../config/...`** (three levels).
* For classes with private methods (e.g. Bridge, PunchingExportsHelper): call via `(instance as any).methodName(...)`; stub with `sinon.stub(instance as any, 'methodName')`. Bridge constructor takes a **single** options object; method is `sendRequest`, not `__sendRequest`.

Example (utility edge case):
```ts
it('should return empty string when all values falsy', () => {
  assert.strictEqual(String.joinNotEmptyValues('-', '', null, undefined), '');
});
```

### 3. Postgres Models (`test/model/postgres/*.test.ts` or `test/pg-models/*.test.ts`)
Patterns (see `users.model.test.ts`, `presence.model.test.ts`):
* Create a mock connection with stubbed methods: `query`, `queryReturnFirst`, `queryPaged`, `insert`, `updateByKey`, `startTransaction`, `commit`, `rollback` if used. Use **`.resolves(t)`** for `startTransaction` so the same transaction reference is used for `commit`/`rollback`.
* Stub return shapes to match actual API: **`queryPaged`** returns `{ totalRowCount, rows }` or `{ total, rows }`; **`query`** returns `{ rows }`. Use **aliased column names** in mock rows when the SQL uses `AS` (e.g. `id`, `user`, `day`, `minutes` for getExtraWotkingTime).
* For each method: assert correct `replacements` and optionally `sinon.match({ sql: sinon.match(/select/), replacements: [...] })`. Use **`transactionClient`** in matches when the method passes a transaction.
* Simulate different DB responses: `{ rows: [...] }`, `{ rows: [] }`, `null`, rejection. Model may return `result?.rows ?? []` or throw when result is null; align stub and assertions.
* Error path must bubble the same Error instance.
* For transactional flows: assert ordering `startTransaction` → updates/inserts → `commit`; error branch triggers `rollback`.

Example (model method happy path):
```ts
it('should return user grants', async () => {
  const grants = [{ id_gr: 1, code_gr: 'ADMIN' }];
  connection.query.resolves({ rows: grants });
  const result = await usersModel.getUserGrants(10);
  expect(result).to.deep.equal(grants);
  sinon.assert.calledWith(connection.query, sinon.match({ replacements: [10] }));
});
```

### 4. Notifications / Derived Domain Logic (`test/lib/notifications/*.test.ts`, `test/lib/*-notifications.test.ts`)
Patterns (see `groups-notifications.test.ts`, `users-notifications.test.ts`, `mailoffice-notifications.test.ts`):
* **Do not change production code** to inject mocks. Provide a **mock config** so `new NotificationsManager(env)` (and thus `new PubSubV2(env.config.pubSubOptions)`) does not throw:
  * Set **`config.pubSubOptions`** with `topicId` and `authentication: { projectId, credentials }` (e.g. `credentials: {}`).
  * Add **`mockNotificationManager.store.resolves()`** and **`mockNotificationManager.publish.resolves()`** so the async flow completes.
* Call **private methods** via `(notifications as any).methodName(...)` (e.g. `buildReceiverName`, `getCustomerIdFromPbx`, `getMailofficeUsers`); use `describe('methodName', ...)` (not `__methodName`).
* Assert payload structure and invocation count using `mockNotificationManager.store` and `mockNotificationManager.publish`.
* Include test for failure in underlying store and verify error propagation.
* **Import paths:** From **`test/lib/notifications/`** use **`../../../src/...`** and **`../../../config/...`** (three levels up to project root).

Example imports (file in `test/lib/notifications/`):
```ts
import sinon from 'sinon';
import { expect } from 'chai';
import { MailOfficeNotifications } from '../../../src/lib/notifications/mailoffice-notifications';
import { NotificationsManager } from '../../../src/lib/notifications/notifications-manager';
import { Topics } from '../../../src/model/mongo/notifications.collection';
import config from '../../../config/config';
```

Example setup (mock config so NotificationsManager constructor does not throw):
```ts
beforeEach(() => {
  mockEnv = {
    pgConnection: { query: sinon.stub(), queryReturnFirst: sinon.stub() },
    logger: { error: sinon.stub(), warn: sinon.stub(), warning: sinon.stub() },
    mongoModels: { notifications: { addDocument: sinon.stub() } },
    config: {
      ...config,
      pubSubOptions: {
        topicId: 'test-topic',
        authentication: { projectId: 'test-project', credentials: {} }
      }
    }
  };
  mockNotificationManager = { store: sinon.stub().resolves(), publish: sinon.stub().resolves() };
  // If the class under test creates NotificationsManager internally, the above config allows it to construct.
  notifications = new MyNotifications(mockEnv, mockSession);
});
```

### 5. External Service Classes (Bridge, Getstream, etc.)
* **Bridge:** Constructor accepts a **single** argument (options object with `protocol`, `host`, `path`, etc.). Private method is **`sendRequest`**, not `__sendRequest`. Stub with `sinon.stub(bridge as any, 'sendRequest')`.
* **Getstream:** Constructor expects **four** arguments: `(pgConnection, mongoClient, config, logger)`. `getUser()` uses **`pgConnection.queryReturnFirst`**, not model methods; stub `pgConnection.queryReturnFirst` for token/user tests. Provide `config.getstream` (e.g. `apiKey`, `adminUserId`) in the mock.
* Always restore stubs in `afterEach`: `sinon.restore()`.
* Prefer providing a **complete mock config** so constructors do not throw; use minimal fake env when the real config is missing or incomplete.

### 6. Export / Batch Utilities (`test/lib/*-exports*.test.ts`, `punchings-exports.test.ts` etc.)
* Use a **minimal fake env** (e.g. `pgConnection`, `pgModels.*` stubs) instead of `new Environment()` when the real config is missing or incomplete.
* For helpers with private methods (e.g. PunchingExportsHelper: `parsePaddingTemplate`, `parseDateFormat`, `parseBoolean`), call via `(helper as any).methodName(...)`.
* If file writes or streams would occur, stub fs or stream constructors.
* Validate produced CSV / lines structure (sample subset, not full huge strings).
* Include performance edge case: large input array (e.g. 1000 items) focusing on not throwing and calling transformation once per item.

## Assertion Strategy
Use:
* `sinon.assert.calledOnce(stub)`, `sinon.assert.calledWith(stub, expectedArgs...)`
* **`sinon.match`** for partial object / regex match of SQL. For `pgConnection.query` / `updateByKey`, use **`transactionClient`** in the expected args (not `transaction`).
* For **query** calls, assert the shape the code passes: e.g. `{ sql, replacements }` or `{ sql, replacements, transactionClient }`.
* **`updateByKey`:** keys are an **array** (e.g. `["id_us"]`, `['id_up']`); payload may include `id_last_updater_up` from session.
* For arrays and order-sensitive transformations, assert deep equality.
* For date fields: use `sinon.match.date` or assert `instanceof Date`.
* **Session/cookie:** assert on the third argument of `response.cookie` (options object); use `sinon.match.object` or check for `expires` when testing persistent sessions.

## Error Assertion Pattern (Async)
```js
try {
	await subject.method(args);
	assert.fail('Expected method to throw');
} catch (err) {
	assert.strictEqual(err, expectedError); // or shape assertions
}
```

## Edge Cases Checklist (Apply Where Relevant)
* Null / undefined inputs
* Empty arrays / empty objects
* Boundary numeric values: 0, -1 (if invalid), large numbers
* Missing required properties
* Duplicate entries (where uniqueness applies)
* Partial updates (omitting optional fields)
* Upstream service failure (token generation, notification push)

## Session & Auth
When controller endpoints require auth:
* Stub `env.session.checkAuthentication` to return `(req, res, next) => next()`.
* For negative path (unauthenticated) only if controller itself branches on session absence; otherwise rely on middleware coverage elsewhere.

## Generated File Behavior
If ${testFile} exists: merge new test blocks without duplicating existing method `describe`. If method block already exists:
* Add only missing branches / cases.
* Do not remove or rename existing tests.

If file ${testFile} does NOT exist:
* Generate full skeleton including imports, top-level describe, and complete method coverage template (with TODO comments for any logic you cannot infer).
 
In all cases, ensure the real ${testFile} on disk is updated to match the produced output (non-negotiable enforcement of rule 11).

## Imports Template
**Import paths:** From `test/` or `test/controllers/` use **`../../src/...`** (two levels to project root). From **`test/lib/notifications/`** use **`../../../src/...`** and **`../../../config/...`** (three levels). Prefer **static imports**; if loading in a hook, `require('../../src/lib/...')` with tsx/cjs resolves correctly.

Controllers (`test/controllers/`):
```ts
import sinon from 'sinon';
import { expect } from 'chai';
import { HttpResponseStatus } from 'common-mjs';
import { AuthController } from '../../src/controllers/auth.controller';
```
Models (`test/model/postgres/` or `test/pg-models/`):
```ts
import sinon from 'sinon';
import { expect } from 'chai';
import { UsersModel } from '../../src/model/postgres/users.model';
```
Utils (`test/lib/`):
```ts
import assert from 'assert';
import { String } from '../../src/lib/utils';
```
Notifications (`test/lib/notifications/` — use three levels):
```ts
import sinon from 'sinon';
import { expect } from 'chai';
import { MailOfficeNotifications } from '../../../src/lib/notifications/mailoffice-notifications';
import { NotificationsManager } from '../../../src/lib/notifications/notifications-manager';
import config from '../../../config/config';
```

## Output Requirements
Provide only the test file content (no extra narrative) inside a fenced ```typescript or ```ts block. If updating, show only the new or changed test blocks preceded by a brief comment `// Added tests for <method>`.

## Parameter Mapping
* ${targetCode} determines which class/method(s) to focus on. Use the **real method name** (e.g. `AuthController.login`), not `__login`. If only a method is supplied (Class.method), generate tests just for that method but still include the class-level + method-level describe hierarchy.
* ${testFile} must end with **`.test.ts`**. It determines import depth: **two levels** (`../../`) from `test/` or `test/controllers/` or `test/lib/` to project root; **three levels** (`../../../`) from `test/lib/notifications/` to project root.
* ${sourceFile} if provided should be used to compute the relative import path. Source lives under **`src/`**; use extension **`.ts`** or no extension as per project resolution. Do not use `.mjs`.

## Quality Gates Before Finish (Self-Check)
1. All new describe blocks follow pattern.
2. No direct references to removed instructions file.
3. Uses sinon assertions consistently.
4. No hardcoded secrets / environment leakage.
5. Edge cases addressed.

## Example Invocation Scenarios
1. ${targetCode}=AuthController.login, ${testFile}=test/controllers/auth.controller.test.ts, ${sourceFile}=src/controllers/auth.controller.ts → Add missing edge case (e.g. persistent cookie expiration) if absent; call via `(controller as any).login(...)`.
2. ${targetCode}=UsersModel.getUserGrants, ${testFile}=test/model/postgres/users.model.test.ts, ${sourceFile}=src/model/postgres/users.model.ts → Ensure empty array branch exists; stub return shape `{ rows: [...] }`; add error propagation test if missing.
3. ${targetCode}=String.joinNotEmptyValues, ${testFile}=test/lib/utils.test.ts, ${sourceFile}=src/lib/utils.ts → Add tests for unusual separators or all-falsy values if missing.

## If Information Is Ambiguous
Insert a `// TODO:` comment with a concise note (max 60 chars) rather than guessing a behavior not inferable from existing code.

Return only the test code output per instructions—no extra commentary beyond mandated added-block comments.
