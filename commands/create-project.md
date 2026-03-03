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
  - **.cursor/rules/** (Cursor project rules, .mdc files)
  - **.cursor/skills/** (Cursor project skills, one folder per skill with SKILL.md)

2) Core Application Files

**TypeScript:** All source under **src/** with **.ts** extension. Use ESM (`"type": "module"`). Run with **tsx** (or compile with `tsc` and run `node dist/main.js`).

src/main.ts:
```typescript
import { App } from "./app.js";

const app = new App();
let port = app.env.config.defaultPort;
if (process.argv.length > 2) {
  port = parseInt(process.argv[2]);
}

(async () => {
  await app.env.initMongoModels();
  try {
    await (app.env.session as any).sessionManager.connect();
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
import { HttpResponseStatus, SessionRequest } from "common-mjs";
import cookieParser from "cookie-parser";
import express, { json, Request, Response, NextFunction } from "express";
import { join } from "path";
import { Environment } from "./environment.js";
import { AuthController } from "./controllers/auth.controller.js";

export class App {
  env: Environment;
  express: express.Application;

  constructor() {
    this.env = new Environment();
    this.express = express();
    this.express.use(json({ limit: this.env.config.bodyParserLimit || '50mb' }));
    this.express.use(cookieParser());

    this.express.use("/healthcheck", (request: Request, response: Response) => {
      response.send({ uptime: process.uptime() });
    });

    const auth = new AuthController(this.env);
    this.express.use(join(this.env.config.root, auth.route), auth.router);

    this.express.use(
      (error: any, request: SessionRequest, response: Response, next: NextFunction) => {
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
            if (error.errors && error.errors.length) {
              let data = error.errors.map((item: any) => {
                return item.message;
              });
              response.status(error.status).send(data);
            } else if (error.status === HttpResponseStatus.MISSING_PARAMS) {
              response.status(error.status).send(error.message);
            } else {
              this.env.logger.error(error.status, error.stack || error.message);
              response.sendStatus(error.status);
            }
          } else {
            let token = request.token ? "JWT: " + request.token : "";
            this.env.logger.error(`[${request.method}]`, request.url, error.stack || error.message, token);
            response.sendStatus(HttpResponseStatus.SERVER_ERROR);
          }
        }
      }
    );
  }
}
```

src/environment.ts:
```typescript
import { Logger, Mailer, MongoClienManager, PgClientManager, SessionMiddleware } from "common-mjs";
import config, { IConfig, projectRoot } from "./config.js";
import { PgModels } from "./model/postgres/pg-models.js";
import { MongoModels } from "./model/mongo/mongo-models.js";

export class Environment {
  /** Project root directory (for assets, templates, etc.). */
  readonly projectRoot: string;
  config: IConfig;
  logger: Logger;
  pgConnection: PgClientManager;
  pgModels: PgModels;
  session: SessionMiddleware;
  mongoClient: MongoClienManager;
  mongoModels: MongoModels;
  mailManager: Mailer;

  constructor() {
    this.projectRoot = projectRoot;
    this.config = config;
    this.logger = new Logger(this.config.logLevel);
    this.pgConnection = new PgClientManager(this.config.databases.postgres.master as any, this.logger.sql.bind(this.logger));
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
```

src/controllers/abstract.controller.ts:
```typescript
import * as express from "express";
import { Environment } from "../environment.js";
import { join } from "path";

/**
 * Abstract base class for controllers
 */
export abstract class Abstract_Controller {
  router: express.Router;
  protected filesPath?: string;

  constructor(public env: Environment, public route: string, folder?: string) {
    this.router = express.Router();
    if (folder && env.config.fileserver?.root && env.config.fileserver?.folders?.[folder]) {
      this.filesPath = join(env.config.fileserver.root, env.config.fileserver.folders[folder]);
    }
  }
}
```

src/controllers/auth.controller.ts:
```typescript
import { HttpResponseStatus, SessionRequest } from "common-mjs";
import { Request, Response, NextFunction } from "express";
import { Abstract_Controller } from "./abstract.controller.js";
import { Environment } from "../environment.js";

export class AuthController extends Abstract_Controller {
  constructor(env: Environment) {
    super(env, "auth");
    this.router.post("/login", this.login.bind(this));
    this.router.post("/logout", this.env.session.checkAuthentication(), this.logout.bind(this));
  }

  /**
   * Logs in the user and generates a JWT token.
   */
  private async login(request: Request, response: Response, next: NextFunction): Promise<void> {
    // TODO: Implement login logic
    response.sendStatus(501);
  }

  /**
   * Logs out the user.
   */
  private async logout(request: SessionRequest, response: Response, next: NextFunction): Promise<void> {
    // TODO: Implement logout logic
    response.sendStatus(501);
  }
}
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
  /**
   * 
   * @param separator 
   * @param values 
   * @returns 
   */
  static joinNotEmptyValues(separator: string, ...values: (string | undefined | null)[]): string {
    return values.filter(item => { return !!_.trimStart(_.trimEnd(item)); }).join(separator);
  }

  /**
   * Converts a string to an integer.
   */
  static stringToPositiveInteger(value: string): number {
    const num = Number(value);
    return _.isInteger(num) && num >= 0 ? num : NaN;
  }

  /**
   * Converts a string to a boolean.
   */
  static stringToBoolean(value: unknown): boolean {
    if (!value) {
      return false;
    }
    if (typeof (value) === "boolean") {
      return value;
    }
    if (typeof value === "string") {
      return value.toLowerCase() === 'true';
    }
    return false;
  }

  /**
   * Formats a number with a minimum length and optional decimal places.
   *
   * @param value - The number to format.
   * @param length - Minimum length of the formatted string (pads with zeros).
   * @param decimal - Number of decimal places to show.
   * @returns The formatted number string.
   */
  static numberFormat(value: number, length: number, decimal?: number): string {
    let _format = value + '';
    if (decimal) {
      _format = value.toFixed(decimal);
    }
    while (_format.length < length) {
      _format = '0' + _format;
    }
    return _format;
  }

  /**
   * Formats a number as a currency string with Euro symbol.
   *
   * @param val - The value to format.
   * @returns The formatted money string (e.g., "10.50 €").
   */
  static moneyFormat(val: number | string): string {
    const _v = parseFloat(val.toString());
    if (isNaN(_v)) {
      return '';
    }
    return this.numberFormat(_v, 0, 2) + ' €';
  }
}

