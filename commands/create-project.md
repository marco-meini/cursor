Create a new backend Node.js project structure in **TypeScript**.

Inputs:
- ${projectName}: The name of the project (will be used as folder name and package.json name)

Goals:
- Create the complete project structure with all necessary files and folders
- Generate skeleton files in **TypeScript** (`.ts`), ESM-compatible
- Set up TypeScript config, documentation, and test structure (Mocha + tsx)

Requirements:

1) Directory Structure
- Create the following directories:
  - **src/** (source code; no `app/`)
  - src/controllers/
  - src/cronie/batch/
  - src/lib/
  - src/model/mongo/
  - src/model/postgres/
  - config/
  - docs/
  - test/controllers/
  - test/lib/
  - test/model/postgres/ (or test/pg-models/)
  - .vscode/

2) Core Application Files

**TypeScript:** All source under **src/** with **.ts** extension. Use ESM (`"type": "module"`). Run with **tsx** (or compile with `tsc` and run `node dist/main.js`).

src/main.ts:
```typescript
import { App } from "./app.js";

const app = new App();
let port = app.env.config.defaultPort;
if (process.argv.length > 2) {
  port = parseInt(process.argv[2], 10);
}

(async () => {
  await app.env.initMongoModels();
  try {
    await app.env.session.sessionManager.connect();
  } catch (e) {
    app.env.logger.error(`Error starting redis client: ${e}`);
  }
  app.express.listen(port, () => {
    app.env.logger.info("### Server started on port", port.toString(), " ###");
  });
})();

process.on("beforeExit", async () => {
  await app.env.pgConnection.disconnect();
  app.env.mongoClient.disconnect();
});
```

src/app.ts:
```typescript
import { HttpResponseStatus } from "common-mjs";
import cookieParser from "cookie-parser";
import express, { json } from "express";
import { join } from "path";
import { Environment } from "./environment.js";
import { AuthController } from "./controllers/auth.controller.js";

class App {
  env: Environment;
  express: ReturnType<typeof express>;

  constructor() {
    this.env = new Environment();
    this.express = express();
    this.express.use(json({ limit: this.env.config.bodyParserLimit }));
    this.express.use(cookieParser());

    this.express.use("/healthcheck", (_request, response) => {
      response.send({ uptime: process.uptime() });
    });

    const auth = new AuthController(this.env);
    this.express.use(join(this.env.config.root, auth.route), auth.router);

    this.express.use(
      (error: any, request: import("common-mjs").SessionRequest, response: import("express").Response, next: import("express").NextFunction) => {
        if (!error) {
          next();
        } else if (error.message === "unexpected end of file" || error.message === "Could not find MIME for Buffer <null>") {
          response.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        } else if (error.name === "JsonWebTokenError") {
          this.env.logger.error(error.status, error.message);
          response.sendStatus(HttpResponseStatus.NOT_AUTHENTICATED);
        } else if (error.stack && error.stack.indexOf("MulterError: Unexpected field") >= 0) {
          response.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        } else {
          if (error.status && error.status !== HttpResponseStatus.SERVER_ERROR) {
            if (error.errors?.length) {
              const data = error.errors.map((item: { message: string }) => item.message);
              response.status(error.status).send(data);
            } else if (error.status === HttpResponseStatus.MISSING_PARAMS) {
              response.status(error.status).send(error.message);
            } else {
              this.env.logger.error(error.status, error.stack || error.message);
              response.sendStatus(error.status);
            }
          } else {
            const token = request.token ? "JWT: " + request.token : "";
            this.env.logger.error(`[${request.method}]`, request.url, error.stack || error.message, token);
            response.sendStatus(HttpResponseStatus.SERVER_ERROR);
          }
        }
      }
    );
  }
}

export { App };
```

src/environment.ts:
```typescript
import { Logger, Mailer, MongoClienManager, PgClientManager, SessionMiddleware } from "common-mjs";
import config from "../config/config.js";
import { PgModels } from "./model/postgres/pg-models.js";
import { MongoModels } from "./model/mongo/mongo-models.js";

class Environment {
  config: typeof config;
  logger: Logger;
  pgConnection: PgClientManager;
  pgModels: PgModels;
  session: SessionMiddleware;
  mongoClient: MongoClienManager;
  mongoModels: MongoModels;
  mailManager: Mailer;

  constructor() {
    this.config = config;
    this.logger = new Logger(this.config.logLevel);
    this.pgConnection = new PgClientManager(this.config.databases.postgres.master, this.logger.sql.bind(this.logger));
    this.pgModels = new PgModels(this.pgConnection);
    this.session = new SessionMiddleware(this.config.sessionCookie.name, this.config.sessionHeaderName, this.config.redisOptions, this.config.sessionExpiration);
    this.mongoClient = new MongoClienManager(this.config.databases.mongo.dbconfig, this.config.databases.mongo.options);
    this.mongoModels = new MongoModels(this.mongoClient);
    this.mailManager = new Mailer(this.config.sparkpost.api);
  }

  async initMongoModels(): Promise<void> {
    try {
      await this.mongoClient.connect();
      this.mongoModels.init();
    } catch (error) {
      this.logger.error(`Error starting mongodb client: ${error}`);
      throw error;
    }
  }
}

export { Environment };
```

src/controllers/abstract.controller.ts:
```typescript
import express from "express";
import { join } from "path";
import type { Environment } from "../environment.js";


abstract class Abstract_Controller {
  router: express.Router;
  env: Environment;
  route: string;
  protected filesPath?: string;

  constructor(env: Environment, route: string, folder?: string) {
    this.env = env;
    this.route = route;
    this.router = express.Router();
    if (folder && (env.config as any).fileserver?.root && (env.config as any).fileserver?.folders?.[folder]) {
      this.filesPath = join((env.config as any).fileserver.root, (env.config as any).fileserver.folders[folder]);
    }
  }
}

export { Abstract_Controller };
```

src/controllers/auth.controller.ts:
```typescript
import { HttpResponseStatus } from "common-mjs";
import type { Request, Response, NextFunction } from "express";
import type { SessionRequest } from "common-mjs";
import type { Environment } from "../environment.js";
import { Abstract_Controller } from "./abstract.controller.js";

/** Use real method names (no __ prefix). Tests call via (controller as any).login(...). */
class AuthController extends Abstract_Controller {
  constructor(env: Environment) {
    super(env, "auth");
    this.router.post("/login", this.login.bind(this));
    this.router.post("/logout", this.env.session.checkAuthentication(), this.logout.bind(this));
  }

