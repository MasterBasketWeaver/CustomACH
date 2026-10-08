// Installs from before licensing never ran "BAACH License Install".
codeunit 81110 "BAACH License Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerDatabase()
    var
        LicenseGuard: Codeunit "BAACH License Guard";
        TokenStore: Codeunit "BALIC Token Store";
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        LicenseGuard.RecordInstallDate();
        TokenStore.RegisterProduct(AppInfo, LicenseGuard.TrialDaysProduction());
    end;
}
