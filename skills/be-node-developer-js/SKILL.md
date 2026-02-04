---
name: backend-nodejs-best-practices
description: Best practices, coding conventions, and patterns for Node.js backend projects. Use this skill when writing code, creating tests, or implementing new features to ensure consistency across all backend projects.
---

# Node.js Backend - Best Practices & Skills

This skill provides comprehensive guidance on technical skills, patterns, and best practices required to work effectively on Node.js backend projects across the organization.

## When to Use

- Use this skill when writing new controllers, models, or utilities
- Use this skill when creating or updating tests
- Use this skill when implementing new features to ensure consistency
- Use this skill when reviewing code to verify adherence to project standards
- Use this skill when refactoring existing code

## Core Technologies

### Runtime & Language
- **Node.js**: ES modules (`.mjs` extension), native ESM syntax
- **JavaScript**: Modern ES6+ features, async/await patterns
- **No CommonJS**: Do not use `require` or `module.exports`

### Testing Framework
- **Mocha**: Test runner for unit and integration tests
- **Chai**: Assertion library (`expect`, `assert`)
- **Sinon**: Stubs, spies, and mocks for test isolation
- **Test Structure**: Top-level `describe` per class, nested `describe` per method, `it` blocks for test cases

### Web Framework
- **Express.js**: HTTP server and routing
- **Middleware Pattern**: Authentication, validation, error handling

## Architecture Patterns

### Project Structure
Typical structure for Node.js backend projects:
```
app/
  controllers/   # HTTP layer (routing + minimal orchestration)
  lib/           # Pure/domain utilities (stateless where possible)
  model/         # Data access (Postgres / Mongo wrappers)
  cronie/        # Scheduled / batch jobs (if applicable)
config/          # Environment-specific configuration
_db/             # SQL alignment & migration scripts (if applicable)
docs/            # OpenAPI fragments + bundling assets (if applicable)
test/            # Test files mirroring source structure
```
Note: Some directories may not be present in all projects; adapt structure to project needs.

### Controller Pattern
- Use base controller class pattern (e.g., `Abstract_Controller`) when available
- Register routes in constructor
- Bind handlers: `this.__method.bind(this)`
- Private methods prefixed with `__` (double underscore)
- Input validation → domain/model calls → response shaping
- Always wrap async logic in try/catch, delegate errors to `next(error)`

### Data Layer
- **PostgreSQL**: Access via connection manager (e.g., `env.pgConnection`) and model layer (e.g., `env.pgModels`)
- **MongoDB**: Access via client manager (e.g., `env.mongoClient`) and model layer (e.g., `env.mongoModels`)
- **Redis**: Session management and caching (when applicable)
- **Parameterized Queries**: Always use parameterized queries, never string concatenation
- **SQL Migrations**: Store in `_db/<YYYYMM>_<FeatureName>/` folders (when applicable)

## Code Style & Conventions

### Formatting
- **Indentation**: 2 spaces, no tabs
- **Strings**: Single quotes unless template literals required
- **Imports**: Absolute package names first, then relative paths
- **Variables**: `const` for immutable bindings, `let` for reassignable, never `var`

### Naming Conventions
- **Files**: kebab-case for controllers (`auth.controller.mjs`)
- **Classes**: PascalCase (`AuthController`, `DateUtils`)
- **Private Methods**: Double underscore prefix (`__login`)
- **Constants**: UPPER_SNAKE_CASE (`DEFAULT_LIMIT`)
- **Config Keys**: lowerCamelCase

### Code Organization
- Early returns for validation & error conditions
- Keep functions cohesive and small
- Extract reusable helpers to `app/lib/`
- Avoid deep nesting

## Error Handling

### Error Patterns
- Use `HttpResponseStatus` constants, never hardcode numeric codes
- Create structured errors with `.status` and optional `.errors` array
- Validation failures: `error.status = HttpResponseStatus.MISSING_PARAMS`
- Never expose stack traces or raw database errors in responses
- Always propagate errors via `next(error)`, never swallow them

