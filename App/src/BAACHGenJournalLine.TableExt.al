tableextension 81101 "BAACH Gen. Journal Line" extends "Gen. Journal Line"
{
    fields
    {
        field(81100; "BAACH EFT File Created"; Boolean)
        {
            Caption = 'EFT File Created';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}
