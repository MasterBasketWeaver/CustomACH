// Stand-in for Microsoft's Library Assert, which is not published in the test environment.
codeunit 81206 "BAACH Assert"
{
    var
        AreEqualErr: Label 'Assert.AreEqual failed. Expected: <%1>. Actual: <%2>. %3', Comment = '%1 = expected value, %2 = actual value, %3 = message';
        AreNotEqualErr: Label 'Assert.AreNotEqual failed. Both values are <%1>. %2', Comment = '%1 = value, %2 = message';
        IsTrueErr: Label 'Assert.IsTrue failed. %1', Comment = '%1 = message';
        IsFalseErr: Label 'Assert.IsFalse failed. %1', Comment = '%1 = message';
        ExpectedErrorErr: Label 'Assert.ExpectedError failed. Expected: <%1>. Actual: <%2>.', Comment = '%1 = expected error text, %2 = actual error text';
        ExpectedErrorContainsErr: Label 'Assert.ExpectedErrorContains failed. Expected the error to contain <%1>. Actual: <%2>.', Comment = '%1 = expected fragment, %2 = actual error text';
        NoErrorErr: Label 'An error was expected, but none was raised. %1', Comment = '%1 = message';
        TextContainsErr: Label 'Assert.TextContains failed. Expected <%1> to contain <%2>. %3', Comment = '%1 = text, %2 = expected fragment, %3 = message';
        RecordCountErr: Label 'Assert.RecordCount failed. Expected %1 record(s) in %2, found %3. Filters: %4', Comment = '%1 = expected count, %2 = table caption, %3 = actual count, %4 = filters';
        FailErr: Label 'Assert.Fail: %1', Comment = '%1 = message';

    procedure AreEqual(Expected: Variant; Actual: Variant; Msg: Text)
    begin
        if Format(Expected, 0, 9) <> Format(Actual, 0, 9) then
            Error(AreEqualErr, Format(Expected, 0, 9), Format(Actual, 0, 9), Msg);
    end;

    procedure AreNotEqual(NotExpected: Variant; Actual: Variant; Msg: Text)
    begin
        if Format(NotExpected, 0, 9) = Format(Actual, 0, 9) then
            Error(AreNotEqualErr, Format(Actual, 0, 9), Msg);
    end;

    procedure IsTrue(Condition: Boolean; Msg: Text)
    begin
        if not Condition then
            Error(IsTrueErr, Msg);
    end;

    procedure IsFalse(Condition: Boolean; Msg: Text)
    begin
        if Condition then
            Error(IsFalseErr, Msg);
    end;

    procedure TextContains(Text: Text; Fragment: Text; Msg: Text)
    begin
        if StrPos(LowerCase(Text), LowerCase(Fragment)) = 0 then
            Error(TextContainsErr, Text, Fragment, Msg);
    end;

    procedure ExpectedError(Expected: Text)
    begin
        if GetLastErrorText() <> Expected then
            Error(ExpectedErrorErr, Expected, GetLastErrorText());
    end;

    procedure ExpectedErrorContains(Fragment: Text)
    begin
        if GetLastErrorText() = '' then
            Error(NoErrorErr, Fragment);
        if StrPos(LowerCase(GetLastErrorText()), LowerCase(Fragment)) = 0 then
            Error(ExpectedErrorContainsErr, Fragment, GetLastErrorText());
    end;

    procedure RecordCount(RecVariant: Variant; ExpectedCount: Integer)
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(RecVariant);
        if RecRef.Count() <> ExpectedCount then
            Error(RecordCountErr, ExpectedCount, RecRef.Caption(), RecRef.Count(), RecRef.GetFilters());
    end;

    procedure RecordIsEmpty(RecVariant: Variant)
    begin
        RecordCount(RecVariant, 0);
    end;

    procedure Fail(Msg: Text)
    begin
        Error(FailErr, Msg);
    end;
}
