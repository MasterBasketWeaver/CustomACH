// Reads the NACHA file that Generate EFT stored in Data Exch. "File Content" and parses its
// 94-character records. Positions are those of the NACHA standard.
codeunit 81208 "BAACH ACH File"
{
    var
        Records: List of [Text];
        FillerRecords: Integer;
        NoFileErr: Label 'No generated file was found for data exchange definition %1.', Comment = '%1 = definition code';
        NoRecordErr: Label 'The file has no record of type %1 number %2.', Comment = '%1 = record type, %2 = occurrence';
        NoEntryForNameErr: Label 'The file has no entry detail record for %1.', Comment = '%1 = payee name';

    procedure LoadForBankAccount(BankAccountNo: Code[20])
    var
        BankAccount: Record "Bank Account";
        BankExportImportSetup: Record "Bank Export/Import Setup";
    begin
        BankAccount.Get(BankAccountNo);
        BankExportImportSetup.Get(BankAccount."Payment Export Format");
        LoadForDefinition(BankExportImportSetup."Data Exch. Def. Code");
    end;

    // Codeunit 10320 always writes into the first Data Exch. entry of the definition's detail
    // line, and clears the footer entries, so the only entry with content holds the latest file.
    procedure LoadForDefinition(DataExchDefCode: Code[20])
    var
        DataExch: Record "Data Exch.";
        ContentStream: InStream;
    begin
        DataExch.SetRange("Data Exch. Def Code", DataExchDefCode);
        if DataExch.FindSet() then
            repeat
                DataExch.CalcFields("File Content");
                if DataExch."File Content".HasValue() then begin
                    DataExch."File Content".CreateInStream(ContentStream);
                    LoadFromStream(ContentStream);
                    exit;
                end;
            until DataExch.Next() = 0;
        Error(NoFileErr, DataExchDefCode);
    end;

    procedure LoadFromStream(var ContentStream: InStream)
    var
        Line: Text;
        LineBreaks: Text;
    begin
        Clear(Records);
        FillerRecords := 0;
        LineBreaks[1] := 13;
        LineBreaks[2] := 10;
        while not ContentStream.EOS() do begin
            ContentStream.ReadText(Line);
            Line := DelChr(Line, '<>', LineBreaks);
            if Line <> '' then
                if Line = PadStr('', 94, '9') then
                    FillerRecords += 1
                else
                    Records.Add(Line);
        end;
    end;

    procedure RecordCount(): Integer
    begin
        exit(Records.Count());
    end;

    procedure FillerCount(): Integer
    begin
        exit(FillerRecords);
    end;

    procedure GetRecord(Index: Integer): Text
    begin
        exit(Records.Get(Index));
    end;

    procedure RecordTypes() Types: Text
    var
        RecordText: Text;
    begin
        foreach RecordText in Records do
            Types += CopyStr(RecordText, 1, 1);
    end;

    procedure AllRecordsHaveLength(Length: Integer): Boolean
    var
        RecordText: Text;
    begin
        foreach RecordText in Records do
            if StrLen(RecordText) <> Length then
                exit(false);
        exit(true);
    end;

    procedure CountOfType(RecordType: Text[1]) Result: Integer
    var
        RecordText: Text;
    begin
        foreach RecordText in Records do
            if CopyStr(RecordText, 1, 1) = RecordType then
                Result += 1;
    end;

    procedure GetRecordOfType(RecordType: Text[1]; Occurrence: Integer): Text
    var
        RecordText: Text;
        Found: Integer;
    begin
        foreach RecordText in Records do
            if CopyStr(RecordText, 1, 1) = RecordType then begin
                Found += 1;
                if Found = Occurrence then
                    exit(RecordText);
            end;
        Error(NoRecordErr, RecordType, Occurrence);
    end;

    procedure EntryCount(): Integer
    begin
        exit(CountOfType('6'));
    end;

    procedure FindEntryByName(PayeeName: Text): Integer
    var
        i: Integer;
    begin
        for i := 1 to EntryCount() do
            if UpperCase(EntryName(i)) = UpperCase(CopyStr(PayeeName, 1, 22)) then
                exit(i);
        Error(NoEntryForNameErr, PayeeName);
    end;

    procedure EntryTransactionCode(Occurrence: Integer): Text
    begin
        exit(CopyStr(GetRecordOfType('6', Occurrence), 2, 2));
    end;

    // Receiving DFI identification (8 digits) followed by its check digit.
    procedure EntryTransitNo(Occurrence: Integer): Text
    begin
        exit(CopyStr(GetRecordOfType('6', Occurrence), 4, 9));
    end;

    procedure EntryAccountNo(Occurrence: Integer): Text
    begin
        exit(DelChr(CopyStr(GetRecordOfType('6', Occurrence), 13, 17), '<>', ' '));
    end;

    procedure EntryAmount(Occurrence: Integer): Decimal
    begin
        exit(Cents(CopyStr(GetRecordOfType('6', Occurrence), 30, 10)));
    end;

    procedure EntryIndividualId(Occurrence: Integer): Text
    begin
        exit(DelChr(CopyStr(GetRecordOfType('6', Occurrence), 40, 15), '<>', ' '));
    end;

    procedure EntryName(Occurrence: Integer): Text
    begin
        exit(DelChr(CopyStr(GetRecordOfType('6', Occurrence), 55, 22), '<>', ' '));
    end;

    procedure BatchEffectiveDate(): Date
    begin
        exit(YYMMDDToDate(CopyStr(GetRecordOfType('5', 1), 70, 6)));
    end;

    procedure BatchEntryCount(): Integer
    begin
        exit(ToInteger(CopyStr(GetRecordOfType('8', 1), 5, 6)));
    end;

    procedure BatchTotalCredit(): Decimal
    begin
        exit(Cents(CopyStr(GetRecordOfType('8', 1), 33, 12)));
    end;

    procedure FileEntryCount(): Integer
    begin
        exit(ToInteger(CopyStr(GetRecordOfType('9', 1), 14, 8)));
    end;

    procedure FileTotalCredit(): Decimal
    begin
        exit(Cents(CopyStr(GetRecordOfType('9', 1), 44, 12)));
    end;

    local procedure Cents(Digits: Text): Decimal
    var
        Amount: Decimal;
    begin
        Evaluate(Amount, DelChr(Digits, '<>', ' '));
        exit(Amount / 100);
    end;

    local procedure ToInteger(Digits: Text): Integer
    var
        Value: Integer;
    begin
        Evaluate(Value, DelChr(Digits, '<>', ' '));
        exit(Value);
    end;

    local procedure YYMMDDToDate(Digits: Text): Date
    begin
        exit(DMY2Date(ToInteger(CopyStr(Digits, 5, 2)), ToInteger(CopyStr(Digits, 3, 2)), 2000 + ToInteger(CopyStr(Digits, 1, 2))));
    end;
}
