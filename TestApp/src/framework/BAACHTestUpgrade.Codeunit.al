codeunit 81204 "BAACH Test Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerCompany()
    var
        TestInstall: Codeunit "BAACH Test Install";
    begin
        TestInstall.RegisterWebService();
    end;
}
