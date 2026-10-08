// Custom ACH's own licence decision. The licensing app only hands over the raw
// signed token; the signature and claims are checked here, against the keys in
// "BAACH License Verifier", so a stubbed licensing app cannot unlock it.
// Never call it from install or upgrade code.
codeunit 81108 "BAACH License Guard"
{
    Access = Internal;
    SingleInstance = true;

    var
        Verifier: Codeunit "BAACH License Verifier";
        CachedPayload: JsonObject;
        CachedStatus: Enum "BALIC License Status";
        CachedReason: Enum "BALIC Failure Reason";
        CachedExpiresAt: Date;
        CachedAt: DateTime;
        TrialDays: Integer;
        InstalledAtKeyTok: Label 'license.installedAt', Locked = true;
        TelemetryEventTok: Label 'BAACH0001', Locked = true;
        TelemetryMsg: Label 'Custom ACH licence checked', Locked = true;
        NotLicensedErr: Label 'Custom ACH is not licensed in this environment. Licence status: %1. %2 Upload a licence on the Licences page.', Comment = '%1 = licence status, %2 = the reason, a full sentence';
        OpenLicensesTxt: Label 'Open Licences';

    procedure IsLicensed(): Boolean
    begin
        EnsureChecked();
        exit(Verifier.IsUsable(CachedStatus));
    end;

    // Blocks generating and exporting; viewing and voiding stay available.
    procedure CheckLicensed()
    var
        NotLicensedErrorInfo: ErrorInfo;
    begin
        if IsLicensed() then
            exit;
        NotLicensedErrorInfo.Message := StrSubstNo(NotLicensedErr, CachedStatus, CachedReason);
        NotLicensedErrorInfo.PageNo := Page::"BALIC Licenses";
        NotLicensedErrorInfo.AddNavigationAction(OpenLicensesTxt);
        Error(NotLicensedErrorInfo);
    end;

    // A trial runs with every feature; a licence only with the ones in its 'f' claim.
    procedure HasFeature(FeatureCode: Text): Boolean
    begin
        if not IsLicensed() then
            exit(false);
        if CachedStatus = CachedStatus::Trial then
            exit(true);
        exit(Verifier.HasListValue(CachedPayload, 'f', FeatureCode));
    end;

    procedure GetStatus(): Enum "BALIC License Status"
    begin
        EnsureChecked();
        exit(CachedStatus);
    end;

    procedure GetReason(): Enum "BALIC Failure Reason"
    begin
        EnsureChecked();
        exit(CachedReason);
    end;

    procedure GetExpiresAt(): Date
    begin
        EnsureChecked();
        exit(CachedExpiresAt);
    end;

    // Drops the cached answer, so a licence uploaded in this session counts at once.
    procedure Refresh()
    begin
        CachedAt := 0DT;
    end;

    procedure RecordInstallDate()
    begin
        if not IsolatedStorage.Contains(InstalledAtKeyTok, DataScope::Module) then
            IsolatedStorage.Set(InstalledAtKeyTok, Format(Today(), 0, 9), DataScope::Module);
    end;

    procedure TrialDaysProduction(): Integer
    begin
        exit(7);
    end;

    // Re-checked hourly rather than once per session, and never per posting line.
    local procedure EnsureChecked()
    begin
        // Nested because AL's "and" evaluates both sides, and 0DT arithmetic throws.
        if CachedAt <> 0DT then
            if CurrentDateTime() - CachedAt < 3600000 then
                exit;
        DoCheck();
        CachedAt := CurrentDateTime();
    end;

    local procedure DoCheck()
    var
        TokenStore: Codeunit "BALIC Token Store";
        EnvironmentInformation: Codeunit "Environment Information";
        AppInfo: ModuleInfo;
        RawToken: Text;
        HasToken: Boolean;
        TokenValid: Boolean;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        TrialDays := TrialDaysProduction();
        Clear(CachedPayload);
        CachedExpiresAt := 0D;
        CachedReason := CachedReason::NoToken;

        HasToken := TokenStore.TryGetToken(AppInfo.Id(), RawToken);
        if HasToken then
            TokenValid := Verifier.VerifyForCurrentEnvironment(RawToken, AppInfo.Id(), CachedPayload, CachedReason);
        if TokenValid then
            Verifier.GetDateClaim(CachedPayload, 'exp', CachedExpiresAt)
        else
            Clear(CachedPayload);

        CachedStatus := Verifier.ComputeStatus(HasToken, TokenValid, CachedReason, CachedExpiresAt, GetInstalledAt(AppInfo),
            TrialDays, EnvironmentInformation.IsSandbox(), Today());
        LogOutcome(AppInfo, EnvironmentInformation.GetEnvironmentName());
    end;

    // The trial start is kept in this app's own storage: the licensing app's copy
    // is only for display and is not trusted here. An install that predates
    // licensing gets its trial from the first check.
    local procedure GetInstalledAt(AppInfo: ModuleInfo): Date
    var
        TokenStore: Codeunit "BALIC Token Store";
        InstalledAtText: Text;
        InstalledAt: Date;
    begin
        if IsolatedStorage.Get(InstalledAtKeyTok, DataScope::Module, InstalledAtText) then
            if Evaluate(InstalledAt, InstalledAtText, 9) then
                exit(InstalledAt);
        RecordInstallDate();
        TokenStore.RegisterProduct(AppInfo, TrialDaysProduction());
        exit(Today());
    end;

    local procedure LogOutcome(AppInfo: ModuleInfo; EnvironmentName: Text)
    var
        AzureADTenant: Codeunit "Azure AD Tenant";
        Dimensions: Dictionary of [Text, Text];
    begin
        Dimensions.Add('lid', Verifier.GetTextClaim(CachedPayload, 'lid'));
        Dimensions.Add('aid', LowerCase(DelChr(Format(AppInfo.Id()), '=', '{}')));
        Dimensions.Add('tid', AzureADTenant.GetAadTenantId());
        Dimensions.Add('env', EnvironmentName);
        Dimensions.Add('status', Format(CachedStatus));
        Dimensions.Add('reason', CachedReason.Names().Get(CachedReason.Ordinals().IndexOf(CachedReason.AsInteger())));
        Session.LogMessage(TelemetryEventTok, TelemetryMsg, Verbosity::Normal, DataClassification::SystemMetadata,
            TelemetryScope::All, Dimensions);
    end;
}
