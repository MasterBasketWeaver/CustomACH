// SOAP entry point, published as BAACHRunTests by "BAACH Test Install" and driven by run_tests.py.
codeunit 81202 "BAACH Run Tests"
{
    var
        Suite: Codeunit "BAACH Suite";
        TestResults: Codeunit "BAACH Test Results";
        DefaultDefResourceTok: Label 'TANAGER-AMEGY.xml', Locked = true;

    procedure RunAll(): Text
    begin
        TestResults.Initialize();
        exit(RunSuite());
    end;

    procedure RunOneCodeunit(CodeunitId: Integer): Text
    begin
        TestResults.Initialize();
        TestResults.AddCodeunitFilter(CodeunitId);
        exit(RunSuite());
    end;

    // Runs one codeunit with the fixtures importing another definition resource, e.g. 'TANAGER-AMEGY.xml'.
    procedure RunOneCodeunitWithDef(CodeunitId: Integer; DefResource: Text): Text
    begin
        TestResults.Initialize();
        TestResults.AddCodeunitFilter(CodeunitId);
        TestResults.SetDataExchDefResource(DefResource);
        exit(RunSuite());
    end;

    // Imports a definition exported with ExportDataExchDef into this company and commits it. An existing
    // definition with the same code is left untouched.
    procedure ImportDataExchDef(DefinitionXml: Text): Text
    var
        DataExchDef: Record "Data Exch. Def";
        TempBlob: Codeunit "Temp Blob";
        ImportStream: InStream;
        ImportOutStream: OutStream;
        XmlDoc: XmlDocument;
        DefNode: XmlNode;
        CodeAttribute: XmlAttribute;
        DefCode: Text;
    begin
        XmlDocument.ReadFrom(DefinitionXml, XmlDoc);
        XmlDoc.SelectSingleNode('/root/DataExchDef', DefNode);
        DefNode.AsXmlElement().Attributes().Get('Code', CodeAttribute);
        DefCode := CodeAttribute.Value();
        if DataExchDef.Get(CopyStr(DefCode, 1, MaxStrLen(DataExchDef.Code))) then
            exit('exists: ' + DefCode);

        TempBlob.CreateOutStream(ImportOutStream, TextEncoding::UTF8);
        XmlDoc.WriteTo(ImportOutStream);
        TempBlob.CreateInStream(ImportStream, TextEncoding::UTF8);
        Xmlport.Import(Xmlport::"Imp / Exp Data Exch Def & Map", ImportStream);
        Commit();
        DataExchDef.Get(CopyStr(DefCode, 1, MaxStrLen(DataExchDef.Code)));
        exit('imported: ' + DefCode);
    end;

    // Custom ACH's own licence verdict in this environment, re-checked now rather than from the hourly cache.
    procedure GetLicenseStatus() Result: Text
    var
        LicenseGuard: Codeunit "BAACH License Guard";
        EnvironmentInformation: Codeunit "Environment Information";
        Status: JsonObject;
    begin
        LicenseGuard.Refresh();
        Status.Add('licensed', LicenseGuard.IsLicensed());
        Status.Add('status', Format(LicenseGuard.GetStatus()));
        Status.Add('reason', Format(LicenseGuard.GetReason()));
        Status.Add('expiresAt', Format(LicenseGuard.GetExpiresAt(), 0, 9));
        Status.Add('environment', EnvironmentInformation.GetEnvironmentName());
        Status.Add('isSandbox', EnvironmentInformation.IsSandbox());
        Status.WriteTo(Result);
    end;

    // Read-only: what Export would hand the V.Remittance reports for a batch, using the calling user's saved request
    // page values, plus a Report.SaveAs dry run, so "No data exists" can be traced without exporting anything.
    procedure GetExportDiagnostics(TemplateName: Text; BatchName: Text) Result: Text
    var
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalLine: Record "Gen. Journal Line";
        ReportSelections: Record "Report Selections";
        CustomReportSelection: Record "Custom Report Selection";
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
        RequestPageParametersHelper: Codeunit "Request Page Parameters Helper";
        TempBlob: Codeunit "Temp Blob";
        ParamsOutStream: OutStream;
        ReportOutStream: OutStream;
        ReportInStream: InStream;
        DataRecRef: RecordRef;
        RequestRecRef: RecordRef;
        Diagnostics: JsonObject;
        Lines: JsonArray;
        Selections: JsonArray;
        Reports: JsonArray;
        Entry: JsonObject;
        SavedParameters: Text;
        ReportXml: Text;
        LineNoFilter: Text;
        Saved: Boolean;
    begin
        if GenJournalTemplate.Get(CopyStr(TemplateName, 1, MaxStrLen(GenJournalTemplate.Name))) then
            Diagnostics.Add('forceDocBalance', GenJournalTemplate."Force Doc. Balance");
        Diagnostics.Add('userId', UserId());

        GenJournalLine.SetRange("Journal Template Name", CopyStr(TemplateName, 1, 10));
        GenJournalLine.SetRange("Journal Batch Name", CopyStr(BatchName, 1, 10));
        if GenJournalLine.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('lineNo', GenJournalLine."Line No.");
                Entry.Add('documentType', Format(GenJournalLine."Document Type"));
                Entry.Add('documentNo', GenJournalLine."Document No.");
                Entry.Add('accountType', Format(GenJournalLine."Account Type"));
                Entry.Add('accountNo', GenJournalLine."Account No.");
                Entry.Add('balAccountType', Format(GenJournalLine."Bal. Account Type"));
                Entry.Add('balAccountNo', GenJournalLine."Bal. Account No.");
                Entry.Add('bankPaymentType', Format(GenJournalLine."Bank Payment Type"));
                Entry.Add('checkPrinted', GenJournalLine."Check Printed");
                Entry.Add('checkExported', GenJournalLine."Check Exported");
                Entry.Add('checkTransmitted', GenJournalLine."Check Transmitted");
                Entry.Add('eftFileCreated', GenJournalLine."BAACH EFT File Created");
                Entry.Add('appliesToId', GenJournalLine."Applies-to ID");
                Entry.Add('appliesToDocNo', GenJournalLine."Applies-to Doc. No.");
                Entry.Add('remitToCode', GenJournalLine."Remit-to Code");
                Lines.Add(Entry);
                if GenJournalLine."BAACH EFT File Created" and not GenJournalLine."Check Transmitted" then begin
                    if LineNoFilter <> '' then
                        LineNoFilter += '|';
                    LineNoFilter += Format(GenJournalLine."Line No.", 0, 9);
                end;
            until GenJournalLine.Next() = 0;
        Diagnostics.Add('lines', Lines);
        Diagnostics.Add('exportLineNoFilter', LineNoFilter);

        CustomReportSelection.SetRange(Usage, CustomReportSelection.Usage::"V.Remittance");
        if CustomReportSelection.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('sourceType', CustomReportSelection."Source Type");
                Entry.Add('sourceNo', CustomReportSelection."Source No.");
                Entry.Add('reportId', CustomReportSelection."Report ID");
                Entry.Add('customReportLayoutCode', CustomReportSelection."Custom Report Layout Code");
                Entry.Add('emailAttachmentLayoutName', CustomReportSelection."Email Attachment Layout Name");
                Entry.Add('sendToEmailSet', CustomReportSelection."Send To Email" <> '');
                Selections.Add(Entry);
            until CustomReportSelection.Next() = 0;
        Diagnostics.Add('customReportSelections', Selections);

        ReportSelections.SetRange(Usage, ReportSelections.Usage::"V.Remittance");
        ReportSelections.SetFilter("Report ID", '<>0');
        if ReportSelections.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('reportId', ReportSelections."Report ID");
                SavedParameters := CustomLayoutReporting.GetReportRequestPageParameters(ReportSelections."Report ID");
                Entry.Add('savedParameters', SavedParameters);

                GenJournalLine.Reset();
                GenJournalLine.SetRange("Journal Template Name", CopyStr(TemplateName, 1, 10));
                GenJournalLine.SetRange("Journal Batch Name", CopyStr(BatchName, 1, 10));
                if LineNoFilter <> '' then
                    GenJournalLine.SetFilter("Line No.", LineNoFilter);
                DataRecRef.GetTable(GenJournalLine);
                DataRecRef.SetView(GenJournalLine.GetView());

                if SavedParameters <> '' then begin
                    Clear(TempBlob);
                    TempBlob.CreateOutStream(ParamsOutStream, TextEncoding::UTF8);
                    ParamsOutStream.WriteText(SavedParameters);
                    RequestRecRef.Open(Database::"Gen. Journal Line");
                    RequestPageParametersHelper.ConvertParametersToFilters(RequestRecRef, TempBlob, TextEncoding::UTF8);
                    Entry.Add('requestPageView', RequestRecRef.GetView());
                    DataRecRef.FilterGroup(10);
                    DataRecRef.SetView(RequestRecRef.GetView());
                    DataRecRef.FilterGroup(0);
                    RequestRecRef.Close();
                end;
                Entry.Add('linesMatchingExportAndRequestPage', DataRecRef.Count());
                DataRecRef.Close();

                RemittanceRunScope.SetBatch(CopyStr(TemplateName, 1, 10), CopyStr(BatchName, 1, 10), BatchBankAccountNo(TemplateName, BatchName));
                RemittanceRunScope.PrefillRequestParameters(ReportSelections."Report ID", SavedParameters);
                Entry.Add('prefilledParameters', SavedParameters);
                DataRecRef.GetTable(GenJournalLine);
                DataRecRef.SetView(GenJournalLine.GetView());
                Clear(TempBlob);
                TempBlob.CreateOutStream(ParamsOutStream, TextEncoding::UTF8);
                ParamsOutStream.WriteText(SavedParameters);
                RequestRecRef.Open(Database::"Gen. Journal Line");
                RequestPageParametersHelper.ConvertParametersToFilters(RequestRecRef, TempBlob, TextEncoding::UTF8);
                DataRecRef.FilterGroup(10);
                DataRecRef.SetView(RequestRecRef.GetView());
                DataRecRef.FilterGroup(0);
                RequestRecRef.Close();
                Entry.Add('linesMatchingAfterPrefill', DataRecRef.Count());

                Clear(TempBlob);
                TempBlob.CreateOutStream(ReportOutStream, TextEncoding::UTF8);
                ClearLastError();
                Saved := Report.SaveAs(ReportSelections."Report ID", SavedParameters, ReportFormat::Xml, ReportOutStream, DataRecRef);
                Entry.Add('saveAsSucceeded', Saved);
                Entry.Add('saveAsError', GetLastErrorText());
                Entry.Add('saveAsCallStack', GetLastErrorCallStack());
                TempBlob.CreateInStream(ReportInStream, TextEncoding::UTF8);
                ReportInStream.Read(ReportXml);
                Entry.Add('reportXmlLength', StrLen(ReportXml));
                Entry.Add('reportXmlHead', CopyStr(ReportXml, 1, 3000));
                DataRecRef.Close();
                Reports.Add(Entry);
            until ReportSelections.Next() = 0;
        Diagnostics.Add('reports', Reports);
        Diagnostics.WriteTo(Result);
    end;

    local procedure BatchBankAccountNo(TemplateName: Text; BatchName: Text): Code[20]
    var
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        if GenJournalBatch.Get(CopyStr(TemplateName, 1, 10), CopyStr(BatchName, 1, 10)) then
            exit(GenJournalBatch."Bal. Account No.");
    end;

    procedure GetSuiteCodeunits(): Text
    begin
        exit(Suite.ToJson());
    end;

    // What the fixtures borrow from the company, so a failing fixture can be told apart from a failing test.
    procedure GetEnvironmentSummary() Result: Text
    var
        CompanyInformation: Record "Company Information";
        GeneralLedgerSetup: Record "General Ledger Setup";
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
        SourceCodeSetup: Record "Source Code Setup";
        Summary: JsonObject;
    begin
        CompanyInformation.Get();
        Summary.Add('company', CompanyName());
        Summary.Add('countryRegionCode', CompanyInformation."Country/Region Code");
        Summary.Add('federalIdNoSet', CompanyInformation."Federal ID No." <> '');
        Summary.Add('workDate', Format(WorkDate(), 0, 9));

        GeneralLedgerSetup.Get();
        Summary.Add('lcyCode', GeneralLedgerSetup."LCY Code");
        Summary.Add('allowPostingFrom', Format(GeneralLedgerSetup."Allow Posting From", 0, 9));
        Summary.Add('allowPostingTo', Format(GeneralLedgerSetup."Allow Posting To", 0, 9));
        Summary.Add('journalTemplNameMandatory', GeneralLedgerSetup."Journal Templ. Name Mandatory");

        if PurchasesPayablesSetup.Get() then
            Summary.Add('switchEnabled', PurchasesPayablesSetup."BAACH Enable EFT Before Export");
        if SourceCodeSetup.Get() then
            Summary.Add('paymentJournalSourceCode', SourceCodeSetup."Payment Journal");

        Summary.Add('postingSetup', PostingSetupSummary());
        Summary.Add('vendorRemittanceReports', VendorRemittanceReports());
        Summary.Add('eftDataExchDefs', EFTDataExchDefs());
        Summary.Add('usEFTDataExchDefExists', USEFTDataExchDefExists());
        Summary.Add('eftExportSetups', EFTExportSetups());
        Summary.Add('bankAccounts', BankAccounts());
        Summary.Add('resourceDataExchDefCode', ResourceDataExchDefCode());
        Summary.WriteTo(Result);
    end;

    // Commits a payment batch with two applied vendor payments for a web client walkthrough, and leaves the
    // switch off so the walkthrough starts from standard behaviour. Unlike the tests, nothing is rolled back.
    procedure CreateUIScenario() Result: Text
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Library: Codeunit "BAACH Library";
        Scenario: JsonObject;
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 1250.75, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 480.1, false);
        Library.SetSwitch(false);
        Commit();

        Scenario.Add('template', GenJournalBatch."Journal Template Name");
        Scenario.Add('batch', GenJournalBatch.Name);
        Scenario.Add('bankAccount', BankAccount."No.");
        Scenario.Add('lastRemittanceAdviceNo', BankAccount."Last Remittance Advice No.");
        Scenario.WriteTo(Result);
    end;

    // Captures a definition as a Test App resource (TestApp/resources/*.xml) from a company that has it.
    procedure ExportDataExchDef("Code": Text) Result: Text
    var
        DataExchDef: Record "Data Exch. Def";
        TempBlob: Codeunit "Temp Blob";
        ExportStream: OutStream;
        ReadStream: InStream;
        Line: Text;
    begin
        DataExchDef.SetRange(Code, CopyStr("Code", 1, MaxStrLen(DataExchDef.Code)));
        DataExchDef.FindFirst();
        TempBlob.CreateOutStream(ExportStream, TextEncoding::UTF8);
        Xmlport.Export(Xmlport::"Imp / Exp Data Exch Def & Map", ExportStream, DataExchDef);
        TempBlob.CreateInStream(ReadStream, TextEncoding::UTF8);
        while not ReadStream.EOS() do begin
            ReadStream.ReadText(Line);
            if Result <> '' then
                Result += NewLine();
            Result += Line;
        end;
    end;

    local procedure RunSuite(): Text
    begin
        if not Codeunit.Run(Codeunit::"BAACH Test Runner") then
            TestResults.SetRunnerError(GetLastErrorText());
        exit(TestResults.ToJson());
    end;

    local procedure PostingSetupSummary() Setup: JsonObject
    var
        SourceVendor: Record Vendor;
        Library: Codeunit "BAACH Library";
    begin
        if TryFindSourceVendor(SourceVendor) then begin
            Setup.Add('sourceVendor', SourceVendor."No.");
            Setup.Add('vendorPostingGroup', SourceVendor."Vendor Posting Group");
            Setup.Add('genBusPostingGroup', SourceVendor."Gen. Bus. Posting Group");
        end else
            Setup.Add('sourceVendorError', GetLastErrorText());
        if TryExpenseGLAccount() then
            Setup.Add('invoiceGLAccount', Library.ExpenseGLAccountNo())
        else
            Setup.Add('invoiceGLAccountError', GetLastErrorText());
        if TryBankAccPostingGroup() then
            Setup.Add('bankAccPostingGroup', Library.BankAccPostingGroupCode())
        else
            Setup.Add('bankAccPostingGroupError', GetLastErrorText());
    end;

    [TryFunction]
    local procedure TryFindSourceVendor(var SourceVendor: Record Vendor)
    var
        Library: Codeunit "BAACH Library";
    begin
        Library.FindSourceVendor(SourceVendor);
    end;

    [TryFunction]
    local procedure TryExpenseGLAccount()
    var
        Library: Codeunit "BAACH Library";
    begin
        Library.ExpenseGLAccountNo();
    end;

    [TryFunction]
    local procedure TryBankAccPostingGroup()
    var
        Library: Codeunit "BAACH Library";
    begin
        Library.BankAccPostingGroupCode();
    end;

    local procedure VendorRemittanceReports() Reports: JsonArray
    var
        ReportSelections: Record "Report Selections";
        Entry: JsonObject;
    begin
        ReportSelections.SetRange(Usage, ReportSelections.Usage::"V.Remittance");
        if ReportSelections.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('sequence', ReportSelections.Sequence);
                Entry.Add('reportId', ReportSelections."Report ID");
                Reports.Add(Entry);
            until ReportSelections.Next() = 0;
    end;

    local procedure EFTDataExchDefs() Defs: JsonArray
    var
        DataExchDef: Record "Data Exch. Def";
        DataExchLineDef: Record "Data Exch. Line Def";
        Entry: JsonObject;
    begin
        DataExchDef.SetRange(Type, DataExchDef.Type::"EFT Payment Export");
        if DataExchDef.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('code', DataExchDef.Code);
                Entry.Add('name', DataExchDef.Name);
                DataExchLineDef.SetRange("Data Exch. Def Code", DataExchDef.Code);
                Entry.Add('lineDefs', DataExchLineDef.Count());
                Defs.Add(Entry);
            until DataExchDef.Next() = 0;
    end;

    local procedure USEFTDataExchDefExists(): Boolean
    var
        BankExportImportSetup: Record "Bank Export/Import Setup";
        DataExchDef: Record "Data Exch. Def";
    begin
        BankExportImportSetup.SetRange(Direction, BankExportImportSetup.Direction::"Export-EFT");
        if BankExportImportSetup.FindSet() then
            repeat
                if DataExchDef.Get(BankExportImportSetup."Data Exch. Def. Code") then
                    exit(true);
            until BankExportImportSetup.Next() = 0;
        exit(DataExchDef.Get('US EFT DEFAULT'));
    end;

    local procedure EFTExportSetups() Setups: JsonArray
    var
        BankExportImportSetup: Record "Bank Export/Import Setup";
        Entry: JsonObject;
    begin
        BankExportImportSetup.SetRange(Direction, BankExportImportSetup.Direction::"Export-EFT");
        if BankExportImportSetup.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('code', BankExportImportSetup.Code);
                Entry.Add('dataExchDefCode', BankExportImportSetup."Data Exch. Def. Code");
                Entry.Add('processingCodeunitId', BankExportImportSetup."Processing Codeunit ID");
                Setups.Add(Entry);
            until BankExportImportSetup.Next() = 0;
    end;

    local procedure BankAccounts() Banks: JsonArray
    var
        BankAccount: Record "Bank Account";
        Entry: JsonObject;
    begin
        if BankAccount.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('no', BankAccount."No.");
                Entry.Add('currencyCode', BankAccount."Currency Code");
                Entry.Add('postingGroup', BankAccount."Bank Acc. Posting Group");
                Entry.Add('exportFormat', Format(BankAccount."Export Format"));
                Entry.Add('paymentExportFormat', BankAccount."Payment Export Format");
                Entry.Add('transitNoSet', BankAccount."Transit No." <> '');
                Entry.Add('lastRemittanceAdviceNo', BankAccount."Last Remittance Advice No.");
                Banks.Add(Entry);
            until BankAccount.Next() = 0;
    end;

    local procedure ResourceDataExchDefCode(): Text
    var
        ResourceStream: InStream;
        XmlDoc: XmlDocument;
        DefNode: XmlNode;
        CodeAttribute: XmlAttribute;
    begin
        NavApp.GetResource(DefaultDefResourceTok, ResourceStream, TextEncoding::UTF8);
        if not XmlDocument.ReadFrom(ResourceStream, XmlDoc) then
            exit('<unreadable>');
        if not XmlDoc.SelectSingleNode('/root/DataExchDef', DefNode) then
            exit('<no DataExchDef>');
        if not DefNode.AsXmlElement().Attributes().Get('Code', CodeAttribute) then
            exit('<no Code>');
        exit(CodeAttribute.Value());
    end;

    local procedure NewLine() Result: Text
    begin
        Result[1] := 13;
        Result[2] := 10;
    end;
}
