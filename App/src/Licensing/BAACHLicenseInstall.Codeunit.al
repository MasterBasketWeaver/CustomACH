codeunit 81109 "BAACH License Install"
{
    Subtype = Install;

    trigger OnInstallAppPerDatabase()
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
