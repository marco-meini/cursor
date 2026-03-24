---
name: test-from-target
description: Generates or updates Mocha-style test suites (.test.ts) from a target class or method. Use when writing tests from controller/model/lib code, when the user asks to test a class or method, or when adding test coverage for a specific target. Assumes TypeScript, ESM, Mocha with tsx/cjs, source under src/, tests under test/.
---

# Test from target (class or method)

Given a **target** (class or class.method), an optional **source file** path, and a **test file** path, produce or update a Mocha-style test suite (TypeScript `.test.ts`) aligned with project patterns. Focus on full logical branch coverage, validation, and error propagation. Source lives under **`src/`**; tests run with **`npm test`** or **`npm run test:all`** (Mocha + **`--require tsx/cjs`**).

## Input parameters

Supply as ordered lines (one per line, no prefixes):

1. **TARGET_NAME** (${targetCode}) — Fully qualified target to test: Class or Class.method. Examples: `UsersModel.getActiveUsers`, `AuthController.login`. Use the **real method name** (no `__` prefix); controllers expose private methods without `__`.
2. **TEST_FILE_PATH** (${testFile}) — Repo-relative path to the test file to create or update (must end with `.test.ts`).
3. **(Optional) SOURCE_FILE_PATH** (${sourceFile}) — Repo-relative path to the implementation file (e.g. `src/controllers/auth.controller.ts`) for context and import resolution.

Example:

```
AuthController.login
test/controllers/auth.controller.test.ts
src/controllers/auth.controller.ts
```

## Output

- **Markdown-fenced TypeScript** test content (or delta additions) only.
- **Apply changes directly** to ${testFile} in the workspace (create/update the file). Chat output must match the saved file. Do **not** only suggest edits in chat.
- **Never modify** the production file (${sourceFile}) when generating tests. Do not add factories or hooks in production to inject mocks.

## Context linking

If ${sourceFile} is supplied, output (before the code block) two plain lines:

- `Implementation: ${sourceFile}`
- `Test File: ${testFile}`

If not supplied, skip these lines; do not guess paths. Relative imports in code are inferred from the provided source path.

---

## Golden rules

1. **TypeScript/ESM:** `import ... from '...'`. Test files are `.test.ts`; source under **`src/`** (e.g. `src/controllers/`, `src/lib/`, `src/model/`).
2. **Structure:** Each **class** gets a top-level `describe('<ClassName>')`. Each **method** gets a nested `describe('<methodName>')` — use the **real method name** (e.g. `login`, `getNations`), **not** `__methodName`.
3. **Organization:** Inside each method block use optional `describe('Success')` / `describe('Error')` when branches > 2; else individual `it` cases.
4. **Sinon:** Use for stubs/spies; prefer `sinon.assert.calledWith` over manual argument inspection.
5. **Async errors:** No chai-as-promised; use try/catch for async error assertions.
6. **Controller private methods:** Call via `(controller as any).methodName(...)`. Stub with `sinon.stub(controller as any, 'methodName')` (real name, no `__`).
7. **Secrets/config:** Never import production secrets or mutate real environment configs.
8. **No obsolete refs:** Do not reference removed or project-specific instruction files; integrate any needed logic into the test design.
9. **SQL:** Do not assert on raw SQL strings; only assert that the query method was called with objects of the expected shape (e.g. replacements). Use **`transactionClient`** in assertions (not `transaction`). Stub **`queryReturnFirst`** when the controller uses it; stub **`query`** when it expects `{ rows }`.
10. **File writes:** Always update ${testFile} on disk; chat output must mirror the saved content.
11. **Production code:** Never modify ${sourceFile}. Prefer: (a) **complete mock config** so constructors do not throw (e.g. pubSub options, getstream, sms), (b) minimal fake env when config is missing, (c) local HTTP server or fixtures under `test/` only.
12. **Run tests (entire file, mandatory):** After writing tests, **always run the full `${testFile}` suite** (e.g. `npm test -- ${testFile}`), not just newly added tests or filtered `describe/it` blocks. Iterate until **all tests in that file pass**. Fix failures by changing **test code only**, not production.
13. **ESM stubs:** Do not stub immutable ES Module default exports; Sinon cannot stub ESM bindings. Use HTTP server in test or indirection under `test/fixtures/` only if that pattern exists (do not edit production).
14. **Static utils:** When encrypt/decrypt or similar static utilities are used, stub only those static methods (e.g. `Crypt.encryptAES`); do not alter the class file.
15. **Unreachable branches:** If a branch is impossible to cover without changing production, add `// TODO: unreachable branch without code change` instead of changing production.
16. **PubSub/Notifications:** Do not stub constructors or add production hooks. In the mock env provide **config** (e.g. `config.pubSubOptions` with `topicId` and `authentication: { projectId, credentials }`) so `new NotificationsManager(env)` (and any internal PubSub client) does not throw. Add `mockNotificationManager.store.resolves()` and `mockNotificationManager.publish.resolves()` so async flow completes. For other deps (e.g. Getstream, SMS), provide the corresponding **config** entries so constructors do not read `undefined`.
17. **Rollback:** If the controller does **not** wrap `rollback` in try/catch, when `rollback` rejects, `next` is called with the **rollback error**. Assert `next(rollbackError)` and do not expect logger.error for rollback in that case.
18. **Logger:** If the code under test uses `this.env.logger.warning`, the mock env must provide `logger.warning` (not only `logger.warn`).

