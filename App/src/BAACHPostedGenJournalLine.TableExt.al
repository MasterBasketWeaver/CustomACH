tableextension 81102 "BAACH Posted Gen. Journal Line" extends "Posted Gen. Journal Line"
{
    fields
    {
        // Same field ID as on Gen. Journal Line so TransferFields in "Copy to Posted Jnl. Lines" carries it over.
        field(81100; "BAACH EFT File Created"; Boolean)
        {
            Caption = 'EFT File Created';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}
