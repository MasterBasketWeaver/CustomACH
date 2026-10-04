codeunit 81351 "BAACH EE Suite Registration"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"BAACH Suite", OnAfterAllCodeunits, '', false, false)]
    local procedure AddEagleEyeTests(var Ids: List of [Integer])
    begin
        Ids.Add(Codeunit::"BAACH EE Bank Commerce Tests");
    end;
}
