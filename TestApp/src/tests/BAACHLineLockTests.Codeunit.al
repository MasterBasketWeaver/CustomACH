codeunit 81212 "BAACH Line Lock Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    RequiredTestIsolation = Function;

    var
        Assert: Codeunit "BAACH Assert";
        Library: Codeunit "BAACH Library";
        StandardLockMessageErr: Label 'Expected the line guard''s own message, not the standard "%1" field error. The error was: %2', Comment = '%1 = Check Printed caption, %2 = error text';

    [Test]
    procedure ModifyWithTriggerIsRefusedAfterGenerate()
    var
        GenJournalLine: Record "Gen. Journal Line";
        OriginalDescription: Text[100];
    begin
        CreateGeneratedLine(GenJournalLine);
        OriginalDescription := GenJournalLine.Description;

        GenJournalLine.Description := 'Changed after Generate';
        asserterror GenJournalLine.Modify(true);
        VerifyGuardMessage(GenJournalLine);

        GenJournalLine.Find();
        Assert.AreEqual(OriginalDescription, GenJournalLine.Description, 'Description must not change.');
    end;

    [Test]
    procedure DeleteWithTriggerIsRefusedAfterGenerate()
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        CreateGeneratedLine(GenJournalLine);

        asserterror GenJournalLine.Delete(true);
        VerifyGuardMessage(GenJournalLine);

        Assert.IsTrue(GenJournalLine.Find(), 'The line must still exist.');
    end;

    [Test]
    procedure RenameIsRefusedAfterGenerate()
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        CreateGeneratedLine(GenJournalLine);

        asserterror GenJournalLine.Rename(GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name", GenJournalLine."Line No." + 1);
        VerifyGuardMessage(GenJournalLine);

        Assert.IsTrue(GenJournalLine.Find(), 'The line must keep its key.');
    end;

    [Test]
    procedure CodeLevelModifyIsStillAllowedAfterGenerate()
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        CreateGeneratedLine(GenJournalLine);

        GenJournalLine.Description := 'Changed by code';
        GenJournalLine.Modify(false);

        GenJournalLine.Find();
        Assert.AreEqual('Changed by code', GenJournalLine.Description, 'Description');
    end;

    [Test]
    procedure LinesAreEditableBeforeGenerate()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, false);

        GenJournalLine.Description := 'Changed before Generate';
        GenJournalLine.Modify(true);
        GenJournalLine.Rename(GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name", GenJournalLine."Line No." + 1);
        GenJournalLine.Delete(true);

        Assert.IsFalse(GenJournalLine.Find(), 'The line must be deletable before Generate.');
    end;

    [Test]
    procedure TheGuardActsOnTheEFTFileCreatedFlag()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        // Check Printed stays off, so the standard lock cannot be what refuses the change.
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, false);
        GenJournalLine."BAACH EFT File Created" := true;
        GenJournalLine.Modify(false);

        GenJournalLine.Description := 'Changed with the flag set';
        asserterror GenJournalLine.Modify(true);

        GenJournalLine.Find();
        asserterror GenJournalLine.Delete(true);
        Assert.IsTrue(GenJournalLine.Find(), 'The line must still exist.');
    end;

    [Test]
    procedure LinesAreNotLockedWhenTheSwitchIsOff()
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, false);
        GenJournalLine."BAACH EFT File Created" := true;
        GenJournalLine.Modify(false);
        Library.SetSwitch(false);

        GenJournalLine.Description := 'Changed with the switch off';
        GenJournalLine.Modify(true);
        GenJournalLine.Delete(true);

        Assert.IsFalse(GenJournalLine.Find(), 'The line must be deletable with the switch off.');
    end;

    local procedure CreateGeneratedLine(var GenJournalLine: Record "Gen. Journal Line")
    var
        BankAccount: Record "Bank Account";
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        Library.CreateEFTScenario(BankAccount, GenJournalBatch);
        Library.CreateVendorPayment(GenJournalLine, GenJournalBatch, 100, true);
        Library.GenerateEFT(GenJournalBatch);
        GenJournalLine.Find();
    end;

    // The standard lock (TestField "Check Printed" = No) would also refuse the change; the
    // guard must get there first with a message that explains the custom process.
    local procedure VerifyGuardMessage(GenJournalLine: Record "Gen. Journal Line")
    var
        ErrorText: Text;
    begin
        ErrorText := GetLastErrorText();
        if StrPos(ErrorText, GenJournalLine.FieldCaption("Check Printed")) <> 0 then
            Assert.Fail(StrSubstNo(StandardLockMessageErr, GenJournalLine.FieldCaption("Check Printed"), ErrorText));
    end;
}
