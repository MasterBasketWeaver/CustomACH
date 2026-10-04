codeunit 81102 "BAACH EFT Run Scope"
{
    EventSubscriberInstance = Manual;

    var
        RunTemplateName: Code[10];
        RunBatchName: Code[10];
        GeneratingFile: Boolean;

    procedure SetBatch(TemplateName: Code[10]; BatchName: Code[10])
    begin
        RunTemplateName := TemplateName;
        RunBatchName := BatchName;
    end;

    procedure SetGeneratingFile()
    begin
        GeneratingFile := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"BAACH Generate EFT", OnIsGeneratingEFTFile, '', false, false)]
    local procedure ReportGeneratingFile(var IsGenerating: Boolean)
    begin
        if GeneratingFile then
            IsGenerating := true;
    end;

    // Step 1 runs before Export, so Check Exported is still false when Generate EFT checks the lines.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Check Line", OnBeforeCheckElectronicPaymentFields, '', false, false)]
    local procedure SkipCheckExportedForRunningBatch(var GenJnlLine: Record "Gen. Journal Line"; var IsHandled: Boolean)
    begin
        if IsRunningBatch(GenJnlLine."Journal Template Name", GenJnlLine."Journal Batch Name") then
            IsHandled := true;
    end;

    // The engine's UpdateEFTExport sets Check Transmitted per detail line. Reverting it here, before the footer's
    // Commit, keeps the line unpostable until Export runs, and commits EFT File Created together with the file.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Exp. Launcher EFT", OnEFTPaymentProcessOnAfterProcessDetailsLoop, '', false, false)]
    local procedure MarkLinesEFTFileCreated(var TempEFTExportWorkset: Record "EFT Export Workset" temporary)
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        if not TempEFTExportWorkset.FindSet() then
            exit;
        repeat
            if IsRunningBatch(TempEFTExportWorkset."Journal Template Name", TempEFTExportWorkset."Journal Batch Name") then
                if GenJournalLine.Get(TempEFTExportWorkset."Journal Template Name", TempEFTExportWorkset."Journal Batch Name", TempEFTExportWorkset."Line No.") then
                    if GenJournalLine."EFT Export Sequence No." = TempEFTExportWorkset."Sequence No." then begin
                        GenJournalLine."BAACH EFT File Created" := true;
                        GenJournalLine."Check Transmitted" := false;
                        GenJournalLine.Modify();
                    end;
        until TempEFTExportWorkset.Next() = 0;
    end;

    local procedure IsRunningBatch(TemplateName: Code[10]; BatchName: Code[10]): Boolean
    begin
        if RunTemplateName = '' then
            exit(false);
        exit((TemplateName = RunTemplateName) and (BatchName = RunBatchName));
    end;
}
