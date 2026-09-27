// Single instance so the results survive the per-test rollback; nothing here touches the database.
codeunit 81201 "BAACH Test Results"
{
    SingleInstance = true;

    var
        Results: JsonArray;
        CurrentTest: JsonObject;
        CodeunitFilter: List of [Integer];
        StartedAt: DateTime;
        SuiteStartedAt: DateTime;
        RunnerError: Text;
        SuccessCount: Integer;
        FailureCount: Integer;
        DataExchDefResource: Text;

    procedure Initialize()
    begin
        Clear(Results);
        Clear(CurrentTest);
        Clear(CodeunitFilter);
        SuccessCount := 0;
        FailureCount := 0;
        RunnerError := '';
        DataExchDefResource := '';
        SuiteStartedAt := CurrentDateTime();
    end;

    procedure SetDataExchDefResource(ResourceName: Text)
    begin
        DataExchDefResource := ResourceName;
    end;

    procedure GetDataExchDefResource(): Text
    begin
        exit(DataExchDefResource);
    end;

    procedure AddCodeunitFilter(CodeunitId: Integer)
    begin
        if not CodeunitFilter.Contains(CodeunitId) then
            CodeunitFilter.Add(CodeunitId);
    end;

    procedure ShouldRun(CodeunitId: Integer): Boolean
    begin
        if CodeunitFilter.Count() = 0 then
            exit(true);
        exit(CodeunitFilter.Contains(CodeunitId));
    end;

    procedure StartTest(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text)
    begin
        Clear(CurrentTest);
        CurrentTest.Add('codeunitId', CodeunitId);
        CurrentTest.Add('codeunit', CodeunitName);
        CurrentTest.Add('test', FunctionName);
        StartedAt := CurrentDateTime();
    end;

    procedure EndTest(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; IsSuccess: Boolean; ErrorText: Text; CallStack: Text)
    var
        TestObj: JsonObject;
    begin
        TestObj := CurrentTest;
        if not TestObj.Contains('test') then begin
            Clear(TestObj);
            TestObj.Add('codeunitId', CodeunitId);
            TestObj.Add('codeunit', CodeunitName);
            TestObj.Add('test', FunctionName);
            StartedAt := CurrentDateTime();
        end;

        TestObj.Add('success', IsSuccess);
        TestObj.Add('duration', Format(CurrentDateTime() - StartedAt));
        if IsSuccess then
            SuccessCount += 1
        else begin
            TestObj.Add('error', ErrorText);
            TestObj.Add('callStack', CallStack);
            FailureCount += 1;
        end;

        Results.Add(TestObj);
        Clear(CurrentTest);
    end;

    procedure SetRunnerError(NewRunnerError: Text)
    begin
        RunnerError := NewRunnerError;
    end;

    procedure ToJson() ResultText: Text
    var
        Summary: JsonObject;
    begin
        Summary.Add('total', SuccessCount + FailureCount);
        Summary.Add('passed', SuccessCount);
        Summary.Add('failed', FailureCount);
        Summary.Add('duration', Format(CurrentDateTime() - SuiteStartedAt));
        Summary.Add('runnerError', RunnerError);
        Summary.Add('results', Results);
        Summary.WriteTo(ResultText);
    end;
}