### Error Object Shape
```javascript
const error = new Error('Validation failed');
error.status = HttpResponseStatus.MISSING_PARAMS;
error.errors = [
  { message: 'username is required' },
  { message: 'password must contain at least 8 chars' }
];
throw error;
```

## HTTP Responses

- Use `HttpResponseStatus` constants
- Empty 200: `response.send()`
- No content: `response.sendStatus(HttpResponseStatus.NO_CONTENT)`
- JSON responses: `response.json(data)`
- Prefer deterministic ordering in list queries

## Validation

- Reuse validators from `app/lib/utils.mjs`
- Validate early at controller entry
- Respond with `MISSING_PARAMS` if required fields absent/malformed
- Add new validators to `app/lib/utils.mjs` if generic

## Async & Promises

- Use `async/await` syntax
- Avoid mixing with raw `.then()` chains
- Wrap awaited blocks in try/catch at controller boundaries
- Use `Promise.all` for parallel operations when appropriate

## Logging

- Use `this.env.logger` or `env.logger`
- Levels: `error` (failures), `warn` (unexpected but tolerated), `info` (notable events), `debug` (verbose)
- Never log sensitive information (passwords, tokens, private keys)
- Pattern: `logger.error(context, error.stack || error.message)`

## Security Practices

- Never log raw JWTs (log presence of token or user id)
- Hash & compare passwords only in model/service layer
- Validate and sanitize all user-provided inputs
- Use parameterized queries exclusively
- Never hardcode secrets in source code
- Centralize secrets in environment variables or secret manager

## Database Patterns

### PostgreSQL
- All calls through `env.pgModels.<model>` methods
- Method naming: verbs (`getUserByUsername`, `checkPassword`)
- **For UPDATE operations**: Always use `updateByKey` instead of raw SQL UPDATE queries
  - Pattern: `await env.pgConnection.updateByKey(object, fieldsToUpdate, keyFields, tableName, transaction?)`
  - Example:
    ```javascript
    const recordToUpdate = { id_vd: room.id_vd, name_vd: data.name, data_vd: JSON.stringify(data.authorization) };
    await env.pgConnection.updateByKey(recordToUpdate, ['name_vd', 'data_vd'], ['id_vd'], 'videocalls_vd', transaction);
    ```
- **Read-only queries (SELECT, COUNT)**: Use `isSlave: true` to route queries to read replicas
  - Reduces load on master database
  - Always use for COUNT queries and read-only SELECT operations
  - Pattern: `await env.pgConnection.queryReturnFirst({ sql, replacements, isSlave: true })`
  - Example:
    ```javascript
    const countResult = await this.env.pgConnection.queryReturnFirst({
      sql: countSql,
      replacements: filter.replacements,
      isSlave: true
    });
    ```
  - **Never use `isSlave: true` for**: INSERT, UPDATE, DELETE, or any write operations
- **Avoid duplicate queries**: If the same SQL query (or very similar) appears in multiple places, extract it to a model method
  - Check for duplicate queries before writing new ones
  - Create reusable methods in the appropriate model class (extending `Abstract_PgModel`)
  - Register the model in `app/model/postgres/pg-models.mjs` if it doesn't exist
  - Example: If querying for customer users appears multiple times, create `CustomersModel.getActiveUserIds(customerId)`
  - Benefits: DRY principle, easier maintenance, better testability
- SQL changes in `_db/<YYYYMM>_<FeatureName>/` folders
- Use `prerelease.sql` for schema modifications
- Use `alignment.sql` for data corrections
- Provide idempotent scripts (guard with `IF NOT EXISTS`)

### Data Sanitization
- Avoid leaking raw model objects with internal fields
- Sanitize in controller before responding
- Remove sensitive fields like `password_us`, internal flags

## External Services

### Integration Patterns
- Wrap each external integration in dedicated environment service
- Do not inline credentials or client creation in controllers
- On failures: log and proceed gracefully if not critical
- Document any degraded capability

