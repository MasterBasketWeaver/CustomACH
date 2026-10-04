// ACHCustom (Eagle Eye's PTE) adds one to "Entry Addenda Count" on every batch and file control record, to count
// the offset entry that its Bank of Commerce format writes as a footer line. Formats without that line end up one
// over. Subscribers on the same event run in no fixed order, so the count is restored in the footer's
// OnBeforeModifyEvent, which always runs after ACHCustom's subscribers.
codeunit 81300 "BAACH EE Entry Count"
{
    SingleInstance = true;
    Access = Internal;

    var
        BAACHGenerateEFT: Codeunit "BAACH Generate EFT";
        EntryCounts: Dictionary of [Code[20], Integer];

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Export EFT (ACH)", OnStartExportFileOnBeforeACHUSHeaderModify, '', false, false)]
    local procedure ResetEntryCount(var ACHUSHeader: Record "ACH US Header"; BankAccount: Record "Bank Account")
    begin
        if not BAACHGenerateEFT.IsGeneratingEFTFile() then
            exit;
        EntryCounts.Set(DataExchDefCode(ACHUSHeader."Data Exch. Entry No."), 0);
    end;

    // Fires once per entry detail record, where the standard engine increments its own count.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Export EFT (ACH)", OnBeforeACHUSDetailModify, '', false, false)]
    local procedure CountEntry(var ACHUSDetail: Record "ACH US Detail"; var TempEFTExportWorkset: Record "EFT Export Workset" temporary; BankAccNo: Code[20])
    var
        DefCode: Code[20];
    begin
        if not BAACHGenerateEFT.IsGeneratingEFTFile() then
            exit;
        DefCode := DataExchDefCode(ACHUSDetail."Data Exch. Entry No.");
        if EntryCounts.ContainsKey(DefCode) then
            EntryCounts.Set(DefCode, EntryCounts.Get(DefCode) + 1);
    end;

    [EventSubscriber(ObjectType::Table, Database::"ACH US Footer", OnBeforeModifyEvent, '', false, false)]
    local procedure RestoreEntryCount(var Rec: Record "ACH US Footer"; var xRec: Record "ACH US Footer"; RunTrigger: Boolean)
    var
        DefCode: Code[20];
        EntryCount: Integer;
    begin
        if Rec.IsTemporary() then
            exit;
        if (Rec."Batch Record Type" <> 8) and (Rec."File Record Type" <> 9) then
            exit;
        if not BAACHGenerateEFT.IsGeneratingEFTFile() then
            exit;
        DefCode := DataExchDefCode(Rec."Data Exch. Entry No.");
        if not EntryCounts.Get(DefCode, EntryCount) then
            exit;
        if WritesEntryAsFooter(DefCode) then
            exit;
        Rec."Entry Addenda Count" := EntryCount;
    end;

    local procedure DataExchDefCode(DataExchEntryNo: Integer): Code[20]
    var
        DataExch: Record "Data Exch.";
    begin
        if DataExch.Get(DataExchEntryNo) then
            exit(DataExch."Data Exch. Def Code");
    end;

    // An entry detail record (type 6) defined as a footer line, like Bank of Commerce's offset entry, is not counted
    // by the standard engine, so ACHCustom's extra count is right for such a format.
    local procedure WritesEntryAsFooter(DefCode: Code[20]): Boolean
    var
        DataExchLineDef: Record "Data Exch. Line Def";
        DataExchColumnDef: Record "Data Exch. Column Def";
    begin
        DataExchLineDef.SetRange("Data Exch. Def Code", DefCode);
        DataExchLineDef.SetRange("Line Type", DataExchLineDef."Line Type"::Footer);
        if DataExchLineDef.FindSet() then
            repeat
                DataExchColumnDef.SetRange("Data Exch. Def Code", DefCode);
                DataExchColumnDef.SetRange("Data Exch. Line Def Code", DataExchLineDef.Code);
                if DataExchColumnDef.FindFirst() then
                    if DataExchColumnDef.Constant = '6' then
                        exit(true);
            until DataExchLineDef.Next() = 0;
        exit(false);
    end;
}
