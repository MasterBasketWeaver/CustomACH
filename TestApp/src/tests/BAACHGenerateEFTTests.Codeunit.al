codeunit 81211 "BAACH Generate EFT Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        RefusalNotReportedErr: Label 'Expected "%1" in the error or in the batch''s payment file errors. The error was: %2', Comment = '%1 = expected text, %2 = error text';

    [Test]
    procedure GenerateRunsHeadlessAndSetsTheLineFlags()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 125.5, true);

        Library.GenerateEFT(GenJournalBatch);

        GenJournalLine.Find();
        Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        Assert.IsTrue(GenJournalLine."Check Printed", 'Check Printed');
        Assert.IsTrue(GenJournalLine."Exported to Payment File", 'Exported to Payment File');
        Assert.IsFalse(GenJournalLine."Check Exported", 'Check Exported must wait for Export.');
        Assert.IsFalse(GenJournalLine."Check Transmitted", 'Check Transmitted must wait for Export.');
        Assert.AreNotEqual(0, GenJournalLine."EFT Export Sequence No.", 'EFT Export Sequence No.');
    end;

    [Test]
    procedure DocumentNosFollowTheLastRemittanceAdviceNo()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExpectedNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 200, false);

        Library.GenerateEFT(GenJournalBatch);

        ExpectedNo := Library.LastRemittanceAdviceNo();
        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindSet();
        repeat
            ExpectedNo := IncStr(ExpectedNo);
            Assert.AreEqual(ExpectedNo, GenJournalLine."Document No.", 'Document No. of line ' + Format(GenJournalLine."Line No."));
        until GenJournalLine.Next() = 0;
        BankAccount.Find();
        Assert.AreEqual(ExpectedNo, BankAccount."Last Remittance Advice No.", 'Last Remittance Advice No. on the bank');
    end;

    [Test]
    procedure CheckLedgerEntriesAreExported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CheckLedgerEntry: Record "Check Ledger Entry";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 200, false);

        Library.GenerateEFT(GenJournalBatch);

        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindSet();
        repeat
            CheckLedgerEntry.SetRange("Bank Account No.", BankAccount."No.");
            CheckLedgerEntry.SetRange("Check No.", GenJournalLine."Document No.");
            Assert.RecordCount(CheckLedgerEntry, 1);
            CheckLedgerEntry.FindFirst();
            Assert.AreEqual(CheckLedgerEntry."Entry Status"::Exported, CheckLedgerEntry."Entry Status", 'Entry Status');
            Assert.AreEqual(CheckLedgerEntry."Bank Payment Type"::"Electronic Payment", CheckLedgerEntry."Bank Payment Type", 'Bank Payment Type');
            Assert.AreEqual(GenJournalLine.Amount, CheckLedgerEntry.Amount, 'Amount');
            Assert.AreEqual(GenJournalLine."Account No.", CheckLedgerEntry."Bal. Account No.", 'Bal. Account No.');
        until GenJournalLine.Next() = 0;
    end;

    [Test]
    procedure EFTExportRowsAreTransmitted()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        EFTExport: Record "EFT Export";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 200, false);

        Library.GenerateEFT(GenJournalBatch);

        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindSet();
        repeat
            EFTExport.SetRange("Journal Template Name", GenJournalLine."Journal Template Name");
            EFTExport.SetRange("Journal Batch Name", GenJournalLine."Journal Batch Name");
            EFTExport.SetRange("Line No.", GenJournalLine."Line No.");
            Assert.RecordCount(EFTExport, 1);
            EFTExport.FindFirst();
            Assert.IsTrue(EFTExport.Transmitted, 'Transmitted');
            Assert.AreEqual(GenJournalLine."EFT Export Sequence No.", EFTExport."Sequence No.", 'Sequence No.');
            Assert.AreEqual(GenJournalLine."Document No.", EFTExport."Document No.", 'Document No.');
            Assert.AreEqual(BankAccount."No.", EFTExport."Bank Account No.", 'Bank Account No.');
            Assert.AreEqual(GenJournalLine."Amount (LCY)", EFTExport."Amount (LCY)", 'Amount (LCY)');
        until GenJournalLine.Next() = 0;
    end;

    [Test]
    procedure AppliesToIDIsRekeyedToTheDocumentNo()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        InvoiceNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        InvoiceNo := Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);

        Library.GenerateEFT(GenJournalBatch);

        GenJournalLine.Find();
        Assert.AreEqual(GenJournalLine."Document No.", GenJournalLine."Applies-to ID", 'Applies-to ID on the line');
        Library.FindOpenInvoiceEntry(VendorLedgerEntry, GenJournalLine."Account No.", InvoiceNo);
        Assert.AreEqual(GenJournalLine."Document No.", VendorLedgerEntry."Applies-to ID", 'Applies-to ID on the invoice entry');
    end;

    [Test]
    procedure ACHFileHas94CharacterRecordsInNachaOrder()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ACHFile: Codeunit "BAACH ACH File";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 200, false);

        Library.GenerateEFT(GenJournalBatch);

        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.IsTrue(ACHFile.AllRecordsHaveLength(94), 'Every record must be 94 characters.');
        Assert.AreEqual('156689', ACHFile.RecordTypes(), 'Record types in order');
        Assert.AreEqual(0, (ACHFile.RecordCount() + ACHFile.FillerCount()) mod 10, 'The file must be padded to a block of 10 records.');
    end;

    [Test]
    procedure ACHFileEntriesCarryPayeeTransitAccountAndAmount()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: array[2] of Record Vendor;
        VendorBankAccount: array[2] of Record "Vendor Bank Account";
        ACHFile: Codeunit "BAACH ACH File";
        Amounts: array[2] of Decimal;
        Entry: Integer;
        i: Integer;
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Amounts[1] := 150.25;
        Amounts[2] := 1234.56;
        for i := 1 to 2 do begin
            Library.CreateVendorWithBankAccount(Vendor[i], VendorBankAccount[i]);
            Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor[i]."No.", VendorBankAccount[i].Code, Amounts[i], i = 1);
        end;

        Library.GenerateEFT(GenJournalBatch);

        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.AreEqual(2, ACHFile.EntryCount(), 'Entry detail records');
        for i := 1 to 2 do begin
            Entry := ACHFile.FindEntryByName(Vendor[i].Name);
            Assert.AreEqual('22', ACHFile.EntryTransactionCode(Entry), 'Transaction code (checking credit)');
            Assert.AreEqual(VendorBankAccount[i]."Transit No.", ACHFile.EntryTransitNo(Entry), 'Transit no.');
            Assert.AreEqual(VendorBankAccount[i]."Bank Account No.", ACHFile.EntryAccountNo(Entry), 'Account no.');
            Assert.AreEqual(Amounts[i], ACHFile.EntryAmount(Entry), 'Amount');
            Assert.AreEqual(Vendor[i]."No.", ACHFile.EntryIndividualId(Entry), 'Individual identification (vendor no.)');
        end;
    end;

    [Test]
    procedure ACHFileTotalsAndEffectiveDateMatchThePayments()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ACHFile: Codeunit "BAACH ACH File";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100.1, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 250.75, false);

        Library.GenerateEFT(GenJournalBatch);

        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.AreEqual(Library.SettlementDate(), ACHFile.BatchEffectiveDate(), 'Effective entry date = settlement date');
        Assert.AreEqual(350.85, ACHFile.BatchTotalCredit(), 'Batch control total credit');
        Assert.AreEqual(350.85, ACHFile.FileTotalCredit(), 'File control total credit');
        Assert.AreEqual(2, ACHFile.BatchEntryCount(), 'Batch control entry count');
        Assert.AreEqual(2, ACHFile.FileEntryCount(), 'File control entry count');
    end;

    [Test]
    procedure MultipleVendorsAndLinesAreAllGenerated()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
        ACHFile: Codeunit "BAACH ACH File";
        ExpectedNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, 100, true);
        Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, 40, false);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 60, true);

        Library.GenerateEFT(GenJournalBatch);

        ExpectedNo := Library.LastRemittanceAdviceNo();
        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        Assert.RecordCount(GenJournalLine, 3);
        GenJournalLine.FindSet();
        repeat
            ExpectedNo := IncStr(ExpectedNo);
            Assert.AreEqual(ExpectedNo, GenJournalLine."Document No.", 'Document No.');
            Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        until GenJournalLine.Next() = 0;

        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.AreEqual(3, ACHFile.EntryCount(), 'Entry detail records');
        Assert.AreEqual(200, ACHFile.FileTotalCredit(), 'File control total credit');
    end;

    [Test]
    procedure MissingRecipientBankAccountIsReported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        Library.CreatePaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", '', 100);

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", 'Recipient Bank Account');
    end;

    [Test]
    procedure RecipientNotForElectronicPaymentsIsReported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, 100, true);
        VendorBankAccount."Use for Electronic Payments" := false;
        VendorBankAccount.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", VendorBankAccount.FieldCaption("Use for Electronic Payments"));
    end;

    [Test]
    procedure NegativeAmountIsReported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        Library.CreatePaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, -50);

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", 'negative');
    end;

    [Test]
    procedure CurrencyDifferentFromTheBankIsReported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        GenJournalLine."Currency Code" := ForeignCurrencyCode();
        GenJournalLine.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", GenJournalLine.FieldCaption("Currency Code"));
    end;

    [Test]
    procedure BatchWithoutAllowPaymentExportIsRefused()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        GenJournalBatch."Allow Payment Export" := false;
        GenJournalBatch.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", GenJournalBatch.FieldCaption("Allow Payment Export"));
    end;

    [Test]
    procedure BatchWithAPostingNoSeriesIsRefused()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        GenJournalBatch."Posting No. Series" := AnyNoSeriesCode();
        GenJournalBatch.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", GenJournalBatch.FieldCaption("Posting No. Series"));
    end;

    [Test]
    procedure MissingFederalIdNoIsRefused()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CompanyInformation: Record "Company Information";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        CompanyInformation.Get();
        CompanyInformation."Federal ID No." := '';
        CompanyInformation.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", CompanyInformation.FieldCaption("Federal ID No."));
    end;

    [Test]
    procedure MissingLastRemittanceAdviceNoIsRefused()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        BankAccount."Last Remittance Advice No." := '';
        BankAccount.Modify();

        AssertGenerateRefusedFrom(GenJournalBatch, BankAccount."No.", BankAccount.FieldCaption("Last Remittance Advice No."), '');
    end;

    [Test]
    procedure BlockedBankAccountIsRefused()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        BankAccount.Blocked := true;
        BankAccount.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", BankAccount.FieldCaption(Blocked));
    end;

    [Test]
    procedure InvalidVendorTransitNoIsRefused()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        Library.CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, 100, true);
        // 123456789 fails the ABA check digit (the valid one is 123456780).
        VendorBankAccount."Transit No." := '123456789';
        VendorBankAccount.Modify();

        AssertGenerateRefused(GenJournalBatch, BankAccount."No.", VendorBankAccount."Transit No.");
    end;

    [Test]
    procedure NonElectronicAndZeroAmountLinesAreIgnored()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        PaidLine: Record "Gen. Journal Line";
        NonElectronicLine: Record "Gen. Journal Line";
        ZeroLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
        ACHFile: Codeunit "BAACH ACH File";
        NonElectronicDocNo: Code[20];
        ZeroDocNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(PaidLine, GenJournalBatch, 100, true);

        // Balanced against a G/L account instead of the bank, which page 256's export checks accept.
        Library.CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        Library.CreatePaymentLine(NonElectronicLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, 70);
        NonElectronicLine.Validate("Bank Payment Type", NonElectronicLine."Bank Payment Type"::" ");
        NonElectronicLine.Validate("Bal. Account Type", NonElectronicLine."Bal. Account Type"::"G/L Account");
        NonElectronicLine.Validate("Bal. Account No.", Library.ExpenseGLAccountNo());
        NonElectronicLine.Modify(true);
        NonElectronicDocNo := NonElectronicLine."Document No.";

        Library.CreatePaymentLine(ZeroLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, 0);
        ZeroDocNo := ZeroLine."Document No.";

        Library.GenerateEFT(GenJournalBatch);

        PaidLine.Find();
        Assert.AreEqual(IncStr(Library.LastRemittanceAdviceNo()), PaidLine."Document No.", 'The electronic line gets the first number.');
        VerifyLineUntouched(NonElectronicLine, NonElectronicDocNo);
        VerifyLineUntouched(ZeroLine, ZeroDocNo);
        BankAccount.Find();
        Assert.AreEqual(IncStr(Library.LastRemittanceAdviceNo()), BankAccount."Last Remittance Advice No.", 'Only one number is consumed.');
        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.AreEqual(1, ACHFile.EntryCount(), 'Entry detail records');
    end;

    [Test]
    procedure OtherBatchesAreUntouched()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        OtherBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        OtherLine: Record "Gen. Journal Line";
        EFTExport: Record "EFT Export";
        ACHFile: Codeunit "BAACH ACH File";
        OtherDocNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateBatchInTemplate(OtherBatch, GenJournalBatch."Journal Template Name", BankAccount."No.");
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.CreateVendorPayment(OtherLine, OtherBatch, 300, true);
        OtherDocNo := OtherLine."Document No.";

        Library.GenerateEFT(GenJournalBatch);

        VerifyLineUntouched(OtherLine, OtherDocNo);
        EFTExport.SetRange("Journal Template Name", OtherBatch."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", OtherBatch.Name);
        Assert.RecordIsEmpty(EFTExport);
        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.AreEqual(1, ACHFile.EntryCount(), 'Entry detail records');
        Assert.AreEqual(100, ACHFile.FileTotalCredit(), 'File control total credit');
    end;

    [Test]
    procedure AResumedRunDoesNotRenumber()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        EFTExport: Record "EFT Export";
        CheckLedgerEntry: Record "Check Ledger Entry";
        ACHFile: Codeunit "BAACH ACH File";
        DocumentNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();
        DocumentNo := GenJournalLine."Document No.";

        // The state codeunit 10098 leaves when it fails after the lines were prepared.
        GenJournalLine."BAACH EFT File Created" := false;
        GenJournalLine."Check Transmitted" := false;
        GenJournalLine.Modify();
        EFTExport.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalBatch.Name);
        EFTExport.ModifyAll(Transmitted, false);

        Library.GenerateEFT(GenJournalBatch);

        GenJournalLine.Find();
        Assert.AreEqual(DocumentNo, GenJournalLine."Document No.", 'Document No. must be kept.');
        Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        BankAccount.Find();
        Assert.AreEqual(DocumentNo, BankAccount."Last Remittance Advice No.", 'No new number may be consumed.');
        Assert.RecordCount(EFTExport, 1);
        EFTExport.FindFirst();
        Assert.IsTrue(EFTExport.Transmitted, 'Transmitted');
        CheckLedgerEntry.SetRange("Bank Account No.", BankAccount."No.");
        Assert.RecordCount(CheckLedgerEntry, 1);
        ACHFile.LoadForBankAccount(BankAccount."No.");
        Assert.AreEqual(1, ACHFile.EntryCount(), 'Entry detail records');
    end;

    local procedure AssertGenerateRefused(GenJournalBatch: Record "Gen. Journal Batch"; BankAccountNo: Code[20]; ExpectedText: Text)
    begin
        AssertGenerateRefusedFrom(GenJournalBatch, BankAccountNo, ExpectedText, Library.LastRemittanceAdviceNo());
    end;

    // The refusal may surface in the error itself or, as in page 256's Export, in the payment file
    // errors the batch keeps. Either way nothing may be numbered or prepared.
    local procedure AssertGenerateRefusedFrom(GenJournalBatch: Record "Gen. Journal Batch"; BankAccountNo: Code[20]; ExpectedText: Text; ExpectedLastNo: Code[20])
    var
        BankAccount: Record "Bank Account";
        GenJournalLine: Record "Gen. Journal Line";
        EFTExport: Record "EFT Export";
        ErrorText: Text;
    begin
        asserterror Library.GenerateEFT(GenJournalBatch);
        ErrorText := GetLastErrorText();
        if StrPos(LowerCase(ErrorText), LowerCase(ExpectedText)) = 0 then
            if not BatchHasPaymentFileError(GenJournalBatch, ExpectedText) then
                Assert.Fail(StrSubstNo(RefusalNotReportedErr, ExpectedText, ErrorText));

        BankAccount.Get(BankAccountNo);
        Assert.AreEqual(ExpectedLastNo, BankAccount."Last Remittance Advice No.", 'No remittance advice number may be consumed.');
        EFTExport.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalBatch.Name);
        Assert.RecordIsEmpty(EFTExport);
        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.SetRange("Check Printed", true);
        Assert.RecordIsEmpty(GenJournalLine);
    end;

    local procedure BatchHasPaymentFileError(GenJournalBatch: Record "Gen. Journal Batch"; ExpectedText: Text): Boolean
    var
        PaymentJnlExportErrorText: Record "Payment Jnl. Export Error Text";
    begin
        PaymentJnlExportErrorText.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        PaymentJnlExportErrorText.SetRange("Journal Batch Name", GenJournalBatch.Name);
        if PaymentJnlExportErrorText.FindSet() then
            repeat
                if StrPos(LowerCase(PaymentJnlExportErrorText."Error Text"), LowerCase(ExpectedText)) <> 0 then
                    exit(true);
            until PaymentJnlExportErrorText.Next() = 0;
        exit(false);
    end;

    local procedure VerifyLineUntouched(var GenJournalLine: Record "Gen. Journal Line"; DocumentNo: Code[20])
    var
        EFTExport: Record "EFT Export";
    begin
        GenJournalLine.Find();
        Assert.AreEqual(DocumentNo, GenJournalLine."Document No.", 'Document No. of an untouched line');
        Assert.IsFalse(GenJournalLine."Check Printed", 'Check Printed of an untouched line');
        Assert.IsFalse(GenJournalLine."BAACH EFT File Created", 'EFT File Created of an untouched line');
        Assert.AreEqual(0, GenJournalLine."EFT Export Sequence No.", 'EFT Export Sequence No. of an untouched line');
        EFTExport.SetRange("Journal Template Name", GenJournalLine."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalLine."Journal Batch Name");
        EFTExport.SetRange("Line No.", GenJournalLine."Line No.");
        Assert.RecordIsEmpty(EFTExport);
    end;

    local procedure ForeignCurrencyCode(): Code[10]
    var
        Currency: Record Currency;
        GeneralLedgerSetup: Record "General Ledger Setup";
    begin
        GeneralLedgerSetup.Get();
        Currency.SetFilter(Code, '<>%1', GeneralLedgerSetup."LCY Code");
        if Currency.FindFirst() then
            exit(Currency.Code);
        Currency.Init();
        Currency.Code := 'BAX';
        Currency.Insert();
        exit(Currency.Code);
    end;

    local procedure AnyNoSeriesCode(): Code[20]
    var
        NoSeries: Record "No. Series";
    begin
        if NoSeries.FindFirst() then
            exit(NoSeries.Code);
        exit('BAACH');
    end;
}
