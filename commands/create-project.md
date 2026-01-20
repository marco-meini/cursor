Create a new backend Node.js project structure.

Inputs:
- ${projectName}: The name of the project (will be used as folder name and package.json name)

Goals:
- Create the complete project structure with all necessary files and folders
- Generate skeleton files with proper content
- Set up configuration files, documentation, and test structure

Requirements:

1) Directory Structure
- Create the following directories:
  - app/controllers/
  - app/cronie/batch/
  - app/lib/
  - app/model/mongo/
  - app/model/postgres/
  - config/
  - docs/
  - test/controllers/
  - test/lib/
  - test/pg-models/
  - .vscode/

2) Core Application Files

app/main.mjs:
```javascript
import { App } from "./app.mjs";

const app = new App();
let port = app.env.config.defaultPort;
if (process.argv.length > 2) {
  port = parseInt(process.argv[2]);
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
  await app.env.pgConnection.disconnect()
  app.env.mongoClient.disconnect();
});
```

app/app.mjs:
```javascript
import { HttpResponseStatus } from "common-mjs";
import cookieParser from "cookie-parser";
import express, { json } from "express";
import { join } from "path";
import { Environment } from "./environment.mjs";
import { AuthController } from "./controllers/auth.controller.mjs";

class App {
  constructor() {
    this.env = new Environment();
    this.express = express();
    this.express.use(json({ limit: this.env.config.bodyParserLimit }));
    this.express.use(cookieParser());

    this.express.use("/healthcheck", (request, response) => {
      response.send({ uptime: process.uptime() });
    });

    const auth = new AuthController(this.env);

    this.express.use(join(this.env.config.root, auth.route), auth.router);
    
    this.express.use(
      /**
       *
       * @param {any} error
       * @param {import("common-mjs").SessionRequest} request
       * @param {import("express").Response} response
       * @param {import("express").NextFunction} next
       */
      (error, request, response, next) => {
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
              let data = error.errors.map((item) => {
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

export { App };
```

app/environment.mjs:
```javascript
import { Logger, Mailer, MongoClienManager, PgClientManager, SessionMiddleware } from "common-mjs";
import config from "../config/config.mjs";
import { PgModels } from "./model/postgres/pg-models.mjs";
import { MongoModels } from "./model/mongo/mongo-models.mjs";

/**
 * @typedef {Object} IConfig
 * @property {Object} databases
 * @property {Object} databases.postgres
 * @property {import("pg").PoolConfig} databases.postgres.master
 * @property {import("pg").PoolConfig} databases.postgres.slave
 * @property {Object} databases.mongo
 * @property {import("common-mjs").MongoDbConfig} databases.mongo.dbconfig
 * @property {import("mongodb").MongoClientOptions} [databases.mongo.options]
 * @property {number} logLevel
 * @property {number} defaultPort
 * @property {string} root
 * @property {string} bodyParserLimit
 * @property {import("redis").RedisClientOptions} redisOptions
 * @property {Object} sessionCookie
 * @property {string} sessionCookie.name
 * @property {import("express").CookieOptions} sessionCookie.options
 * @property {string} sessionHeaderName
 * @property {Object} sessionExpiration
 * @property {number} sessionExpiration.short
 * @property {number} sessionExpiration.long
 * @property {Object} sparkpost
 * @property {string} sparkpost.api
 */

class Environment {
  /** @type {IConfig} */
  config;
  /** @type {Logger} */
  logger;
  /** @type {PgClientManager} */
  pgConnection;
  /** @type {PgModels} */
  pgModels;
  /** @type {SessionMiddleware} */
  session;
  /** @type {MongoClienManager} */
  mongoClient;
  /** @type {MongoModels} */
  mongoModels;
  /** @type {Mailer} */
  mailManager;

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

  async initMongoModels() {
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

app/controllers/abstract.controller.mjs:
```javascript
import * as express from "express";
import { Environment } from "../environment.mjs";
import { join } from "path";

/**
 * @abstract
 */
class Abstract_Controller {
  /**
   * @type {express.Router}
   */
  router;
  /**
   * @type {Environment}
   */
  env;
  /**
   * @type {string}
   */
  route;
  /**
   * @type {string}
   * @protected
   */
  __filesPath;

