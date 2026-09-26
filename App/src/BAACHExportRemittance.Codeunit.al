codeunit 81103 "BAACH Export Remittance"
{
    procedure ExportForBatch(TemplateName: Code[10]; BatchName: Code[10])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeExportRemittance(TemplateName: Code[10]; BatchName: Code[10])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterExportRemittance(TemplateName: Code[10]; BatchName: Code[10])
    begin
    end;
}