export class Validators {
  static isEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  static isNotEmptyString(value: unknown): boolean {
    return _.isString(value) && _.trim(value) !== '';
  }

  /**
   * Verifica se una stringa è un URL valido con protocollo http o https.
   * @param value - La stringa da validare.
   * @returns true se è un URL valido, false altrimenti.
   */
  static isValidUrl(value: string): boolean {
    try {
      new URL(value);
      return true;
    } catch (err) {
      return false;
    }
  }

  static validPassword(value: string | null | undefined): boolean {
    if (_.isNil(value) || _.isEmpty(value)) {
      return false;
    }
    if (value.length < 8) {
      return false;
    }
    return /\d/.test(value) && /[a-z]/.test(value) && /[A-Z]/.test(value) && /\W|_/.test(value);
  }
}

export class GenericFunctions {
  /**
   * Pauses the execution for a specified number of milliseconds.
   *
   * @param ms - The number of milliseconds to sleep.
   * @returns A promise that resolves after the specified duration.
   */
  static async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
```

src/lib/express-middlewares.ts:
```typescript
import { HttpResponseStatus } from "common-mjs";
import _ from "lodash";
import { Request, Response, NextFunction } from "express";
import { String } from "./utils.js";

export class ExpressMiddlewares {
  /**
   * Middleware function to validate and parse an integer parameter from the request.
   *
   * @param param - The name of the parameter to validate and parse.
   * @param status - The HTTP status code to send if the parameter is invalid.
   * @returns Middleware function to validate and parse the parameter.
   */
  static validIntegerPathParam(param: string, status: number = HttpResponseStatus.MISSING_PARAMS) {
    /**
     * Middleware function to validate and parse a parameter from the request.
     *
     * @param req - The request object.
     * @param res - The response object.
     * @param next - The next middleware function.
     */
    const _middleware = (req: Request, res: Response, next: NextFunction): void => {
      const paramValue = req.params[param];
      const value = parseInt(paramValue);

      if (!paramValue || !/^\d+$/.test(paramValue)) {
        res.sendStatus(status);
        return;
      }

      if (_.isInteger(value) && value === parseFloat(paramValue)) {
        res.locals[param] = value;
        next();
        return;
      }

      res.sendStatus(status);
      return;
    };

    return _middleware;
  }

