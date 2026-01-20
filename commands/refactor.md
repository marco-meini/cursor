Refactor a legacy yn-be controller to yn-be-v2.

Inputs:
- ${newFile}: path to new v2 controller (e.g., app/controllers/addressbook.controller.mjs)
- ${legacyFile}: path to legacy controller in yn-be (e.g., src/controllers/addressbook-controller.ts)
- ${method}: (optional) specific method/API to implement (e.g., "getById", "POST /users/:id"). If provided, implement only this method; otherwise implement the entire class

Goals:
- Port routes and logic from ${legacyFile} to ${newFile}
- If ${method} is provided, implement only that specific method/API; otherwise port all routes and logic
- Use JavaScript (ESM), PgClientManager (env.pgConnection), and shared utils
- Enforce ExpressMiddlewares for pagination and path params

Requirements:
1) Controller skeleton
- Extend Abstract_Controller; call super(env, "<scope>")
- Register routes in constructor: this.router.<verb>(path, middlewares..., this.__handler.bind(this))
- Always add ExpressMiddlewares:
  - validIntegerPathParam('<param>') for numeric :params
  - parsePaginationParams(required=true|false) for list endpoints
  - validIntegerQueryParam('<param>', required?) when needed

2) Handlers
- Each handler: try/catch → validate → call env.pgConnection / env.pgModels → shape response
- Read parsed values from res.locals (e.g., res.locals.id, res.locals.limit, res.locals.offset)
- Use HttpResponseStatus constants (no numeric literals)
- Transactions: const tx = await env.pgConnection.startTransaction(); commit/rollback explicitly
- **Validation best practice:** Always use `_.isNil(variable)` instead of `!variable` for null/undefined checks to be explicit and avoid falsy value pitfalls (e.g., `if (_.isNil(data.text) || _.isNil(data.id))` instead of `if (!data.text || !data.id)`)
- **Model methods best practice:** Apply the same `_.isNil()` pattern in model methods as well (e.g., `if (_.isNil(groupIds) || groupIds.length === 0)` instead of `if (!groupIds || groupIds.length === 0)`)

3) SQL & filtering
- Replace Sequelize with SQL via env.pgConnection.{query, queryReturnFirst, queryPaged}
- Preserve legacy behavior (filters, sorting, response shape)
- For lists: deterministic ordering and envelope { total, data }
- **Read-only queries**: Always use `isSlave: true` for COUNT queries and read-only SELECT operations
  - Pattern: `await env.pgConnection.queryReturnFirst({ sql, replacements, isSlave: true })`
  - Reduces load on master database
  - Never use `isSlave: true` for write operations (INSERT, UPDATE, DELETE)
- **Avoid duplicate queries**: Before writing SQL queries, check if similar queries already exist in the controller
  - If the same query (or very similar) appears multiple times, extract it to a model method
  - Create the method in the appropriate model class (extending `Abstract_PgModel`)
  - Register the model in `app/model/postgres/pg-models.mjs` if it's a new model
  - Use `this.env.pgModels.<model>.<method>()` instead of direct SQL in controllers
  - Example: If querying customer users appears in multiple places, create `CustomersModel.getActiveUserIds(customerId)` and use it everywhere
- **CRITICAL: PgFilter method mapping from Sequelize Filter**
  - PgFilter (common-mjs) has DIFFERENT method signatures than Sequelize Filter
  - Available PgFilter methods:
    - `addEqual(column, value)` - equals condition
    - `addIn(column, array)` - IN condition
    - `addCondition(sqlCondition)` - raw SQL condition (use getParameterPlaceHolder for values)
    - **CRITICAL: Always use `getParameterPlaceHolder(value)` for custom SQL conditions**
      - Never manually construct placeholders like `$${paramIndex}` or `$1`, `$2`, etc.
      - `getParameterPlaceHolder()` automatically adds value to `replacements` and returns correct placeholder
      - After calling `getParameterPlaceHolder()`, update replacements: `replacements = [...filter.replacements]`
      - Example:
        ```javascript
        // ❌ WRONG
        sql += ` AND field = $${paramIndex}`;
        replacements.push(value);
        paramIndex++;
        
        // ✅ CORRECT
        const placeholder = filter.getParameterPlaceHolder(value);
        sql += ` AND field = ${placeholder}`;
        replacements = [...filter.replacements];
        ```
    - `addSearchInString(column, searchTerm)` - text search
    - `addGreaterThan(column, value, orEqual = false)` - greater than (>), or >= if orEqual=true
    - `addLessThan(column, value, orEqual = false)` - less than (<), or <= if orEqual=true
    - `addPagination(limit, offset)` - add LIMIT/OFFSET
    - `getWhere()` - get WHERE clause string
    - `getPagination()` - get LIMIT/OFFSET string
    - `getParameterPlaceHolder(value)` - get parameter placeholder ($1, $2, etc.)
  - **Mapping from Sequelize Filter to PgFilter:**
    - `filter.addGreaterEqualTo(col, val, type)` → `filter.addGreaterThan(col, val, true)` (third param `orEqual=true` makes it `>=`)
    - `filter.addLessEqualTo(col, val, type)` → `filter.addLessThan(col, val, true)` (third param `orEqual=true` makes it `<=`)
    - `filter.addGreaterThan(col, val, type)` → `filter.addGreaterThan(col, val, false)` (strict `>`, orEqual defaults to false)
    - `filter.addLessThan(col, val, type)` → `filter.addLessThan(col, val, false)` (strict `<`, orEqual defaults to false)
  - **IMPORTANT:** The third parameter in PgFilter's `addGreaterThan`/`addLessThan` is `orEqual` (boolean), NOT the Sequelize type. When `true`, it includes equality (>= or <=). When `false` (default), it's strict (> or <).
  - Example:
    ```javascript
    // Legacy (Sequelize Filter):
    filter.addGreaterEqualTo('insert_time', 1234567890, NUMBER);
    filter.addLessEqualTo('insert_time', 1234567999, NUMBER);
    
    // Correct (PgFilter):
    filter.addGreaterThan('insert_time', 1234567890, true);  // >= (orEqual=true)
    filter.addLessThan('insert_time', 1234567999, true);    // <= (orEqual=true)
    ```

4) AuthZ
- Mirror legacy grants/ownership checks using request.session.grants, idCustomer, idUser

5) Output
- Overwrite ${newFile}; ensure imports resolve inside yn-be-v2
- No TS/Sequelize remnants; ES modules only; .mjs extension

6) Code completeness
- If ${method} is provided: implement ONLY that specific method/API from ${legacyFile}
- If ${method} is NOT provided: ALL code from ${legacyFile} MUST be replicated in ${newFile}
- Do NOT skip or omit any logic, routes, or functionality (within the scope defined by ${method})
- If you encounter calls to unimplemented classes/modules or code that cannot be directly ported:
  - Keep the code structure in place
  - Add a TODO comment explaining what needs to be implemented
  - Example: // TODO: Implement MongoModel.findById() or migrate to PG equivalent
- Never silently drop functionality; make incomplete parts explicit with TODOs

References:
- app/controllers/fax.controller.mjs (pagination & SQL patterns)
- app/lib/express-middlewares.mjs (param parsing)
- .github/prompts/refactor.prompt.md (general playbook)

