// Runs the V.Remittance reports after step 1 through Report.SaveAs (no request page) and reads
// their dataset XML: the advice must carry the remittance advice number and find the invoice.
codeunit 81214 "BAACH Remittance Report Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        ColumnNotFoundErr: Label 'The report dataset has no column %1.', Comment = '%1 = column name';

    [Test]
    procedure ExportElectronicPaymentsShowsAnInvoiceAppliedByAppliesToID()
    begin
        VerifyRemittanceAdvice(Report::"Export Electronic Payments", true);
    end;

    [Test]
    procedure ExportElectronicPaymentsShowsAnInvoiceAppliedByDocNo()
    begin
        VerifyRemittanceAdvice(Report::"Export Electronic Payments", false);
    end;

    [Test]
    procedure ExportElecPaymentsWordShowsAnInvoiceAppliedByAppliesToID()
    begin
        VerifyRemittanceAdvice(Report::"ExportElecPayments - Word", true);
    end;

    [Test]
    procedure ExportElecPaymentsWordShowsAnInvoiceAppliedByDocNo()
    begin
        VerifyRemittanceAdvice(Report::"ExportElecPayments - Word", false);
    end;

    local procedure VerifyRemittanceAdvice(ReportId: Integer; ApplyByAppliesToID: Boolean)
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
        Dataset: XmlDocument;
        InvoiceNo: Code[20];
        PaymentAmount: Decimal;
    begin
        PaymentAmount := 432.1;
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        InvoiceNo := Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, PaymentAmount, ApplyByAppliesToID);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();

        RunReport(ReportId, GenJournalBatch, Dataset);

        Assert.AreEqual(GenJournalLine."Document No.", ColumnText(Dataset, 'Gen__Journal_Line___Document_No__'), 'Remittance advice no.');
        Assert.AreEqual(Vendor.Name, ColumnText(Dataset, 'PayeeAddress_1_'), 'Payee');
        Assert.AreEqual(VendorBankAccount."Transit No.", ColumnText(Dataset, 'PayeeBankTransitNo'), 'Payee transit no.');
        Assert.AreEqual(PaymentAmount, ColumnDecimal(Dataset, 'ExportAmount'), 'Deposit amount');
        if ApplyByAppliesToID then begin
            Assert.AreEqual(GenJournalLine."Document No.", ColumnText(Dataset, 'Vendor_Ledger_Entry_Applies_to_ID'), 'Invoice found through the re-keyed Applies-to ID');
            Assert.AreEqual(InvoiceNo, ColumnText(Dataset, 'Vendor_Ledger_Entry__External_Document_No__'), 'Invoice');
            Assert.AreEqual(PaymentAmount, ColumnDecimal(Dataset, 'AmountPaid_Control43'), 'Amount paid on the invoice');
        end else begin
            Assert.AreEqual(InvoiceNo, ColumnText(Dataset, 'VendLedgEntry__External_Document_No__'), 'Invoice');
            Assert.AreEqual(PaymentAmount, ColumnDecimal(Dataset, 'AmountPaid'), 'Amount paid on the invoice');
        end;
    end;

    local procedure RunReport(ReportId: Integer; GenJournalBatch: Record "Gen. Journal Batch"; var Dataset: XmlDocument)
    var
        TempBlob: Codeunit "Temp Blob";
        ReportOutStream: OutStream;
        ReportInStream: InStream;
    begin
        TempBlob.CreateOutStream(ReportOutStream, TextEncoding::UTF8);
        Report.SaveAs(ReportId, RequestParameters(ReportId, GenJournalBatch), ReportFormat::Xml, ReportOutStream);
        TempBlob.CreateInStream(ReportInStream, TextEncoding::UTF8);
        XmlDocument.ReadFrom(ReportInStream, Dataset);
    end;

    // Both reports name their options by source expression, which is what request-page XML uses.
    local procedure RequestParameters(ReportId: Integer; GenJournalBatch: Record "Gen. Journal Batch") Result: Text
    var
        GenJournalLine: Record "Gen. Journal Line";
        XmlDoc: XmlDocument;
        Root: XmlElement;
        Options: XmlElement;
        DataItems: XmlElement;
        DataItem: XmlElement;
    begin
        XmlDoc := XmlDocument.Create();
        XmlDoc.SetDeclaration(XmlDeclaration.Create('1.0', 'utf-8', 'yes'));
        Root := XmlElement.Create('ReportParameters');
        Root.SetAttribute('id', Format(ReportId));

        Options := XmlElement.Create('Options');
        AddOption(Options, 'BankAccount."No."', GenJournalBatch."Bal. Account No.");
        AddOption(Options, 'NoCopies', '0');
        if ReportId = Report::"Export Electronic Payments" then
            AddOption(Options, 'PrintCompany', 'false')
        else begin
            AddOption(Options, 'PrintCompanyAdd', 'false');
            AddOption(Options, 'PrintCompanyPicture', 'false');
        end;
        Root.Add(Options);

        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        DataItems := XmlElement.Create('DataItems');
        DataItem := XmlElement.Create('DataItem');
        DataItem.SetAttribute('name', 'Gen. Journal Line');
        DataItem.Add(XmlText.Create(GenJournalLine.GetView(false)));
        DataItems.Add(DataItem);
        Root.Add(DataItems);

        XmlDoc.Add(Root);
        XmlDoc.WriteTo(Result);
    end;

    local procedure AddOption(var Options: XmlElement; Name: Text; Value: Text)
    var
        Field: XmlElement;
    begin
        Field := XmlElement.Create('Field');
        Field.SetAttribute('name', Name);
        Field.Add(XmlText.Create(Value));
        Options.Add(Field);
    end;

    local procedure ColumnText(Dataset: XmlDocument; ColumnName: Text): Text
    var
        ColumnNode: XmlNode;
    begin
        if not Dataset.SelectSingleNode(StrSubstNo('//*[local-name()=''Column''][@name=''%1'']', ColumnName), ColumnNode) then
            Error(ColumnNotFoundErr, ColumnName);
        exit(ColumnNode.AsXmlElement().InnerText());
    end;

    local procedure ColumnDecimal(Dataset: XmlDocument; ColumnName: Text) Value: Decimal
    var
        ValueText: Text;
    begin
        ValueText := ColumnText(Dataset, ColumnName);
        if not Evaluate(Value, ValueText, 9) then
            Evaluate(Value, ValueText);
    end;
}
