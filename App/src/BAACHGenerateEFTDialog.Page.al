page 81100 "BAACH Generate EFT Dialog"
{
    Caption = 'Generate EFT File';
    PageType = StandardDialog;
    ApplicationArea = Basic, Suite;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                InstructionalText = 'The EFT (ACH) file is generated for the electronic payment lines in this journal batch and downloaded. The lines are then locked until you export the remittances or void the EFT file.';

                field(BankAccountNo; BankAccountNo)
                {
                    Caption = 'Bank Account No.';
                    Editable = false;
                    ToolTip = 'Specifies the bank account that the payments are made from.';
                }
                field(BankAccountName; BankAccountName)
                {
                    Caption = 'Bank Account Name';
                    Editable = false;
                    ToolTip = 'Specifies the name of the bank account that the payments are made from.';
                }
                field(SettlementDate; SettlementDate)
                {
                    Caption = 'Settlement Date';
                    ShowMandatory = true;
                    ToolTip = 'Specifies the date on which the bank settles the payments. It becomes the effective entry date in the file.';
                }
                field(NoOfLines; NoOfLines)
                {
                    Caption = 'Number of Lines';
                    Editable = false;
                    ToolTip = 'Specifies how many electronic payment lines are included in the EFT file.';
                }
                field(TotalAmount; TotalAmount)
                {
                    AutoFormatType = 1;
                    AutoFormatExpression = CurrencyCode;
                    Caption = 'Total Amount';
                    Editable = false;
                    ToolTip = 'Specifies the total amount of the electronic payment lines included in the EFT file.';
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if SettlementDate = 0D then
            SettlementDate := Today();
    end;

    trigger OnQueryClosePage(CloseAction: Action): Boolean
    begin
        if CloseAction in [Action::OK, Action::LookupOK, Action::Yes] then
            if SettlementDate = 0D then
                Error(SettlementDateMissingErr);
        exit(true);
    end;

    var
        BankAccountNo: Code[20];
        BankAccountName: Text[100];
        CurrencyCode: Code[10];
        SettlementDate: Date;
        NoOfLines: Integer;
        TotalAmount: Decimal;
        SettlementDateMissingErr: Label 'You must specify a settlement date.';

    procedure SetBatch(TemplateName: Code[10]; BatchName: Code[10])
    var
        BankAccount: Record "Bank Account";
        GenJournalLine: Record "Gen. Journal Line";
        SetupMgt: Codeunit "BAACH Setup Mgt.";
        GenerateEFT: Codeunit "BAACH Generate EFT";
    begin
        if SetupMgt.GetBatchBankAccount(TemplateName, BatchName, BankAccount) then begin
            BankAccountNo := BankAccount."No.";
            BankAccountName := BankAccount.Name;
            CurrencyCode := BankAccount."Currency Code";
        end;

        GenerateEFT.SetLinesToGenerateFilter(GenJournalLine, TemplateName, BatchName);
        NoOfLines := GenJournalLine.Count();
        GenJournalLine.CalcSums(Amount);
        TotalAmount := GenJournalLine.Amount;
    end;

    procedure GetSettlementDate(): Date
    begin
        exit(SettlementDate);
    end;
}
