codeunit 81215 "BAACH Posting Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";

    [Test]
    procedure PostingIsRefusedAfterGenerateAlone()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);

        asserterror Library.PostBatch(GenJournalBatch);
        Assert.ExpectedErrorContains(GenJournalLine.FieldCaption("Check Exported"));

        Assert.IsTrue(GenJournalLine.Find(), 'The line must still be in the journal.');
    end;

    [Test]
    procedure TheBatchPostsAfterGenerateAndExport()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        ByIDLine: Record "Gen. Journal Line";
        ByDocNoLine: Record "Gen. Journal Line";
        GenJournalLine: Record "Gen. Journal Line";
        ByIDInvoiceNo: Code[20];
        ByDocNoInvoiceNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        ByIDInvoiceNo := Library.CreateVendorPayment(ByIDLine, GenJournalBatch, 100, true);
        ByDocNoInvoiceNo := Library.CreateVendorPayment(ByDocNoLine, GenJournalBatch, 250, false);
        Library.GenerateEFT(GenJournalBatch);
        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());
        ByIDLine.Find();
        ByDocNoLine.Find();

        Library.PostBatch(GenJournalBatch);

        Library.FilterBatchLines(GenJournalLine, GenJournalBatch);
        Assert.RecordIsEmpty(GenJournalLine);
        VerifyPosted(BankAccount."No.", ByIDLine, ByIDInvoiceNo);
        VerifyPosted(BankAccount."No.", ByDocNoLine, ByDocNoInvoiceNo);
    end;

    [Test]
    procedure PostedJournalLinesKeepEFTFileCreated()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalLine: Record "Gen. Journal Line";
        PostedGenJournalLine: Record "Posted Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        GenJournalTemplate.Get(GenJournalBatch."Journal Template Name");
        GenJournalTemplate."Copy to Posted Jnl. Lines" := true;
        GenJournalTemplate.Modify();
        GenJournalBatch."Copy to Posted Jnl. Lines" := true;
        GenJournalBatch.Modify();
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());
        GenJournalLine.Find();

        Library.PostBatch(GenJournalBatch);

        PostedGenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        PostedGenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        PostedGenJournalLine.SetRange("Document No.", GenJournalLine."Document No.");
        Assert.RecordCount(PostedGenJournalLine, 1);
        PostedGenJournalLine.FindFirst();
        Assert.IsTrue(PostedGenJournalLine."BAACH EFT File Created", 'EFT File Created on the posted journal line');
    end;

    local procedure VerifyPosted(BankAccountNo: Code[20]; GenJournalLine: Record "Gen. Journal Line"; InvoiceNo: Code[20])
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        CheckLedgerEntry: Record "Check Ledger Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
    begin
        Library.FindInvoiceEntry(VendorLedgerEntry, GenJournalLine."Account No.", InvoiceNo);
        Assert.IsFalse(VendorLedgerEntry.Open, 'The invoice must be closed by the payment ' + GenJournalLine."Document No.");

        CheckLedgerEntry.SetRange("Bank Account No.", BankAccountNo);
        CheckLedgerEntry.SetRange("Check No.", GenJournalLine."Document No.");
        Assert.RecordCount(CheckLedgerEntry, 1);
        CheckLedgerEntry.FindFirst();
        Assert.AreEqual(CheckLedgerEntry."Entry Status"::Posted, CheckLedgerEntry."Entry Status", 'Check ledger entry status');
        Assert.IsTrue(BankAccountLedgerEntry.Get(CheckLedgerEntry."Bank Account Ledger Entry No."), 'The check ledger entry must link to a bank account ledger entry.');
        Assert.AreEqual(GenJournalLine."Document No.", BankAccountLedgerEntry."Document No.", 'Bank ledger Document No.');
        Assert.AreEqual(BankAccountNo, BankAccountLedgerEntry."Bank Account No.", 'Bank ledger bank account');
        Assert.AreEqual(-GenJournalLine.Amount, BankAccountLedgerEntry.Amount, 'Bank ledger amount');
    end;
}
