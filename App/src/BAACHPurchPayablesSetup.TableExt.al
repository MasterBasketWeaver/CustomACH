tableextension 81100 "BAACH Purch. & Payables Setup" extends "Purchases & Payables Setup"
{
    fields
    {
        field(81100; "BAACH Enable EFT Before Export"; Boolean)
        {
            Caption = 'Enable EFT Generate before Export';
            DataClassification = CustomerContent;

            trigger OnValidate()
            var
                SetupMgt: Codeunit "BAACH Setup Mgt.";
            begin
                if not Rec."BAACH Enable EFT Before Export" then
                    SetupMgt.CheckNoLinesInProgress();
            end;
        }
    }
}
