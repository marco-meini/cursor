## Goal
Model: GPT-5 (desired)
Parameters (required – provided as ordered lines, each separated by a newline):
1. TARGET_NAME → becomes `${targetCode}` in the template; fully qualified target to test (Class or Class.method). Example: `UsersModel.getActiveUsers` or `AuthController.__login`.
2. TEST_FILE_PATH → becomes `${testFile}`; repo-relative path to the test file to create/update (must end with `.test.mjs`).
When invoking the prompt, supply the parameters in this order, one per line without prefixes, for example:
```
/test
TargetClassOrMethod
test/controllers/target.controller.test.mjs
app/controllers/target.controller.mjs
```

Output: Markdown fenced javascript code for the test content (or delta additions) only.

Audience: project contributors / maintainers.
Given ${targetCode}, ${sourceFile} (if provided) and ${testFile} produce (or update) a Mocha-style test suite (ESM `.mjs`) aligned with project patterns (see existing tests under `test/`). Focus on full logical branch coverage, validation, and error propagation.

## Context Linking
If ${sourceFile} is supplied:
* Output (before the code block) two plain lines (no clickable links to avoid validation issues):
	* `Implementation: ${sourceFile}`
	* `Test File: ${testFile}`
If it is not supplied, skip these lines; do not guess paths. Relative imports inside code still inferred or derived from provided source path.

