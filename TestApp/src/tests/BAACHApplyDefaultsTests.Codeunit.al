codeunit 81218 "BAACH Apply Defaults Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        NotElectronicTok: Label 'AAA', Locked = true;
        FirstElectronicTok: Label 'BBB', Locked = true;
        SecondElectronicTok: Label 'CCC', Locked = true;

    [Test]
    procedure AppliesToDocNoSetsElectronicPaymentAndRecipient()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        InvoiceNo: Code[20];
    begin
        CreateScenario(GenJournalBatch, Vendor, true);
        InvoiceNo := Library.PostVendorInvoice(Vendor."No.", 100);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 100);

        Library.ApplyByDocNo(GenJournalLine, InvoiceNo);

        GenJournalLine.Find();
        AssertElectronic(GenJournalLine, FirstElectronicTok);
    end;

    [Test]
    procedure ApplyEntriesSetsElectronicPaymentAndRecipient()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        ApplyEntriesStub: Codeunit "BAACH Apply Entries Stub";
        InvoiceNo: Code[20];
    begin
        CreateScenario(GenJournalBatch, Vendor, true);
        InvoiceNo := Library.PostVendorInvoice(Vendor."No.", 100);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 0);

        ApplyEntriesStub.SelectInvoice(InvoiceNo);
        BindSubscription(ApplyEntriesStub);
        Codeunit.Run(Codeunit::"Gen. Jnl.-Apply", GenJournalLine);
        UnbindSubscription(ApplyEntriesStub);

        GenJournalLine.Find();
        Assert.AreEqual(100, GenJournalLine.Amount, 'Apply Entries must have applied the invoice.');
        AssertElectronic(GenJournalLine, FirstElectronicTok);
    end;

    [Test]
    procedure AnElectronicRecipientAlreadyChosenIsKept()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        InvoiceNo: Code[20];
    begin
        CreateScenario(GenJournalBatch, Vendor, true);
        InvoiceNo := Library.PostVendorInvoice(Vendor."No.", 100);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 100);
        GenJournalLine.Validate("Recipient Bank Account", SecondElectronicTok);
        GenJournalLine.Modify(true);

        Library.ApplyByDocNo(GenJournalLine, InvoiceNo);

        GenJournalLine.Find();
        AssertElectronic(GenJournalLine, SecondElectronicTok);
    end;

    [Test]
    procedure ARecipientNotForElectronicPaymentsIsReplaced()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        InvoiceNo: Code[20];
    begin
        CreateScenario(GenJournalBatch, Vendor, true);
        InvoiceNo := Library.PostVendorInvoice(Vendor."No.", 100);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 100);
        GenJournalLine.Validate("Recipient Bank Account", NotElectronicTok);
        GenJournalLine.Modify(true);

        Library.ApplyByDocNo(GenJournalLine, InvoiceNo);

        GenJournalLine.Find();
        AssertElectronic(GenJournalLine, FirstElectronicTok);
    end;

    [Test]
    procedure AVendorWithoutAnElectronicBankAccountStillGetsElectronicPayment()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        InvoiceNo: Code[20];
    begin
        CreateScenario(GenJournalBatch, Vendor, false);
        InvoiceNo := Library.PostVendorInvoice(Vendor."No.", 100);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 100);

        Library.ApplyByDocNo(GenJournalLine, InvoiceNo);

        GenJournalLine.Find();
        Assert.AreEqual(InvoiceNo, GenJournalLine."Applies-to Doc. No.", 'The invoice must still be applied.');
        AssertElectronic(GenJournalLine, '');
    end;

    [Test]
    procedure WithTheSwitchOffTheLineIsUntouched()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        InvoiceNo: Code[20];
    begin
        CreateScenario(GenJournalBatch, Vendor, true);
        InvoiceNo := Library.PostVendorInvoice(Vendor."No.", 100);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 100);
        Library.SetSwitch(false);

        Library.ApplyByDocNo(GenJournalLine, InvoiceNo);

        GenJournalLine.Find();
        Assert.AreEqual(InvoiceNo, GenJournalLine."Applies-to Doc. No.", 'The invoice must still be applied.');
        Assert.AreEqual(GenJournalLine."Bank Payment Type"::" ", GenJournalLine."Bank Payment Type", 'Bank Payment Type with the switch off.');
        Assert.AreEqual('', GenJournalLine."Recipient Bank Account", 'Recipient Bank Account with the switch off.');
    end;

    [Test]
    procedure APrintedCheckIsUntouched()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        Vendor: Record Vendor;
        ApplyPaymentDefaults: Codeunit "BAACH Apply Payment Defaults";
    begin
        CreateScenario(GenJournalBatch, Vendor, true);
        CreatePlainPaymentLine(GenJournalLine, GenJournalBatch, Vendor."No.", 100);
        GenJournalLine.Validate("Bank Payment Type", GenJournalLine."Bank Payment Type"::"Computer Check");
        GenJournalLine."Check Printed" := true;
        GenJournalLine.Modify();

        ApplyPaymentDefaults.SetElectronicPaymentDefaults(GenJournalLine);

        Assert.AreEqual(GenJournalLine."Bank Payment Type"::"Computer Check", GenJournalLine."Bank Payment Type", 'A printed check keeps its Bank Payment Type.');
        Assert.AreEqual('', GenJournalLine."Recipient Bank Account", 'A printed check gets no recipient.');
    end;

    // The non-electronic account sorts first, so the tests prove the first *electronic* one is chosen.
    local procedure CreateScenario(var GenJournalBatch: Record "Gen. Journal Batch"; var Vendor: Record Vendor; WithElectronicBankAccounts: Boolean)
    var
        BankAccount: Record "Bank Account";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendor(Vendor);
        AddVendorBankAccount(Vendor."No.", NotElectronicTok, false);
        if WithElectronicBankAccounts then begin
            AddVendorBankAccount(Vendor."No.", SecondElectronicTok, true);
            AddVendorBankAccount(Vendor."No.", FirstElectronicTok, true);
        end;
    end;

    local procedure AddVendorBankAccount(VendorNo: Code[20]; BankAccountCode: Code[20]; UseForElectronicPayments: Boolean)
    var
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        Library.CreateVendorBankAccount(VendorBankAccount, VendorNo);
        VendorBankAccount.Rename(VendorNo, BankAccountCode);
        VendorBankAccount."Use for Electronic Payments" := UseForElectronicPayments;
        VendorBankAccount.Modify();
    end;

    local procedure CreatePlainPaymentLine(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; PaymentAmount: Decimal)
    begin
        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := GenJournalBatch."Journal Template Name";
        GenJournalLine."Journal Batch Name" := GenJournalBatch.Name;
        GenJournalLine."Line No." := Library.NextLineNo(GenJournalBatch);
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine.Validate("Document Type", GenJournalLine."Document Type"::Payment);
        GenJournalLine."Document No." := Library.UniqueCode('BAP', 20);
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Vendor);
        GenJournalLine.Validate("Account No.", VendorNo);
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"Bank Account");
        GenJournalLine.Validate("Bal. Account No.", GenJournalBatch."Bal. Account No.");
        GenJournalLine.Validate(Amount, PaymentAmount);
        GenJournalLine.Insert(true);
    end;

    local procedure AssertElectronic(GenJournalLine: Record "Gen. Journal Line"; ExpectedRecipient: Code[20])
    begin
        Assert.AreEqual(GenJournalLine."Bank Payment Type"::"Electronic Payment", GenJournalLine."Bank Payment Type", 'Bank Payment Type after applying.');
        Assert.AreEqual(ExpectedRecipient, GenJournalLine."Recipient Bank Account", 'Recipient Bank Account after applying.');
    end;
}