  /**
   * Middleware function to validate and parse an integer parameter from the request.
   *
   * @param param - The name of the parameter to validate and parse.
   * @param required - Whether the parameter is required.
   * @returns Middleware function to validate and parse the parameter.
   */
  static validIntegerQueryParam(param: string, required: boolean = false) {
    /**
     * Middleware function to validate and parse a parameter from the request.
     *
     * @param req - The request object.
     * @param res - The response object.
     * @param next - The next middleware function.
     */
    const _middleware = (req: Request, res: Response, next: NextFunction): void => {
      const paramValue = req.query[param] as string | undefined;
      const valued = !_.isNil(paramValue);
      const value = valued ? parseInt(paramValue!) : null;

      if ((required && !valued) || (valued && !/^\d+$/.test(paramValue!))) {
        res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        return;
      }

      if (valued && _.isInteger(value) && value === parseFloat(paramValue!)) {
        res.locals[param] = value;
      }

      next();
      return;
    };

    return _middleware;
  }

  static parsePaginationParams(required: boolean = true) {
    /**
     * Middleware function to parse pagination parameters from the request query.
     *
     * @param req - The request object.
     * @param res - The response object.
     * @param next - The next middleware function.
     */
    const _middleware = (req: Request, res: Response, next: NextFunction): void => {
      let queryParams = req.query as { page?: string; pageSize?: string };

      /**
       * The maximum number of profiles to retrieve.
       */
      let limit: number | null;
      /**
       * The offset to start retrieving profiles.
       */
      let offset: number;

      if (!_.isNil(queryParams.page) && !_.isNil(queryParams.pageSize)) {
        limit = String.stringToPositiveInteger(queryParams.pageSize);
        offset = (String.stringToPositiveInteger(queryParams.page) - 1) * limit;
      } else {
        if (required) {
          res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
          return;
        } else {
          limit = null;
          offset = 0;
        }
      }

      if (Number.isNaN(limit!) || Number.isNaN(offset) || limit === 0) {
        res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        return;
      }

      res.locals["limit"] = limit;
      res.locals["offset"] = offset;
      next();
    };

    return _middleware;
  }

