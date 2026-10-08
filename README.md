# Custom ACH

Business Central extension that reorders the Payment Journal electronic payment
process for a standard BC 27/28 (NA/US) environment:

1. **Generate EFT File**: creates the ACH .txt file(s) for the batch and sets
   *EFT File Created*, which locks the lines. **Void** can reverse this step.
2. **Export**: creates the vendor remittances (V.Remittance reports 10083/11383)
   and sets *Check Exported* and *Check Transmitted*.

Each company opts in through **Enable EFT Generate before Export** on
Purchases & Payables Setup. When it is off, standard BC behaviour applies.

| Folder | App | Object IDs |
|---|---|---|
| `App/` | Custom ACH | 81100–81199 |
| `TestApp/` | Custom ACH Tests (depends on the App; no Microsoft test libraries) | 81200–81299 |

All objects and fields use the `BAACH` affix.

## Licensing

Custom ACH depends on the **BALIC Licensing** app (`2e64ea38-…`, repo
`MasterBasketWeaver/BCLicensing`), which must be published and installed first
in every environment, including `MCSandbox_09222026`. Customers upload their
`.lic` file on its **Licences** page.

- **What is checked:** `App/src/Licensing/` verifies the licence itself.
  `BAACH License Verifier` is a renamed copy of the licensing app's `BALIC Token
  Verifier`; keep the two identical.
- **What it blocks:** Generate EFT File and Export. Void and everything else
  stay available, so a lapsed customer can still reverse a batch.
- **Trial:** 7 days in production from the first install. Sandboxes always run,
  with or without a licence.
- **Status check:** `BAACHRunTests.GetLicenseStatus` returns the guard's own
  verdict for the environment.

## Building and publishing

The tooling lives one level up, outside this repo, next to the credentials:
`bc_config.py`, `bc_auth.py`, `bc_api.py`, `bc_symbols.py`, `bc_publish.py`, `bc_env.py`
and `run_tests.py`. The target is sandbox `MCSandbox_09222026`, and the tests run in
company "Estacado IOS Fund I, LLC".

```
cd ..
./bc_symbols.py --app-dir CustomACH/App
alc /project:CustomACH/App /packagecachepath:CustomACH/App/.alpackages /out:CustomACH/output/CustomACH.app
./bc_publish.py CustomACH/output/CustomACH.app
./bc_symbols.py --app-dir CustomACH/TestApp          # fetches the published App as well
alc /project:CustomACH/TestApp /packagecachepath:CustomACH/TestApp/.alpackages /out:CustomACH/output/CustomACHTests.app
./bc_publish.py CustomACH/output/CustomACHTests.app
./run_tests.py
```

`alc` ships with the VS Code AL extension:
`~/.vscode/extensions/ms-dynamics-smb.al-<version>/bin/linux/alc`.
Never bump the `app.json` version to get a publish through.

`run_tests.py` records every run in `../test_runs/<time>_<env>_<company>.json`: each test's result,
error and call stack, plus a `failures` list and a `status` of `passed`, `failed` or `aborted`. The
file is rewritten after each codeunit, so a run that dies partway keeps what it got. Check it when a
failure does not reproduce.

## Eagle Eye

Eagle Eye's `DEV-SANDBOX` (tenant `de2a36e9-…`) runs BC 28.0. It ran 27.5 until October 2026, which
is why the apps target platform/application 27.0 and runtime 16.0; they install on both. Its sign-in
needs MFA: `BC_PROFILE=eagleeye` selects the tenant, and the first run of `bc_auth.py` prints a device
code to approve once.

Since 2026-10-08 Custom ACH, Custom ACH Eagle Eye and BALIC Licensing are installed there as **PTEs**
(uploaded through the automation API's `extensionUpload`); the test apps go through the dev endpoint. So
the dev-endpoint publish below works only for Custom ACH Tests. To update a PTE, raise its version and
upload it: BC refuses a PTE with the same app id and version as the package it replaces, and the upload
then just reports `Failed` with no reason. A version upgrade of the sandbox removes dev-published apps,
so after one, check with `./bc_env.py check` and republish the test apps.

**Custom ACH Eagle Eye** (81300–81349) and **Custom ACH Eagle Eye Tests** (81350–81399) live in the Eagle
Eye repo, MasterBasketWeaver/EagleEye, as `CustomACH/Custom ACH App` and `CustomACH/Custom ACH Test App`.
Eagle Eye's `ACHCustom` PTE adds one to the entry/addenda count for the offset entry its Bank of Commerce
format writes; Custom ACH Eagle Eye gives Custom ACH's files the standard count back when their format
has no such line, scoped with `"BAACH Generate EFT".IsGeneratingEFTFile()`. Its tests join this suite
through `"BAACH Suite".OnAfterAllCodeunits`, so `run_tests.py` runs them when they are installed.

```
cd ..
export BC_PROFILE=eagleeye
./bc_symbols.py --app-dir CustomACH/App --out <pk>      # the sandbox's own symbols, kept apart from Tanager's
alc /project:CustomACH/App /packagecachepath:<pk> /out:CustomACH/output/eagleeye/CustomACH.app
cp CustomACH/output/eagleeye/CustomACH.app <pk>/
alc /project:CustomACH/TestApp /packagecachepath:<pk> /out:CustomACH/output/eagleeye/CustomACHTests.app
./bc_publish.py CustomACH/output/eagleeye/CustomACHTests.app  # Custom ACH itself is a PTE there
BC_COMPANY="Test - Eagle Eye Logistics" ./run_tests.py         # also "Test - CTS", "Test - Diesel Repair Shop"
```