  /**
   *
   * @param {Environment} env
   * @param {string} route
   * @param {string} [folder]
   */
  constructor(env, route, folder) {
    this.env = env;
    this.route = route;
    this.router = express.Router();
    if (folder) this.__filesPath = join(env.config.fileserver.root, env.config.fileserver.folders[folder]);
  }
}

export { Abstract_Controller };
```

app/controllers/auth.controller.mjs:
```javascript
import { HttpResponseStatus } from "common-mjs";
import { Abstract_Controller } from "./abstract.controller.mjs";

/**
 * @typedef {Object} LoginData
 * @property {string} username - The username of the user.
 * @property {string} password - The password of the user.
 * @property {boolean} persistent - Whether the login session should be persistent.
 */

class AuthController extends Abstract_Controller {
  constructor(env) {
    super(env, "auth");
    this.router.post("/login", this.__login.bind(this));
    this.router.post("/logout", this.env.session.checkAuthentication(), this.__logout.bind(this));
  }

  /**
   * Logs in the user and generates a JWT token.
   * 
   * @param {import("express").Request} request - The request object.
   * @param {import("express").Response} response - The response object.
   * @param {import("express").NextFunction} next - The next middleware function.
   */
  async __login(request, response, next) {
    // TODO: Implement login logic
    response.sendStatus(HttpResponseStatus.NOT_IMPLEMENTED);
  }

  /**
   * Logs out the user.
   *
   * @param {import("common-mjs").SessionRequest} request - The request object.
   * @param {import("express").Response} response - The response object.
   * @param {import("express").NextFunction} next - The next middleware function.
   */
  async __logout(request, response, next) {
    // TODO: Implement logout logic
    response.sendStatus(HttpResponseStatus.NOT_IMPLEMENTED);
  }
}

export { AuthController };
```

app/cronie/main-cronie.mjs:
```javascript
import { program } from "commander";
import { Environment } from "../environment.mjs";

