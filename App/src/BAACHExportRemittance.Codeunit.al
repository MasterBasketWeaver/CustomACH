codeunit 81103 "BAACH Export Remittance"
{
    var
        NotEnabledErr: Label 'The Generate EFT before Export process does not apply to journal batch %1 %2. Turn on Enable EFT Generate before Export in Purchases & Payables Setup and use a batch whose bank account has Export Format US, CA or MX.', Comment = '%1 = journal template name, %2 = journal batch name';
        VendRemittanceReportSelectionErr: Label 'You must add at least one Vendor Remittance report to the report selection.';
        GenerateEFTFirstErr: Label 'Generate the EFT file first. Line %1 in journal batch %2 %3 does not have an EFT file yet.', Comment = '%1 = line number, %2 = journal template name, %3 = journal batch name';
        NothingToExportErr: Label 'There is nothing to export in journal batch %1 %2. The remittances for every line with an EFT file have already been exported.', Comment = '%1 = journal template name, %2 = journal batch name';
        LineBankMismatchErr: Label 'Line %1 is paid from bank account %2, but journal batch %3 %4 pays from bank account %5.', Comment = '%1 = line number, %2 = bank account on the line, %3 = journal template name, %4 = journal batch name, %5 = bank account on the batch';
        OutputFileBaseNameTxt: Label 'Remittance Advice';

    procedure ExportForBatch(TemplateName: Code[10]; BatchName: Code[10])
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ReportSelections: Record "Report Selections";
        GenJournalLine: Record "Gen. Journal Line";
        RecordRestrictionMgt: Codeunit "Record Restriction Mgt.";
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";
        GenJournalLineRecRef: RecordRef;
        JoinFieldName: Text;
        JoinTableNo: Integer;
    begin
        CheckEnabled(TemplateName, BatchName);
        GenJournalBatch.Get(TemplateName, BatchName);
        GenJournalBatch.TestField("Bal. Account Type", GenJournalBatch."Bal. Account Type"::"Bank Account");
        GenJournalBatch.TestField("Bal. Account No.");
        RecordRestrictionMgt.GenJournalBatchCheckGenJournalLineExportRestrictions(GenJournalBatch);
        CheckReportSelectionsExists();
        CheckAllLinesHaveEFTFile(TemplateName, BatchName);

        FilterLinesToExport(GenJournalLine, TemplateName, BatchName, GenJournalBatch."Bal. Account No.");
        GetJoinFields(GenJournalLine, JoinFieldName, JoinTableNo);

        OnBeforeExportRemittance(TemplateName, BatchName);

        GenJournalLineRecRef.GetTable(GenJournalLine);
        GenJournalLineRecRef.SetView(GenJournalLine.GetView());

        RemittanceRunScope.SetBatch(TemplateName, BatchName, GenJournalBatch."Bal. Account No.");
        BindSubscription(RemittanceRunScope);
        CustomLayoutReporting.SetRunReportOncePerFilter(true);
        CustomLayoutReporting.SetOutputFileBaseName(OutputFileBaseNameTxt);
        CustomLayoutReporting.ProcessReportData(
            ReportSelections.Usage::"V.Remittance", GenJournalLineRecRef, JoinFieldName, JoinTableNo, 'No.', false);
        UnbindSubscription(RemittanceRunScope);

        OnAfterExportRemittance(TemplateName, BatchName);
    end;

    local procedure CheckEnabled(TemplateName: Code[10]; BatchName: Code[10])
    var
        SetupMgt: Codeunit "BAACH Setup Mgt.";
    begin
        if not SetupMgt.IsEnabledForBatch(TemplateName, BatchName) then
            Error(NotEnabledErr, TemplateName, BatchName);
    end;

    local procedure CheckReportSelectionsExists()
    var
        ReportSelections: Record "Report Selections";
    begin
        ReportSelections.SetRange(Usage, ReportSelections.Usage::"V.Remittance");
        ReportSelections.SetFilter("Report ID", '<>0');
        if ReportSelections.IsEmpty() then
            Error(VendRemittanceReportSelectionErr);
    end;

    local procedure CheckAllLinesHaveEFTFile(TemplateName: Code[10]; BatchName: Code[10])
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", TemplateName);
        GenJournalLine.SetRange("Journal Batch Name", BatchName);
        GenJournalLine.SetFilter("Bank Payment Type", '%1|%2',
            GenJournalLine."Bank Payment Type"::"Electronic Payment", GenJournalLine."Bank Payment Type"::"Electronic Payment-IAT");
        GenJournalLine.SetFilter("Amount (LCY)", '<>0');
        GenJournalLine.SetRange("BAACH EFT File Created", false);
        if GenJournalLine.FindFirst() then
            Error(GenerateEFTFirstErr, GenJournalLine."Line No.", TemplateName, BatchName);
    end;

    // The report data is filtered on Line No. rather than on Check Transmitted, because the run scope sets
    // Check Transmitted while the engine is still iterating and running reports over these lines.
    local procedure FilterLinesToExport(var GenJournalLine: Record "Gen. Journal Line"; TemplateName: Code[10]; BatchName: Code[10]; BatchBankAccountNo: Code[20])
    var
        LineNoFilter: Text;
        RangeStart: Integer;
        RangeEnd: Integer;
    begin
        GenJournalLine.SetRange("Journal Template Name", TemplateName);
        GenJournalLine.SetRange("Journal Batch Name", BatchName);
        RangeStart := 0;
        RangeEnd := 0;
        if GenJournalLine.FindSet() then
            repeat
                if GenJournalLine."BAACH EFT File Created" and not GenJournalLine."Check Transmitted" then begin
                    CheckLineBankAccount(GenJournalLine, BatchBankAccountNo);
                    if RangeStart = 0 then
                        RangeStart := GenJournalLine."Line No.";
                    RangeEnd := GenJournalLine."Line No.";
                end else
                    AddLineNoRange(LineNoFilter, RangeStart, RangeEnd);
            until GenJournalLine.Next() = 0;
        AddLineNoRange(LineNoFilter, RangeStart, RangeEnd);

        if LineNoFilter = '' then
            Error(NothingToExportErr, TemplateName, BatchName);

        GenJournalLine.SetFilter("Line No.", LineNoFilter);
        GenJournalLine.FindFirst();
    end;

    local procedure AddLineNoRange(var LineNoFilter: Text; var RangeStart: Integer; var RangeEnd: Integer)
    begin
        if RangeStart = 0 then
            exit;
        if LineNoFilter <> '' then
            LineNoFilter += '|';
        if RangeStart = RangeEnd then
            LineNoFilter += Format(RangeStart, 0, 9)
        else
            LineNoFilter += Format(RangeStart, 0, 9) + '..' + Format(RangeEnd, 0, 9);
        RangeStart := 0;
        RangeEnd := 0;
    end;

    local procedure CheckLineBankAccount(GenJournalLine: Record "Gen. Journal Line"; BatchBankAccountNo: Code[20])
    var
        LineBankAccountNo: Code[20];
    begin
        if GenJournalLine."Account Type" = GenJournalLine."Account Type"::"Bank Account" then
            LineBankAccountNo := GenJournalLine."Account No."
        else
            LineBankAccountNo := GenJournalLine."Bal. Account No.";
        if LineBankAccountNo <> BatchBankAccountNo then
            Error(LineBankMismatchErr, GenJournalLine."Line No.", LineBankAccountNo,
                GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name", BatchBankAccountNo);
    end;

    // Same join as codeunit 10250 "Bulk Vendor Remit Reporting".RunWithRecord, taken from the first line.
    local procedure GetJoinFields(GenJournalLine: Record "Gen. Journal Line"; var JoinFieldName: Text; var JoinTableNo: Integer)
    begin
        case GenJournalLine."Bal. Account Type" of
            GenJournalLine."Bal. Account Type"::Vendor:
                begin
                    JoinFieldName := GenJournalLine.FieldName("Bal. Account No.");
                    JoinTableNo := Database::Vendor;
                end;
            GenJournalLine."Bal. Account Type"::Customer:
                begin
                    JoinFieldName := GenJournalLine.FieldName("Bal. Account No.");
                    JoinTableNo := Database::Customer;
                end;
            GenJournalLine."Bal. Account Type"::"Bank Account":
                case GenJournalLine."Account Type" of
                    GenJournalLine."Account Type"::Customer:
                        begin
                            JoinFieldName := GenJournalLine.FieldName("Account No.");
                            JoinTableNo := Database::Customer;
                        end;
                    GenJournalLine."Account Type"::Vendor:
                        begin
                            JoinFieldName := GenJournalLine.FieldName("Account No.");
                            JoinTableNo := Database::Vendor;
                        end;
                    else
                        GenJournalLine.FieldError("Account Type");
                end;
            else
                GenJournalLine.FieldError("Bal. Account No.");
        end;
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
