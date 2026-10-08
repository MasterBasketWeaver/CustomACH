codeunit 81104 "BAACH Remittance Run Scope"
{
    EventSubscriberInstance = Manual;

    var
        JnlTemplateName: Code[10];
        JnlBatchName: Code[10];
        BatchBankAccountNo: Code[20];
        TargetLineNos: List of [Integer];
        LinesMarked: Boolean;
        BankOptionsVerified: Boolean;
        EmailRunSeen: Boolean;
        AnyReportRun: Boolean;
        BankOptionNameTok: Label 'BankAccount."No."', Locked = true;
        ReportParametersTok: Label 'ReportParameters', Locked = true;
        OptionsTok: Label 'Options', Locked = true;
        DataItemsTok: Label 'DataItems', Locked = true;
        DataItemTok: Label 'DataItem', Locked = true;
        FieldTok: Label 'Field', Locked = true;
        NameTok: Label 'name', Locked = true;
        RequestPageBankErr: Label 'Report %1 %2 is set to bank account %3, but journal batch %4 %5 pays from bank account %6. The report only includes payments from the bank account chosen on its request page. Choose bank account %6 and run Export again.', Comment = '%1 = report ID, %2 = report caption, %3 = bank account on the request page, %4 = journal template name, %5 = journal batch name, %6 = bank account of the batch';
        NothingLeftToReportErr: Label 'The journal line filters on the remittance report''s request page leave no lines of journal batch %1 to report on. Clear those filters, or set them to batch %1, and run Export again.', Comment = '%1 = journal batch name';

    procedure SetBatch(TemplateName: Code[10]; BatchName: Code[10]; BankAccountNo: Code[20])
    begin
        JnlTemplateName := TemplateName;
        JnlBatchName := BatchName;
        BatchBankAccountNo := BankAccountNo;
        Clear(TargetLineNos);
        LinesMarked := false;
        BankOptionsVerified := false;
        EmailRunSeen := false;
        AnyReportRun := false;
    end;

    // OutputType uses Custom Layout Reporting's option values (GetPreviewOption() etc.).
    procedure MarkLinesExported(OutputType: Integer)
    var
        GenJournalLine: Record "Gen. Journal Line";
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";
        LineNo: Integer;
    begin
        if OutputType = CustomLayoutReporting.GetPreviewOption() then
            exit;
        if LinesMarked then
            exit;
        LinesMarked := true;

        GenJournalLine.SetRange("Journal Template Name", JnlTemplateName);
        GenJournalLine.SetRange("Journal Batch Name", JnlBatchName);
        GenJournalLine.SetRange("BAACH EFT File Created", true);
        GenJournalLine.SetRange("Check Transmitted", false);
        if GenJournalLine.FindSet() then
            repeat
                TargetLineNos.Add(GenJournalLine."Line No.");
            until GenJournalLine.Next() = 0;

        foreach LineNo in TargetLineNos do begin
            GenJournalLine.Get(JnlTemplateName, JnlBatchName, LineNo);
            GenJournalLine."Check Exported" := true;
            GenJournalLine."Check Transmitted" := true;
            GenJournalLine.Modify();
        end;
    end;

    procedure MarkVendorEmailFailed(VendorNo: Code[20])
    begin
        MarkPayeeEmailFailed("Gen. Journal Account Type"::Vendor, VendorNo);
    end;

    local procedure MarkPayeeEmailFailed(PayeeType: Enum "Gen. Journal Account Type"; PayeeNo: Code[20])
    var
        GenJournalLine: Record "Gen. Journal Line";
        FailedLineNos: List of [Integer];
        LineNo: Integer;
        LinePayeeType: Enum "Gen. Journal Account Type";
        LinePayeeNo: Code[20];
    begin
        GenJournalLine.SetRange("Journal Template Name", JnlTemplateName);
        GenJournalLine.SetRange("Journal Batch Name", JnlBatchName);
        GenJournalLine.SetRange("BAACH EFT File Created", true);
        GenJournalLine.SetRange("Check Exported", true);
        if GenJournalLine.FindSet() then
            repeat
                if IsLineInThisRun(GenJournalLine."Line No.") then begin
                    GetPayee(GenJournalLine, LinePayeeType, LinePayeeNo);
                    if (LinePayeeType = PayeeType) and (LinePayeeNo = PayeeNo) then
                        FailedLineNos.Add(GenJournalLine."Line No.");
                end;
            until GenJournalLine.Next() = 0;

        foreach LineNo in FailedLineNos do
            ClearCheckTransmitted(LineNo);
    end;

    local procedure IsLineInThisRun(LineNo: Integer): Boolean
    begin
        if TargetLineNos.Count() = 0 then
            exit(true);
        exit(TargetLineNos.Contains(LineNo));
    end;

    local procedure ClearCheckTransmitted(LineNo: Integer)
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.Get(JnlTemplateName, JnlBatchName, LineNo);
        if not GenJournalLine."Check Transmitted" then
            exit;
        GenJournalLine."Check Transmitted" := false;
        GenJournalLine.Modify();
    end;

    // The payee is the record the engine joins each line to, as in "Custom Layout Reporting".SetIteratorJoinFieldRef.
    local procedure GetPayee(GenJournalLine: Record "Gen. Journal Line"; var PayeeType: Enum "Gen. Journal Account Type"; var PayeeNo: Code[20])
    begin
        if GenJournalLine."Bal. Account Type" in [GenJournalLine."Bal. Account Type"::Vendor, GenJournalLine."Bal. Account Type"::Customer] then begin
            PayeeType := GenJournalLine."Bal. Account Type";
            PayeeNo := GenJournalLine."Bal. Account No.";
        end else begin
            PayeeType := GenJournalLine."Account Type";
            PayeeNo := GenJournalLine."Account No.";
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Custom Layout Reporting", 'OnRunRequestPageOnBeforeReportRunRequestPage', '', false, false)]
    local procedure PrefillOnRunRequestPage(ReportId: Integer; var SavedParameters: Text)
    begin
        PrefillRequestParameters(ReportId, SavedParameters);
    end;

    // The saved request page holds the user's last-used journal line filters, often another batch's. Custom Layout
    // Reporting intersects them with the lines being exported, which leaves nothing to report ("No data exists").
    procedure PrefillRequestParameters(ReportId: Integer; var SavedParameters: Text)
    var
        IsStandardReport: Boolean;
    begin
        IsStandardReport := ReportId in [Report::"Export Electronic Payments", Report::"ExportElecPayments - Word"];
        if IsStandardReport or HasBankOption(SavedParameters) then
            SetBankOption(ReportId, SavedParameters);
        SetJournalLineFilter(ReportId, SavedParameters, IsStandardReport);
    end;

    // Every run raises OnBeforeRunReportWithCustomReportSelection, except a RunReport call whose OnBeforeRunReport
    // another subscriber handles; subscribing to both catches the first run either way.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Custom Layout Reporting", 'OnBeforeRunReport', '', false, false)]
    local procedure OnBeforeRunReport(var TempBlobIndicesNameValueBuffer: Record "Name/Value Buffer" temporary; var TempBlobList: Codeunit "Temp Blob List"; var OutputType: Option)
    begin
        OnReportRun(OutputType, TempBlobIndicesNameValueBuffer, TempBlobList);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Custom Layout Reporting", 'OnBeforeRunReportWithCustomReportSelection', '', false, false)]
    local procedure OnBeforeRunReportWithCustomReportSelection(var TempBlobIndicesNameValueBuffer: Record "Name/Value Buffer" temporary; var TempBlobList: Codeunit "Temp Blob List"; var OutputType: Option)
    begin
        OnReportRun(OutputType, TempBlobIndicesNameValueBuffer, TempBlobList);
    end;

    local procedure OnReportRun(OutputType: Integer; var TempBlobIndicesNameValueBuffer: Record "Name/Value Buffer" temporary; var TempBlobList: Codeunit "Temp Blob List")
    var
        CustomLayoutReporting: Codeunit "Custom Layout Reporting";
    begin
        if not AnyReportRun then begin
            LimitStoredParametersToBatch(TempBlobIndicesNameValueBuffer, TempBlobList);
            AnyReportRun := true;
        end;
        if OutputType = CustomLayoutReporting.GetPreviewOption() then
            exit;
        if OutputType = CustomLayoutReporting.GetEmailOption() then
            EmailRunSeen := true;
        if not BankOptionsVerified then begin
            VerifyRequestPageBanks(TempBlobIndicesNameValueBuffer, TempBlobList);
            BankOptionsVerified := true;
        end;
        MarkLinesExported(OutputType);
    end;

    // The request page's journal line filters can be changed by the user, and Report.SaveAs reads them from the
    // stored parameters, so they are pinned to the exported batch before the first report runs. Any other filter
    // the user set is kept.
    procedure LimitStoredParametersToBatch(var TempBlobIndicesNameValueBuffer: Record "Name/Value Buffer" temporary; var TempBlobList: Codeunit "Temp Blob List")
    var
        TempReportParametersBuffer: Record "Name/Value Buffer" temporary;
        TempBlob: Codeunit "Temp Blob";
        LimitedTempBlob: Codeunit "Temp Blob";
        TypeHelper: Codeunit "Type Helper";
        ParametersInStream: InStream;
        ParametersOutStream: OutStream;
        Parameters: Text;
        Index: Integer;
    begin
        TempReportParametersBuffer.Copy(TempBlobIndicesNameValueBuffer, true);
        TempReportParametersBuffer.Reset();
        if TempReportParametersBuffer.FindSet() then
            repeat
                if Evaluate(Index, TempReportParametersBuffer.Value) then
                    if TempBlobList.Exists(Index) then begin
                        TempBlobList.Get(Index, TempBlob);
                        TempBlob.CreateInStream(ParametersInStream, TextEncoding::UTF8);
                        Parameters := TypeHelper.ReadAsTextWithSeparator(ParametersInStream, TypeHelper.LFSeparator());
                        if LimitRequestParametersToBatch(Parameters) then begin
                            Clear(LimitedTempBlob);
                            LimitedTempBlob.CreateOutStream(ParametersOutStream, TextEncoding::UTF8);
                            ParametersOutStream.WriteText(Parameters);
                            TempBlobList.Set(Index, LimitedTempBlob);
                        end;
                    end;
            until TempReportParametersBuffer.Next() = 0;
    end;

    // Reports without a "Gen. Journal Line" data item, such as a custom remittance report, are left unchanged.
    procedure LimitRequestParametersToBatch(var Parameters: Text): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        ParametersXml: XmlDocument;
        DataItemElement: XmlElement;
        View: Text;
    begin
        if Parameters = '' then
            exit(false);
        if not XmlDocument.ReadFrom(Parameters, ParametersXml) then
            exit(false);
        if not FindJournalLineDataItem(ParametersXml, false, DataItemElement) then
            exit(false);

        View := DataItemElement.InnerText();
        if View <> '' then
            GenJournalLine.SetView(View);
        GenJournalLine.SetRange("Journal Template Name", JnlTemplateName);
        GenJournalLine.SetRange("Journal Batch Name", JnlBatchName);
        DataItemElement.RemoveNodes();
        DataItemElement.Add(XmlText.Create(GenJournalLine.GetView(false)));

        WriteSingleLine(ParametersXml, Parameters);
        exit(true);
    end;

    // When the request page filters leave none of the batch's lines, Custom Layout Reporting runs no report and only
    // says "No data exists for the specified report filters", which does not tell the user what to change.
    procedure CheckLinesLeftToReport(var ReportDataRecordRef: RecordRef)
    begin
        if AnyReportRun then
            exit;
        if ReportDataRecordRef.Number() <> Database::"Gen. Journal Line" then
            exit;
        if ReportDataRecordRef.IsEmpty() then
            Error(NothingLeftToReportErr, JnlBatchName);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Custom Layout Reporting", 'OnBeforeThrowProcessReportError', '', false, false)]
    local procedure ExplainNothingLeftToReport(var ReportDataRecordRef: RecordRef)
    begin
        CheckLinesLeftToReport(ReportDataRecordRef);
    end;

    // Every request page has been run before the first report, so all reports are checked before anything is sent.
    local procedure VerifyRequestPageBanks(var TempBlobIndicesNameValueBuffer: Record "Name/Value Buffer" temporary; var TempBlobList: Codeunit "Temp Blob List")
    var
        TempReportParametersBuffer: Record "Name/Value Buffer" temporary;
        TempBlob: Codeunit "Temp Blob";
        TypeHelper: Codeunit "Type Helper";
        ParametersInStream: InStream;
        Parameters: Text;
        ChosenBankAccountNo: Text;
        Index: Integer;
    begin
        TempReportParametersBuffer.Copy(TempBlobIndicesNameValueBuffer, true);
        TempReportParametersBuffer.Reset();
        if TempReportParametersBuffer.FindSet() then
            repeat
                if Evaluate(Index, TempReportParametersBuffer.Value) then
                    if TempBlobList.Exists(Index) then begin
                        TempBlobList.Get(Index, TempBlob);
                        TempBlob.CreateInStream(ParametersInStream, TextEncoding::UTF8);
                        Parameters := TypeHelper.ReadAsTextWithSeparator(ParametersInStream, TypeHelper.LFSeparator());
                        if GetBankOption(Parameters, ChosenBankAccountNo) then
                            if UpperCase(ChosenBankAccountNo) <> BatchBankAccountNo then
                                Error(RequestPageBankErr, TempReportParametersBuffer.ID, GetReportCaption(TempReportParametersBuffer.ID),
                                    ChosenBankAccountNo, JnlTemplateName, JnlBatchName, BatchBankAccountNo);
                    end;
            until TempReportParametersBuffer.Next() = 0;
    end;

    local procedure GetReportCaption(ReportId: Integer): Text
    var
        AllObjWithCaption: Record AllObjWithCaption;
    begin
        if AllObjWithCaption.Get(AllObjWithCaption."Object Type"::Report, ReportId) then
            exit(AllObjWithCaption."Object Caption");
    end;

    local procedure HasBankOption(Parameters: Text): Boolean
    var
        ChosenBankAccountNo: Text;
    begin
        exit(GetBankOption(Parameters, ChosenBankAccountNo));
    end;

    local procedure GetBankOption(Parameters: Text; var ChosenBankAccountNo: Text): Boolean
    var
        ParametersXml: XmlDocument;
        BankField: XmlElement;
        OptionsElement: XmlElement;
    begin
        if Parameters = '' then
            exit(false);
        if not XmlDocument.ReadFrom(Parameters, ParametersXml) then
            exit(false);
        if not FindOptionsElement(ParametersXml, false, OptionsElement) then
            exit(false);
        if not FindBankField(OptionsElement, BankField) then
            exit(false);
        ChosenBankAccountNo := BankField.InnerText();
        exit(true);
    end;

    // Request page XML names each option after its source expression, e.g. <Field name="BankAccount.&quot;No.&quot;">.
    // Only the bank option is changed; every other saved option and filter is kept.
    local procedure SetBankOption(ReportId: Integer; var SavedParameters: Text)
    var
        ParametersXml: XmlDocument;
        OptionsElement: XmlElement;
        BankField: XmlElement;
    begin
        if SavedParameters = '' then
            CreateParametersXml(ReportId, ParametersXml)
        else
            if not XmlDocument.ReadFrom(SavedParameters, ParametersXml) then
                exit;

        if not FindOptionsElement(ParametersXml, true, OptionsElement) then
            exit;
        if FindBankField(OptionsElement, BankField) then
            BankField.RemoveNodes()
        else begin
            BankField := XmlElement.Create(FieldTok);
            BankField.SetAttribute(NameTok, BankOptionNameTok);
            OptionsElement.Add(BankField);
        end;
        BankField.Add(XmlText.Create(BatchBankAccountNo));

        ParametersXml.WriteTo(SavedParameters);
    end;

    local procedure SetJournalLineFilter(ReportId: Integer; var SavedParameters: Text; CreateIfMissing: Boolean)
    var
        GenJournalLine: Record "Gen. Journal Line";
        ParametersXml: XmlDocument;
        DataItemElement: XmlElement;
    begin
        if SavedParameters = '' then begin
            if not CreateIfMissing then
                exit;
            CreateParametersXml(ReportId, ParametersXml);
        end else
            if not XmlDocument.ReadFrom(SavedParameters, ParametersXml) then
                exit;
        if not FindJournalLineDataItem(ParametersXml, CreateIfMissing, DataItemElement) then
            exit;

        DataItemElement.RemoveNodes();
        GenJournalLine.SetRange("Journal Template Name", JnlTemplateName);
        GenJournalLine.SetRange("Journal Batch Name", JnlBatchName);
        DataItemElement.Add(XmlText.Create(GenJournalLine.GetView(false)));

        ParametersXml.WriteTo(SavedParameters);
    end;

    local procedure FindJournalLineDataItem(ParametersXml: XmlDocument; CreateIfMissing: Boolean; var DataItemElement: XmlElement): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        RootElement: XmlElement;
        DataItemsElement: XmlElement;
        DataItemsNode: XmlNode;
        DataItemNode: XmlNode;
        NameAttribute: XmlAttribute;
    begin
        if not ParametersXml.GetRoot(RootElement) then
            exit(false);

        if RootElement.SelectSingleNode(DataItemsTok, DataItemsNode) then
            DataItemsElement := DataItemsNode.AsXmlElement()
        else begin
            if not CreateIfMissing then
                exit(false);
            DataItemsElement := XmlElement.Create(DataItemsTok);
            RootElement.Add(DataItemsElement);
        end;

        foreach DataItemNode in DataItemsElement.GetChildElements(DataItemTok) do
            if DataItemNode.AsXmlElement().Attributes().Get(NameTok, NameAttribute) then
                if NameAttribute.Value() = GenJournalLine.TableName() then begin
                    DataItemElement := DataItemNode.AsXmlElement();
                    exit(true);
                end;

        if not CreateIfMissing then
            exit(false);
        DataItemElement := XmlElement.Create(DataItemTok);
        DataItemElement.SetAttribute(NameTok, GenJournalLine.TableName());
        DataItemsElement.Add(DataItemElement);
        exit(true);
    end;

    // Custom Layout Reporting reads the stored parameters back with a single InStream.ReadText, which stops at a line break.
    local procedure WriteSingleLine(ParametersXml: XmlDocument; var Parameters: Text)
    var
        WriteOptions: XmlWriteOptions;
    begin
        WriteOptions.PreserveWhitespace := true;
        ParametersXml.WriteTo(WriteOptions, Parameters);
    end;

    local procedure CreateParametersXml(ReportId: Integer; var ParametersXml: XmlDocument)
    var
        RootElement: XmlElement;
    begin
        ParametersXml := XmlDocument.Create();
        ParametersXml.SetDeclaration(XmlDeclaration.Create('1.0', 'utf-8', 'yes'));
        RootElement := XmlElement.Create(ReportParametersTok);
        RootElement.SetAttribute('id', Format(ReportId, 0, 9));
        ParametersXml.Add(RootElement);
    end;

    local procedure FindOptionsElement(ParametersXml: XmlDocument; CreateIfMissing: Boolean; var OptionsElement: XmlElement): Boolean
    var
        RootElement: XmlElement;
        OptionsNode: XmlNode;
    begin
        if not ParametersXml.GetRoot(RootElement) then
            exit(false);
        if RootElement.SelectSingleNode(OptionsTok, OptionsNode) then begin
            OptionsElement := OptionsNode.AsXmlElement();
            exit(true);
        end;
        if not CreateIfMissing then
            exit(false);
        OptionsElement := XmlElement.Create(OptionsTok);
        RootElement.AddFirst(OptionsElement);
        exit(true);
    end;

    local procedure FindBankField(OptionsElement: XmlElement; var BankField: XmlElement): Boolean
    var
        FieldNode: XmlNode;
        NameAttribute: XmlAttribute;
    begin
        foreach FieldNode in OptionsElement.GetChildElements(FieldTok) do
            if FieldNode.AsXmlElement().Attributes().Get(NameTok, NameAttribute) then
                if NameAttribute.Value() = BankOptionNameTok then begin
                    BankField := FieldNode.AsXmlElement();
                    exit(true);
                end;
        exit(false);
    end;

    // Option A: vendors whose remittance email failed keep Check Exported but lose Check Transmitted, so they cannot be
    // posted and the next Export sends only to them. The Commit keeps that result when the engine raises its error list.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Custom Layout Reporting", 'OnBeforeThrowProcessReportError', '', false, false)]
    local procedure HandleEmailFailures()
    var
        TempErrorMessage: Record "Error Message" temporary;
        ErrorMessageManagement: Codeunit "Error Message Management";
        LineRecordIdTexts: Dictionary of [Integer, Text];
        FailedLineNos: List of [Integer];
        LineNo: Integer;
        ErrorAttributed: Boolean;
        AllLinesFailed: Boolean;
    begin
        if not (EmailRunSeen and LinesMarked) then
            exit;

        TempErrorMessage.SetRange("Message Type", TempErrorMessage."Message Type"::Error);
        if not ErrorMessageManagement.GetErrors(TempErrorMessage) then
            exit;

        GetLineRecordIdTexts(LineRecordIdTexts);
        TempErrorMessage.FindSet();
        repeat
            ErrorAttributed := false;
            foreach LineNo in LineRecordIdTexts.Keys() do
                if MessageNamesRecord(TempErrorMessage."Message", LineRecordIdTexts.Get(LineNo)) then begin
                    ErrorAttributed := true;
                    if not FailedLineNos.Contains(LineNo) then
                        FailedLineNos.Add(LineNo);
                end;
            if not ErrorAttributed then
                AllLinesFailed := true;
        until TempErrorMessage.Next() = 0;

        // An error that names no journal line (for example "No data exists") cannot be traced to a vendor,
        // so no line is treated as sent.
        if AllLinesFailed then
            foreach LineNo in TargetLineNos do
                ClearCheckTransmitted(LineNo)
        else
            foreach LineNo in FailedLineNos do
                MarkLinePayeeEmailFailed(LineNo);

        Commit();
    end;

    local procedure GetLineRecordIdTexts(var LineRecordIdTexts: Dictionary of [Integer, Text])
    var
        GenJournalLine: Record "Gen. Journal Line";
        LineNo: Integer;
    begin
        foreach LineNo in TargetLineNos do
            if GenJournalLine.Get(JnlTemplateName, JnlBatchName, LineNo) then
                LineRecordIdTexts.Add(LineNo, Format(GenJournalLine.RecordId()));
    end;

    local procedure MarkLinePayeeEmailFailed(LineNo: Integer)
    var
        GenJournalLine: Record "Gen. Journal Line";
        PayeeType: Enum "Gen. Journal Account Type";
        PayeeNo: Code[20];
    begin
        GenJournalLine.Get(JnlTemplateName, JnlBatchName, LineNo);
        GetPayee(GenJournalLine, PayeeType, PayeeNo);
        MarkPayeeEmailFailed(PayeeType, PayeeNo);
    end;

    // The engine's error texts name the journal line only through its formatted record ID ("... for <record ID>, ...").
    // Codeunit 10250 looks for the template, batch and line number separately, which also lets line 10000 match
    // line 100000; the digit check here prevents that.
    local procedure MessageNamesRecord(MessageText: Text; RecordIdText: Text): Boolean
    var
        Position: Integer;
        NextPosition: Integer;
    begin
        Position := StrPos(MessageText, RecordIdText);
        while Position > 0 do begin
            NextPosition := Position + StrLen(RecordIdText);
            if NextPosition > StrLen(MessageText) then
                exit(true);
            if not (MessageText[NextPosition] in ['0' .. '9']) then
                exit(true);
            MessageText := CopyStr(MessageText, NextPosition);
            Position := StrPos(MessageText, RecordIdText);
        end;
        exit(false);
    end;
}
