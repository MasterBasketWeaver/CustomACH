codeunit 81210 "BAACH Setup Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        SetupMgt: Codeunit "BAACH Setup Mgt.";

    [Test]
    procedure SwitchIsOffOnANewSetupRecord()
    var
        TempPurchasesPayablesSetup: Record "Purchases & Payables Setup" temporary;
    begin
        TempPurchasesPayablesSetup.Init();
        Assert.IsFalse(TempPurchasesPayablesSetup."BAACH Enable EFT Before Export", 'The switch must default to off (standard process).');
    end;

    [Test]
    procedure IsEnabledFollowsTheSwitch()
    begin
        Library.SetSwitch(false);
        Assert.IsFalse(SetupMgt.IsEnabled(), 'IsEnabled with the switch off.');
        Library.SetSwitch(true);
        Assert.IsTrue(SetupMgt.IsEnabled(), 'IsEnabled with the switch on.');
    end;

    [Test]
    procedure IsEnabledForBatchNeedsTheSwitchAndAUSFormatBank()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Assert.IsTrue(SetupMgt.IsEnabledForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'Switch on, US bank.');

        Library.SetSwitch(false);
        Assert.IsFalse(SetupMgt.IsEnabledForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'Switch off, US bank.');
    end;

    [Test]
    procedure IsEnabledForBatchIsFalseForBlankOrOtherExportFormat()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);

        BankAccount."Export Format" := BankAccount."Export Format"::Other;
        BankAccount.Modify();
        Assert.IsFalse(SetupMgt.IsEnabledForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'Export Format Other (AMC) stays standard.');

        BankAccount."Export Format" := 0;
        BankAccount.Modify();
        Assert.IsFalse(SetupMgt.IsEnabledForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'A blank Export Format stays standard.');
    end;

    [Test]
    procedure GenerateIsRefusedWhenTheSwitchIsOff()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        DocumentNo: Code[20];
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        DocumentNo := GenJournalLine."Document No.";
        Library.SetSwitch(false);

        Commit();
        asserterror Library.GenerateEFT(GenJournalBatch);

        GenJournalLine.Find();
        Assert.AreEqual(DocumentNo, GenJournalLine."Document No.", 'Document No. must not change.');
        Assert.IsFalse(GenJournalLine."Check Printed", 'Check Printed must stay off.');
        Assert.IsFalse(GenJournalLine."BAACH EFT File Created", 'EFT File Created must stay off.');
        BankAccount.Find();
        Assert.AreEqual(Library.LastRemittanceAdviceNo(), BankAccount."Last Remittance Advice No.", 'No remittance advice number may be consumed.');
    end;

    [Test]
    procedure ExportIsRefusedWhenTheSwitchIsOff()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExportRemittance: Codeunit "BAACH Export Remittance";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.SetSwitch(false);

        Commit();
        asserterror ExportRemittance.ExportForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        GenJournalLine.Find();
        Assert.IsFalse(GenJournalLine."Check Exported", 'Check Exported must stay off.');
        Assert.IsFalse(GenJournalLine."Check Transmitted", 'Check Transmitted must stay off.');
    end;

    [Test]
    procedure VoidIsRefusedWhenTheSwitchIsOff()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        VoidEFT: Codeunit "BAACH Void EFT";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.SetSwitch(false);

        Commit();
        asserterror VoidEFT.VoidForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);

        GenJournalLine.Find();
        Assert.IsTrue(GenJournalLine."BAACH EFT File Created", 'EFT File Created must stay on.');
        Assert.IsTrue(GenJournalLine."Check Printed", 'Check Printed must stay on.');
    end;

    [Test]
    procedure LineGuardIsInertWhenTheSwitchIsOff()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        GenJournalLine."BAACH EFT File Created" := true;
        GenJournalLine.Modify();
        Library.SetSwitch(false);

        GenJournalLine.Description := 'Changed with the switch off';
        GenJournalLine.Modify(true);
        GenJournalLine.Delete(true);

        Assert.IsFalse(GenJournalLine.Find(), 'The line must be deletable with the switch off.');
    end;

    [Test]
    procedure CheckLineBypassIsNotActiveOutsideGenerate()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);

        Commit();
        asserterror Codeunit.Run(Codeunit::"Gen. Jnl.-Check Line", GenJournalLine);
        Assert.ExpectedErrorContains(GenJournalLine.FieldCaption("Check Exported"));

        Library.SetSwitch(false);
        Commit();
        asserterror Codeunit.Run(Codeunit::"Gen. Jnl.-Check Line", GenJournalLine);
        Assert.ExpectedErrorContains(GenJournalLine.FieldCaption("Check Exported"));
    end;

    [Test]
    procedure SwitchOffIsRefusedWhileLinesAreInProgress()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);

        PurchasesPayablesSetup.Get();
        Commit();
        asserterror PurchasesPayablesSetup.Validate("BAACH Enable EFT Before Export", false);
        Assert.ExpectedErrorContains(GenJournalBatch.Name);
    end;

    [Test]
    procedure CheckNoLinesInProgressNamesTheBatch()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);

        Commit();
        asserterror SetupMgt.CheckNoLinesInProgress();
        Assert.ExpectedErrorContains(GenJournalBatch.Name);
    end;

    [Test]
    procedure SwitchOffIsAllowedOnceTheLinesAreExported()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        Library.MarkBatchExported(GenJournalBatch, Library.PDFOutput());

        PurchasesPayablesSetup.Get();
        PurchasesPayablesSetup.Validate("BAACH Enable EFT Before Export", false);
        PurchasesPayablesSetup.Modify();

        Assert.IsFalse(SetupMgt.IsEnabled(), 'The switch must be off.');
    end;

    [Test]
    procedure SwitchOffIsAllowedWithNothingInProgress()
    var
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
    begin
        Library.SetSwitch(true);

        PurchasesPayablesSetup.Get();
        PurchasesPayablesSetup.Validate("BAACH Enable EFT Before Export", false);
        PurchasesPayablesSetup.Modify();

        Assert.IsFalse(SetupMgt.IsEnabled(), 'The switch must be off.');
    end;
}
