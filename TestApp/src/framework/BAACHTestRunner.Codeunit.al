// TestIsolation = Function rolls back after every test method, including what Generate EFT and
// posting commit, so no test can pass on data a previous one left behind.
codeunit 81200 "BAACH Test Runner"
{
    Subtype = TestRunner;
    TestIsolation = Function;

    var
        Suite: Codeunit "BAACH Suite";
        TestResults: Codeunit "BAACH Test Results";

    trigger OnRun()
    var
        CodeunitId: Integer;
    begin
        foreach CodeunitId in Suite.AllCodeunits() do
            if TestResults.ShouldRun(CodeunitId) then
                Codeunit.Run(CodeunitId);
    end;

    trigger OnBeforeTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions): Boolean
    begin
        TestResults.StartTest(CodeunitId, CodeunitName, FunctionName);
        exit(true);
    end;

    trigger OnAfterTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions; Success: Boolean)
    begin
        // The codeunit's OnRun also reports, with an empty function name; the per-test entries already cover it.
        if FunctionName = '' then
            exit;
        TestResults.EndTest(CodeunitId, CodeunitName, FunctionName, Success, GetLastErrorText(), GetLastErrorCallStack());
    end;
}
