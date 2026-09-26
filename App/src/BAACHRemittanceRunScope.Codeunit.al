codeunit 81104 "BAACH Remittance Run Scope"
{
    EventSubscriberInstance = Manual;

    procedure SetBatch(TemplateName: Code[10]; BatchName: Code[10]; BankAccountNo: Code[20])
    begin
    end;

    // OutputType uses Custom Layout Reporting's option values (GetPreviewOption() etc.).
    procedure MarkLinesExported(OutputType: Integer)
    begin
    end;

    procedure MarkVendorEmailFailed(VendorNo: Code[20])
    begin
    end;
}