  /** Logs in the user and generates a JWT token. */
  private async login(request: Request, response: Response, next: NextFunction): Promise<void> {
    // TODO: Implement login logic
    response.sendStatus(HttpResponseStatus.NOT_IMPLEMENTED);
  }

  /** Logs out the user. */
  private async logout(request: SessionRequest, response: Response, next: NextFunction): Promise<void> {
    // TODO: Implement logout logic
    response.sendStatus(HttpResponseStatus.NOT_IMPLEMENTED);
  }
}

export { AuthController };
```

src/cronie/main-cronie.ts:
```typescript
import { program } from "commander";
import { Environment } from "../environment.js";

(async () => {
  let env: Environment;
  try {
    env = new Environment();
    await env.mongoClient.connect();
  } catch (e) {
    console.error("ERROR WHILE CREATING ENV", e);
    process.exit(1);
  }

  program.parse(process.argv);
  process.setMaxListeners(0);
  // TODO: Add batch implementations here
})();
```

src/lib/utils.ts:
```typescript
import _ from "lodash";

export class String {
  static joinNotEmptyValues(separator: string, ...values: string[]): string {
    return values.filter(item => !!_.trimStart(_.trimEnd(item))).join(separator);
  }

  static stringToPositiveInteger(value: string): number {
    const num = Number(value);
    return _.isInteger(num) && num >= 0 ? num : NaN;
  }

  static stringToBoolean(value: string | boolean): boolean {
    if (!value) return false;
    if (typeof value === "boolean") return value;
    return String(value).toLowerCase() === "true";
  }

  static numberFormat(value: number, length: number, decimal?: number): string {
    let fmt = value + "";
    if (decimal != null) fmt = value.toFixed(decimal);
    while (fmt.length < length) fmt = "0" + fmt;
    return fmt;
  }

