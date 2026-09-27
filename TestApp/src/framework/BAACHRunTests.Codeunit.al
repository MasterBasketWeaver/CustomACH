// SOAP entry point, published as BAACHRunTests by "BAACH Test Install" and driven by run_tests.py.
codeunit 81202 "BAACH Run Tests"
{
    var
        Suite: Codeunit "BAACH Suite";
        TestResults: Codeunit "BAACH Test Results";
        USEFTResourceTok: Label 'US-EFT-DEFAULT.xml', Locked = true;

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

    // Used once to capture TestApp/resources/US-EFT-DEFAULT.xml from a company that has the definition.
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
        NavApp.GetResource(USEFTResourceTok, ResourceStream, TextEncoding::UTF8);
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
