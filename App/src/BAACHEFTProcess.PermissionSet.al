permissionset 81100 "BAACH EFT PROCESS"
{
    Assignable = true;
    Caption = 'Custom ACH EFT Process';
    Permissions =
        codeunit "BAACH Setup Mgt." = X,
        codeunit "BAACH Generate EFT" = X,
        codeunit "BAACH EFT Run Scope" = X,
        codeunit "BAACH Export Remittance" = X,
        codeunit "BAACH Remittance Run Scope" = X,
        codeunit "BAACH Void EFT" = X,
        codeunit "BAACH Line Guard" = X,
        page "BAACH Generate EFT Dialog" = X;
}