### External Services Integration
Common services that may be integrated (project-specific):
- **Redis**: Session management and caching
- **Cloud Storage**: File storage (AWS S3, Google Cloud Storage, etc.)
- **Email Services**: Email delivery (SparkPost, SendGrid, SES, etc.)
- **Message Queues**: Async processing (RabbitMQ, Redis Pub/Sub, etc.)
- **Third-party APIs**: Chat, video conferencing, payment gateways, etc.
- Always wrap external service calls in try/catch with proper error handling

## Testing Skills

### Test Structure
```javascript
describe('ClassName', () => {
  describe('methodName', () => {
    describe('Success', () => {
      it('should <expected behavior>', async () => {
        // Arrange
        // Act
        // Assert
      });
    });
    describe('Error', () => {
      it('should propagate database errors', async () => {
        // Error test
      });
    });
  });
});
```

### Testing Patterns
- Use `sinon` for stubs/spies/mocks
- Prefer `sinon.assert.calledWith` over manual argument inspection
- No `chai-as-promised`; use try/catch for async error assertions
- Stub prototype methods when code instantiates classes internally
- Never import production secrets or mutate real environment configs
- Do not test raw SQL strings; assert query method calls with expected shape/replacements
- Test all branches: happy path, conditional logic, error propagation

### Test Coverage Requirements
- Happy path
- Each branch of conditional logic
- Error propagation (ensuring `next` called with error)
- Edge cases: empty, null, invalid format, boundary values
- Side effects: status codes, response method calls, service calls, argument ordering

## Configuration Management

- Do not read `process.env` directly in controllers
- Centralize in Environment/config layer
- Update all environment files when adding config entries
- Document defaults in `config/config.mjs`

## Documentation

### Code Comments
- Use JSDoc for public class methods and complex private handlers
- Keep comments in English
- State the WHY for non-trivial algorithms, not just the WHAT

### API Documentation
- Document all API endpoints (OpenAPI/Swagger, YAML fragments, or project-specific format)
- Ensure response codes and required parameters match controller behavior
- Keep documentation in sync with implementation

## Batch Jobs & Cron

- Organize batch logic in dedicated directories (e.g., `app/cronie/batch/`, `app/jobs/`, etc.)
- Use clear file naming conventions
- Orchestrate entry points appropriately (e.g., `app/cronie/main-cronie.mjs`, cron configuration, etc.)
- Ensure idempotency where tasks may be retried
- Log start/end + summary metrics (counts, durations) at `info` level

## Internationalization

- Centralize user-facing message templates (e.g., `assets/messages.mjs`, `locales/`, etc.)
- Keep placeholders explicit (e.g., `${userName}`)
- Document placeholders
- Use project-specific i18n library if applicable

## Performance & Reliability

- Avoid unnecessary awaits; use `Promise.all` for parallel operations
- Implement retries with backoff for batch/cron jobs
- Configure limits for streaming/large payload uploads via `bodyParserLimit`
- Prefer deterministic ordering in queries to avoid flaky tests

## Git Workflow

### Branch Naming
- `feature/<short-kebab>`
- `fix/<short-kebab>`
- `chore/<short-kebab>`
- `refactor/<short-kebab>`

### Commit Messages
- Imperative present tense (`Add user lock check`)
- Include scope if useful: `controller(auth): ...`

### Pull Requests
- Keep PRs small & single-topic (< ~400 lines diff preferred, excluding tests)
- Before review: builds locally, tests pass, endpoints documented, no secrets exposed

## Dependency Management

- Prefer built-in or existing project utilities before adding new libraries
- Justify any new dependency in PR description (benefit, size, maintenance risk)
- Avoid transitive duplication (e.g., date libraries – already using `moment`)

## Adding New Controllers Checklist

