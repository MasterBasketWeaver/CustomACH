// Fixtures. Every record a test needs is created here under a unique code, and test isolation
// removes it again. Company setup that cannot be invented (posting groups, a G/L account to
// post invoices against) is borrowed from records the company already has.
codeunit 81207 "BAACH Library"
{
    var
        USEFTResourceTok: Label 'US-EFT-DEFAULT.xml', Locked = true;
        FederalIdNoTok: Label '123456789', Locked = true;
        BankTransitNoTok: Label '021000021', Locked = true;
        VendorTransitNoTok: Label '011000015', Locked = true;
        LastRemittanceAdviceNoTok: Label 'RA000100', Locked = true;
        LastEPayFileNameTok: Label 'ACH000001', Locked = true;
        NoDataExchDefInResourceErr: Label 'The resource %1 contains no DataExchDef element.', Comment = '%1 = resource name';
        NoSourceVendorErr: Label 'The company has no unblocked LCY vendor with a vendor posting group that has a payables account. One is needed to copy posting groups from.';
        NoExpenseAccountErr: Label 'The company has no direct-posting income statement G/L account without a general posting type. One is needed to post test invoices against.';
        NoBankPostingGroupErr: Label 'The company has no bank account posting group with a G/L account.';
        VendorLedgerEntryNotFoundErr: Label 'No open vendor ledger entry for invoice %1 of vendor %2.', Comment = '%1 = document no., %2 = vendor no.';

    procedure SetSwitch(Enabled: Boolean)
    var
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
    begin
        PurchasesPayablesSetup.Get();
        PurchasesPayablesSetup."BAACH Enable EFT Before Export" := Enabled;
        PurchasesPayablesSetup.Modify();
    end;

    procedure UniqueCode(Prefix: Text; MaxLength: Integer): Code[20]
    begin
        exit(CopyStr(UpperCase(Prefix + DelChr(Format(CreateGuid()), '=', '{}-')), 1, MaxLength));
    end;

    procedure SettlementDate(): Date
    begin
        exit(CalcDate('<+3D>', WorkDate()));
    end;

    procedure PrepareCompany()
    begin
        EnsureFederalIdNo();
        OpenPostingDates();
        EnsureVendorRemittanceSelection();
    end;

    procedure EnsureFederalIdNo()
    var
        CompanyInformation: Record "Company Information";
    begin
        CompanyInformation.Get();
        if CompanyInformation."Federal ID No." <> '' then
            exit;
        CompanyInformation."Federal ID No." := FederalIdNoTok;
        CompanyInformation.Modify();
    end;

    procedure OpenPostingDates()
    var
        GeneralLedgerSetup: Record "General Ledger Setup";
        UserSetup: Record "User Setup";
    begin
        GeneralLedgerSetup.Get();
        if (GeneralLedgerSetup."Allow Posting From" <> 0D) or (GeneralLedgerSetup."Allow Posting To" <> 0D) then begin
            GeneralLedgerSetup."Allow Posting From" := 0D;
            GeneralLedgerSetup."Allow Posting To" := 0D;
            GeneralLedgerSetup.Modify();
        end;
        if UserSetup.Get(UserId()) then
            if (UserSetup."Allow Posting From" <> 0D) or (UserSetup."Allow Posting To" <> 0D) then begin
                UserSetup."Allow Posting From" := 0D;
                UserSetup."Allow Posting To" := 0D;
                UserSetup.Modify();
            end;
    end;

    procedure EnsureVendorRemittanceSelection()
    var
        ReportSelections: Record "Report Selections";
    begin
        ReportSelections.SetRange(Usage, ReportSelections.Usage::"V.Remittance");
        ReportSelections.SetFilter("Report ID", '<>0');
        if not ReportSelections.IsEmpty() then
            exit;
        ReportSelections.Init();
        ReportSelections.Usage := ReportSelections.Usage::"V.Remittance";
        ReportSelections.Sequence := 'BAACH';
        ReportSelections."Report ID" := Report::"Export Electronic Payments";
        ReportSelections.Insert(true);
    end;

    procedure RemoveVendorRemittanceSelections()
    var
        ReportSelections: Record "Report Selections";
    begin
        ReportSelections.SetRange(Usage, ReportSelections.Usage::"V.Remittance");
        ReportSelections.DeleteAll();
    end;

    // The definition is imported under a fresh code every time, so it never collides with the
    // company's own copy and no earlier Data Exch. entry of it exists. Codeunit 10320 writes the
    // file to the first Data Exch. entry of the definition's detail line, which "BAACH ACH File" relies on.
    procedure ImportUSEFTDataExchDef(): Code[20]
    var
        DataExchDef: Record "Data Exch. Def";
        TempBlob: Codeunit "Temp Blob";
        ResourceStream: InStream;
        ImportStream: InStream;
        ImportOutStream: OutStream;
        XmlDoc: XmlDocument;
        DefNode: XmlNode;
        NewCode: Code[20];
    begin
        NavApp.GetResource(USEFTResourceTok, ResourceStream, TextEncoding::UTF8);
        XmlDocument.ReadFrom(ResourceStream, XmlDoc);
        if not XmlDoc.SelectSingleNode('/root/DataExchDef', DefNode) then
            Error(NoDataExchDefInResourceErr, USEFTResourceTok);
        NewCode := UniqueCode('BAX', MaxStrLen(DataExchDef.Code));
        DefNode.AsXmlElement().SetAttribute('Code', NewCode);

        TempBlob.CreateOutStream(ImportOutStream, TextEncoding::UTF8);
        XmlDoc.WriteTo(ImportOutStream);
        TempBlob.CreateInStream(ImportStream, TextEncoding::UTF8);
        Xmlport.Import(Xmlport::"Imp / Exp Data Exch Def & Map", ImportStream);

        DataExchDef.Get(NewCode);
        exit(NewCode);
    end;

    procedure CreateEFTExportSetup(): Code[20]
    var
        BankExportImportSetup: Record "Bank Export/Import Setup";
    begin
        BankExportImportSetup.Init();
        BankExportImportSetup.Code := UniqueCode('BAE', MaxStrLen(BankExportImportSetup.Code));
        BankExportImportSetup.Name := 'BAACH US EFT';
        // Export-EFT sets the processing codeunit to "Exp. Launcher EFT", as the standard US setup has it.
        BankExportImportSetup.Validate(Direction, BankExportImportSetup.Direction::"Export-EFT");
        BankExportImportSetup."Data Exch. Def. Code" := ImportUSEFTDataExchDef();
        BankExportImportSetup.Insert(true);
        exit(BankExportImportSetup.Code);
    end;

    procedure CreateEFTBankAccount(var BankAccount: Record "Bank Account")
    begin
        BankAccount.Init();
        BankAccount."No." := UniqueCode('BAB', MaxStrLen(BankAccount."No."));
        BankAccount.Name := 'BAACH Test Bank';
        BankAccount."Bank Acc. Posting Group" := BankAccPostingGroupCode();
        BankAccount."Currency Code" := '';
        BankAccount."Bank Account No." := '987654321';
        BankAccount."Transit No." := BankTransitNoTok;
        BankAccount."Export Format" := BankAccount."Export Format"::US;
        BankAccount."Last Remittance Advice No." := LastRemittanceAdviceNoTok;
        BankAccount."Last E-Pay Export File Name" := LastEPayFileNameTok;
        BankAccount."Payment Export Format" := CreateEFTExportSetup();
        BankAccount.Insert();
    end;

    procedure LastRemittanceAdviceNo(): Code[20]
    begin
        exit(LastRemittanceAdviceNoTok);
    end;

    procedure CreateVendor(var Vendor: Record Vendor)
    var
        SourceVendor: Record Vendor;
    begin
        FindSourceVendor(SourceVendor);
        Vendor.Init();
        Vendor."No." := UniqueCode('BAV', 15);
        // Kept within the 22 characters of the ACH individual name field.
        Vendor.Name := CopyStr('BAACH ' + Vendor."No.", 1, 22);
        Vendor.Address := '1 Test Street';
        Vendor.City := 'Dallas';
        Vendor."Vendor Posting Group" := SourceVendor."Vendor Posting Group";
        Vendor."Gen. Bus. Posting Group" := SourceVendor."Gen. Bus. Posting Group";
        Vendor."VAT Bus. Posting Group" := SourceVendor."VAT Bus. Posting Group";
        Vendor.Insert();
    end;

    procedure CreateVendorBankAccount(var VendorBankAccount: Record "Vendor Bank Account"; VendorNo: Code[20])
    begin
        VendorBankAccount.Init();
        VendorBankAccount."Vendor No." := VendorNo;
        VendorBankAccount.Code := 'BAACH';
        VendorBankAccount.Name := 'BAACH Vendor Bank';
        VendorBankAccount."Transit No." := VendorTransitNoTok;
        VendorBankAccount."Bank Account No." := CopyStr('4455' + Format(Random(99999999), 0, 9), 1, 17);
        VendorBankAccount."Country/Region Code" := 'US';
        VendorBankAccount."Use for Electronic Payments" := true;
        VendorBankAccount.Insert(true);
    end;

    procedure CreateVendorWithBankAccount(var Vendor: Record Vendor; var VendorBankAccount: Record "Vendor Bank Account")
    begin
        CreateVendor(Vendor);
        CreateVendorBankAccount(VendorBankAccount, Vendor."No.");
    end;

    procedure CreatePaymentBatch(var GenJournalBatch: Record "Gen. Journal Batch"; BankAccountNo: Code[20])
    var
        GenJournalTemplate: Record "Gen. Journal Template";
    begin
        GenJournalTemplate.Init();
        GenJournalTemplate.Name := UniqueCode('BT', MaxStrLen(GenJournalTemplate.Name));
        GenJournalTemplate.Description := 'BAACH payments';
        GenJournalTemplate.Validate(Type, GenJournalTemplate.Type::Payments);
        // Report 10083 asks for confirmation (impossible headless) when Force Doc. Balance is off.
        GenJournalTemplate."Force Doc. Balance" := true;
        GenJournalTemplate."Bal. Account Type" := GenJournalTemplate."Bal. Account Type"::"Bank Account";
        GenJournalTemplate."Bal. Account No." := BankAccountNo;
        GenJournalTemplate."No. Series" := '';
        GenJournalTemplate."Posting No. Series" := '';
        GenJournalTemplate.Insert(true);

        CreateBatchInTemplate(GenJournalBatch, GenJournalTemplate.Name, BankAccountNo);
    end;

    procedure CreateBatchInTemplate(var GenJournalBatch: Record "Gen. Journal Batch"; TemplateName: Code[10]; BankAccountNo: Code[20])
    begin
        GenJournalBatch.Init();
        GenJournalBatch."Journal Template Name" := TemplateName;
        GenJournalBatch.Name := UniqueCode('BB', MaxStrLen(GenJournalBatch.Name));
        GenJournalBatch.Description := 'BAACH payments';
        GenJournalBatch.Insert(true);
        GenJournalBatch."Bal. Account Type" := GenJournalBatch."Bal. Account Type"::"Bank Account";
        GenJournalBatch."Bal. Account No." := BankAccountNo;
        GenJournalBatch."No. Series" := '';
        GenJournalBatch."Posting No. Series" := '';
        GenJournalBatch."Allow Payment Export" := true;
        GenJournalBatch.Modify(true);
    end;

    // Switch on, company ready, and an empty payment batch on a fresh US-format bank account.
    procedure CreateEFTScenario(var BankAccount: Record "Bank Account"; var GenJournalBatch: Record "Gen. Journal Batch")
    begin
        SetSwitch(true);
        PrepareCompany();
        CreateEFTBankAccount(BankAccount);
        CreatePaymentBatch(GenJournalBatch, BankAccount."No.");
    end;

    procedure PostVendorInvoice(VendorNo: Code[20]; InvoiceAmount: Decimal): Code[20]
    var
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
    begin
        GenJournalTemplate.Init();
        GenJournalTemplate.Name := UniqueCode('BG', MaxStrLen(GenJournalTemplate.Name));
        GenJournalTemplate.Description := 'BAACH invoices';
        GenJournalTemplate.Validate(Type, GenJournalTemplate.Type::General);
        GenJournalTemplate."No. Series" := '';
        GenJournalTemplate."Posting No. Series" := '';
        GenJournalTemplate.Insert(true);
        GenJournalBatch.Init();
        GenJournalBatch."Journal Template Name" := GenJournalTemplate.Name;
        GenJournalBatch.Name := UniqueCode('BI', MaxStrLen(GenJournalBatch.Name));
        GenJournalBatch.Insert(true);

        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := GenJournalTemplate.Name;
        GenJournalLine."Journal Batch Name" := GenJournalBatch.Name;
        GenJournalLine."Line No." := 10000;
        GenJournalLine."Source Code" := GenJournalTemplate."Source Code";
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine.Validate("Document Type", GenJournalLine."Document Type"::Invoice);
        GenJournalLine."Document No." := UniqueCode('BAI', 20);
        GenJournalLine."External Document No." := GenJournalLine."Document No.";
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Vendor);
        GenJournalLine.Validate("Account No.", VendorNo);
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"G/L Account");
        GenJournalLine.Validate("Bal. Account No.", ExpenseGLAccountNo());
        GenJournalLine.Validate(Amount, -InvoiceAmount);
        GenJnlPostLine.RunWithCheck(GenJournalLine);
        exit(GenJournalLine."Document No.");
    end;

    procedure CreatePaymentLine(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; RecipientBankAccount: Code[20]; PaymentAmount: Decimal)
    begin
        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := GenJournalBatch."Journal Template Name";
        GenJournalLine."Journal Batch Name" := GenJournalBatch.Name;
        GenJournalLine."Line No." := NextLineNo(GenJournalBatch);
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine.Validate("Document Type", GenJournalLine."Document Type"::Payment);
        GenJournalLine."Document No." := UniqueCode('BAP', 20);
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Vendor);
        GenJournalLine.Validate("Account No.", VendorNo);
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"Bank Account");
        GenJournalLine.Validate("Bal. Account No.", GenJournalBatch."Bal. Account No.");
        GenJournalLine.Validate("Bank Payment Type", GenJournalLine."Bank Payment Type"::"Electronic Payment");
        GenJournalLine.Validate("Recipient Bank Account", RecipientBankAccount);
        GenJournalLine.Validate(Amount, PaymentAmount);
        GenJournalLine.Insert(true);
    end;

    // Posts an invoice for the vendor and adds a payment line applied to it, by Applies-to ID
    // (as Suggest Vendor Payments does) or by Applies-to Doc. No.
    procedure CreateAppliedPayment(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; RecipientBankAccount: Code[20]; PaymentAmount: Decimal; ApplyByAppliesToID: Boolean) InvoiceNo: Code[20]
    begin
        InvoiceNo := PostVendorInvoice(VendorNo, PaymentAmount);
        CreatePaymentLine(GenJournalLine, GenJournalBatch, VendorNo, RecipientBankAccount, PaymentAmount);
        if ApplyByAppliesToID then
            ApplyByID(GenJournalLine, InvoiceNo)
        else
            ApplyByDocNo(GenJournalLine, InvoiceNo);
    end;

    procedure CreateVendorPayment(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; PaymentAmount: Decimal; ApplyByAppliesToID: Boolean) InvoiceNo: Code[20]
    var
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        CreateVendorWithBankAccount(Vendor, VendorBankAccount);
        InvoiceNo := CreateAppliedPayment(GenJournalLine, GenJournalBatch, Vendor."No.", VendorBankAccount.Code, PaymentAmount, ApplyByAppliesToID);
    end;

    procedure ApplyByDocNo(var GenJournalLine: Record "Gen. Journal Line"; InvoiceNo: Code[20])
    begin
        GenJournalLine.Validate("Applies-to Doc. Type", GenJournalLine."Applies-to Doc. Type"::Invoice);
        GenJournalLine.Validate("Applies-to Doc. No.", InvoiceNo);
        GenJournalLine.Modify(true);
    end;

    procedure ApplyByID(var GenJournalLine: Record "Gen. Journal Line"; InvoiceNo: Code[20])
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        AppliesToID: Code[50];
    begin
        AppliesToID := UniqueCode('BAA', 20);
        FindOpenInvoiceEntry(VendorLedgerEntry, GenJournalLine."Account No.", InvoiceNo);
        VendorLedgerEntry."Applies-to ID" := AppliesToID;
        VendorLedgerEntry."Amount to Apply" := -GenJournalLine.Amount;
        Codeunit.Run(Codeunit::"Vend. Entry-Edit", VendorLedgerEntry);

        GenJournalLine.Validate("Applies-to ID", AppliesToID);
        GenJournalLine.Modify(true);
    end;

    procedure FindOpenInvoiceEntry(var VendorLedgerEntry: Record "Vendor Ledger Entry"; VendorNo: Code[20]; InvoiceNo: Code[20])
    begin
        FindInvoiceEntry(VendorLedgerEntry, VendorNo, InvoiceNo);
        if not VendorLedgerEntry.Open then
            Error(VendorLedgerEntryNotFoundErr, InvoiceNo, VendorNo);
    end;

    procedure FindInvoiceEntry(var VendorLedgerEntry: Record "Vendor Ledger Entry"; VendorNo: Code[20]; InvoiceNo: Code[20])
    begin
        VendorLedgerEntry.SetRange("Vendor No.", VendorNo);
        VendorLedgerEntry.SetRange("Document Type", VendorLedgerEntry."Document Type"::Invoice);
        VendorLedgerEntry.SetRange("Document No.", InvoiceNo);
        if not VendorLedgerEntry.FindFirst() then
            Error(VendorLedgerEntryNotFoundErr, InvoiceNo, VendorNo);
    end;

    procedure NextLineNo(GenJournalBatch: Record "Gen. Journal Batch"): Integer
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        if GenJournalLine.FindLast() then
            exit(GenJournalLine."Line No." + 10000);
        exit(10000);
    end;

    procedure FilterBatchLines(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch")
    begin
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
    end;

    procedure GenerateEFT(GenJournalBatch: Record "Gen. Journal Batch")
    var
        BAACHGenerateEFT: Codeunit "BAACH Generate EFT";
    begin
        BAACHGenerateEFT.GenerateForBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name, SettlementDate());
    end;

    procedure MarkBatchExported(GenJournalBatch: Record "Gen. Journal Batch"; OutputType: Integer)
    var
        RemittanceRunScope: Codeunit "BAACH Remittance Run Scope";
    begin
        RemittanceRunScope.SetBatch(GenJournalBatch."Journal Template Name", GenJournalBatch.Name, GenJournalBatch."Bal. Account No.");
        RemittanceRunScope.MarkLinesExported(OutputType);
    end;

    procedure PDFOutput(): Integer
    var
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";
    begin
        exit(CustomLayoutReporting.GetPDFOption());
    end;

    procedure PostBatch(GenJournalBatch: Record "Gen. Journal Batch")
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        FilterBatchLines(GenJournalLine, GenJournalBatch);
        GenJournalLine.FindFirst();
        Codeunit.Run(Codeunit::"Gen. Jnl.-Post Batch", GenJournalLine);
    end;

    procedure ExpenseGLAccountNo(): Code[20]
    var
        GLAccount: Record "G/L Account";
    begin
        GLAccount.SetRange("Account Type", GLAccount."Account Type"::Posting);
        GLAccount.SetRange(Blocked, false);
        GLAccount.SetRange("Direct Posting", true);
        GLAccount.SetRange("Gen. Posting Type", GLAccount."Gen. Posting Type"::" ");
        GLAccount.SetRange("Income/Balance", GLAccount."Income/Balance"::"Income Statement");
        if GLAccount.FindSet() then
            repeat
                if not HasMandatoryDimensionWithoutValue(Database::"G/L Account", GLAccount."No.") then
                    exit(GLAccount."No.");
            until GLAccount.Next() = 0;
        Error(NoExpenseAccountErr);
    end;

    procedure FindSourceVendor(var SourceVendor: Record Vendor)
    var
        VendorPostingGroup: Record "Vendor Posting Group";
    begin
        SourceVendor.SetFilter("Vendor Posting Group", '<>%1', '');
        SourceVendor.SetRange(Blocked, SourceVendor.Blocked::" ");
        SourceVendor.SetRange("Privacy Blocked", false);
        SourceVendor.SetRange("Currency Code", '');
        if SourceVendor.FindSet() then
            repeat
                if VendorPostingGroup.Get(SourceVendor."Vendor Posting Group") then
                    if VendorPostingGroup."Payables Account" <> '' then
                        exit;
            until SourceVendor.Next() = 0;
        Error(NoSourceVendorErr);
    end;

    procedure BankAccPostingGroupCode(): Code[20]
    var
        BankAccount: Record "Bank Account";
        BankAccountPostingGroup: Record "Bank Account Posting Group";
    begin
        BankAccount.SetRange("Currency Code", '');
        BankAccount.SetFilter("Bank Acc. Posting Group", '<>%1', '');
        if BankAccount.FindSet() then
            repeat
                if BankAccountPostingGroup.Get(BankAccount."Bank Acc. Posting Group") then
                    if BankAccountPostingGroup."G/L Account No." <> '' then
                        exit(BankAccountPostingGroup.Code);
            until BankAccount.Next() = 0;
        BankAccountPostingGroup.SetFilter("G/L Account No.", '<>%1', '');
        if BankAccountPostingGroup.FindFirst() then
            exit(BankAccountPostingGroup.Code);
        Error(NoBankPostingGroupErr);
    end;

    local procedure HasMandatoryDimensionWithoutValue(TableId: Integer; No: Code[20]): Boolean
    var
        DefaultDimension: Record "Default Dimension";
    begin
        DefaultDimension.SetRange("Table ID", TableId);
        DefaultDimension.SetFilter("No.", '%1|%2', No, '');
        DefaultDimension.SetRange("Value Posting", DefaultDimension."Value Posting"::"Code Mandatory");
        DefaultDimension.SetRange("Dimension Value Code", '');
        exit(not DefaultDimension.IsEmpty());
    end;
}