  static moneyFormat(val: number): string {
    const v = parseFloat(val.toString());
    if (isNaN(v)) return "";
    return this.numberFormat(v, 0, 2) + " €";
  }
}

export class Validators {
  static isEmail(email: string): boolean {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  static isNotEmptyString(value: unknown): boolean {
    return _.isString(value) && _.trim(value) !== "";
  }

  static isValidUrl(value: string): boolean {
    try {
      new URL(value);
      return true;
    } catch {
      return false;
    }
  }

  static validPassword(value: string | null | undefined): boolean {
    if (_.isNil(value) || _.isEmpty(value) || value.length < 8) return false;
    return /\d/.test(value) && /[a-z]/.test(value) && /[A-Z]/.test(value) && /\W|_/.test(value);
  }
}

export class GenericFunctions {
  static sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
```

src/lib/express-middlewares.ts:
```typescript
import { HttpResponseStatus } from "common-mjs";
import _ from "lodash";
import type { Request, Response, NextFunction } from "express";
import { String } from "./utils.js";

export class ExpressMiddlewares {
  /** Sets res.locals[param] with the parsed integer. */
  static validIntegerPathParam(param: string, status = HttpResponseStatus.MISSING_PARAMS) {
    return (req: Request, res: Response, next: NextFunction): void => {
      const paramValue = req.params[param];
      const value = parseInt(paramValue, 10);
      if (!paramValue || !/^\d+$/.test(paramValue) || !_.isInteger(value) || value !== parseFloat(paramValue)) {
        res.sendStatus(status);
        return;
      }
      res.locals[param] = value;
      next();
    };
  }

  static validIntegerQueryParam(param: string, required = false) {
    return (req: Request, res: Response, next: NextFunction): void => {
      const paramValue = req.query[param];
      const valued = !_.isNil(paramValue);
      const value = valued ? parseInt(String(paramValue), 10) : null;
      if ((required && !valued) || (valued && !/^\d+$/.test(String(paramValue)))) {
        res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        return;
      }
      if (valued && _.isInteger(value) && value === parseFloat(String(paramValue))) {
        res.locals[param] = value;
      }
      next();
    };
  }

  /** Sets res.locals.limit and res.locals.offset. Offset = (page - 1) * limit. */
  static parsePaginationParams(required = true) {
    return (req: Request, res: Response, next: NextFunction): void => {
      const queryParams = req.query as { page?: string; pageSize?: string };
      let limit: number | null;
      let offset: number;
      if (!_.isNil(queryParams.page) && !_.isNil(queryParams.pageSize)) {
        limit = String.stringToPositiveInteger(queryParams.pageSize);
        const page = String.stringToPositiveInteger(queryParams.page);
        offset = (page - 1) * limit;
      } else {
        if (required) {
          res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
          return;
        }
        limit = null;
        offset = 0;
      }
      if (limit === null || Number.isNaN(limit) || Number.isNaN(offset) || limit === 0) {
        res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        return;
      }
      res.locals.limit = limit;
      res.locals.offset = offset;
      next();
    };
  }

  static checkHeaderToken(headerName: string, expectedToken: string) {
    return (req: Request, res: Response, next: NextFunction): void => {
      const token = req.headers[headerName.toLowerCase()];
      if (_.isNil(token) || token !== expectedToken) {
        res.sendStatus(HttpResponseStatus.NOT_AUTHORIZED);
        return;
      }
      next();
    };
  }
}
```

src/model/mongo/mongo-models.ts:
```typescript
import type { MongoClienManager } from "common-mjs";
import { ExampleCollection } from "./example.collection.js";

export class MongoModels {
  private mongoClient: MongoClienManager;
  example!: ExampleCollection;

  constructor(mongoClient: MongoClienManager) {
    this.mongoClient = mongoClient;
  }

