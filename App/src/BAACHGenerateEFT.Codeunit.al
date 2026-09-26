codeunit 81101 "BAACH Generate EFT"
{
    procedure GenerateForBatch(TemplateName: Code[10]; BatchName: Code[10]; SettlementDate: Date)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenerateEFT(TemplateName: Code[10]; BatchName: Code[10]; SettlementDate: Date)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPrepareLine(var GenJournalLine: Record "Gen. Journal Line"; var EFTExport: Record "EFT Export")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGenerateEFT(TemplateName: Code[10]; BatchName: Code[10]; SettlementDate: Date)
    begin
    end;
}
