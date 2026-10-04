// Generates files with the company's own BANK OF COMMERCE-V1 format. Its FOOTER A line writes an offset debit
// entry (type 6, transaction code 27) that ACHCustom counts and hashes, and Custom ACH Eagle Eye leaves alone.
codeunit 81350 "BAACH EE Bank Commerce Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        BankOfCommerceDefTok: Label 'BANK OF COMMERCE-V1', Locked = true;
        DetailLineDefTok: Label 'DETAILA', Locked = true;
        NoBankOfCommerceSetupErr: Label 'No Bank Export/Import Setup in company %1 uses data exchange definition %2.', Comment = '%1 = company name, %2 = definition code';
        NoFileErr: Label 'Generate EFT File wrote no file into the %1 %2 data exchange.', Comment = '%1 = definition code, %2 = line definition code';

    [Test]
    procedure OffsetEntryIsWrittenCountedAndHashed()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ACHFile: Codeunit "BAACH ACH File";
        OffsetEntry: Text;
    begin
        CreateBankOfCommerceScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100.1, true);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 250.75, false);

        Library.GenerateEFT(GenJournalBatch);

        LoadBankOfCommerceFile(ACHFile);
        Assert.IsTrue(ACHFile.AllRecordsHaveLength(94), 'Every record is 94 characters');
        Assert.AreEqual('1566689', ACHFile.RecordTypes(), 'File header, batch header, two payments, the offset entry, batch and file control');
        Assert.AreEqual('22', ACHFile.EntryTransactionCode(1), 'First payment is a checking credit');
        Assert.AreEqual('22', ACHFile.EntryTransactionCode(2), 'Second payment is a checking credit');

        OffsetEntry := ACHFile.GetRecordOfType('6', 3);
        Assert.AreEqual('27', CopyStr(OffsetEntry, 2, 2), 'Offset entry is a checking debit');
        Assert.AreEqual(BankAccount."Transit No.", CopyStr(OffsetEntry, 4, 9), 'Offset entry routes to the company bank');
        Assert.AreEqual(350.85, ACHFile.EntryAmount(3), 'Offset entry amount equals the credits');

        Assert.AreEqual(3, ACHFile.BatchEntryCount(), 'Batch control entry count includes the offset entry');
        Assert.AreEqual(350.85, ACHFile.BatchTotalCredit(), 'Batch control total credit');
        Assert.AreEqual(350.85, Cents(CopyStr(ACHFile.GetRecordOfType('8', 1), 21, 12)), 'Batch control total debit balances the credits');
        Assert.AreEqual(ExpectedEntryHash(GenJournalBatch, BankAccount), ToBigInteger(CopyStr(ACHFile.GetRecordOfType('8', 1), 11, 10)), 'Batch control entry hash includes the offset entry');

        Assert.AreEqual(3, ACHFile.FileEntryCount(), 'File control entry count includes the offset entry');
        Assert.AreEqual(350.85, ACHFile.FileTotalCredit(), 'File control total credit');
        Assert.AreEqual(350.85, Cents(CopyStr(ACHFile.GetRecordOfType('9', 1), 32, 12)), 'File control total debit balances the credits');
        Assert.AreEqual(ExpectedEntryHash(GenJournalBatch, BankAccount), ToBigInteger(CopyStr(ACHFile.GetRecordOfType('9', 1), 22, 10)), 'File control entry hash includes the offset entry');
    end;

    [Test]
    procedure SinglePaymentFileCountsTheOffsetEntry()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ACHFile: Codeunit "BAACH ACH File";
    begin
        CreateBankOfCommerceScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 75, true);

        Library.GenerateEFT(GenJournalBatch);

        LoadBankOfCommerceFile(ACHFile);
        Assert.AreEqual('156689', ACHFile.RecordTypes(), 'File header, batch header, the payment, the offset entry, batch and file control');
        Assert.AreEqual(2, ACHFile.BatchEntryCount(), 'Batch control entry count');
        Assert.AreEqual(2, ACHFile.FileEntryCount(), 'File control entry count');
        Assert.AreEqual(ExpectedEntryHash(GenJournalBatch, BankAccount), ToBigInteger(CopyStr(ACHFile.GetRecordOfType('9', 1), 22, 10)), 'File control entry hash');
    end;

    // A fresh bank account from the library, switched to the company's Bank of Commerce export setup, so the
    // company's own bank accounts and remittance numbers stay untouched.
    local procedure CreateBankOfCommerceScenario(var BankAccount: Record "Bank Account"; var GenJournalBatch: Record "Gen. Journal Batch")
    var
        BankExportImportSetup: Record "Bank Export/Import Setup";
    begin
        BankExportImportSetup.SetRange("Data Exch. Def. Code", BankOfCommerceDefTok);
        if not BankExportImportSetup.FindFirst() then
            Error(NoBankOfCommerceSetupErr, CompanyName(), BankOfCommerceDefTok);

        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        BankAccount."Payment Export Format" := BankExportImportSetup.Code;
        BankAccount.Modify();
    end;

    // The engine writes each file into the first Data Exch. entry of the definition's detail line.
    local procedure LoadBankOfCommerceFile(var ACHFile: Codeunit "BAACH ACH File")
    var
        DataExch: Record "Data Exch.";
        ContentStream: InStream;
    begin
        DataExch.SetRange("Data Exch. Def Code", BankOfCommerceDefTok);
        DataExch.SetRange("Data Exch. Line Def Code", DetailLineDefTok);
        DataExch.FindFirst();
        DataExch.CalcFields("File Content");
        if not DataExch."File Content".HasValue() then
            Error(NoFileErr, BankOfCommerceDefTok, DetailLineDefTok);
        DataExch."File Content".CreateInStream(ContentStream);
        ACHFile.LoadFromStream(ContentStream);
    end;

    // NACHA entry hash: the sum of the first 8 digits of every entry's routing number, the offset entry included.
    local procedure ExpectedEntryHash(GenJournalBatch: Record "Gen. Journal Batch"; BankAccount: Record "Bank Account") Hash: BigInteger
    var
        GenJournalLine: Record "Gen. Journal Line";
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindSet();
        repeat
            VendorBankAccount.Get(GenJournalLine."Account No.", GenJournalLine."Recipient Bank Account");
            Hash += ToBigInteger(CopyStr(VendorBankAccount."Transit No.", 1, 8));
        until GenJournalLine.Next() = 0;
        Hash += ToBigInteger(CopyStr(BankAccount."Transit No.", 1, 8));
    end;

    local procedure Cents(Digits: Text): Decimal
    begin
        exit(ToBigInteger(Digits) / 100);
    end;

    local procedure ToBigInteger(Digits: Text) Value: BigInteger
    begin
        Evaluate(Value, DelChr(Digits, '<>', ' '));
    end;
}
