// The one place a test codeunit is registered: the runner, "BAACH Run Tests" and run_tests.py
// (through GetSuiteCodeunits) all read this list. Test apps that extend this one add theirs through
// OnAfterAllCodeunits.
codeunit 81205 "BAACH Suite"
{
    procedure AllCodeunits() Ids: List of [Integer]
    begin
        Ids.Add(Codeunit::"BAACH Setup Tests");
        Ids.Add(Codeunit::"BAACH Generate EFT Tests");
        Ids.Add(Codeunit::"BAACH Line Lock Tests");
        Ids.Add(Codeunit::"BAACH Export Remittance Tests");
        Ids.Add(Codeunit::"BAACH Remittance Report Tests");
        Ids.Add(Codeunit::"BAACH Posting Tests");
        Ids.Add(Codeunit::"BAACH Void Tests");
        Ids.Add(Codeunit::"BAACH License Tests");
        Ids.Add(Codeunit::"BAACH Apply Defaults Tests");
        OnAfterAllCodeunits(Ids);
    end;

    procedure ToJson() Result: Text
    var
        Codeunits: JsonArray;
        Entry: JsonObject;
        Id: Integer;
    begin
        foreach Id in AllCodeunits() do begin
            Clear(Entry);
            Entry.Add('id', Id);
            Entry.Add('name', NameOf(Id));
            Codeunits.Add(Entry);
        end;
        Codeunits.WriteTo(Result);
    end;

    local procedure NameOf(CodeunitId: Integer): Text
    var
        AllObjWithCaption: Record AllObjWithCaption;
    begin
        if AllObjWithCaption.Get(AllObjWithCaption."Object Type"::Codeunit, CodeunitId) then
            exit(AllObjWithCaption."Object Name");
        exit('');
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterAllCodeunits(var Ids: List of [Integer])
    begin
    end;
}