  init(): void {
    this.example = new ExampleCollection(this.mongoClient);
  }
}
```

src/model/mongo/example.collection.ts:
```typescript
import { Abstract_BaseCollection, type MongoClienManager } from "common-mjs";

class ExampleCollection extends Abstract_BaseCollection {
  constructor(dbMan: MongoClienManager) {
    super("example", dbMan);
  }
}

export { ExampleCollection };
```

src/model/postgres/pg-models.ts:
```typescript
import type { PgClientManager } from "common-mjs";
import { UsersModel } from "./users.model.js";

export class PgModels {
  users: UsersModel;

  constructor(connection: PgClientManager) {
    this.users = new UsersModel(connection);
  }
}
```

src/model/postgres/users.model.ts:
```typescript
import { Abstract_PgModel, type PgClientManager } from "common-mjs";

class UsersModel extends Abstract_PgModel {
  constructor(connection: PgClientManager) {
    super(connection);
  }
}

export { UsersModel };
```

3) Configuration Files

config/config.ts:
```typescript
const config = {
  databases: {
    postgres: {
      master: { database: "", user: "", password: "", host: "" },
      slave: { database: "", user: "", password: "", host: "" }
    },
    mongo: {
      dbconfig: "",
      options: { maxPoolSize: 5 }
    }
  },
  logLevel: 3,
  root: "/api/v2",
  defaultPort: 9804,
  bodyParserLimit: "50mb",
  redisOptions: { url: "", password: "" },
  sessionCookie: { name: "", options: { sameSite: "none" } },
  sessionHeaderName: "",
  sessionExpiration: { short: 7890000, long: 31536000 },
  sparkpost: { api: "" }
};

export default config;
```

4) Documentation Files

docs/index.html:
```html
<!doctype html>
<html lang="en">

<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Web API</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet"
    integrity="sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH" crossorigin="anonymous">
  <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <link href="sidebar.css" rel="stylesheet">
</head>

<body class="h-100">
  <main>
    <div class="d-flex flex-column flex-shrink-0 p-3 text-white bg-dark" style="width: 280px;">
      <span class="d-flex align-items-center mb-3 mb-md-0 me-md-auto text-white text-decoration-none">
        <span class="fs-5">Documentation</span>
      </span>
      <hr>
      <ul class="nav nav-pills flex-column mb-auto">
        <li class="nav-item">
          <a href="#/Authentication" class="nav-link" aria-current="page">
            Authentication
          </a>
        </li>
      </ul>
    </div>
    <div id="swagger-ui" class="w-100" style="overflow-y: scroll;"></div>
  </main>
  <script src="index.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"
    integrity="sha384-YvpcrYf0tY3lHB60NNkmXc5s9fDVZLESaAA55NDzOxhy9GkcIdslK1eN7N6jIeHz"
    crossorigin="anonymous"></script>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
</body>

</html>
```

docs/index.js:
```javascript
const routes = {
  '/': "auth.yaml",
  '/Authentication': "auth.yaml"
};

const handleRouting = () => {
  let fullPath = window.location.hash.slice(1) || '/';
  let path = '/' + fullPath.split('/')[1];
  bindSwaggerUi(routes[path]);
  updateActiveLink(path);
};

const updateActiveLink = (currentPath) => {
  const navLinks = document.querySelectorAll('.nav-link');
  navLinks.forEach(link => {
    const linkPath = link.getAttribute('href').slice(1);
    if (linkPath === currentPath) {
      link.classList.add('active');
    } else if (linkPath === '/Authentication' && currentPath === '/') {
      link.classList.add('active');
    } else {
      link.classList.remove('active');
    }
  });
};

const bindSwaggerUi = (yamlUrl) => {
  window.ui = SwaggerUIBundle({
    url: yamlUrl,
    dom_id: '#swagger-ui',
    deepLinking: true,
    presets: [
      SwaggerUIBundle.presets.apis,
      SwaggerUIBundle.SwaggerUIStandalonePreset
    ],
    plugins: [
      SwaggerUIBundle.plugins.DownloadUrl
    ],
  });
};

window.addEventListener('hashchange', handleRouting);
window.addEventListener('load', handleRouting);
```

docs/sidebar.css:
```css
body {
  min-height: 100vh;
  min-height: -webkit-fill-available;
}

html {
  height: -webkit-fill-available;
}

main {
  display: flex;
  flex-wrap: nowrap;
  height: 100vh;
  height: -webkit-fill-available;
  max-height: 100vh;
  overflow-x: auto;
  overflow-y: hidden;
}

.b-example-divider {
  flex-shrink: 0;
  width: 1.5rem;
  height: 100vh;
  background-color: rgba(0, 0, 0, .1);
  border: solid rgba(0, 0, 0, .15);
  border-width: 1px 0;
  box-shadow: inset 0 .5em 1.5em rgba(0, 0, 0, .1), inset 0 .125em .5em rgba(0, 0, 0, .15);
}

.bi {
  vertical-align: -.125em;
  pointer-events: none;
  fill: currentColor;
}

.dropdown-toggle { outline: 0; }

.nav-flush .nav-link {
  border-radius: 0;
}

.btn-toggle {
  display: inline-flex;
  align-items: center;
  padding: .25rem .5rem;
  font-weight: 600;
  color: rgba(0, 0, 0, .65);
  background-color: transparent;
  border: 0;
}
.btn-toggle:hover,
.btn-toggle:focus {
  color: rgba(0, 0, 0, .85);
  background-color: #d2f4ea;
}

.btn-toggle::before {
  width: 1.25em;
  line-height: 0;
  content: url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='rgba%280,0,0,.5%29' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M5 14l6-6-6-6'/%3e%3c/svg%3e");
  transition: transform .35s ease;
  transform-origin: .5em 50%;
}

.btn-toggle[aria-expanded="true"] {
  color: rgba(0, 0, 0, .85);
}
.btn-toggle[aria-expanded="true"]::before {
  transform: rotate(90deg);
}

.btn-toggle-nav a {
  display: inline-flex;
  padding: .1875rem .5rem;
  margin-top: .125rem;
  margin-left: 1.25rem;
  text-decoration: none;
}
.btn-toggle-nav a:hover,
.btn-toggle-nav a:focus {
  background-color: #d2f4ea;
}

.scrollarea {
  overflow-y: auto;
}

.fw-semibold { font-weight: 600; }
.lh-tight { line-height: 1.25; }
```

docs/auth.yaml:
```yaml
openapi: 3.0.3
info:
  title: Web API
  version: 1.0.0
servers:
  - url: http://localhost:9804/api/v2
    description: Local development server
security:
  - cookieAuth: []

tags:
  - name: Authentication
    description: Authentication API

paths:
  /auth/login:
    post:
      security: []
      tags:
        - Authentication
      summary: Login
      description: Log in the user and set the authentication cookie.
      requestBody:
        description: Credentials
        content:
          application/json:
            schema:
              type: object
              description: Authentication credentials.
              properties:
                username:
                  type: string
                  description: Username.
                password:
                  type: string
                  description: Password.
                persistent:
                  type: boolean
                  description: |
                    Optional. If true, keeps the session active for one year; otherwise it expires with the browser session.
              required:
                - username
                - password
        required: true
      responses:
        '200':
          description: Login successful
        '400':
          description: Bad Request
        '401':
          description: Unauthorized
        '403':
          description: Forbidden
  /auth/logout:
    post:
      tags:
        - Authentication
      summary: Logout
      description: Logs out the current authenticated user and invalidates its tokens.
      responses:
        '200':
          description: User logged out.
        '401':
          description: Unauthorized

components:
  securitySchemes:
    cookieAuth:
      type: apiKey
      in: cookie
      name: youneed-sid
```

5) Test Structure
- Create empty directories: test/controllers/, test/lib/, test/model/postgres/ (or test/pg-models/)
- No test files, just directory structure. Tests will be **.test.ts**; run with **`npm test`** (Mocha + **`--require tsx/cjs`**).

6) TypeScript Configuration

tsconfig.json:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": ".",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*.ts", "config/**/*.ts"],
  "exclude": ["node_modules", "dist", "test"]
}
```

7) Project Configuration Files

.gitignore:
```
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Directory for instrumented libs generated by jscoverage/JSCover
lib-cov

# Coverage directory used by tools like istanbul
coverage

# nyc test coverage
.nyc_output

# Grunt intermediate storage (http://gruntjs.com/creating-plugins#storing-task-files)
.grunt

# Bower dependency directory (https://bower.io/)
bower_components

# node-waf configuration
.lock-wscript

# Compiled binary addons (https://nodejs.org/api/addons.html)
build/Release

# Dependency directories
node_modules/
jspm_packages/

# Typescript v1 declaration files
typings/

# Npm
.npm
package-lock.json

# Optional eslint cache
.eslintcache

# Optional REPL history
.node_repl_history

# Output of 'npm pack'
*.tgz

# Yarn Integrity file
.yarn-integrity

# dotenv environment variables file
.env

# configurations
config/config.json
config/config.ts

# TypeScript
dist/
*.tsbuildinfo

# Visual Studio Code Settings
.vscode

# Files
fileserver
.DS_Store
src/.DS_Store
```

.dockerignore:
```
npm-debug.log
.cache
dev-dockerfile
node_modules
```

package.json:
```json
{
  "name": "${projectName}",
  "version": "1.0.0",
  "description": "Backend API",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "tsx src/main.ts",
    "start:dev": "tsx watch src/main.ts",
    "start-debug": "node --import tsx --inspect src/main.ts",
    "start-nodemon-debug": "nodemon --exec tsx --inspect src/main.ts",
    "test": "mocha 'test/**/*.test.ts' --require tsx/cjs",
    "test:all": "mocha 'test/**/*.test.ts' --require tsx/cjs",
    "test:watch": "mocha 'test/**/*.test.ts' --require tsx/cjs --watch"
  },
  "devDependencies": {
    "@types/chai": "^5.0.0",
    "@types/cookie-parser": "^1.4.7",
    "@types/express": "^4.17.21",
    "@types/lodash": "^4.17.10",
    "@types/node": "^22.0.0",
    "@types/sinon": "^17.0.3",
    "chai": "^5.1.1",
    "mocha": "^11.7.5",
    "sinon": "^21.0.1",
    "tsx": "^4.19.0",
    "typescript": "^5.6.0"
  },
  "dependencies": {
    "commander": "^12.0.0",
    "common-mjs": "git+ssh://common-mjs/ambrogio-dev/common-mjs#fe-refactor",
    "cookie-parser": "^1.4.6",
    "express": "^4.19.2",
    "lodash": "^4.17.21",
    "mongodb": "^6.8.0",
    "pg": "^8.12.0",
    "redis": "^4.7.0"
  }
}
```

.vscode/launch.json:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Launch Program",
      "runtimeExecutable": "npx",
      "runtimeArgs": ["tsx", "src/main.ts"],
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

README.md:
```markdown
# ${projectName}

TypeScript backend (Node.js, Express, ESM). Source under **src/**.

## Setup

1. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`

2. Configure the application:
   - Copy or adapt `config/config.ts` and set database and service credentials.

3. Start the server:
   \`\`\`bash
   npm start
   \`\`\`
   (runs with **tsx**; no build step required for development.)

## Development

- Build: `npm run build` (output in `dist/`)
- Start with watch: `npm run start:dev`
- Start with debug: `npm run start-debug`
- Run tests: `npm test` or `npm run test:all` (Mocha + tsx/cjs for `.test.ts` files)
```

Output:
- Create all files and directories in the current workspace root
- Use the write tool for each file
- All file paths should be relative to the workspace root (create the project structure directly in the current directory)

Important Notes:
- **TypeScript:** All source under **src/** with **.ts** extension. Use ESM (`"type": "module"`). Run with **tsx** (or compile with `tsc` and run from `dist/`).
- **Controller methods:** Use **private** method names **without** `__` (e.g. `login`, `logout`). Tests call them via `(controller as any).methodName(...)`.
- **Imports:** Use **.js** extension in import paths for ESM resolution (e.g. `from "./app.js"`); tsx/Node resolve to `.ts` at runtime when needed.
- Ensure all imports match the structure (src/, config/). The project should be runnable after `npm install` and config setup.
- Create all paths relative to the workspace root. Replace **${projectName}** with the actual project name when creating files.
- **Tests:** Use **.test.ts** and **`--require tsx/cjs`** in Mocha scripts (see refactor.md / test.md for conventions).
