// ExportForBatch opens the report request pages, which a SOAP session cannot show, so only its
// guards are called here; the marking rules are driven through "BAACH Remittance Run Scope".
codeunit 81213 "BAACH Export Remittance Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";

    [Test]
    procedure ExportIsRefusedBeforeTheEFTFileIsGenerated()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExportRemittance: Codeunit "BAACH Export Remittance";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);

        Commit();
        asserterror ExportRemittance.ExportForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
        Assert.ExpectedErrorContains('EFT');

        GenJournalLine.Find();
        Assert.IsFalse(GenJournalLine."Check Exported", 'Check Exported');
        Assert.IsFalse(GenJournalLine."Check Printed", 'Check Printed');
    end;

    [Test]
    procedure ExportIsRefusedWithoutAVendorRemittanceReportSelection()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExportRemittance: Codeunit "BAACH Export Remittance";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.RemoveVendorRemittanceSelections();

        Commit();
        asserterror ExportRemittance.ExportForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
        Assert.ExpectedErrorContains('Vendor Remittance report');

        GenJournalLine.Find();
        Assert.IsFalse(GenJournalLine."Check Exported", 'Check Exported');
    end;

    [Test]
    procedure ExportIsRefusedWhenEverythingIsExported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExportRemittance: Codeunit "BAACH Export Remittance";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());

        Commit();
        asserterror ExportRemittance.ExportForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
    end;

    [Test]
    procedure APDFRunMarksTheLinesExportedAndTransmitted()
    begin
        VerifyRunMarksLines(CustomLayoutReporting.GetPDFOption());
    end;

    [Test]
    procedure APrintRunMarksTheLinesExportedAndTransmitted()
    begin
        VerifyRunMarksLines(CustomLayoutReporting.GetPrintOption());
    end;

    [Test]
    procedure AnEmailRunMarksTheLinesExportedAndTransmitted()
    begin
        VerifyRunMarksLines(CustomLayoutReporting.GetEmailOption());
    end;

    [Test]
    procedure APreviewRunMarksNothing()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);

        Library.MarkBatchExported(GenJournalBatch, CustomLayoutReporting.GetPreviewOption());

        GenJournalLine.Find();
        Assert.IsFalse(GenJournalLine."Check Exported", 'Check Exported after Preview');
        Assert.IsFalse(GenJournalLine."Check Transmitted", 'Check Transmitted after Preview');
        Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
    end;

    [Test]
    procedure MarkingLeavesOtherBatchesAlone()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        OtherBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        OtherLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateBatchInTemplate(OtherBatch, GenJournalBatch."Journal Template Name", BankAccount."No.");
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(OtherLine, OtherBatch, 200, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.GenerateEFT(OtherBatch);

        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());

        GenJournalLine.Find();
        Assert.IsTrue(GenJournalLine."Check Exported", 'Check Exported in the exported batch');
        OtherLine.Find();
        Assert.IsFalse(OtherLine."Check Exported", 'Check Exported in the other batch');
        Assert.IsFalse(OtherLine."Check Transmitted", 'Check Transmitted in the other batch');
    end;

    [Test]
    procedure AFailedEmailKeepsCheckExportedButNotCheckTransmittedForThatVendor()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        FailedVendor: Record Vendor;
        OtherVendorLine: Record "Gen. Journal Line";
    begin
        CreateTwoVendorBatch(BankAccount, GenJournalBatch, FailedVendor, OtherVendorLine);
        Library.GenerateEFT(GenJournalBatch);

        ExportWithFailedEmail(GenJournalBatch, FailedVendor."No.");

        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.SetRange("Account No.", FailedVendor."No.");
        Assert.RecordCount(GenJournalLine, 2);
        GenJournalLine.FindSet();
        repeat
            Assert.IsTrue(GenJournalLine."Check Exported", 'Check Exported of the failed vendor');
            Assert.IsFalse(GenJournalLine."Check Transmitted", 'Check Transmitted of the failed vendor');
        until GenJournalLine.Next() = 0;

        OtherVendorLine.Find();
        Assert.IsTrue(OtherVendorLine."Check Exported", 'Check Exported of the other vendor');
        Assert.IsTrue(OtherVendorLine."Check Transmitted", 'Check Transmitted of the other vendor');
    end;

    [Test]
    procedure AVendorWithAFailedEmailCannotBePosted()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        FailedVendor: Record Vendor;
        OtherVendorLine: Record "Gen. Journal Line";
    begin
        CreateTwoVendorBatch(BankAccount, GenJournalBatch, FailedVendor, OtherVendorLine);
        Library.GenerateEFT(GenJournalBatch);
        ExportWithFailedEmail(GenJournalBatch, FailedVendor."No.");

        Commit();
        asserterror Library.PostBatch(GenJournalBatch);
        Assert.ExpectedErrorContains(GenJournalLine.FieldCaption("Check Transmitted"));
    end;

    [Test]
    procedure ARerunExportsTheFailedVendorWithTheSameNumbers()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        FailedVendor: Record Vendor;
        OtherVendorLine: Record "Gen. Journal Line";
        CheckLedgerEntry: Record "Check Ledger Entry";
        EFTExport: Record "EFT Export";
        DocumentNos: List of [Code[20]];
        LastNo: Code[20];
    begin
        CreateTwoVendorBatch(BankAccount, GenJournalBatch, FailedVendor, OtherVendorLine);
        Library.GenerateEFT(GenJournalBatch);
        ExportWithFailedEmail(GenJournalBatch, FailedVendor."No.");
        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindSet();
        repeat
            DocumentNos.Add(GenJournalLine."Document No.");
        until GenJournalLine.Next() = 0;
        BankAccount.Find();
        LastNo := BankAccount."Last Remittance Advice No.";

        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());

        GenJournalLine.FindSet();
        repeat
            Assert.IsTrue(DocumentNos.Contains(GenJournalLine."Document No."), 'Document No. must be kept: ' + GenJournalLine."Document No.");
            Assert.IsTrue(GenJournalLine."Check Exported", 'Check Exported');
            Assert.IsTrue(GenJournalLine."Check Transmitted", 'Check Transmitted');
        until GenJournalLine.Next() = 0;
        BankAccount.Find();
        Assert.AreEqual(LastNo, BankAccount."Last Remittance Advice No.", 'No new number may be consumed.');
        CheckLedgerEntry.SetRange("Bank Account No.", BankAccount."No.");
        Assert.RecordCount(CheckLedgerEntry, 3);
        EFTExport.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalBatch.Name);
        Assert.RecordCount(EFTExport, 3);
    end;

    [Test]
    procedure ARequestPageLastUsedForAnotherBatchIsLimitedToTheExportedBatch()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        OtherBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
        Parameters: Text;
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateBatchInTemplate(OtherBatch, GenJournalBatch."Journal Template Name", BankAccount."No.");
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, false);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();
        Parameters := LastUsedParameters(OtherBatch);
        Assert.AreEqual(0, CountLinesToReport(GenJournalBatch, Parameters), 'Lines left by the other batch''s filter');

        RemittanceRunScope.SetBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name, BankAccount."No.");
        RemittanceRunScope.PrefillRequestParameters(Report::"Export Electronic Payments", Parameters);

        Assert.AreEqual(1, CountLinesToReport(GenJournalBatch, Parameters), 'Lines to report after the pre-fill');
        Assert.IsTrue(ReportDatasetContains(GenJournalBatch, Parameters, GenJournalLine."Document No."), 'The remittance advice must carry the line.');
    end;

    [Test]
    procedure ARequestPageNeverUsedIsLimitedToTheExportedBatch()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
        Parameters: Text;
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, false);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();

        RemittanceRunScope.SetBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name, BankAccount."No.");
        RemittanceRunScope.PrefillRequestParameters(Report::"Export Electronic Payments", Parameters);

        Assert.AreEqual(1, CountLinesToReport(GenJournalBatch, Parameters), 'Lines to report after the pre-fill');
        Assert.IsTrue(ReportDatasetContains(GenJournalBatch, Parameters, GenJournalLine."Document No."), 'The remittance advice must carry the line.');
    end;

    local procedure VerifyRunMarksLines(OutputType: Integer)
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        DocumentNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 50, false);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();
        DocumentNo := GenJournalLine."Document No.";

        Library.MarkBatchExported(GenJournalBatch, OutputType);

        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindSet();
        repeat
            Assert.IsTrue(GenJournalLine."Check Exported", 'Check Exported');
            Assert.IsTrue(GenJournalLine."Check Transmitted", 'Check Transmitted');
            Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        until GenJournalLine.Next() = 0;
        GenJournalLine.FindLast();
        Assert.AreEqual(DocumentNo, GenJournalLine."Document No.", 'Document No. must not change on Export.');
    end;

    // The failed vendor has two lines, so "all of that vendor's lines" is actually exercised.
    local procedure CreateTwoVendorBatch(var BankAccount: Record "Bank Account"; var GenJournalBatch: Record "Gen. Journal Batch"; var FailedVendor: Record Vendor; var OtherVendorLine: Record "Gen. Journal Line")
    var
        GenJournalLine: Record "Gen. Journal Line";
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(FailedVendor, VendorBankAccount);
        Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, FailedVendor."No.", VendorBankAccount.Code, 100, true);
        Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, FailedVendor."No.", VendorBankAccount.Code, 20, false);
        Library.CreateVendorPayment(OtherVendorLine, GenJournalBatch, 300, true);
    end;

    // The saved request page XML BC keeps per user as "last used", with another batch's journal line filter.
    local procedure LastUsedParameters(OtherBatch: Record "Gen. Journal Batch"): Text
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.FilterBatchLines(GenJournalLine, OtherBatch);
        exit(
            '<?xml version="1.0" standalone="yes"?><ReportParameters name="Export Electronic Payments" id="10083"><Options>' +
            '<Field name="BankAccount.&quot;No.&quot;">' + OtherBatch."Bal. Account No." + '</Field><Field name="NoCopies">0</Field>' +
            '<Field name="PrintCompany">false</Field></Options><DataItems><DataItem name="Gen. Journal Line">' +
            GenJournalLine.GetView(false) + '</DataItem></DataItems></ReportParameters>');
    end;

    // Custom Layout Reporting applies the request page's filters in a filter group of their own on top of the
    // lines Export passes in, and reports "No data exists" when nothing is left.
    local procedure FilterLinesToReport(var DataRecRef: RecordRef; GenJournalBatch: Record "Gen. Journal Batch"; Parameters: Text)
    var
        GenJournalLine: Record "Gen. Journal Line";
        RequestPageParametersHelper: Codeunit "Request Page Parameters Helper";
        TempBlob: Codeunit "Temp Blob";
        RequestRecRef: RecordRef;
        ParametersOutStream: OutStream;
    begin
        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.SetRange("BAACH EFT File Created", true);
        DataRecRef.GetTable(GenJournalLine);
        DataRecRef.SetView(GenJournalLine.GetView());

        TempBlob.CreateOutStream(ParametersOutStream, TextEncoding::UTF8);
        ParametersOutStream.WriteText(Parameters);
        RequestRecRef.Open(Database::"Gen. Journal Line");
        RequestPageParametersHelper.ConvertParametersToFilters(RequestRecRef, TempBlob, TextEncoding::UTF8);
        DataRecRef.FilterGroup(10);
        DataRecRef.SetView(RequestRecRef.GetView());
        DataRecRef.FilterGroup(0);
    end;

    local procedure CountLinesToReport(GenJournalBatch: Record "Gen. Journal Batch"; Parameters: Text): Integer
    var
        DataRecRef: RecordRef;
    begin
        FilterLinesToReport(DataRecRef, GenJournalBatch, Parameters);
        exit(DataRecRef.Count());
    end;

    local procedure ReportDatasetContains(GenJournalBatch: Record "Gen. Journal Batch"; Parameters: Text; Value: Text): Boolean
    var
        TempBlob: Codeunit "Temp Blob";
        DataRecRef: RecordRef;
        ReportOutStream: OutStream;
        ReportInStream: InStream;
        Dataset: Text;
    begin
        FilterLinesToReport(DataRecRef, GenJournalBatch, Parameters);
        TempBlob.CreateOutStream(ReportOutStream, TextEncoding::UTF8);
        Report.SaveAs(Report::"Export Electronic Payments", Parameters, ReportFormat::Xml, ReportOutStream, DataRecRef);
        TempBlob.CreateInStream(ReportInStream, TextEncoding::UTF8);
        ReportInStream.Read(Dataset);
        exit(Dataset.Contains('>' + Value + '<'));
    end;

    local procedure ExportWithFailedEmail(GenJournalBatch: Record "Gen. Journal Batch"; FailedVendorNo: Code[20])
    var
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
    begin
        RemittanceRunScope.SetBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name, GenJournalBatch."Bal. Account No.");
        RemittanceRunScope.MarkLinesExported(CustomLayoutReporting.GetEmailOption());
        RemittanceRunScope.MarkVendorEmailFailed(FailedVendorNo);
    end;
}