---

## Coverage expectations

Cover: happy path, each conditional branch, invalid parameters, edge values (0, empty array, null, undefined), error propagation (`next(error)` in controllers, thrown errors in models/libs). Validate:

- HTTP status codes and response methods (`send`, `sendStatus`, `json`, `cookie`, `clearCookie`).
- Sequence and arguments of model/DB operations.
- Side effects: cookie set/cleared, session manager calls, grants updated, data transformations.

---

## Folder-specific directives

### Controllers (`test/controllers/*.test.ts`)

- Mock **env** with: session config, getstream/sms (or equivalent) config, `pgConnection`, `pgModels`, `session` (and `sessionManager` if used), and any other connections the controller uses (e.g. `documentsConnection`).
- For code that builds a notifications/pub-sub manager, provide **config** (e.g. `config.pubSubOptions` with `topicId` and `authentication: { projectId, credentials }`) so the constructor does not throw; add `store.resolves()` and `publish.resolves()` on the mock where needed.
- Stub `env.session.checkAuthentication()` to return a pass-through middleware when needed.
- **Call controller methods** via `(controller as any).methodName(request, response, next)` — real method name.
- For methods that set cookies: assert the **third argument** of `response.cookie` (options object); use `sinon.match.object` or check for `expires` when testing persistent sessions.
- **Transactions:** Stub `pgConnection.startTransaction` with `.resolves(t)` and use the same `t` for `commit(t)` / `rollback(t)`. In assertions use **`transactionClient`** (not `transaction`). For **`updateByKey`**, keys are an **array** (e.g. `["id_us"]`, `['id_up']`); payload may include fields from `request.session` (e.g. `id_last_updater_up`).
- Error path: ensure `next(error)` is called with the correct error (original or **rollback error** if rollback rejects and controller does not wrap it).
- Assert only externally observable behavior (responses and env calls), not implementation details.

### Lib utilities (`test/lib/*.test.ts`)

- Use Node `assert` or `chai.expect` for pure functions; exhaustive yet concise.
- Cover boundaries: empty arrays, null/undefined, formatting edge cases.
- For validators: valid value, invalid formats, null, undefined, empty, malformed.
- Stub only when the function uses time or randomness (e.g. `sinon.useFakeTimers()`).
- **Import paths:** From `test/lib/` use **`../../src/...`** (two levels to project root). From **`test/lib/notifications/`** use **`../../../src/...`** and **`../../../config/...`** (three levels).
- For classes with private methods: call via `(instance as any).methodName(...)`; stub with `sinon.stub(instance as any, 'methodName')`. If the class has a single-argument constructor (e.g. options object), use that; method names are real (e.g. `sendRequest`), not prefixed with `__`.

### Postgres models (`test/model/postgres/*.test.ts` or `test/pg-models/*.test.ts`)

- Mock connection with stubbed methods: `query`, `queryReturnFirst`, `queryPaged`, `insert`, `updateByKey`, `startTransaction`, `commit`, `rollback` as used. Use `.resolves(t)` for `startTransaction` so the same `t` is used for `commit`/`rollback`.
- Stub return shapes to match the actual API: **`queryPaged`** returns `{ totalRowCount, rows }` or `{ total, rows }`; **`query`** returns `{ rows }`. Use **aliased column names** in mock rows when the SQL uses `AS`.
- For each method: assert correct `replacements` and optionally `sinon.match({ sql: sinon.match(/select/), replacements: [...] })`. Use **`transactionClient`** when the method passes a transaction.
- Simulate DB responses: `{ rows: [...] }`, `{ rows: [] }`, `null`, rejection. Align stub with how the model uses the result (e.g. `result?.rows ?? []` or throw when null).
- Error path must bubble the same Error instance.
- Transactional flows: assert order `startTransaction` → updates/inserts → `commit`; error branch triggers `rollback`.

### Notifications / domain logic (`test/lib/notifications/*.test.ts`, `test/lib/*-notifications.test.ts`)

- Do not change production to inject mocks. Provide **mock config** so the notifications/pub-sub manager constructor does not throw (e.g. `config.pubSubOptions` with `topicId` and `authentication: { projectId, credentials }`).
- Add `mockNotificationManager.store.resolves()` and `mockNotificationManager.publish.resolves()` so async flow completes.
- Call **private methods** via `(notifications as any).methodName(...)`; use `describe('methodName', ...)`.
- Assert payload structure and invocation count on store/publish mocks. Include failure of underlying store and error propagation.
- **Import paths:** From **`test/lib/notifications/`** use **`../../../src/...`** and **`../../../config/...`** (three levels).