## Golden Rules
1. Use native ES modules: `import ... from '...'`.
2. Each CLASS gets a top-level `describe('<ClassName>')`.
3. Each METHOD of that class under test gets its own nested `describe('<methodName>')` block.
4. Organize inside each method block: optional context `describe('Success')` / `describe('Error')` if branches > 2; else individual `it` cases.
5. Use `sinon` for stubs/spies; prefer `sinon.assert.calledWith` over manual arg inspection.
6. No chai-as-promised; use try/catch for async error assertions.
7. Stub prototype methods when the code instantiates a class internally (see guidance in legacy instructions).
8. Never import production secrets or mutate real environment configs.
9. Do NOT reference `test/test-instructions.md` (file will be removed). Integrate its logic here.
10. Do not test raw SQL strings; only assert that query method was called with objects containing expected shape / replacements.
11. ALWAYS apply changes directly to ${testFile} in the workspace (create/update the file) rather than only suggesting edits in chat. The chat output must mirror the actual saved file content. (IT: L'agent deve sempre modificare direttamente il file di test e non solo suggerire il codice in chat.)
12. NEVER modify the production implementation file (`${sourceFile}`) while generating tests. If additional seams are needed for testability, prefer: (a) local HTTP server / fixtures to simulate external services, (b) wrapper helper modules placed under `test/` only, (c) dynamic import patterns. Do not introduce constructor params or change signatures in source just for tests.
13. After writing tests to ${testFile}, ALWAYS run them using the test runner and iterate until ALL tests pass. Use `npm test -- ${testFile}` to run the specific test file. Fix any failing tests by adjusting the test code (NOT the production code) until the entire suite is green. (IT: Dopo aver scritto i test, eseguirli SEMPRE e iterare fino a quando tutti i test non passano. Correggere eventuali test falliti modificando SOLO il codice di test, non il codice di produzione.)
13. Do not attempt to stub immutable ES Module default exports (e.g. `import fetch from 'node-fetch'`). Sinon cannot stub ESM bindings directly. Instead use one of:
	* Spin up a lightweight HTTP server in the test (Node `http.createServer`) and let the real fetch/client call it.
	* Create a tiny indirection module in `test/fixtures/` that re-exports the dependency; import that indirection in the test subject only if such pattern already exists (do NOT edit prod code to add it).
	* For network error branches, close the server before the request or point to an unused localhost port to trigger connection refusal.
14. When encrypt/decrypt or similar static utility calls occur, it's acceptable to stub only those static methods (e.g., `Crypt.encryptAES`) but NEVER alter the underlying class file.
15. If a required branch is impossible to reach without altering production code (rare), add a `// TODO: unreachable branch without code change` comment rather than changing production.
16. For classes instantiated within methods (e.g., `new NotificationsManager(this.env)`), use the appropriate stubbing pattern:
	* NotificationsManager: use `sinon.createStubInstance()` + `.callsFake()` pattern (see section 4) with real config
	* Other external service classes: provide minimal config structure to prevent constructor failures
	* For complex dependencies like PubSubV2, the real config with `sinon.createStubInstance()` pattern handles it automatically
	* DO NOT mock `env.config` partially - use `import config from '../../config/config.mjs'` instead

## Coverage Expectations
Cover: happy path, each conditional branch, invalid parameters, edge values (0, empty array, null, undefined), error propagation (`next(error)` in controllers, thrown errors in models/libs). Validate:
* HTTP status codes & response methods (`send`, `sendStatus`, `json`, `cookie`, `clearCookie`).
* Sequence & arguments of model / DB operations.
* Side-effects: cookie set/cleared, session manager calls, grants updated, transformation of data objects.

## Folder-Specific Directives

### 1. Controllers (`test/controllers/*.test.mjs`)
Patterns (see `auth.controller.test.mjs`):
* Mock `env` object with: `config.sessionCookie`, `pgModels`, `session`, external services (getStream, etc.).
* For NotificationsManager dependencies, use the pattern from section 4 (createStubInstance with real config)
* For other external services, provide minimal required config properties
* Always stub `env.session.checkAuthentication()` to return a pass-through middleware when needed.
* For methods that set cookies: assert `response.cookie` args (including presence/absence of `expires`).
* For protected endpoints: assert proper status codes when prerequisites fail.
* Error path: ensure `next(error)` called once with the original error instance.
* Avoid leaking implementation details: only assert externally observable behavior (responses + env calls).

Example (controller method error branch snippet):
```js
it('should propagate DB error', async () => {
	const dbError = new Error('Database failed');
	env.pgModels.users.getUserByUsername.rejects(dbError);
	request.body = { username: 'u', password: 'p', persistent: false };
	await controller.__login(request, response, next);
	sinon.assert.calledWith(next, dbError);
	sinon.assert.notCalled(response.send); // ensure no premature response
});
```

Example (controller method with external service):
```js
beforeEach(() => {
	// For NotificationsManager, use createStubInstance pattern (see section 4)
	mockNotificationManager = sinon.createStubInstance(NotificationsManager);
	sinon.stub(NotificationsManager.prototype, 'store').callsFake(mockNotificationManager.store);
	sinon.stub(NotificationsManager.prototype, 'publish').callsFake(mockNotificationManager.publish);
});
afterEach(() => {
	sinon.restore(); // Restores all stubs
});
```

### 2. Lib Utilities (`test/lib/*.test.mjs`)
Patterns (see `utils.test.mjs`):
* Use Node `assert` for pure functions; keep tests exhaustive yet concise.
* Cover boundary: empty input arrays, null/undefined, formatting edge cases.
* For validators: valid value, common invalid formats, null, undefined, empty, malformed.
* No external stubs unless a function internally calls time or randomness—then stub with `sinon.useFakeTimers()` when needed.

Example (utility edge case):
```js
it('should return empty string when all values falsy', () => {
	assert.strictEqual(String.joinNotEmptyValues('-', '', null, undefined), '');
});
```

### 3. Postgres Models (`test/pg-models/*.test.mjs`)
Patterns (see `users.model.test.mjs`):
* Create a mock connection object with stubbed methods: `query`, `queryReturnFirst`, `insert`, `updateByKey`, `startTransaction`, `commit`, `rollback` if used.
* For each method: assert correct `replacements` array; avoid asserting entire SQL string – use `sinon.match({ sql: sinon.match(/select/), replacements: [...] })`.
* Simulate different DB responses: `{ rows: [...] }`, `{ rows: [] }`, `null`, rejection.
* Test transformation of DB record into returned domain structure.
* Error path must bubble the same Error instance.
* For transactional flows: assert ordering `startTransaction` -> updates/inserts -> `commit`; error branch triggers `rollback`.

Example (model method happy path):
```js
it('should return user grants', async () => {
	const grants = [{ id_gr: 1, code_gr: 'ADMIN' }];
	connection.query.resolves({ rows: grants });
	const result = await usersModel.getUserGrants(10);
	expect(result).to.deep.equal(grants);
	sinon.assert.calledWith(connection.query, sinon.match({ replacements: [10] }));
});
```

### 4. Notifications / Derived Domain Logic (`test/lib/*-notifications.test.mjs`)
Patterns (see `groups-notifications.test.mjs`, `users-notifications.test.mjs`):
* Import the real `config` instead of mocking it: `import config from '../../config/config.mjs'`
* Use `sinon.createStubInstance(NotificationsManager)` to create a mock instance
* Stub prototype methods with `.callsFake()` to link to the mock instance:
  ```js
  mockNotificationManager = sinon.createStubInstance(NotificationsManager);
  sinon.stub(NotificationsManager.prototype, 'store').callsFake(mockNotificationManager.store);
  sinon.stub(NotificationsManager.prototype, 'publish').callsFake(mockNotificationManager.publish);
  ```
* Always set up stubs BEFORE instantiating the class under test
* Assert payload structure & invocation count using `mockNotificationManager.store` and `mockNotificationManager.publish`
* Include test for failure in underlying store and verify error propagation or graceful degrade
* For classes extending `TopicNotifications`, stub `customerUsers()` if needed

Example imports for notifications tests:
```js
import sinon from 'sinon';
import { expect } from 'chai';
import { MailOfficeNotifications } from '../../app/lib/notifications/mailoffice-notifications.mjs';
import { NotificationsManager } from '../../app/lib/notifications/notifications-manager.mjs';
import { Topics } from '../../app/model/mongo/notifications.collection.mjs';
import config from '../../config/config.mjs';
```

Example setup:
```js
beforeEach(() => {
  mockEnv = {
    pgConnection: { query: sinon.stub(), queryReturnFirst: sinon.stub() },
    logger: { error: sinon.stub(), warn: sinon.stub() },
    mongoModels: { notifications: { addDocument: sinon.stub() } },
    config: config  // Use real config, not mock
  };
  mockSession = { idCustomer: 1, idUser: 1 };
  
  // Create stub instance BEFORE instantiating the class
  mockNotificationManager = sinon.createStubInstance(NotificationsManager);
  sinon.stub(NotificationsManager.prototype, 'store').callsFake(mockNotificationManager.store);
  sinon.stub(NotificationsManager.prototype, 'publish').callsFake(mockNotificationManager.publish);
  
  notifications = new MyNotifications(mockEnv, mockSession);
});
```

### 5. External Service Classes (Bridge, Getstream, etc.)
When testing methods that instantiate other external service classes (non-NotificationsManager):
* For classes with complex dependencies (Google Cloud, external APIs), use `sinon.createStubInstance()` pattern
* Always restore stubs in `afterEach`: `sinon.restore()` (restores all stubs at once)
* If the constructor itself requires validation that cannot be stubbed, consider:
  - Using the real config: `import config from '../../config/config.mjs'`
  - Creating a wrapper/fixture in `test/` directory
  - Testing only the publicly observable behavior without direct constructor calls

### 6. Export / Batch Utilities (`punchings-exports.test.mjs` etc.)
* If file writes or streams would occur, stub fs or stream constructors.
* Validate produced CSV / lines structure (sample subset, not full huge strings).
* Include performance edge case: large input array (simulate with 1000 items) focusing on not throwing and calling transformation once per item.

## Assertion Strategy
Use:
* `sinon.assert.calledOnce(stub)`
* `sinon.assert.calledWith(stub, expectedArgs...)`
* `sinon.match` for partial object / regex match of SQL.
* For arrays order-sensitive transformations, assert deep equality.
* For date fields: use `sinon.match.date` or assert `instanceof Date`.

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
Controllers:
```js
import sinon from 'sinon';
import { HttpResponseStatus } from 'common-mjs';
import { AuthController } from '../../app/controllers/auth.controller.mjs';
// If testing methods with NotificationsManager:
// import { NotificationsManager } from '../../app/lib/notifications/notifications-manager.mjs';
```
Models:
```js
import sinon from 'sinon';
import { expect } from 'chai';
import { UsersModel } from '../../app/model/postgres/users.model.mjs';
```
Utils:
```js
import assert from 'assert';
import { String } from '../../app/lib/utils.mjs';
```
Notifications (see section 4 for full pattern):
```js
import sinon from 'sinon';
import { expect } from 'chai';
import { MailOfficeNotifications } from '../../app/lib/notifications/mailoffice-notifications.mjs';
import { NotificationsManager } from '../../app/lib/notifications/notifications-manager.mjs';
import { Topics } from '../../app/model/mongo/notifications.collection.mjs';
import config from '../../config/config.mjs';
```

## Output Requirements
Provide only the test file content (no extra narrative) inside a fenced ```javascript block. If updating, show only the new or changed test blocks preceded by a brief comment `// Added tests for <method>`.

## Parameter Mapping
* ${targetCode} determines which class/method(s) to focus on. If only a method is supplied (Class.method) generate tests just for that method but still include/enforce the class-level + method-level describe hierarchy.
* ${testFile} determines relative import depth (`../../` etc.). Derive correct relative paths automatically.
* ${sourceFile} if provided should be used to compute the relative import path instead of inference. Validate extension `.mjs`; if missing, append `.mjs` in the import only (do not modify the link text).

## Quality Gates Before Finish (Self-Check)
1. All new describe blocks follow pattern.
2. No direct references to removed instructions file.
3. Uses sinon assertions consistently.
4. No hardcoded secrets / environment leakage.
5. Edge cases addressed.

## Example Invocation Scenarios
1. ${targetCode}=AuthController.__login, ${testFile}=test/controllers/auth.controller.test.mjs, ${sourceFile}=app/controllers/auth.controller.mjs -> Add missing edge case (e.g., persistent cookie expiration) if absent.
2. ${targetCode}=UsersModel.getUserGrants, ${testFile}=test/pg-models/users.model.test.mjs, ${sourceFile}=app/model/postgres/users.model.mjs -> Ensure empty array branch exists; if already present, create error propagation test if missing.
3. ${targetCode}=String.joinNotEmptyValues, ${testFile}=test/lib/utils.test.mjs, ${sourceFile}=app/lib/utils.mjs -> Add tests for unusual separators or all-falsy values if missing.

## If Information Is Ambiguous
Insert a `// TODO:` comment with a concise note (max 60 chars) rather than guessing a behavior not inferable from existing code.

Return only the test code output per instructions—no extra commentary beyond mandated added-block comments.
