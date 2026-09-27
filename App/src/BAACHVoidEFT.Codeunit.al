codeunit 81105 "BAACH Void EFT"
{
    var
        NotEnabledErr: Label 'The Generate EFT before Export process does not apply to journal batch %1 %2. Use the standard Void action instead.', Comment = '%1 = journal template name, %2 = journal batch name';
        AlreadyExportedErr: Label 'Line %1 in journal batch %2 %3 has already been exported. The EFT file can only be voided before the remittances are exported.', Comment = '%1 = line number, %2 = journal template name, %3 = journal batch name';
        NoEntriesToVoidErr: Label 'There are no entries to void.';

    procedure VoidForBatch(TemplateName: Code[10]; BatchName: Code[10])
    var
        LineNosToVoid: List of [Integer];
        LineNo: Integer;
    begin
        CheckCanVoid(TemplateName, BatchName, LineNosToVoid);
        foreach LineNo in LineNosToVoid do
            VoidLine(TemplateName, BatchName, LineNo);
    end;

    // Lets the page refuse before it asks the user to confirm the void.
    procedure CheckCanVoid(TemplateName: Code[10]; BatchName: Code[10])
    var
        LineNosToVoid: List of [Integer];
    begin
        CheckCanVoid(TemplateName, BatchName, LineNosToVoid);
    end;

    local procedure CheckCanVoid(TemplateName: Code[10]; BatchName: Code[10]; var LineNosToVoid: List of [Integer])
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        BankAccount: Record "Bank Account";
    begin
        CheckEnabled(TemplateName, BatchName);
        GenJournalBatch.Get(TemplateName, BatchName);
        GenJournalBatch.TestField("Bal. Account Type", GenJournalBatch."Bal. Account Type"::"Bank Account");
        BankAccount.Get(GenJournalBatch."Bal. Account No.");
        BankAccount.TestField(Blocked, false);
        BankAccount.TestField("Export Format");

        CheckNoLineExported(TemplateName, BatchName);
        FindLinesToVoid(TemplateName, BatchName, LineNosToVoid);
        if LineNosToVoid.Count() = 0 then
            Error(NoEntriesToVoidErr);
    end;

    local procedure CheckEnabled(TemplateName: Code[10]; BatchName: Code[10])
    var
        SetupMgt: Codeunit "BAACH Setup Mgt.";
    begin
        if not SetupMgt.IsEnabledForBatch(TemplateName, BatchName) then
            Error(NotEnabledErr, TemplateName, BatchName);
    end;

    local procedure CheckNoLineExported(TemplateName: Code[10]; BatchName: Code[10])
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", TemplateName);
        GenJournalLine.SetRange("Journal Batch Name", BatchName);
        GenJournalLine.SetRange("Check Exported", true);
        if GenJournalLine.FindFirst() then
            Error(AlreadyExportedErr, GenJournalLine."Line No.", TemplateName, BatchName);
    end;

    local procedure FindLinesToVoid(TemplateName: Code[10]; BatchName: Code[10]; var LineNosToVoid: List of [Integer])
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", TemplateName);
        GenJournalLine.SetRange("Journal Batch Name", BatchName);
        GenJournalLine.SetFilter("Bank Payment Type", '%1|%2',
            GenJournalLine."Bank Payment Type"::"Electronic Payment", GenJournalLine."Bank Payment Type"::"Electronic Payment-IAT");
        GenJournalLine.SetRange("Check Exported", false);
        if GenJournalLine.FindSet() then
            repeat
                if IsPreparedOrGenerated(GenJournalLine) then
                    LineNosToVoid.Add(GenJournalLine."Line No.");
            until GenJournalLine.Next() = 0;
    end;

    local procedure IsPreparedOrGenerated(GenJournalLine: Record "Gen. Journal Line"): Boolean
    var
        EFTExport: Record "EFT Export";
    begin
        if GenJournalLine."BAACH EFT File Created" or GenJournalLine."Check Printed" or (GenJournalLine."EFT Export Sequence No." <> 0) then
            exit(true);
        FilterEFTExportForLine(EFTExport, GenJournalLine);
        EFTExport.SetRange(Transmitted, false);
        exit(not EFTExport.IsEmpty());
    end;

    local procedure VoidLine(TemplateName: Code[10]; BatchName: Code[10]; LineNo: Integer)
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.Get(TemplateName, BatchName, LineNo);
        if GenJournalLine."Document No." <> '' then
            VoidCheckLedgerEntries(GenJournalLine);
        DeleteEFTExportRows(GenJournalLine);

        // The same resets as report 10084 "Void/Transmit Elec. Payments", plus the flags that step 1 sets.
        GenJournalLine."Check Exported" := false;
        GenJournalLine."Check Printed" := false;
        GenJournalLine."Check Transmitted" := false;
        GenJournalLine."Exported to Payment File" := false;
        GenJournalLine."BAACH EFT File Created" := false;
        GenJournalLine."Document No." := '';
        ClearApplication(GenJournalLine);
        GenJournalLine."EFT Export Sequence No." := 0;
        GenJournalLine.Modify();
    end;

    // ProcessElectronicPayment refuses lines that are not Check Exported or not a Payment/Refund, but step 1 prepares
    // lines without exporting them and, like the standard Export, does not require a document type. The copy is never saved.
    local procedure VoidCheckLedgerEntries(GenJournalLine: Record "Gen. Journal Line")
    var
        GenJournalLineToVoid: Record "Gen. Journal Line";
        CheckManagement: Codeunit CheckManagement;
        WhichProcess: Option ,Void,Transmit;
    begin
        GenJournalLineToVoid := GenJournalLine;
        GenJournalLineToVoid."Check Exported" := true;
        if not (GenJournalLineToVoid."Document Type" in [GenJournalLineToVoid."Document Type"::Payment, GenJournalLineToVoid."Document Type"::Refund]) then
            GenJournalLineToVoid."Document Type" := GenJournalLineToVoid."Document Type"::Payment;
        CheckManagement.ProcessElectronicPayment(GenJournalLineToVoid, WhichProcess::Void);
    end;

    // EFT Export rows are never deleted on posting and journal line numbers are reused, so a transmitted row is
    // deleted only when it is the one this line points to; older transmitted rows belong to payments already posted.
    local procedure DeleteEFTExportRows(GenJournalLine: Record "Gen. Journal Line")
    var
        EFTExport: Record "EFT Export";
    begin
        FilterEFTExportForLine(EFTExport, GenJournalLine);
        if EFTExport.FindSet() then
            repeat
                if not EFTExport.Transmitted or
                   ((GenJournalLine."EFT Export Sequence No." <> 0) and (EFTExport."Sequence No." = GenJournalLine."EFT Export Sequence No."))
                then
                    EFTExport.Delete();
            until EFTExport.Next() = 0;
    end;

    local procedure FilterEFTExportForLine(var EFTExport: Record "EFT Export"; GenJournalLine: Record "Gen. Journal Line")
    begin
        EFTExport.SetRange("Journal Template Name", GenJournalLine."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalLine."Journal Batch Name");
        EFTExport.SetRange("Line No.", GenJournalLine."Line No.");
    end;

    // Mirrors report 10084 ClearApplication. With an Applies-to ID set, IsApplied() is true and nothing changes, so the
    // line and its vendor ledger entries stay applied through the old document number, which the next Generate EFT
    // File re-keys to the new one.
    local procedure ClearApplication(var GenJournalLine: Record "Gen. Journal Line")
    begin
        if (GenJournalLine."Applies-to Doc. Type" <> GenJournalLine."Applies-to Doc. Type"::" ") or GenJournalLine.IsApplied() then
            exit;

        if GenJournalLine."Applies-to ID" <> '' then begin
            GenJournalLine.Validate("Applies-to ID", '');
            GenJournalLine.Validate("Applies-to Doc. No.", '');
        end;
    end;
}
