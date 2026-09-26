codeunit 81106 "BAACH Line Guard"
{
    var
        LineLockedErr: Label 'You cannot change or delete journal line %1 in %2 %3 because it has EFT File Created. Void the EFT file first or export the remittances.', Comment = '%1 = line no., %2 = journal template name, %3 = journal batch name';

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnBeforeModifyEvent, '', false, false)]
    local procedure OnBeforeModifyGenJournalLine(var Rec: Record "Gen. Journal Line"; var xRec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        CheckStoredLine(Rec, RunTrigger);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnBeforeDeleteEvent, '', false, false)]
    local procedure OnBeforeDeleteGenJournalLine(var Rec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        CheckStoredLine(Rec, RunTrigger);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnBeforeRenameEvent, '', false, false)]
    local procedure OnBeforeRenameGenJournalLine(var Rec: Record "Gen. Journal Line"; var xRec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        CheckStoredLine(xRec, RunTrigger);
    end;

    // Reads the stored line: the in-memory record may already carry changed values, and posting and the
    // custom process itself write with trigger-less Modify/DeleteAll, which never reach this check.
    local procedure CheckStoredLine(GenJournalLine: Record "Gen. Journal Line"; RunTrigger: Boolean)
    var
        StoredLine: Record "Gen. Journal Line";
        SetupMgt: Codeunit "BAACH Setup Mgt.";
    begin
        if not RunTrigger then
            exit;
        if GenJournalLine.IsTemporary() then
            exit;
        if not SetupMgt.IsEnabled() then
            exit;
        if not StoredLine.Get(GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name", GenJournalLine."Line No.") then
            exit;
        if not StoredLine."BAACH EFT File Created" then
            exit;
        Error(LineLockedErr, StoredLine."Line No.", StoredLine."Journal Template Name", StoredLine."Journal Batch Name");
    end;
}
