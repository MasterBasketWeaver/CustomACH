# Custom ACH

Business Central extension that reorders the Payment Journal electronic payment
process for a standard BC 28 (NA/US) environment:

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
