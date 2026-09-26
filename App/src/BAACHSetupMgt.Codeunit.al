codeunit 81100 "BAACH Setup Mgt."
{
    var
        LinesInProgressErr: Label 'You cannot turn off %1 while payment journal lines are part-way through the EFT process. Void the EFT file or export the remittances first in these journal batches: %2', Comment = '%1 = the setup field caption, %2 = list of journal template/batch names';

    procedure IsEnabled(): Boolean
    var
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
    begin
        if not PurchasesPayablesSetup.Get() then
            exit(false);
        exit(PurchasesPayablesSetup."BAACH Enable EFT Before Export");
    end;

    procedure IsEnabledForBatch(TemplateName: Code[10]; BatchName: Code[10]): Boolean
    var
        BankAccount: Record "Bank Account";
    begin
        if not IsEnabled() then
            exit(false);
        if not GetBatchBankAccount(TemplateName, BatchName, BankAccount) then
            exit(false);
        exit(IsCustomExportFormat(BankAccount));
    end;

    // Mirrors page 256 SetAMCAppearance: a blank or Other format is AMC and keeps the standard process.
    procedure IsCustomExportFormat(BankAccount: Record "Bank Account"): Boolean
    begin
        exit(BankAccount."Export Format" in [BankAccount."Export Format"::US, BankAccount."Export Format"::CA, BankAccount."Export Format"::MX]);
    end;

    procedure GetBatchBankAccount(TemplateName: Code[10]; BatchName: Code[10]; var BankAccount: Record "Bank Account"): Boolean
    var
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        Clear(BankAccount);
        if not GenJournalBatch.Get(TemplateName, BatchName) then
            exit(false);
        if GenJournalBatch."Bal. Account Type" <> GenJournalBatch."Bal. Account Type"::"Bank Account" then
            exit(false);
        if GenJournalBatch."Bal. Account No." = '' then
            exit(false);
        exit(BankAccount.Get(GenJournalBatch."Bal. Account No."));
    end;

    procedure IsElectronicPayment(GenJournalLine: Record "Gen. Journal Line"): Boolean
    begin
        exit(GenJournalLine."Bank Payment Type" in [GenJournalLine."Bank Payment Type"::"Electronic Payment", GenJournalLine."Bank Payment Type"::"Electronic Payment-IAT"]);
    end;

    procedure IsTargetLine(GenJournalLine: Record "Gen. Journal Line"): Boolean
    begin
        exit(IsElectronicPayment(GenJournalLine) and (GenJournalLine."Amount (LCY)" <> 0));
    end;

    // Prepared by step 1 but the EFT file is not generated yet: the untransmitted EFT Export row
    // that step 1 created is still there. Standard Export never leaves Check Exported = false on such a line.
    procedure IsLinePrepared(GenJournalLine: Record "Gen. Journal Line"): Boolean
    var
        EFTExport: Record "EFT Export";
    begin
        if GenJournalLine."BAACH EFT File Created" or GenJournalLine."Check Exported" then
            exit(false);
        if not (GenJournalLine."Check Printed" and IsElectronicPayment(GenJournalLine)) then
            exit(false);
        if GenJournalLine."EFT Export Sequence No." = 0 then
            exit(false);
        if not EFTExport.Get(GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name", GenJournalLine."Line No.", GenJournalLine."EFT Export Sequence No.") then
            exit(false);
        exit(not EFTExport.Transmitted);
    end;

    // Deliberately wider than IsLinePrepared: any electronic line that step 1 has touched (Check Printed with an
    // EFT Export Sequence No.) but that is not exported counts, even if its EFT Export row is missing or inconsistent.
    procedure IsLineInProgress(GenJournalLine: Record "Gen. Journal Line"): Boolean
    begin
        if GenJournalLine."Check Exported" then
            exit(false);
        if GenJournalLine."BAACH EFT File Created" then
            exit(true);
        exit(GenJournalLine."Check Printed" and IsElectronicPayment(GenJournalLine) and (GenJournalLine."EFT Export Sequence No." <> 0));
    end;

    procedure CheckNoLinesInProgress()
    var
        GenJournalLine: Record "Gen. Journal Line";
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
        Batches: List of [Text];
        BatchText: Text;
        BatchList: Text;
    begin
        GenJournalLine.SetRange("Check Exported", false);
        GenJournalLine.SetRange("Check Printed", true);
        if GenJournalLine.FindSet() then
            repeat
                if IsLineInProgress(GenJournalLine) then begin
                    BatchText := GenJournalLine."Journal Template Name" + '/' + GenJournalLine."Journal Batch Name";
                    if not Batches.Contains(BatchText) then
                        Batches.Add(BatchText);
                end;
            until GenJournalLine.Next() = 0;

        GenJournalLine.SetRange("Check Printed");
        GenJournalLine.SetRange("BAACH EFT File Created", true);
        if GenJournalLine.FindSet() then
            repeat
                BatchText := GenJournalLine."Journal Template Name" + '/' + GenJournalLine."Journal Batch Name";
                if not Batches.Contains(BatchText) then
                    Batches.Add(BatchText);
            until GenJournalLine.Next() = 0;

        if Batches.Count() = 0 then
            exit;

        foreach BatchText in Batches do begin
            if BatchList <> '' then
                BatchList += ', ';
            BatchList += BatchText;
        end;
        Error(LinesInProgressErr, PurchasesPayablesSetup.FieldCaption("BAACH Enable EFT Before Export"), BatchList);
    end;
}
