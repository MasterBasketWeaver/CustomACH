codeunit 81216 "BAACH Void Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        VoidEFT: Codeunit "BAACH Void EFT";

    [Test]
    procedure VoidAfterGenerateReversesStepOne()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CheckLedgerEntry: Record "Check Ledger Entry";
        EFTExport: Record "EFT Export";
        VoidedNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();
        VoidedNo := GenJournalLine."Document No.";

        VoidEFT.VoidForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        GenJournalLine.Find();
        Assert.IsFalse(GenJournalLine."Check Printed", 'Check Printed');
        Assert.IsFalse(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        Assert.IsFalse(GenJournalLine."Check Exported", 'Check Exported');
        Assert.IsFalse(GenJournalLine."Check Transmitted", 'Check Transmitted');
        Assert.IsFalse(GenJournalLine."Exported to Payment File", 'Exported to Payment File');
        Assert.AreEqual(0, GenJournalLine."EFT Export Sequence No.", 'EFT Export Sequence No.');
        Assert.AreNotEqual(VoidedNo, GenJournalLine."Document No.", 'The voided remittance advice no. must be released from the line.');

        EFTExport.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalBatch.Name);
        Assert.RecordIsEmpty(EFTExport);

        CheckLedgerEntry.SetRange("Bank Account No.", BankAccount."No.");
        CheckLedgerEntry.SetRange("Check No.", VoidedNo);
        Assert.RecordCount(CheckLedgerEntry, 1);
        CheckLedgerEntry.FindFirst();
        Assert.AreEqual(CheckLedgerEntry."Entry Status"::Voided, CheckLedgerEntry."Entry Status", 'Check ledger entry status');
    end;

    [Test]
    procedure LinesAreEditableAgainAfterVoid()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);

        VoidEFT.VoidForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        GenJournalLine.Find();
        GenJournalLine.Description := 'Changed after Void';
        GenJournalLine.Modify(true);
        GenJournalLine.Find();
        Assert.AreEqual('Changed after Void', GenJournalLine.Description, 'Description');
    end;

    [Test]
    procedure RegeneratingAfterVoidAssignsANewNumber()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        FirstNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();
        FirstNo := GenJournalLine."Document No.";
        VoidEFT.VoidForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        Library.GenerateEFT(GenJournalBatch);

        GenJournalLine.Find();
        Assert.AreEqual(IncStr(FirstNo), GenJournalLine."Document No.", 'A voided number stays consumed; the next one is used.');
        Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        BankAccount.Find();
        Assert.AreEqual(IncStr(FirstNo), BankAccount."Last Remittance Advice No.", 'Last Remittance Advice No.');
    end;

    [Test]
    procedure VoidIsRefusedOnceTheLinesAreExported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());

        Commit();
        asserterror VoidEFT.VoidForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        VerifyStillExported(BankAccount."No.", GenJournalLine);
    end;

    [Test]
    procedure VoidIsRefusedForAVendorWhoseEmailFailed()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        RemittanceRunScope.SetBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name, BankAccount."No.");
        RemittanceRunScope.MarkLinesExported(CustomLayoutReporting.GetEmailOption());
        RemittanceRunScope.MarkVendorEmailFailed(GenJournalLine."Account No.");

        Commit();
        asserterror VoidEFT.VoidForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        VerifyStillExported(BankAccount."No.", GenJournalLine);
    end;

    local procedure VerifyStillExported(BankAccountNo: Code[20]; var GenJournalLine: Record "Gen. Journal Line")
    var
        CheckLedgerEntry: Record "Check Ledger Entry";
    begin
        GenJournalLine.Find();
        Assert.IsTrue(GenJournalLine."Check Exported", 'Check Exported');
        Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created');
        Assert.IsTrue(GenJournalLine."Check Printed", 'Check Printed');
        CheckLedgerEntry.SetRange("Bank Account No.", BankAccountNo);
        CheckLedgerEntry.SetRange("Check No.", GenJournalLine."Document No.");
        CheckLedgerEntry.FindFirst();
        Assert.AreEqual(CheckLedgerEntry."Entry Status"::Exported, CheckLedgerEntry."Entry Status", 'Check ledger entry status');
    end;
}
