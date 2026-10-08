// Stands in for the Apply Vendor Entries page, which cannot run headless, so the rest of
// "Gen. Jnl.-Apply" (the Apply Entries action) runs as it does in the client.
codeunit 81219 "BAACH Apply Entries Stub"
{
    EventSubscriberInstance = Manual;

    var
        InvoiceNoToSelect: Code[20];

    procedure SelectInvoice(InvoiceNo: Code[20])
    begin
        InvoiceNoToSelect := InvoiceNo;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Apply", OnBeforeSelectVendLedgEntry, '', false, false)]
    local procedure SelectTheInvoice(var GenJournalLine: Record "Gen. Journal Line"; var AccNo: Code[20]; var Selected: Boolean; var IsHandled: Boolean; var CustomAppliesToId: Code[50])
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        Library: Codeunit "BAACH Library";
    begin
        if GenJournalLine."Applies-to ID" = '' then
            GenJournalLine."Applies-to ID" := GenJournalLine."Document No.";
        Library.FindOpenInvoiceEntry(VendorLedgerEntry, AccNo, InvoiceNoToSelect);
        VendorLedgerEntry.CalcFields("Remaining Amount");
        VendorLedgerEntry."Applies-to ID" := GenJournalLine."Applies-to ID";
        VendorLedgerEntry."Amount to Apply" := VendorLedgerEntry."Remaining Amount";
        Codeunit.Run(Codeunit::"Vend. Entry-Edit", VendorLedgerEntry);

        Selected := true;
        IsHandled := true;
    end;
}