  static checkHeaderToken(headerName: string, expectedToken: string) {
    /**
     * Middleware function to check the presence and validity of a specific header token.
     *
     * @param req - The request object.
     * @param res - The response object.
     * @param next - The next middleware function.
     */
    const _middleware = (req: Request, res: Response, next: NextFunction): void => {
      const token = req.headers[headerName.toLowerCase()];
      if (_.isNil(token) || token !== expectedToken) {
        res.sendStatus(HttpResponseStatus.NOT_AUTHORIZED);
        return;
      }
      next();
    };

    return _middleware;
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
    super(dbMan, "example");
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

**Config in src/config.ts:** Types and loader in `src/config.ts`; actual values in `config/config.json` at project root (so `dist/` contains only compiled `src/`, and `node dist/main.js` works). Loads JSON from project root `config/` directory.

src/config.ts:
```typescript
import type { PoolConfig } from "pg";
import type { MongoClientOptions } from "mongodb";
import type { CookieOptions } from "express";
import type { RedisClientOptions } from "redis";
import { readFileSync, existsSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";

export interface IConfig {
  databases: {
    postgres: { master: PoolConfig; slave: PoolConfig };
    mongo: { dbconfig: string; options?: MongoClientOptions };
  };
  logLevel: number;
  defaultPort: number;
  root: string;
  redisOptions: RedisClientOptions;
  sessionCookie: { name: string; options: CookieOptions };
  sessionHeaderName: string;
  sessionExpiration: { short: number; long: number };
  sparkpost: { api: string };
  bodyParserLimit?: string;
  fileserver?: { root: string; folders: Record<string, string> };
}

/** Minimal config when no config file exists (e.g. tests that stub Environment). */
function minimalTestConfig(): IConfig {
  const pg: PoolConfig = { host: "localhost", port: 5432, user: "test", password: "test", database: "test" };
  return {
    databases: {
      postgres: { master: pg, slave: pg },
      mongo: { dbconfig: "mongodb://localhost:27017" },
    },
    logLevel: 2,
    defaultPort: 3000,
    root: "/",
    redisOptions: { socket: { host: "localhost", port: 6379 } },
    sessionCookie: { name: "session", options: {} },
    sessionHeaderName: "x-session",
    sessionExpiration: { short: 3600, long: 86400 },
    sparkpost: { api: "" },
  };
}

/** Load config from project root config/config.json (outside src/dist). */
const __dirname = path.dirname(fileURLToPath(import.meta.url));
/** Project root directory (one level up from src/ or dist/). Use for assets, templates, etc. */
export const projectRoot = path.join(__dirname, "..");
const configDir = path.join(projectRoot, "config");
const configPath = path.join(configDir, "config.json");
const examplePath = path.join(configDir, "config.json.example");
const pathToLoad = existsSync(configPath) ? configPath : existsSync(examplePath) ? examplePath : null;

const configValues: IConfig = pathToLoad
  ? (JSON.parse(readFileSync(pathToLoad, "utf-8")) as IConfig)
  : minimalTestConfig();

if (configValues.sessionCookie?.options?.sameSite === "none") {
  configValues.sessionCookie.options.sameSite = "none" as "none" | "lax" | "strict" | boolean;
}

export default configValues;
```

config/config.json.example (at project root; not compiled; add config.json to .gitignore if it contains secrets):
```json
{
  "databases": {
    "postgres": {
      "master": {
        "host": "localhost",
        "port": 5432,
        "user": "postgres",
        "password": "",
        "database": ""
      },
      "slave": {
        "host": "localhost",
        "port": 5432,
        "user": "postgres",
        "password": "",
        "database": ""
      }
    },
    "mongo": {
      "dbconfig": "",
      "options": {
        "maxPoolSize": 5
      }
    }
  },
  "logLevel": 3,
  "defaultPort": 9804,
  "root": "/api/v2",
  "redisOptions": {
    "socket": {
      "host": "localhost",
      "port": 6379
    }
  },
  "sessionCookie": {
    "name": "",
    "options": {
      "sameSite": "none"
    }
  },
  "sessionHeaderName": "",
  "sessionExpiration": {
    "short": 7890000,
    "long": 31536000
  },
  "sparkpost": {
    "api": ""
  },
  "bodyParserLimit": "50mb"
}
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

Use **rootDir: "src"** and **include** only **src/** so that `dist/` contains only compiled source (e.g. `dist/main.js`), and `npm start` runs `node dist/main.js` without changing paths to config. Config is loaded at runtime from project root `config/config.json`.

tsconfig.json:
```json
{
  "compilerOptions": {
    /* Basic Options */
    "target": "ES2022",
    "module": "ES2022",
    "lib": ["ES2022"],
    "moduleResolution": "node",
    
    /* Output: only src in dist, no dist/src subfolder (config and assets stay at project root, referenced as ../config, ../assets) */
    "outDir": "./dist",
    "rootDir": "./src",
    "sourceMap": true,
    "declaration": true,
    "declarationMap": true,
    
    /* Interop */
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "forceConsistentCasingInFileNames": true,
    
    /* Type Checking */
    "strict": false,
    "noImplicitAny": false,
    "strictNullChecks": false,
    "strictFunctionTypes": false,
    "strictPropertyInitialization": false,
    "noImplicitThis": false,
    "alwaysStrict": false,
    
    /* Additional Checks */
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noImplicitReturns": false,
    "noFallthroughCasesInSwitch": false,
    
    /* Skip type checking */
    "skipLibCheck": true,
    
    /* Resolve */
    "resolveJsonModule": true,
    "allowJs": true,
    "types": ["node"]
  },
  "include": [
    "src/**/*"
  ],
  "typeRoots": [
    "./node_modules/@types",
    "./types"
  ],
  "exclude": [
    "node_modules",
    "dist",
    "test",
    "config",
    "assets",
    "**/*.test.mjs",
    "**/*.test.ts",
    "**/*.spec.ts"
  ]
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

# configurations (config/config.json at root holds runtime values; ignore if it contains secrets)
config/config.json

# TypeScript
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
    "build:watch": "tsc -w",
    "start": "node --enable-source-maps ./dist/main.js",
    "start:dev": "tsx ./src/main.ts",
    "start-debug": "node --enable-source-maps --inspect ./dist/main.js",
    "start-nodemon-debug": "nodemon --exec \"node --enable-source-maps --inspect\" ./dist/main.js",
    "test": "mocha --require tsx/cjs",
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
  },
  "overrides": {
    "mongodb": "^6.8.0"
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
   - Copy `config/config.json.example` to `config/config.json` and set database and service credentials.

3. Build and start the server:
   \`\`\`bash
   npm run build
   npm start
   \`\`\`
   (Production: `npm start` runs `node dist/main.js`. Development: `npm run start:dev` runs **tsx** on `src/`.)

## Development

- Build: `npm run build` (output in `dist/`; do not edit `dist/` by hand)
- Start (production): `npm start` (requires build)
- Start (development): `npm run start:dev` (tsx)
- Start with watch: `npm run start:watch`
- Start with debug: `npm run start-debug`
- Run tests: `npm test` or `npm run test:all` (Mocha + tsx/cjs for `.test.ts` files)
```

8) Cursor rules and skills

Create project-local Cursor rules and a TypeScript backend skill so the AI follows the same conventions across machines (no symlinks or absolute paths).

**.cursor/rules/use-backend-skill.mdc:**
```yaml
---
description: Use the TypeScript backend skill for conventions in this project.
alwaysApply: true
---

# Use backend TypeScript skill

When writing or modifying code in this project, **always follow the conventions and best practices** defined in the skill at `.cursor/skills/yn-be-developer-ts/SKILL.md`.

Apply the skill when working on controllers, models, lib, SQL (PgFilter, row_to_json, flat query result shape), types and interfaces, tests (Mocha + tsx), validation, and error handling.
```

**.cursor/skills/yn-be-developer-ts/SKILL.md:** Create the directory `.cursor/skills/yn-be-developer-ts/` and add a SKILL.md with YAML frontmatter and content. Use the same structure as the shared skill (see **cursor/skills/yn-be-developer-ts/SKILL.md** in the cursor workspace if available): `name`, `description` in frontmatter, then sections for When to Use, Core Technologies, Architecture Patterns, TypeScript Conventions, SQL & PgFilter, Transactions, Testing, etc. If that file is not available, create a minimal SKILL.md:

```markdown
---
name: yn-be-developer-typescript
description: Best practices for TypeScript backends (src/, Express, PostgreSQL/MongoDB, Mocha+tsx).
---

# Backend TypeScript – Best Practices

Follow the patterns in **refactor.md** and **test.md**: TypeScript under src/, ESM, private methods without __, transactionClient, one interface per table, flat query result shape, row_to_json for joined data, getParameterPlaceHolder, no unnecessary variables. Use env.pgConnection / env.pgModels; validate with _.isNil, _.isArray, Number.isInteger(id) && id > 0.
```

(When the full skill document is available, replace the minimal content above with it so the project is self-contained and works on any machine.)

Output:
- Create all files and directories in the current workspace root
- Use the write tool for each file
- All file paths should be relative to the workspace root (create the project structure directly in the current directory)
- Create **.cursor/rules/** and **.cursor/skills/** with at least one rule (e.g. use-backend-skill.mdc) and one skill (e.g. .cursor/skills/yn-be-developer-ts/SKILL.md) so the project uses Cursor conventions without symlinks or user-specific paths

Important Notes:
- **TypeScript:** All source under **src/** with **.ts** extension. Use ESM (`"type": "module"` in package.json) so that `node dist/main.js` runs correctly. Run in dev with **tsx** or compile with `tsc` and run from `dist/`.
- **Never modify dist/:** Files in **dist/** are build output only; do not edit them. All path and ESM fixes are done in **src/** (e.g. `.js` in imports).
- **Controller methods:** Use **private** method names **without** `__` (e.g. `login`, `logout`). Tests call them via `(controller as any).methodName(...)`.
- **Imports:** Use **.js** extension in **every** relative import (e.g. `from "./app.js"`, `from "../lib/utils.js"`). TypeScript does not rewrite paths; Node ESM requires the extension when running `node dist/main.js`.
- **CommonJS dependencies:** If a package (e.g. exceljs) is CommonJS and triggers "Named export not found", use default import for values and `import type` for types: `import pkg from "exceljs";` `import type { Worksheet } from "exceljs";` `const { Workbook } = pkg;` Use `InstanceType<typeof Workbook>` for instance types when needed.
- **Loading ESM config from outside src:** If `src/config/config.ts` loads a file at project root (e.g. `config/config.js`) that is ESM, do **not** use `createRequire` + `require()` (ERR_REQUIRE_ESM). Use dynamic import with pathToFileURL and top-level await: `import { pathToFileURL } from "url";` then `const configModule = await import(pathToFileURL(configPath).href);` and use `configModule.default`.
- Ensure all imports match the structure (src/, config/). The project should be runnable after `npm install` and config setup.
- Create all paths relative to the workspace root. Replace **${projectName}** with the actual project name when creating files.
- **Tests:** Use **.test.ts** and **`--require tsx/cjs`** in Mocha scripts (see refactor.md / test.md for conventions).