### External service classes (e.g. Bridge, Getstream)

- If the class constructor takes a **single** options object and has a private method like `sendRequest`, stub with `sinon.stub(instance as any, 'sendRequest')`.
- If the class needs DB/config/logger, provide a **complete mock** (e.g. `pgConnection.queryReturnFirst`, `config.getstream`) so constructors do not throw.
- Restore stubs in `afterEach`: `sinon.restore()`.

### Export / batch utilities

- Use a **minimal fake env** (e.g. stubbed `pgConnection`, `pgModels`) instead of a full real Environment when config is missing or incomplete.
- For helpers with private methods, call via `(helper as any).methodName(...)`.
- If file writes or streams occur, stub fs or stream constructors. Validate produced output (e.g. CSV) with a sample subset.
- Include an edge case for larger input (e.g. 1000 items) to ensure no throw and transformation called per item.

---

## Assertion strategy

- `sinon.assert.calledOnce(stub)`, `sinon.assert.calledWith(stub, expectedArgs...)`
- **`sinon.match`** for partial object or regex match of SQL. For `pgConnection.query` / `updateByKey`, use **`transactionClient`** in expected args (not `transaction`).
- For **query** calls, assert the shape passed by the code: e.g. `{ sql, replacements }` or `{ sql, replacements, transactionClient }`.
- **`updateByKey`:** keys are an **array**; payload may include session-derived fields.
- For arrays and order-sensitive logic, use deep equality.
- For dates: `sinon.match.date` or `instanceof Date`.
- **Session/cookie:** assert the third argument of `response.cookie` (options object); use `sinon.match.object` or check `expires` for persistent sessions.

---

## Error assertion pattern (async)

```ts
try {
  await subject.method(args);
  assert.fail('Expected method to throw');
} catch (err) {
  assert.strictEqual(err, expectedError); // or shape assertions
}
```

---

## Edge cases checklist

- Null / undefined inputs
- Empty arrays / empty objects
- Boundary numerics: 0, -1 (if invalid), large numbers
- Missing required properties
- Duplicate entries (where uniqueness applies)
- Partial updates (optional fields omitted)
- Upstream failure (e.g. token generation, notification push)

---

## Session and auth

When controller endpoints require auth:

- Stub `env.session.checkAuthentication` to return `(req, res, next) => next()`.
- Test unauthenticated path only if the controller itself branches on session absence; otherwise rely on middleware coverage elsewhere.

---

## Generated file behavior

- **If ${testFile} exists:** Merge new test blocks without duplicating existing method `describe`. If the method block already exists, add only missing branches/cases. Do not remove or rename existing tests.
- **If ${testFile} does not exist:** Generate full skeleton (imports, top-level describe, method-level describes, coverage template). Use `// TODO` for logic that cannot be inferred.

In all cases, **update the real ${testFile} on disk** to match the produced output.

---

## Import paths

- From `test/` or `test/controllers/` or `test/lib/`: **`../../src/...`** (two levels to project root).
- From **`test/lib/notifications/`**: **`../../../src/...`** and **`../../../config/...`** (three levels).

Use **static imports** where possible. If loading in a hook, `require('../../src/lib/...')` with tsx/cjs resolves correctly. Use the project’s shared types/constants package (e.g. `HttpResponseStatus`) when the codebase does.

---

## Output format

Provide only the test file content inside a fenced ` ```ts ` or ` ```typescript ` block. When updating, show only new or changed blocks preceded by a brief comment `// Added tests for <method>`.

---

## Parameter mapping

- **${targetCode}:** Class or Class.method to test. Use the **real method name**. If only Class.method is supplied, generate tests for that method but keep the class-level and method-level `describe` hierarchy.
- **${testFile}:** Must end with **`.test.ts`**. Drives import depth: **two levels** (`../../`) from `test/`, `test/controllers/`, or `test/lib/`; **three levels** (`../../../`) from `test/lib/notifications/`.
- **${sourceFile}:** Optional; use to compute relative import path. Source under **`src/`**; use **`.ts`** or no extension per project resolution. Do not use `.mjs`.

---

## Quality gates (self-check)

- [ ] All new describe blocks follow the pattern.
- [ ] No references to removed or project-specific instruction files.
- [ ] Sinon assertions used consistently.
- [ ] No hardcoded secrets or environment leakage.
- [ ] Edge cases addressed.
- [ ] Tests run and pass after writing.

---

## When information is ambiguous

Insert a `// TODO:` comment with a concise note (max 60 chars) rather than guessing behavior that cannot be inferred from the code.

Return only the test code per the instructions above — no extra commentary beyond mandated context lines and added-block comments.

END OF SKILL.
