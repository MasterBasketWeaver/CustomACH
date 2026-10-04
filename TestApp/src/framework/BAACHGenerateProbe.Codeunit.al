codeunit 81209 "BAACH Generate Probe"
{
    EventSubscriberInstance = Manual;

    var
        EntryCount: Integer;
        GeneratingAtEveryEntry: Boolean;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Export EFT (ACH)", OnBeforeACHUSDetailModify, '', false, false)]
    local procedure RecordGeneratingState(var ACHUSDetail: Record "ACH US Detail"; var TempEFTExportWorkset: Record "EFT Export Workset" temporary; BankAccNo: Code[20])
    var
        BAACHGenerateEFT: Codeunit "BAACH Generate EFT";
    begin
        if EntryCount = 0 then
            GeneratingAtEveryEntry := true;
        EntryCount += 1;
        GeneratingAtEveryEntry := GeneratingAtEveryEntry and BAACHGenerateEFT.IsGeneratingEFTFile();
    end;

    procedure GetEntryCount(): Integer
    begin
        exit(EntryCount);
    end;

    procedure WasGeneratingAtEveryEntry(): Boolean
    begin
        exit(GeneratingAtEveryEntry);
    end;
}