(async () => {
  /** @type {Environment} */
  var env;
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

app/lib/utils.mjs:
```javascript
import _ from "lodash";
import moment from "moment";

export class String {
  /**
   * 
   * @param {string} separator 
   * @param  {...string} values 
   * @returns 
   */
  static joinNotEmptyValues(separator, ...values) {
    return values.filter(item => { return !!_.trimStart(_.trimEnd(item)); }).join(separator);
  }

  /**
   * Converts a string to an integer.
   *
   * @param {string} value - The string to convert.
   * @returns {number} The converted integer if the value is a non-negative integer, otherwise NaN.
   */
  static stringToPositiveInteger(value) {
    const num = Number(value);
    return _.isInteger(num) && num >= 0 ? num : NaN;
  }

  /**
   * Converts a string to a boolean.
   *
   * @param {string} value - The string to convert.
   * @returns {boolean} The converted boolean if the value is a boolean, otherwise false.
   */
  static stringToBoolean(value) {
    if (!value) {
      return false;
    }
    if (typeof (value) === "boolean") {
      return value;
    }
    return value.toLowerCase() === 'true';
  }

  /**
   * Formats a number with a minimum length and optional decimal places.
   *
   * @param {number} value - The number to format.
   * @param {number} length - Minimum length of the formatted string (pads with zeros).
   * @param {number} [decimal] - Number of decimal places to show.
   * @returns {string} The formatted number string.
   */
  static numberFormat(value, length, decimal) {
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
   * @param {number} val - The value to format.
   * @returns {string} The formatted money string (e.g., "10.50 €").
   */
  static moneyFormat(val) {
    const _v = parseFloat(val.toString());
    if (isNaN(_v)) {
      return '';
    }
    return this.numberFormat(_v, 0, 2) + ' €';
  }
}

export class Validators {
  static isEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  static isNotEmptyString(value) {
    return _.isString(value) && _.trim(value) !== '';
  }

  /**
   * Verifica se una stringa è un URL valido con protocollo http o https.
   * @param {string} value - La stringa da validare.
   * @returns {boolean} true se è un URL valido, false altrimenti.
   */
  static isValidUrl(value) {
    try {
      new URL(value);
      return true;
    } catch (err) {
      return false;
    }
  }

  static validPassword(value) {
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
   * @param {number} ms - The number of milliseconds to sleep.
   * @returns {Promise<void>} A promise that resolves after the specified duration.
   */
  static async sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
```

app/lib/express-middlewares.mjs:
```javascript
import { HttpResponseStatus } from "common-mjs";
import _ from "lodash";
import { String } from "./utils.mjs";

export class ExpressMiddlewares {
  /**
   * Middleware function to validate and parse an integer parameter from the request.
   *
   * @param {string} param - The name of the parameter to validate and parse.
   * @param {number} status - The HTTP status code to send if the parameter is invalid.
   * @returns {function(import("express").Request, import("express").Response, import("express").NextFunction): void} Middleware function to validate and parse the parameter.
   */
  static validIntegerPathParam(param, status = HttpResponseStatus.MISSING_PARAMS) {
    /**
     * Middleware function to validate and parse a parameter from the request.
     *
     * @param {import("express").Request} req - The request object.
     * @param {import("express").Response} res - The response object.
     * @param {import("express").NextFunction} next - The next middleware function.
     */
    const _middleware = (req, res, next) => {
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
   * @param {string} param - The name of the parameter to validate and parse.
   * @param {number} status - The HTTP status code to send if the parameter is invalid.
   * @returns {function(import("express").Request, import("express").Response, import("express").NextFunction): void} Middleware function to validate and parse the parameter.
   */
  static validIntegerQueryParam(param, required = false) {
    /**
     * Middleware function to validate and parse a parameter from the request.
     *
     * @param {import("express").Request} req - The request object.
     * @param {import("express").Response} res - The response object.
     * @param {import("express").NextFunction} next - The next middleware function.
     */
    const _middleware = (req, res, next) => {
      const paramValue = req.query[param];
      const valued = !_.isNil(paramValue);
      const value = valued ? parseInt(paramValue) : null;

      if ((required && !valued) || (valued && !/^\d+$/.test(paramValue))) {
        res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        return;
      }

      if (valued && _.isInteger(value) && value === parseFloat(paramValue)) {
        res.locals[param] = value;
      }

      next();
      return;
    };

    return _middleware;
  }

  static parsePaginationParams(required = true) {
    /**
     * Middleware function to parse pagination parameters from the request query.
     *
     * @param {import("express").Request} req - The request object.
     * @param {import("express").Response} res - The response object.
     * @param {import("express").NextFunction} next - The next middleware function.
     */
    const _middleware = (req, res, next) => {
      /** @type {{page: string, pageSize: string}} */
      let queryParams = req.query;

      /**
       * @type {number}
       * @description The maximum number of profiles to retrieve.
       */
      let limit;
      /**
       * @type {number}
       * @description The offset to start retrieving profiles.
       */
      let offset;

      if (!_.isNil(queryParams.page) && !_.isNil(queryParams.pageSize)) {
        limit = String.stringToPositiveInteger(queryParams.pageSize);
        offset = String.stringToPositiveInteger(queryParams.page - 1) * limit;
      } else {
        if (required) {
          res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
          return;
        } else {
          limit = null;
          offset = 0;
        }
      }

      if (Number.isNaN(limit) || Number.isNaN(offset) || limit === 0) {
        res.sendStatus(HttpResponseStatus.MISSING_PARAMS);
        return;
      }

      res.locals["limit"] = limit;
      res.locals["offset"] = offset;
      next();
    };

    return _middleware;
  }

  static checkHeaderToken(headerName, expectedToken) {
    /**
     * Middleware function to check the presence and validity of a specific header token.
     *
     * @param {import("express").Request} req - The request object.
     * @param {import("express").Response} res - The response object.
     * @param {import("express").NextFunction} next - The next middleware function.
     */
    const _middleware = (req, res, next) => {
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

app/model/mongo/mongo-models.mjs:
```javascript
import { MongoClienManager } from "common-mjs";
import { ExampleCollection } from "./example.collection.mjs";

export class MongoModels {
  /** @type {MongoClienManager} */
  __mongoClient;

  /**
   * 
   * @param {MongoClienManager} mongoClient 
   */
  constructor(mongoClient) {
    this.__mongoClient = mongoClient;
  }

  init() {
    this.example = new ExampleCollection(this.__mongoClient);
  }
}
```

app/model/mongo/example.collection.mjs:
```javascript
import { Abstract_BaseCollection, MongoClienManager } from "common-mjs";

/**
 * Example MongoDB collection
 */
class ExampleCollection extends Abstract_BaseCollection {
  /**
   * 
   * @param {MongoClienManager} dbMan 
   */
  constructor(dbMan) {
    super("example", dbMan);
  }
}

export { ExampleCollection };
```

app/model/postgres/pg-models.mjs:
```javascript
import { PgClientManager } from "common-mjs";
import { UsersModel } from "./users.model.mjs";

class PgModels {
  /**
   *
   * @param {PgClientManager} connection
   */
  constructor(connection) {
    this.users = new UsersModel(connection);
  }
}

export { PgModels };
```

app/model/postgres/users.model.mjs:
```javascript
import { Abstract_PgModel } from "common-mjs";

/**
 * Users model for PostgreSQL
 * TODO: Implement user-related database operations
 */
class UsersModel extends Abstract_PgModel {
  /**
   * 
   * @param {import("common-mjs").PgClientManager} connection 
   */
  constructor(connection) {
    super(connection);
  }
}

export { UsersModel };
```

3) Configuration Files

config/config.mjs:
```javascript
export default {
  databases: {
    postgres: {
      master: {
        database: "",
        user: "",
        password: "",
        host: ""
      },
      slave: {
        database: "",
        user: "",
        password: "",
        host: ""
      }
    },
    mongo: {
      dbconfig: "",
      options: {
        maxPoolSize: 5
      }
    }
  },
  logLevel: 3,
  root: "/api/v2",
  defaultPort: 9804,
  bodyParserLimit: "50mb",
  redisOptions: {
    url: "",
    password: ""
  },
  sessionCookie: {
    name: "",
    options: {
      sameSite: "none"
    }
  },
  sessionHeaderName: "",
  sessionExpiration: {
    short: 7890000,
    long: 31536000
  },
  sparkpost: {
    api: ""
  }
};
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
- Create empty directories: test/controllers/, test/lib/, test/pg-models/
- No test files, just directory structure

6) Project Configuration Files

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
config/config.mjs

# Visual Studio Code Settings
.vscode

# Files
fileserver
.DS_Store
app/.DS_Store
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
    "start": "node ./app/main.mjs",
    "start-debug": "node --inspect ./app/main.mjs",
    "start-nodemon-debug": "nodemon --inspect ./app/main.mjs",
    "test": "mocha"
  },
  "devDependencies": {
    "@types/chai": "^5.0.0",
    "@types/cookie-parser": "^1.4.7",
    "@types/fs-extra": "^11.0.4",
    "@types/lodash": "^4.17.10",
    "@types/sinon": "^17.0.3",
    "chai": "^5.1.1",
    "chai-as-promised": "^8.0.0",
    "mocha": "^11.7.5",
    "sinon": "^21.0.1"
  },
  "dependencies": {
    "@types/pg": "^8.11.8",
    "common-mjs": "git+ssh://common-mjs/ambrogio-dev/common-mjs#fe-refactor",
    "cookie-parser": "^1.4.6",
    "express": "^4.19.2",
    "lodash": "^4.17.21",
    "moment": "^2.30.1",
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
      "skipFiles": [
        "<node_internals>/**"
      ],
      "program": "${workspaceFolder}/app/main.mjs"
    }
  ]
}
```

README.md:
```markdown
# ${projectName}

## Setup

1. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`

2. Configure the application:
   - Copy `config/config.mjs` and fill in your database and service credentials

3. Start the server:
   \`\`\`bash
   npm start
   \`\`\`

## Development

- Start with debug: `npm run start-debug`
- Start with nodemon: `npm run start-nodemon-debug`
- Run tests: `npm test`
```

Output:
- Create all files and directories in the current workspace root
- Use the write tool for each file
- All file paths should be relative to the workspace root (create the project structure directly in the current directory)

Important Notes:
- All files must use ES modules (.mjs extension)
- Use proper JSDoc comments where applicable
- Ensure all imports are correct and match the structure
- The project should be immediately runnable after npm install and config setup
- All file paths should be created relative to the workspace root (not in a subfolder)
- The project structure should be self-contained and independent
- Replace ${projectName} with the actual project name when creating files
