codeunit 81101 "BAACH Generate EFT"
{
    var
        SetupMgt: Codeunit "BAACH Setup Mgt.";
        NotCustomModeErr: Label 'Generate EFT File is not available for journal batch %1 %2. It needs %3 turned on in Purchases & Payables Setup and a batch whose balancing bank account has Export Format US, CA or MX.', Comment = '%1 = journal template name, %2 = journal batch name, %3 = the setup field caption';
        SettlementDateMissingErr: Label 'You must specify a settlement date.';
        NothingToGenerateErr: Label 'There is nothing to generate. Journal batch %1 %2 has no electronic payment lines waiting for an EFT file.', Comment = '%1 = journal template name, %2 = journal batch name';
        LineStateInconsistentErr: Label 'Journal line %1 in %2 %3 is marked Check Printed but has no EFT Export entry waiting to be generated, so the EFT file cannot be generated for it.', Comment = '%1 = line no., %2 = journal template name, %3 = journal batch name';
        NoNextRemittanceNoErr: Label 'The next remittance advice number cannot be calculated from %1 %2 on bank account %3. It must end in a number.', Comment = '%1 = field caption, %2 = current value, %3 = bank account no.';
        HasErrorsErr: Label 'The file export has one or more errors.\\For each line to be exported, resolve the errors displayed to the right and then try to export again.';
        LastRemittanceErr: Label 'Last Remittance Advice No. must have a value in the bank account.';
        NoExportNegativeErr: Label 'You cannot export journal entries with negative amounts.';
        UseForElecPaymentCheckedErr: Label 'The Use for Electronic Payments check box must be selected on the vendor or customer bank account card.';
        NoExportDiffCurrencyErr: Label 'You cannot export journal entries if Currency Code is different in Gen. Journal Line and Bank Account.';
        RecipientBankAccountEmptyErr: Label 'Recipient Bank Account must be filled.';
        DifferentBankAccountErr: Label 'The line pays from bank account %1, but the journal batch pays from bank account %2. Generate EFT File only handles lines for the batch bank account.', Comment = '%1 = the line bank account no., %2 = the batch bank account no.';
        VendorTransitNumNotValidErr: Label 'The specified transit number %1 for vendor %2  is not valid.', Comment = '%1 the transit number, %2 The Vendor No.';

    procedure GenerateForBatch(TemplateName: Code[10]; BatchName: Code[10]; SettlementDate: Date)
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        BankAccount: Record "Bank Account";
        TempEFTExportWorkset: Record "EFT Export Workset" temporary;
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
        GenerateEFT: Codeunit "Generate EFT";
        EFTValues: Codeunit "EFT Values";
        EFTRunScope: Codeunit "BAACH EFT Run Scope";
    begin
        if not SetupMgt.IsEnabledForBatch(TemplateName, BatchName) then
            Error(NotCustomModeErr, TemplateName, BatchName, PurchasesPayablesSetup.FieldCaption("BAACH Enable EFT Before Export"));
        if SettlementDate = 0D then
            Error(SettlementDateMissingErr);

        OnBeforeGenerateEFT(TemplateName, BatchName, SettlementDate);

        CheckBatchAndBank(TemplateName, BatchName, GenJournalBatch, BankAccount);
        CheckLinesBeforeExport(GenJournalBatch, BankAccount);
        PreCheckLines(GenJournalBatch, BankAccount);
        PrepareLines(GenJournalBatch, BankAccount);
        BuildWorkset(GenJournalBatch, BankAccount, TempEFTExportWorkset);

        EFTRunScope.SetBatch(TemplateName, BatchName);
        EFTRunScope.SetGeneratingFile();
        BindSubscription(EFTRunScope);
        GenerateEFT.ProcessAndGenerateEFTFile(BankAccount."No.", SettlementDate, TempEFTExportWorkset, EFTValues);
        UnbindSubscription(EFTRunScope);

        OnAfterGenerateEFT(TemplateName, BatchName, SettlementDate);
    end;

    // True only while GenerateForBatch runs the standard EFT engine. The answer comes from the bound run scope, so
    // it cannot outlive the run when the engine errors. Lets an extension limit its subscribers on standard EFT
    // events to the files this app generates.
    procedure IsGeneratingEFTFile(): Boolean
    var
        IsGenerating: Boolean;
    begin
        OnIsGeneratingEFTFile(IsGenerating);
        exit(IsGenerating);
    end;

    procedure SetLinesToGenerateFilter(var GenJournalLine: Record "Gen. Journal Line"; TemplateName: Code[10]; BatchName: Code[10])
    begin
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", TemplateName);
        GenJournalLine.SetRange("Journal Batch Name", BatchName);
        GenJournalLine.SetFilter("Bank Payment Type", '%1|%2', GenJournalLine."Bank Payment Type"::"Electronic Payment", GenJournalLine."Bank Payment Type"::"Electronic Payment-IAT");
        GenJournalLine.SetFilter("Amount (LCY)", '<>0');
        GenJournalLine.SetRange("Check Exported", false);
        GenJournalLine.SetRange("BAACH EFT File Created", false);
    end;

    procedure GetLineBankAccountNo(GenJournalLine: Record "Gen. Journal Line"): Code[20]
    begin
        if GenJournalLine."Account Type" = GenJournalLine."Account Type"::"Bank Account" then
            exit(GenJournalLine."Account No.");
        exit(GenJournalLine."Bal. Account No.");
    end;

    local procedure CheckBatchAndBank(TemplateName: Code[10]; BatchName: Code[10]; var GenJournalBatch: Record "Gen. Journal Batch"; var BankAccount: Record "Bank Account")
    var
        GenJournalLine: Record "Gen. Journal Line";
        CompanyInformation: Record "Company Information";
        BankExportImportSetup: Record "Bank Export/Import Setup";
        RecordRestrictionMgt: Codeunit "Record Restriction Mgt.";
    begin
        GenJournalBatch.Get(TemplateName, BatchName);
        GenJournalBatch.TestField("Bal. Account Type", GenJournalBatch."Bal. Account Type"::"Bank Account");
        GenJournalBatch.TestField("Posting No. Series", '');
        // The batch's own OnCheckGenJournalLineExportRestrictions is OnPrem; this is its public subscriber.
        RecordRestrictionMgt.GenJournalBatchCheckGenJournalLineExportRestrictions(GenJournalBatch);

        BankAccount.Get(GenJournalBatch."Bal. Account No.");
        BankAccount.TestField(Blocked, false);
        BankAccount.TestField("Export Format");

        CompanyInformation.Get();
        CompanyInformation.TestField("Federal ID No.");

        GenJournalLine.SetRange("Journal Template Name", TemplateName);
        GenJournalLine.SetRange("Journal Batch Name", BatchName);
        GenJournalLine.CheckIfPrivacyBlocked();

        SetLinesToGenerateFilter(GenJournalLine, TemplateName, BatchName);
        if GenJournalLine.IsEmpty() then
            Error(NothingToGenerateErr, TemplateName, BatchName);

        GenJournalLine.SetRange("Bank Payment Type", GenJournalLine."Bank Payment Type"::"Electronic Payment");
        if not GenJournalLine.IsEmpty() then begin
            BankAccount.TestField("Payment Export Format");
            BankExportImportSetup.Get(BankAccount."Payment Export Format");
        end;
        GenJournalLine.SetRange("Bank Payment Type", GenJournalLine."Bank Payment Type"::"Electronic Payment-IAT");
        if not GenJournalLine.IsEmpty() then begin
            BankAccount.TestField("EFT Export Code");
            BankExportImportSetup.Get(BankAccount."EFT Export Code");
        end;
    end;

    // Page 256 ExportPaymentsToFile: errors go to the payment file error table (shown in the journal's
    // errors factbox), then it commits so they survive the Error.
    local procedure CheckLinesBeforeExport(GenJournalBatch: Record "Gen. Journal Batch"; BankAccount: Record "Bank Account")
    var
        GenJournalLine: Record "Gen. Journal Line";
        BatchLine: Record "Gen. Journal Line";
    begin
        BatchLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        BatchLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        BatchLine.FindFirst();
        BatchLine.DeletePaymentFileBatchErrors();

        SetLinesToGenerateFilter(GenJournalLine, GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
        GenJournalLine.FindSet();
        if BankAccount."Last Remittance Advice No." = '' then
            GenJournalLine.InsertPaymentFileError(LastRemittanceErr);
        repeat
            CheckPaymentLineBeforeExport(GenJournalLine, GenJournalBatch, BankAccount);
        until GenJournalLine.Next() = 0;

        if BatchLine.HasPaymentFileErrorsInBatch() then begin
            Commit();
            Error(HasErrorsErr);
        end;
    end;

    // Page 256 CheckPaymentLineBeforeExport, applied only to the lines this step will generate. Its Bank Payment
    // Type check is left out because non-electronic lines are not targets here.
    local procedure CheckPaymentLineBeforeExport(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; BankAccount: Record "Bank Account")
    var
        PaymentExportGenJnlCheck: Codeunit "Payment Export Gen. Jnl Check";
    begin
        if GenJournalLine."Currency Code" <> BankAccount."Currency Code" then
            GenJournalLine.InsertPaymentFileError(NoExportDiffCurrencyErr);
        if GetLineBankAccountNo(GenJournalLine) <> BankAccount."No." then
            GenJournalLine.InsertPaymentFileError(StrSubstNo(DifferentBankAccountErr, GetLineBankAccountNo(GenJournalLine), BankAccount."No."));
        if not GenJournalBatch."Allow Payment Export" then
            PaymentExportGenJnlCheck.AddBatchEmptyError(GenJournalLine, GenJournalBatch.FieldCaption("Allow Payment Export"), '');
        if GenJournalLine.Amount < 0 then
            GenJournalLine.InsertPaymentFileError(NoExportNegativeErr);
        if GenJournalLine."Recipient Bank Account" = '' then
            GenJournalLine.InsertPaymentFileError(RecipientBankAccountEmptyErr)
        else
            if not UseForElecPaymentChecked(GenJournalLine) then
                GenJournalLine.InsertPaymentFileError(UseForElecPaymentCheckedErr);
    end;

    local procedure UseForElecPaymentChecked(GenJournalLine: Record "Gen. Journal Line"): Boolean
    var
        CustomerBankAccount: Record "Customer Bank Account";
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        if GenJournalLine."Bal. Account Type" <> GenJournalLine."Bal. Account Type"::"Bank Account" then
            case GenJournalLine."Bal. Account Type" of
                GenJournalLine."Bal. Account Type"::Vendor:
                    begin
                        if VendorBankAccount.Get(GenJournalLine."Bal. Account No.", GenJournalLine."Recipient Bank Account") then
                            exit(VendorBankAccount."Use for Electronic Payments");
                        exit(false);
                    end;
                GenJournalLine."Bal. Account Type"::Customer:
                    begin
                        if CustomerBankAccount.Get(GenJournalLine."Bal. Account No.", GenJournalLine."Recipient Bank Account") then
                            exit(CustomerBankAccount."Use for Electronic Payments");
                        exit(false);
                    end;
                else
                    exit(true);
            end;

        case GenJournalLine."Account Type" of
            GenJournalLine."Account Type"::"Bank Account":
                exit(false);
            GenJournalLine."Account Type"::Vendor:
                begin
                    if VendorBankAccount.Get(GenJournalLine."Account No.", GenJournalLine."Recipient Bank Account") then
                        exit(VendorBankAccount."Use for Electronic Payments");
                    exit(false);
                end;
            GenJournalLine."Account Type"::Customer:
                begin
                    if CustomerBankAccount.Get(GenJournalLine."Account No.", GenJournalLine."Recipient Bank Account") then
                        exit(CustomerBankAccount."Use for Electronic Payments");
                    exit(false);
                end;
            else
                exit(true);
        end;
    end;

    // Runs the checks that Generate EFT makes before it writes anything, so a problem surfaces before any
    // remittance advice number is consumed.
    local procedure PreCheckLines(GenJournalBatch: Record "Gen. Journal Batch"; BankAccount: Record "Bank Account")
    var
        GenJournalLine: Record "Gen. Journal Line";
        TempGenJournalLine: Record "Gen. Journal Line" temporary;
        EFTRunScope: Codeunit "BAACH EFT Run Scope";
        CheckTheCheckDigit: Boolean;
        NextDocumentNo: Code[20];
    begin
        CheckTheCheckDigit := not (BankAccount."Export Format" in [BankAccount."Export Format"::CA, BankAccount."Export Format"::MX]);
        NextDocumentNo := CopyStr(IncStr(BankAccount."Last Remittance Advice No."), 1, MaxStrLen(NextDocumentNo));
        if NextDocumentNo = '' then
            NextDocumentNo := BankAccount."Last Remittance Advice No.";

        EFTRunScope.SetBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
        BindSubscription(EFTRunScope);
        SetLinesToGenerateFilter(GenJournalLine, GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
        if GenJournalLine.FindSet() then
            repeat
                CheckVendorTransitNum(GenJournalLine, CheckTheCheckDigit);

                TempGenJournalLine := GenJournalLine;
                if not SetupMgt.IsLinePrepared(GenJournalLine) then
                    TempGenJournalLine."Document No." := NextDocumentNo;
                Codeunit.Run(Codeunit::"Gen. Jnl.-Check Line", TempGenJournalLine);
            until GenJournalLine.Next() = 0;
        UnbindSubscription(EFTRunScope);
    end;

    // Replicates Export Payments (ACH).CheckVendorTransitNum, which is OnPrem, as Generate EFT calls it:
    // with the line's Account No. whatever its account type.
    local procedure CheckVendorTransitNum(GenJournalLine: Record "Gen. Journal Line"; CheckTheCheckDigit: Boolean)
    var
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
        EFTRecipientBankAccountMgt: Codeunit "EFT Recipient Bank Account Mgt";
        ExportPaymentsACH: Codeunit "Export Payments (ACH)";
    begin
        Vendor.Get(GenJournalLine."Account No.");
        Vendor.TestField(Blocked, Vendor.Blocked::" ");
        Vendor.TestField("Privacy Blocked", false);

        EFTRecipientBankAccountMgt.GetRecipientVendorBankAccount(VendorBankAccount, GenJournalLine, GenJournalLine."Account No.");

        if CheckTheCheckDigit and (VendorBankAccount."Country/Region Code" = 'US') then
            if not ExportPaymentsACH.CheckDigit(VendorBankAccount."Transit No.") then
                Error(VendorTransitNumNotValidErr, VendorBankAccount."Transit No.", Vendor."No.");

        VendorBankAccount.TestField("Bank Account No.");
    end;

    local procedure PrepareLines(GenJournalBatch: Record "Gen. Journal Batch"; BankAccount: Record "Bank Account")
    var
        LineToCheck: Record "Gen. Journal Line";
        GenJournalLine: Record "Gen. Journal Line";
        EFTExport: Record "EFT Export";
    begin
        SetLinesToGenerateFilter(LineToCheck, GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
        if LineToCheck.FindSet() then
            repeat
                if not SetupMgt.IsLinePrepared(LineToCheck) then begin
                    if LineToCheck."Check Printed" then
                        Error(LineStateInconsistentErr, LineToCheck."Line No.", LineToCheck."Journal Template Name", LineToCheck."Journal Batch Name");
                    GenJournalLine := LineToCheck;
                    UpdateDocNoForGenLedgLine(GenJournalLine, BankAccount."No.");
                    CreateEFTRecord(EFTExport, GenJournalLine, BankAccount."No.");
                    UpdateCheckInfoForGenLedgLine(GenJournalLine, EFTExport);
                    CreateCreditTransferRegister(BankAccount."No.", GenJournalLine."Bal. Account No.", GenJournalLine."Bank Payment Type");
                    UpdateApplication(GenJournalLine);
                    OnAfterPrepareLine(GenJournalLine, EFTExport);
                end;
            until LineToCheck.Next() = 0;
    end;

    local procedure UpdateDocNoForGenLedgLine(var GenJournalLine: Record "Gen. Journal Line"; BankAccountNo: Code[20])
    var
        BankAccount: Record "Bank Account";
        NextRemittanceNo: Code[20];
    begin
        BankAccount.ReadIsolation := IsolationLevel::UpdLock;
        BankAccount.Get(BankAccountNo);
        NextRemittanceNo := CopyStr(IncStr(BankAccount."Last Remittance Advice No."), 1, MaxStrLen(NextRemittanceNo));
        if NextRemittanceNo = '' then
            Error(NoNextRemittanceNoErr, BankAccount.FieldCaption("Last Remittance Advice No."), BankAccount."Last Remittance Advice No.", BankAccount."No.");
        BankAccount."Last Remittance Advice No." := NextRemittanceNo;
        BankAccount.Modify();

        GenJournalLine."Document No." := NextRemittanceNo;
        GenJournalLine.Modify();

        InsertIntoCheckLedger(GenJournalLine, BankAccountNo);
    end;

    local procedure InsertIntoCheckLedger(var GenJournalLine: Record "Gen. Journal Line"; BankAccountNo: Code[20])
    var
        CheckLedgerEntry: Record "Check Ledger Entry";
        BankAccount: Record "Bank Account";
        CheckManagement: Codeunit CheckManagement;
    begin
        BankAccount.Get(BankAccountNo);

        CheckLedgerEntry.Init();
        CheckLedgerEntry."Bank Account No." := BankAccount."No.";
        CheckLedgerEntry."Posting Date" := GenJournalLine."Document Date";
        CheckLedgerEntry."Document Type" := GenJournalLine."Document Type";
        CheckLedgerEntry."Document No." := GenJournalLine."Document No.";
        CheckLedgerEntry.Description := GenJournalLine.Description;
        CheckLedgerEntry."Bank Payment Type" := CheckLedgerEntry."Bank Payment Type"::"Electronic Payment";
        CheckLedgerEntry."Entry Status" := CheckLedgerEntry."Entry Status"::Exported;
        CheckLedgerEntry."Check Date" := GenJournalLine."Document Date";
        CheckLedgerEntry."Check No." := GenJournalLine."Document No.";

        if GenJournalLine."Account Type" = GenJournalLine."Account Type"::"Bank Account" then begin
            CheckLedgerEntry."Bal. Account Type" := GenJournalLine."Bal. Account Type";
            CheckLedgerEntry."Bal. Account No." := GenJournalLine."Bal. Account No.";
            CheckLedgerEntry.Amount := -GenJournalLine.Amount;
        end else begin
            CheckLedgerEntry."Bal. Account Type" := GenJournalLine."Account Type";
            CheckLedgerEntry."Bal. Account No." := GenJournalLine."Account No.";
            CheckLedgerEntry.Amount := GenJournalLine.Amount;
        end;
        CheckManagement.InsertCheck(CheckLedgerEntry, GenJournalLine.RecordId);
    end;

    local procedure CreateEFTRecord(var EFTExport: Record "EFT Export"; GenJournalLine: Record "Gen. Journal Line"; BankAccountNo: Code[20])
    begin
        EFTExport.Init();
        EFTExport."Journal Template Name" := GenJournalLine."Journal Template Name";
        EFTExport."Journal Batch Name" := GenJournalLine."Journal Batch Name";
        EFTExport."Line No." := GenJournalLine."Line No.";
        EFTExport."Sequence No." := GetNextSequenceNo();

        EFTExport."Bank Account No." := BankAccountNo;
        EFTExport."Bank Payment Type" := GenJournalLine."Bank Payment Type";
        EFTExport."Transaction Code" := GenJournalLine."Transaction Code";
        EFTExport."Document Type" := GenJournalLine."Document Type";
        EFTExport."Posting Date" := GenJournalLine."Posting Date";
        EFTExport."Account Type" := GenJournalLine."Account Type";
        EFTExport."Account No." := GenJournalLine."Account No.";
        EFTExport."Applies-to ID" := GenJournalLine."Applies-to ID";
        EFTExport."Document No." := GenJournalLine."Document No.";
        EFTExport.Description := GenJournalLine.Description;
        EFTExport."Currency Code" := GenJournalLine."Currency Code";
        EFTExport."Bal. Account No." := GenJournalLine."Bal. Account No.";
        EFTExport."Bal. Account Type" := GenJournalLine."Bal. Account Type";
        EFTExport."Applies-to Doc. Type" := GenJournalLine."Applies-to Doc. Type";
        EFTExport."Applies-to Doc. No." := GenJournalLine."Applies-to Doc. No.";
        EFTExport."Check Exported" := true;
        EFTExport."Check Printed" := true;
        EFTExport."Exported to Payment File" := true;
        EFTExport."Amount (LCY)" := GenJournalLine."Amount (LCY)";
        EFTExport."Foreign Exchange Reference" := GenJournalLine."Foreign Exchange Reference";
        EFTExport."Foreign Exchange Indicator" := GenJournalLine."Foreign Exchange Indicator";
        EFTExport."Foreign Exchange Ref.Indicator" := GenJournalLine."Foreign Exchange Ref.Indicator";
        EFTExport."Country/Region Code" := GenJournalLine."Country/Region Code";
        EFTExport."Source Code" := GenJournalLine."Source Code";
        EFTExport."Company Entry Description" := GenJournalLine."Company Entry Description";
        EFTExport."Transaction Type Code" := GenJournalLine."Transaction Type Code";
        EFTExport."Payment Related Information 1" := GenJournalLine."Payment Related Information 1";
        EFTExport."Payment Related Information 2" := GenJournalLine."Payment Related Information 2";
        EFTExport."Gateway Operator OFAC Scr.Inc" := GenJournalLine."Gateway Operator OFAC Scr.Inc";
        EFTExport."Secondary OFAC Scr.Indicator" := GenJournalLine."Secondary OFAC Scr.Indicator";
        EFTExport."Origin. DFI ID Qualifier" := GenJournalLine."Origin. DFI ID Qualifier";
        EFTExport."Receiv. DFI ID Qualifier" := GenJournalLine."Receiv. DFI ID Qualifier";
        EFTExport."Document Date" := GenJournalLine."Document Date";
        EFTExport."External Document No." := GenJournalLine."External Document No.";
        EFTExport."Payment Reference" := GenJournalLine."Payment Reference";
        EFTExport.Insert();
    end;

    // Unlike standard Export this leaves Check Exported false: that flag now means the remittance went out (step 2).
    local procedure UpdateCheckInfoForGenLedgLine(var GenJournalLine: Record "Gen. Journal Line"; EFTExport: Record "EFT Export")
    begin
        GenJournalLine."Check Printed" := true;
        GenJournalLine."Exported to Payment File" := true;
        GenJournalLine."EFT Export Sequence No." := EFTExport."Sequence No.";
        GenJournalLine.Modify();
    end;

    // Standard commits here after every line; this step leaves the first Commit to Generate EFT, so a failure
    // before the file is started rolls the whole preparation back.
    local procedure CreateCreditTransferRegister(BankAccountNo: Code[20]; BalAccountNo: Code[20]; BankPaymentType: Enum "Bank Payment Type")
    var
        BankExportImportSetup: Record "Bank Export/Import Setup";
        CreditTransferRegister: Record "Credit Transfer Register";
        DataExchDef: Record "Data Exch. Def";
        BankAccount: Record "Bank Account";
        NewIdentifier: Code[20];
    begin
        BankAccount.Get(BankAccountNo);

        if BankPaymentType = "Bank Payment Type"::"Electronic Payment" then
            BankExportImportSetup.Get(BankAccount."Payment Export Format")
        else
            if BankPaymentType = "Bank Payment Type"::"Electronic Payment-IAT" then
                BankExportImportSetup.Get(BankAccount."EFT Export Code");

        if BankExportImportSetup.Direction <> BankExportImportSetup.Direction::"Export-EFT" then
            if BankAccount."Payment Export Format" <> '' then begin
                DataExchDef.Get(BankAccount."Payment Export Format");
                NewIdentifier := DataExchDef.Code;
            end;

        CreditTransferRegister.CreateNew(NewIdentifier, BalAccountNo);
    end;

    local procedure UpdateApplication(var GenJournalLine: Record "Gen. Journal Line")
    begin
        if GenJournalLine."Document No." = '' then
            exit;

        UpdateVendorLedgerEntryByAppliesToID(GenJournalLine);

        if GenJournalLine."Applies-to ID" <> '' then begin
            GenJournalLine.Validate("Applies-to ID", GenJournalLine."Document No.");
            GenJournalLine.Modify();
        end;
    end;

    local procedure UpdateVendorLedgerEntryByAppliesToID(GenJournalLine: Record "Gen. Journal Line")
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        if (GenJournalLine."Document No." = GenJournalLine."Applies-to ID") or (GenJournalLine."Applies-to ID" = '') then
            exit;

        VendorLedgerEntry.SetRange("Vendor No.", GetVendorNo(GenJournalLine));
        VendorLedgerEntry.SetRange("Applies-to ID", GenJournalLine."Applies-to ID");
        if VendorLedgerEntry.FindSet() then
            repeat
                VendorLedgerEntry."Applies-to ID" := GenJournalLine."Document No.";
                Codeunit.Run(Codeunit::"Vend. Entry-Edit", VendorLedgerEntry);
            until VendorLedgerEntry.Next() = 0;
    end;

    local procedure GetVendorNo(GenJournalLine: Record "Gen. Journal Line"): Code[20]
    begin
        if GenJournalLine."Account Type" = GenJournalLine."Account Type"::Vendor then
            exit(GenJournalLine."Account No.");
        exit(GenJournalLine."Bal. Account No.");
    end;

    local procedure GetNextSequenceNo(): Integer
    var
        EFTExport: Record "EFT Export";
    begin
        EFTExport.SetCurrentKey("Sequence No.");
        if EFTExport.FindLast() then
            exit(EFTExport."Sequence No." + 1);
        exit(1);
    end;

    // As page 10811 "Generate EFT File Lines" builds it, limited to this batch's lines that step 1 prepared.
    local procedure BuildWorkset(GenJournalBatch: Record "Gen. Journal Batch"; BankAccount: Record "Bank Account"; var TempEFTExportWorkset: Record "EFT Export Workset" temporary)
    var
        EFTExport: Record "EFT Export";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        TempEFTExportWorkset.Reset();
        TempEFTExportWorkset.DeleteAll();

        EFTExport.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        EFTExport.SetRange("Journal Batch Name", GenJournalBatch.Name);
        EFTExport.SetRange("Bank Account No.", BankAccount."No.");
        EFTExport.SetRange(Transmitted, false);
        if EFTExport.FindSet() then
            repeat
                if GenJournalLine.Get(EFTExport."Journal Template Name", EFTExport."Journal Batch Name", EFTExport."Line No.") then
                    if (GenJournalLine."EFT Export Sequence No." = EFTExport."Sequence No.") and SetupMgt.IsLinePrepared(GenJournalLine) and SetupMgt.IsTargetLine(GenJournalLine) then begin
                        EFTExport.Description := CopyStr(EFTExport.Description, 1, MaxStrLen(TempEFTExportWorkset.Description));
                        TempEFTExportWorkset.TransferFields(EFTExport);
                        TempEFTExportWorkset.Include := true;
                        TempEFTExportWorkset.Insert();
                    end;
            until EFTExport.Next() = 0;

        if TempEFTExportWorkset.IsEmpty() then
            Error(NothingToGenerateErr, GenJournalBatch."Journal Template Name", GenJournalBatch.Name);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenerateEFT(TemplateName: Code[10]; BatchName: Code[10]; SettlementDate: Date)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPrepareLine(var GenJournalLine: Record "Gen. Journal Line"; var EFTExport: Record "EFT Export")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGenerateEFT(TemplateName: Code[10]; BatchName: Code[10]; SettlementDate: Date)
    begin
    end;

    [InternalEvent(false)]
    local procedure OnIsGeneratingEFTFile(var IsGenerating: Boolean)
    begin
    end;
}
