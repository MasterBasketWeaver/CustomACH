codeunit 81217 "BAACH License Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        LicenseGuard: Codeunit "BAACH License Guard";
        Verifier: Codeunit "BAACH License Verifier";
        EnvironmentInformation: Codeunit "Environment Information";

    // Sandboxes never block: with no licence, or a bad one, they run on the unlimited trial.
    [Test]
    procedure GuardNeverBlocksASandbox()
    begin
        if not EnvironmentInformation.IsSandbox() then
            exit;
        LicenseGuard.Refresh();
        Assert.IsTrue(LicenseGuard.IsLicensed(), StrSubstNo('IsLicensed in a sandbox, status %1.', LicenseGuard.GetStatus()));
        LicenseGuard.CheckLicensed();
    end;

    [Test]
    procedure GuardStatusInASandboxIsUsable()
    var
        Status: Enum "BALIC License Status";
    begin
        if not EnvironmentInformation.IsSandbox() then
            exit;
        LicenseGuard.Refresh();
        Status := LicenseGuard.GetStatus();
        Assert.IsTrue(Status in [Status::Trial, Status::Active, Status::Expiring], StrSubstNo('Sandbox status %1.', Status));
    end;

    [Test]
    procedure TrialEndsOnDayEightInProduction()
    var
        Status: Enum "BALIC License Status";
        Reason: Enum "BALIC Failure Reason";
    begin
        Assert.AreEqual(Status::Trial, Verifier.ComputeStatus(false, false, Reason::NoToken, 0D, WorkDate() - 6, 7, false, WorkDate()), 'Day 7.');
        Assert.AreEqual(Status::Expired, Verifier.ComputeStatus(false, false, Reason::NoToken, 0D, WorkDate() - 7, 7, false, WorkDate()), 'Day 8.');
    end;

    [Test]
    procedure ProductionWithoutInstallDateIsTrial()
    var
        Status: Enum "BALIC License Status";
        Reason: Enum "BALIC Failure Reason";
    begin
        Assert.AreEqual(Status::Trial, Verifier.ComputeStatus(false, false, Reason::NoToken, 0D, 0D, 7, false, WorkDate()), 'No install date.');
    end;

    [Test]
    procedure ValidLicenceStatusFollowsExpiry()
    var
        Status: Enum "BALIC License Status";
        Reason: Enum "BALIC Failure Reason";
    begin
        Assert.AreEqual(Status::Active, Verifier.ComputeStatus(true, true, Reason::None, WorkDate() + 31, 0D, 7, false, WorkDate()), 'T-31.');
        Assert.AreEqual(Status::Expiring, Verifier.ComputeStatus(true, true, Reason::None, WorkDate() + 30, 0D, 7, false, WorkDate()), 'T-30.');
        Assert.AreEqual(Status::Grace, Verifier.ComputeStatus(true, true, Reason::None, WorkDate() - 1, 0D, 7, false, WorkDate()), 'Production, one day past expiry.');
    end;

    [Test]
    procedure RejectsATokenThatIsNotSigned()
    var
        Payload: JsonObject;
        Reason: Enum "BALIC Failure Reason";
    begin
        Assert.IsFalse(Verifier.VerifyForCurrentEnvironment('eyJ2IjoxLCJraWQiOjF9.AAAA', CurrentAppId(), Payload, Reason), 'An unsigned token must not verify.');
        Assert.AreEqual(Reason::BadSignature, Reason, 'Reason for an unsigned token.');
        Assert.IsFalse(Verifier.VerifyForCurrentEnvironment('not a token', CurrentAppId(), Payload, Reason), 'Garbage must not verify.');
        Assert.AreEqual(Reason::Malformed, Reason, 'Reason for garbage.');
    end;

    local procedure CurrentAppId(): Guid
    var
        AppId: Guid;
    begin
        Evaluate(AppId, 'a42f1852-a8b3-4587-b855-e470f4431838');
        exit(AppId);
    end;
}