1. Create controller file following project conventions (e.g., `app/controllers/<name>.controller.mjs`)
2. Extend base controller class if available (e.g., `Abstract_Controller`)
3. Define route via constructor or configuration
4. Register routes inside constructor
5. Implement handlers with validation + model calls
6. Export class & register instance in main app file with mounting path
7. Add tests under `test/controllers/` replicating structure
8. Update API documentation
9. Ensure error paths use HTTP status constants (never hardcode numeric codes)

## Utility Classes

- Group related concerns (string ops, dates, validation) into cohesive classes
- Avoid state; all methods static unless stateful caching required
- When adding new static method: include JSDoc, edge case notes, and at least one test verifying failure branch

## Common Libraries & Tools

### Core Dependencies
- `express`: Web framework
- `pg`: PostgreSQL client
- `mongodb`: MongoDB client
- `redis`: Redis client
- `stream-chat`: GetStream chat integration
- `lodash`: Utility functions
- `moment`: Date manipulation
- `handlebars`: Template engine
- `multer`: File upload handling
- `exceljs`: Excel file processing
- `csv-parse`: CSV parsing
- `soap`: SOAP client
- `node-fetch`: HTTP client

### Development Tools
- `mocha`: Test runner
- `chai`: Assertions
- `sinon`: Test doubles
- `nodemon`: Development server with auto-reload

## Key Concepts

### Environment Object
- Central dependency container: logger, session, config, external services
- Do not scatter creation logic
- Access via `this.env` in controllers

### Session Management
- Do not directly manipulate JWT/session except through `env.session.sessionManager`
- Use `env.session.checkAuthentication()` middleware
- Use `env.session.checkPermission()` for authorization

### PgFilter
- Use `PgFilter` from `common-mjs` for building dynamic SQL queries
- Add conditions: `where.addEqual()`, `where.addCondition()`
- Use `where.getWhere()` and `where.replacements` in queries
- **CRITICAL: Always use `getParameterPlaceHolder(value)` for custom SQL conditions**
  - Never manually construct parameter placeholders like `$${paramIndex}`
  - `getParameterPlaceHolder()` automatically adds the value to `replacements` array and returns the correct placeholder (`$1`, `$2`, etc.)
  - After calling `getParameterPlaceHolder()`, always update `replacements` array: `replacements = [...filter.replacements]`
  - Example:
    ```javascript
    // ❌ WRONG - Manual placeholder construction
    sql += ` AND field = $${paramIndex}`;
    replacements.push(value);
    paramIndex++;
    
    // ✅ CORRECT - Use getParameterPlaceHolder
    const placeholder = filter.getParameterPlaceHolder(value);
    sql += ` AND field = ${placeholder}`;
    replacements = [...filter.replacements];
    ```

## Instructions

When working on any Node.js backend project, follow these guidelines:

1. **Always use ES modules** – no CommonJS
2. **Test everything** – controllers, utilities, models
3. **Validate early** – at controller entry point
4. **Handle errors properly** – propagate via `next(error)`
5. **Use constants** – `HttpResponseStatus`, never hardcode
6. **Sanitize data** – remove sensitive fields before responding
7. **Parameterize queries** – never string concatenation
8. **Log appropriately** – never sensitive information
9. **Document APIs** – update YAML fragments
10. **Keep it simple** – small functions, early returns, clear naming

When creating tests:
- Mirror the source structure in `test/` directory
- Use the test structure pattern shown above
- Cover all branches and edge cases
- Use sinon for mocking and stubbing
- Never modify production code just for testability

When writing controllers:
- Use base controller pattern when available (e.g., extend `Abstract_Controller`)
- Register routes in constructor
- Use private methods with `__` prefix
- Validate input early
- Handle errors with try/catch and `next(error)`
- Use HTTP status constants (never hardcode numeric codes)

When working with databases:
- Use model layer when available (e.g., `env.pgModels`, `env.mongoModels`)
- Always use parameterized queries (never string concatenation)
- Store SQL migrations in appropriate directories (e.g., `_db/<YYYYMM>_<FeatureName>/`)
- Sanitize data before responding
- Use read replicas (`isSlave: true`) for read-only queries when available

