pageextension 81100 "BAACH Payment Journal" extends "Payment Journal"
{
    layout
    {
        addafter("Check Printed")
        {
            field("BAACH EFT File Created"; Rec."BAACH EFT File Created")
            {
                ApplicationArea = Basic, Suite;
                ToolTip = 'Specifies that the EFT (ACH) file with this payment has been generated. The line stays locked until the remittances are exported or the EFT file is voided.';
                Visible = CustomMode;
            }
        }
    }

    actions
    {
        addfirst("Electronic Payments")
        {
            action(BAACHGenerateEFTFile)
            {
                ApplicationArea = Basic, Suite;
                Caption = 'Generate EFT File';
                Ellipsis = true;
                Image = ExportFile;
                ToolTip = 'Generate and download the EFT (ACH) file for the electronic payment lines in this batch. Do this before you export the remittances.';
                Visible = CustomMode;

                trigger OnAction()
                var
                    GenerateEFT: Codeunit "BAACH Generate EFT";
                    GenerateEFTDialog: Page "BAACH Generate EFT Dialog";
                    TemplateName: Code[10];
                begin
                    TemplateName := GetTemplateName();
                    GenerateEFTDialog.SetBatch(TemplateName, CurrentJnlBatchName);
                    if GenerateEFTDialog.RunModal() <> Action::OK then
                        exit;
                    GenerateEFT.GenerateForBatch(TemplateName, CurrentJnlBatchName, GenerateEFTDialog.GetSettlementDate());
                    CurrPage.Update(false);
                end;
            }
            action(BAACHExportRemittance)
            {
                ApplicationArea = Basic, Suite;
                Caption = 'E&xport';
                Ellipsis = true;
                Image = ExportFile;
                ToolTip = 'Print, download or email the vendor remittance advices for the payments whose EFT file has been generated. The lines can then be posted.';
                Visible = CustomMode;

                trigger OnAction()
                var
                    ExportRemittance: Codeunit "BAACH Export Remittance";
                begin
                    ExportRemittance.ExportForBatch(GetTemplateName(), CurrentJnlBatchName);
                    CurrPage.Update(false);
                end;
            }
            action(BAACHVoidEFTFile)
            {
                ApplicationArea = Basic, Suite;
                Caption = 'Void EFT File';
                Ellipsis = true;
                Image = VoidElectronicDocument;
                ToolTip = 'Void the generated EFT (ACH) file before the remittances are exported. The lines are unlocked and get a new document number when the file is generated again.';
                Visible = CustomMode;

                trigger OnAction()
                var
                    VoidEFT: Codeunit "BAACH Void EFT";
                begin
                    VoidEFT.CheckCanVoid(GetTemplateName(), CurrentJnlBatchName);
                    if not Confirm(VoidEFTFileQst, false) then
                        exit;
                    VoidEFT.VoidForBatch(GetTemplateName(), CurrentJnlBatchName);
                    CurrPage.Update(false);
                end;
            }
        }
        modify(ExportPaymentsToFile)
        {
            Visible = not CustomMode;
        }
        modify(VoidPayments)
        {
            Visible = not CustomMode;
        }
        modify(GenerateEFT)
        {
            Visible = not CustomMode;
        }
        addfirst(Category_Category4)
        {
            actionref(BAACHGenerateEFTFile_Promoted; BAACHGenerateEFTFile)
            {
            }
            actionref(BAACHExportRemittance_Promoted; BAACHExportRemittance)
            {
            }
            actionref(BAACHVoidEFTFile_Promoted; BAACHVoidEFTFile)
            {
            }
        }
    }

    trigger OnOpenPage()
    begin
        SetCustomMode();
    end;

    trigger OnAfterGetCurrRecord()
    begin
        SetCustomMode();
    end;

    var
        CustomMode: Boolean;
        VoidEFTFileQst: Label 'Do you want to void the EFT file?';

    local procedure SetCustomMode()
    var
        SetupMgt: Codeunit "BAACH Setup Mgt.";
    begin
        CustomMode := SetupMgt.IsEnabledForBatch(GetTemplateName(), CurrentJnlBatchName);
    end;

    // An empty journal has no current record, so fall back to the template filter the page sets.
    local procedure GetTemplateName(): Code[10]
    var
        TemplateName: Code[10];
        CurrentFilterGroup: Integer;
    begin
        if Rec."Journal Template Name" <> '' then
            exit(Rec."Journal Template Name");
        CurrentFilterGroup := Rec.FilterGroup();
        Rec.FilterGroup(2);
        if Rec.GetFilter("Journal Template Name") <> '' then
            TemplateName := Rec.GetRangeMax("Journal Template Name");
        Rec.FilterGroup(CurrentFilterGroup);
        exit(TemplateName);
    end;
}
