pageextension 81101 "BAACH Purch. & Payables Setup" extends "Purchases & Payables Setup"
{
    layout
    {
        addlast(General)
        {
            field("BAACH Enable EFT Before Export"; Rec."BAACH Enable EFT Before Export")
            {
                ApplicationArea = Basic, Suite;
                ToolTip = 'Specifies whether the Payment Journal generates the EFT (ACH) file before the vendor remittances are exported. When this is off, the standard Export, Generate EFT and Void actions apply.';
            }
        }
    }
}
