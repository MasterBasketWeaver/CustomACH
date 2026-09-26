codeunit 81203 "BAACH Test Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    begin
        RegisterWebService();
    end;

    internal procedure RegisterWebService()
    var
        TenantWebService: Record "Tenant Web Service";
        WebServiceManagement: Codeunit "Web Service Management";
    begin
        TenantWebService.SetRange("Object Type", TenantWebService."Object Type"::Codeunit);
        TenantWebService.SetRange("Object ID", Codeunit::"BAACH Run Tests");
        if not TenantWebService.IsEmpty() then
            exit;
        WebServiceManagement.CreateTenantWebService(TenantWebService."Object Type"::Codeunit, Codeunit::"BAACH Run Tests", ServiceNameLbl, true);
    end;

    var
        ServiceNameLbl: Label 'BAACHRunTests', Locked = true;
}
