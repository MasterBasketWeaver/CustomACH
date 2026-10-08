// SetJournalLineFieldsFromApplication runs for Applies-to Doc. No. (validate and lookup), Applies-to ID and the
// Apply Entries action (codeunit "Gen. Jnl.-Apply", which modifies the line afterwards), so one pair of events
// covers every way an invoice gets applied.
codeunit 81111 "BAACH Apply Payment Defaults"
{
    var
        SetupMgt: Codeunit "BAACH Setup Mgt.";

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnSetJournalLineFieldsFromApplicationOnAfterFindFirstVendLedgEntryWithAppliesToDocNo, '', false, false)]
    local procedure OnApplyByAppliesToDocNo(var GenJournalLine: Record "Gen. Journal Line"; VendLedgEntry: Record "Vendor Ledger Entry")
    begin
        SetElectronicPaymentDefaults(GenJournalLine);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnSetJournalLineFieldsFromApplicationOnAfterFindFirstVendLedgEntryWithAppliesToID, '', false, false)]
    local procedure OnApplyByAppliesToID(var GenJournalLine: Record "Gen. Journal Line"; VendLedgEntry: Record "Vendor Ledger Entry")
    begin
        SetElectronicPaymentDefaults(GenJournalLine);
    end;

    procedure SetElectronicPaymentDefaults(var GenJournalLine: Record "Gen. Journal Line")
    var
        VendorBankAccount: Record "Vendor Bank Account";
        VendorNo: Code[20];
    begin
        if GenJournalLine.IsTemporary() then
            exit;
        // A printed check, a line step 1 has prepared, or one already exported keeps what it was issued with.
        if GenJournalLine."Check Printed" or GenJournalLine."Check Exported" or GenJournalLine."BAACH EFT File Created" then
            exit;
        if not GetVendorNo(GenJournalLine, VendorNo) then
            exit;
        if not SetupMgt.IsEnabledForBatch(GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name") then
            exit;

        if not SetupMgt.IsElectronicPayment(GenJournalLine) then
            GenJournalLine.Validate("Bank Payment Type", GenJournalLine."Bank Payment Type"::"Electronic Payment");

        if IsElectronicBankAccount(VendorNo, GenJournalLine."Recipient Bank Account") then
            exit;
        if FindElectronicBankAccount(VendorNo, VendorBankAccount) then
            GenJournalLine.Validate("Recipient Bank Account", VendorBankAccount.Code);
    end;

    // Only a vendor paid from a bank account: Bank Payment Type's validation refuses any other combination.
    local procedure GetVendorNo(GenJournalLine: Record "Gen. Journal Line"; var VendorNo: Code[20]): Boolean
    begin
        VendorNo := '';
        if (GenJournalLine."Account Type" = GenJournalLine."Account Type"::Vendor) and
           (GenJournalLine."Bal. Account Type" = GenJournalLine."Bal. Account Type"::"Bank Account")
        then
            VendorNo := GenJournalLine."Account No.";
        if (GenJournalLine."Bal. Account Type" = GenJournalLine."Bal. Account Type"::Vendor) and
           (GenJournalLine."Account Type" = GenJournalLine."Account Type"::"Bank Account")
        then
            VendorNo := GenJournalLine."Bal. Account No.";
        exit(VendorNo <> '');
    end;

    local procedure IsElectronicBankAccount(VendorNo: Code[20]; BankAccountCode: Code[20]): Boolean
    var
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        if BankAccountCode = '' then
            exit(false);
        if not VendorBankAccount.Get(VendorNo, BankAccountCode) then
            exit(false);
        exit(VendorBankAccount."Use for Electronic Payments");
    end;

    local procedure FindElectronicBankAccount(VendorNo: Code[20]; var VendorBankAccount: Record "Vendor Bank Account"): Boolean
    begin
        VendorBankAccount.SetRange("Vendor No.", VendorNo);
        VendorBankAccount.SetRange("Use for Electronic Payments", true);
        exit(VendorBankAccount.FindFirst());
    end;
}
