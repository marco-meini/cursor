Split a model interface into a **Record** (table columns only) and an **Extended** interface (Record + derived/join fields).

Inputs:
- ${modelFile}: path to the model file (e.g. `src/model/postgres/addressbook.model.ts`, `src/model/postgres/associations.model.ts`)
- ${interfaceName}: current interface to split (e.g. `IAddressbookRecord`, `IAssociationMemberRecord`, `IDistributionListRaw`)
- ${suffix}: column suffix used by the table (e.g. `_ab`, `_asm`, `_dl`, `_mo`). Only fields ending with this suffix belong to the Record.

Goals:
- Keep in the **Record** interface only fields whose name ends with `${suffix}` (direct table columns).
- Create a new **Extended** interface that `extends` the Record and adds all other fields (from JOINs, computed values, JSON aggregates, etc.).
- Update all references in the project: return types of model methods, controller variables, lib types, so that:
  - Queries that return only table columns use the Record type.
  - Queries that return table columns + derived fields use the Extended type.

Requirements:

1) Record interface
- Name: keep `${interfaceName}` as the Record (e.g. `IAddressbookRecord`, `IAssociationMemberRecord`).
- Properties: only those with the table suffix (e.g. `id_ab`, `name_ab`, `surname_ab` for `_ab`).
- Remove from the Record any property that does NOT end with `${suffix}` (e.g. `fullname`, `numbers`, `tags`, `customer`, `name`, `sharing`).

2) Extended interface
- Name: derive from the Record name by replacing "Record" with "Extended", or "Raw" with "Extended" (e.g. `IAddressbookRecord` → `IContact` or `IAddressbookExtended`; `IDistributionListRaw` → `IDistributionListExtended`; `IAssociationMemberRecord` → `IAssociationMemberExtended`). If the codebase already uses a name like `IContact` for the extended shape, use that.
- Definition: `export interface I<Name>Extended extends I<Name>Record { ... }` with only the non-suffixed fields.
- Add the Extended interface in the same file, immediately after the Record.

3) Model methods
- For each method that returns rows from a query:
  - If the SQL returns only table columns (no JOIN/aggregate/computed columns): type the result as the Record (or `Record | null`, `Record[]` as appropriate).
  - If the SQL returns table columns plus extra fields (e.g. `retrieve_abook_fullname(...) as fullname`, `row_to_json(b.*) as customer`, `array_agg(...) AS sharing`): type the result as the Extended (or `Extended | null`, `Extended[]`).
- Use the correct generic on `query`, `queryReturnFirst`, `queryPaged` (e.g. `queryReturnFirst<IContact>`, `queryPaged<IDistributionListExtended>`).

4) Controllers and lib
- Search the project for all usages of the Record and Extended types (imports, variable types, method return types).
- Where the value actually has the extended shape (e.g. includes `fullname` or `customer`), use the Extended type (e.g. `let contacts: IAddressbookExtended[]` instead of `IAddressbookRecord[]` when passing to `addressbookExport.export(contacts)`).
- Do not change DTOs or response shapes that are intentionally different (e.g. controller-specific interfaces like `IAssociationMember` with camelCase); only fix types that refer to the model Record/Extended.

5) Optional fields
- If a query returns the Extended shape but does not populate some optional extended fields (e.g. no `numbers` in a simple by-id query), either:
  - Make those properties optional in the Extended interface (e.g. `numbers?: Array<...>`), or
  - Introduce a narrower type (e.g. `IContactBasic`) for that method’s return type. Prefer optional when the same interface is used in many places.

6) Naming conventions
- Record = table row (suffix only).
- Extended = Record + derived/join fields (no suffix on those extra fields).
- Keep existing exported names if they are already used elsewhere; only split the structure and add the Extended interface.

Checklist:
- [ ] Record has only `${suffix}`-suffixed properties.
- [ ] Extended extends Record and declares only non-suffixed properties.
- [ ] All model methods that return query results use Record or Extended consistently with their SQL.
- [ ] Controllers/libs that use the extended shape use the Extended type; no type errors at build.
- [ ] `npm run build` (or `tsc`) passes.

References (yn-be-v2 examples):
- `IAddressbookRecord` / `IContact` (or `IAddressbookExtended`) in `addressbook.model.ts`
- `IDistributionListRecord` / `IDistributionListExtended` in `addressbook.model.ts`
- `IAssociationMemberRecord` / `IAssociationMemberExtended` in `associations.model.ts`
