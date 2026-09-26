# Custom ACH Tests

Automated tests for `App/`. A separate extension so the tested app ships without it. Never install it in
production.

It depends only on the App: the Microsoft test libraries (Test Runner, Library Assert, Any, ...) are not
published in `MCSandbox_09222026`, so the framework uses platform features only (`Subtype = Test` /
`TestRunner`, `TestIsolation`, `asserterror`) plus its own `BAACH Assert` and `BAACH Library`.

## Running

From `ach_reorder_app/` (the directory above the repo, where `bc_auth.py` lives):

```
python3 run_tests.py            # every codeunit in the suite, one SOAP call per codeunit
python3 run_tests.py 81211      # one test codeunit
python3 run_tests.py 81211 -v   # with call stacks on failures
python3 run_tests.py --suite    # the codeunits the suite holds
python3 run_tests.py --env      # what the fixtures borrow from the company
```

`run_tests.py` calls the SOAP service `BAACHRunTests` in company "Estacado IOS Fund I, LLC".
`BAACH Test Install` publishes it when the Test App is installed. The first run after a publish can report
0/0 or a metadata error: retry once before investigating. Check a new test codeunit by its test count, not
by a green result.

## Building

Publish the App first, then refresh `TestApp/.alpackages` (the Microsoft symbols plus the freshly compiled
`CustomACH.app`) and build:

```
alc /project:TestApp /packagecachepath:TestApp/.alpackages /out:output/CustomACHTests.app
```

## Objects

| Id | Object | Purpose |
| --- | --- | --- |
| 81200 | `BAACH Test Runner` | `TestRunner`, `TestIsolation = Function`: everything a test writes, commits included, is rolled back. |
| 81201 | `BAACH Test Results` | Single-instance JSON sink that survives the rollback. |
| 81202 | `BAACH Run Tests` | SOAP entry: `RunAll`, `RunOneCodeunit`, `GetSuiteCodeunits`, `GetEnvironmentSummary`, `ExportDataExchDef`. |
| 81203 / 81204 | `BAACH Test Install` / `Upgrade` | Publish the `BAACHRunTests` web service. |
| 81205 | `BAACH Suite` | The single place a test codeunit is registered. |
| 81206 | `BAACH Assert` | Assertions. |
| 81207 | `BAACH Library` | Fixtures. |
| 81208 | `BAACH ACH File` | Reads the generated NACHA file from Data Exch. "File Content" and parses its records. |
| 81210–81216 | test codeunits | Setup, Generate EFT, Line Lock, Export Remittance, Remittance Report, Posting, Void. |

## Fixtures

Every test builds its own records under unique codes: a Data Exchange Definition imported from
`resources/US-EFT-DEFAULT.xml` (renamed to a fresh code on import), a Bank Export/Import Setup
(Export-EFT), a US-format bank account, vendors with bank accounts, a payment template and batch, and vendor
invoices posted through a general journal. Posting groups and a G/L account for the invoices are borrowed
from what the company already has; `--env` shows which ones.

`resources/US-EFT-DEFAULT.xml` is the company's US EFT definition exported with XMLport 1225. To capture it
again, call `ExportDataExchDef` (SOAP parameter `code`) with the definition code and save the returned text.

Headless limits: a SOAP session cannot show request pages or modal pages, so `ExportForBatch` is only called
for its guards; the marking rules are tested through `BAACH Remittance Run Scope`, and the remittance reports
through `Report.SaveAs` with request-parameter XML. Request-page pre-fill, downloads, email output and action
visibility need a UI run.
