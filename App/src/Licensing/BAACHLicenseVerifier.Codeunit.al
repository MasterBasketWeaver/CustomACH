// A copy of the licensing app's "BALIC Token Verifier" (bc_licensing_app,
// App/src), renamed. Custom ACH verifies its own licence against the
// public keys compiled in here, so a replaced licensing app cannot unlock it.
// Keep it identical to the original apart from the names.
codeunit 81107 "BAACH License Verifier"
{
    Access = Internal;

    var
        PublicKeyV1Tok: Label '<RSAKeyValue><Modulus>pwCQdprxKs2ZPohgAUKudg994kK2uFAQTlyGPqZyZIQOg/KS2BB2kmvyuqsGv/1zJxxg3TH58SS6lJmoLNepILKu/35TmsfQO+qSnMSch4veLQn8ACzFTzr9G1a01kmzOzLnyZi6pyK9ijTLPt+tBu1dFlotwyTxoGbxeAM3Nqh7Jq+EZrHMoUEoLmVVnNczDXnSNe4aCSOm9O0xLOYal6GlAiWbKdhLfTPKwMipUsJxfBWy91QSnFVBjitl0fgGieP/Cgtm7zpHeAsKku7PszTWsIMVwdhrniE0skB/w8qhA23CZeRQ4F2Qs450P1RgRu6WMpXcLJxNmB8uLoUckw==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>', Locked = true;
        PublicKeyV2Tok: Label '<RSAKeyValue><Modulus>sWGqTTVdVROjhSdbSR4eS3YYnyyTuB0IB61M4iOFKmEph0arhHU1I5sI1qPSm00NewfmYz6Hl4dZdvc+fJHFb9oH4/PNgQiHqw2VIlcnocRJUZBL2y7DLpFzhNJoZXrH1oqex1Gw9wUie2OL3sJiPsB0h3ZLCmYMXE33SWKJO+GCK+eGuF9oHGwz9RYb8RzKG1nvu82UOKRU5NAkZ3hETh5PaBzfJ12IEo/5N0PPsAyscaxIqwSqsqiL7xLe2ON029qskMQpus/QIkcbfoCus+2TCyJqabAxl8eZZLzQ+L64GuBQhsSW3t0uBq7RdQ0w/fubN2SVKLxmzcsacaoRYw==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>', Locked = true;

    local procedure PublicKeyXml(Kid: Integer): Text
    begin
        case Kid of
            1:
                exit(PublicKeyV1Tok);
            2:
                exit(PublicKeyV2Tok);
            else
                exit('');
        end;
    end;

    procedure ExtractToken(LicenseText: Text): Text
    var
        Body: TextBuilder;
        Line: Text;
        Trimmed: Text;
        LF: Char;
        InHeader: Boolean;
        InBody: Boolean;
    begin
        if StrPos(LicenseText, '-----BEGIN') = 0 then
            exit(StripWhitespace(LicenseText));

        LF := 10;
        foreach Line in LicenseText.Split(Format(LF)) do begin
            Trimmed := StripWhitespace(Line);
            case true of
                InBody:
                    begin
                        if Trimmed.StartsWith('-----END') then
                            exit(Body.ToText());
                        Body.Append(Trimmed);
                    end;
                InHeader:
                    begin
                        if Trimmed.StartsWith('-----END') then
                            exit('');
                        if Trimmed = '' then
                            InBody := true;
                    end;
                Trimmed.StartsWith('-----BEGIN'):
                    InHeader := true;
            end;
        end;
        exit('');
    end;

    procedure Verify(RawToken: Text; AppId: Guid; TenantId: Text; EnvironmentName: Text; IsSandbox: Boolean; AsOf: Date; var Payload: JsonObject; var Reason: Enum "BALIC Failure Reason"): Boolean
    var
        ClaimGuid: Guid;
        TenantGuid: Guid;
        ExpiresAt: Date;
        PayloadPart: Text;
        SignaturePart: Text;
        KeyXml: Text;
        SeparatorPos: Integer;
        GraceDays: Integer;
        SignatureValid: Boolean;
    begin
        Clear(Payload);
        RawToken := StripWhitespace(RawToken);
        SeparatorPos := StrPos(RawToken, '.');
        if SeparatorPos = 0 then
            exit(Fail(Reason, Reason::Malformed));
        PayloadPart := CopyStr(RawToken, 1, SeparatorPos - 1);
        SignaturePart := CopyStr(RawToken, SeparatorPos + 1);
        if (PayloadPart = '') or (SignaturePart = '') then
            exit(Fail(Reason, Reason::Malformed));

        // The payload is read before the signature to learn 'kid', and stays
        // untrusted until the key it names has verified it.
        if not TryDecodePayload(PayloadPart, Payload) then begin
            Clear(Payload);
            exit(Fail(Reason, Reason::Malformed));
        end;

        KeyXml := PublicKeyXml(GetIntClaim(Payload, 'kid'));
        if KeyXml = '' then
            exit(Fail(Reason, Reason::UnknownKey));
        if not TryVerifySignature(PayloadPart, SignaturePart, KeyXml, SignatureValid) then
            exit(Fail(Reason, Reason::Malformed));
        if not SignatureValid then
            exit(Fail(Reason, Reason::BadSignature));

        if GetIntClaim(Payload, 'v') <> 1 then
            exit(Fail(Reason, Reason::UnsupportedVersion));

        if not Evaluate(ClaimGuid, GetTextClaim(Payload, 'aid')) then
            exit(Fail(Reason, Reason::WrongProduct));
        if IsNullGuid(ClaimGuid) or (ClaimGuid <> AppId) then
            exit(Fail(Reason, Reason::WrongProduct));

        // GetAadTenantId() returns '' when it cannot find the tenant; that must
        // fail, never pass.
        if TenantId = '' then
            exit(Fail(Reason, Reason::TenantUnavailable));
        if not Evaluate(TenantGuid, TenantId) then
            exit(Fail(Reason, Reason::TenantUnavailable));
        if IsNullGuid(TenantGuid) then
            exit(Fail(Reason, Reason::TenantUnavailable));
        if not Evaluate(ClaimGuid, GetTextClaim(Payload, 'tid')) then
            exit(Fail(Reason, Reason::WrongTenant));
        if ClaimGuid <> TenantGuid then
            exit(Fail(Reason, Reason::WrongTenant));

        if IsSandbox then begin
            if not GetBoolClaim(Payload, 'sbx') then
                exit(Fail(Reason, Reason::SandboxNotLicensed));
        end else
            // Production is bound by environment type, not name: any production
            // environment of the tenant is covered when 'env' lists anything.
            if not CoversProduction(Payload) then
                exit(Fail(Reason, Reason::WrongEnvironment));

        if not GetDateClaim(Payload, 'exp', ExpiresAt) then
            exit(Fail(Reason, Reason::Malformed));
        if not IsSandbox then
            GraceDays := GetIntClaim(Payload, 'g');
        if GraceDays < 0 then
            GraceDays := 0;
        if AsOf > ExpiresAt + GraceDays then
            exit(Fail(Reason, Reason::Expired));

        Reason := Reason::None;
        exit(true);
    end;

    procedure VerifyForCurrentEnvironment(RawToken: Text; AppId: Guid; var Payload: JsonObject; var Reason: Enum "BALIC Failure Reason"): Boolean
    var
        AzureADTenant: Codeunit "Azure AD Tenant";
        EnvironmentInformation: Codeunit "Environment Information";
    begin
        exit(Verify(RawToken, AppId, AzureADTenant.GetAadTenantId(), EnvironmentInformation.GetEnvironmentName(),
            EnvironmentInformation.IsSandbox(), Today(), Payload, Reason));
    end;

    procedure ComputeStatus(HasToken: Boolean; TokenValid: Boolean; Reason: Enum "BALIC Failure Reason"; ExpiresAt: Date; InstalledAt: Date; TrialDays: Integer; IsSandbox: Boolean; AsOf: Date): Enum "BALIC License Status"
    var
        Status: Enum "BALIC License Status";
    begin
        if TokenValid then begin
            if (not IsSandbox) and (AsOf > ExpiresAt) then
                exit(Status::Grace);
            if ExpiresAt - AsOf <= 30 then
                exit(Status::Expiring);
            exit(Status::Active);
        end;
        if IsSandbox then
            exit(Status::Trial);
        // AL's "or" does not short-circuit, and 0D arithmetic throws.
        if InstalledAt = 0D then
            exit(Status::Trial);
        // Day 1 is the install day, so day 8 of a 7-day trial is already Expired.
        if AsOf - InstalledAt < TrialDays then
            exit(Status::Trial);
        if HasToken and (Reason = Reason::Expired) then
            exit(Status::Expired);
        if HasToken then
            exit(Status::Invalid);
        exit(Status::Expired);
    end;

    procedure IsUsable(Status: Enum "BALIC License Status"): Boolean
    begin
        exit(Status in [Status::Trial, Status::Active, Status::Expiring, Status::Grace]);
    end;

    procedure GetTextClaim(Payload: JsonObject; Name: Text): Text
    var
        Value: JsonValue;
        Result: Text;
    begin
        if not GetClaimValue(Payload, Name, Value) then
            exit('');
        if not TryAsText(Value, Result) then
            exit('');
        exit(Result);
    end;

    procedure GetIntClaim(Payload: JsonObject; Name: Text): Integer
    var
        Value: JsonValue;
        Result: Integer;
    begin
        if not GetClaimValue(Payload, Name, Value) then
            exit(0);
        if not TryAsInteger(Value, Result) then
            exit(0);
        exit(Result);
    end;

    procedure GetBoolClaim(Payload: JsonObject; Name: Text): Boolean
    var
        Value: JsonValue;
        Result: Boolean;
    begin
        if not GetClaimValue(Payload, Name, Value) then
            exit(false);
        if not TryAsBoolean(Value, Result) then
            exit(false);
        exit(Result);
    end;

    // Evaluate with format 9 (ISO 8601); JsonValue.AsDate() is not relied on
    // for "yyyy-mm-dd" strings.
    procedure GetDateClaim(Payload: JsonObject; Name: Text; var Value: Date): Boolean
    var
        DateText: Text;
    begin
        Value := 0D;
        DateText := GetTextClaim(Payload, Name);
        if DateText = '' then
            exit(false);
        if not Evaluate(Value, DateText, 9) then begin
            Value := 0D;
            exit(false);
        end;
        exit(Value <> 0D);
    end;

    procedure GetListClaim(Payload: JsonObject; Name: Text): Text
    var
        Items: JsonArray;
        Item: JsonToken;
        Result: TextBuilder;
        ItemText: Text;
    begin
        if not GetClaimArray(Payload, Name, Items) then
            exit('');
        foreach Item in Items do
            if Item.IsValue() then
                if TryAsText(Item.AsValue(), ItemText) then begin
                    if Result.Length() > 0 then
                        Result.Append(', ');
                    Result.Append(ItemText);
                end;
        exit(Result.ToText());
    end;

    procedure HasListValue(Payload: JsonObject; Name: Text; Value: Text): Boolean
    var
        Items: JsonArray;
        Item: JsonToken;
        ItemText: Text;
    begin
        if Value = '' then
            exit(false);
        if not GetClaimArray(Payload, Name, Items) then
            exit(false);
        foreach Item in Items do
            if Item.IsValue() then
                if TryAsText(Item.AsValue(), ItemText) then
                    if LowerCase(ItemText) = LowerCase(Value) then
                        exit(true);
        exit(false);
    end;

    local procedure CoversProduction(Payload: JsonObject): Boolean
    var
        Items: JsonArray;
    begin
        if not GetClaimArray(Payload, 'env', Items) then
            exit(false);
        exit(Items.Count() > 0);
    end;

    local procedure Fail(var Reason: Enum "BALIC Failure Reason"; FailureReason: Enum "BALIC Failure Reason"): Boolean
    begin
        Reason := FailureReason;
        exit(false);
    end;

    // Email clients wrap long base64; every space, tab, CR and LF is noise.
    local procedure StripWhitespace(Value: Text): Text
    var
        Tab: Char;
        CR: Char;
        LF: Char;
    begin
        Tab := 9;
        CR := 13;
        LF := 10;
        exit(DelChr(Value, '=', ' ' + Format(Tab) + Format(CR) + Format(LF)));
    end;

    [TryFunction]
    local procedure TryDecodePayload(PayloadPart: Text; var Payload: JsonObject)
    var
        Base64Convert: Codeunit "Base64 Convert";
    begin
        if not Payload.ReadFrom(Base64Convert.FromBase64(PayloadPart)) then
            Error('');
    end;

    // Verifies the encoded payload string, byte for byte what was signed.
    [TryFunction]
    local procedure TryVerifySignature(PayloadPart: Text; SignaturePart: Text; KeyXml: Text; var SignatureValid: Boolean)
    var
        Base64Convert: Codeunit "Base64 Convert";
        CryptographyManagement: Codeunit "Cryptography Management";
        TempBlob: Codeunit "Temp Blob";
        SignatureInStream: InStream;
        SignatureOutStream: OutStream;
    begin
        TempBlob.CreateOutStream(SignatureOutStream);
        Base64Convert.FromBase64(SignaturePart, SignatureOutStream);
        TempBlob.CreateInStream(SignatureInStream);
        SignatureValid := CryptographyManagement.VerifyData(PayloadPart, KeyXml, Enum::"Hash Algorithm"::SHA256, SignatureInStream);
    end;

    local procedure GetClaimValue(Payload: JsonObject; Name: Text; var Value: JsonValue): Boolean
    var
        Token: JsonToken;
    begin
        if not Payload.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        Value := Token.AsValue();
        exit(not Value.IsNull());
    end;

    local procedure GetClaimArray(Payload: JsonObject; Name: Text; var Items: JsonArray): Boolean
    var
        Token: JsonToken;
    begin
        if not Payload.Get(Name, Token) then
            exit(false);
        if not Token.IsArray() then
            exit(false);
        Items := Token.AsArray();
        exit(true);
    end;

    [TryFunction]
    local procedure TryAsText(Value: JsonValue; var Result: Text)
    begin
        Result := Value.AsText();
    end;

    [TryFunction]
    local procedure TryAsInteger(Value: JsonValue; var Result: Integer)
    begin
        Result := Value.AsInteger();
    end;

    [TryFunction]
    local procedure TryAsBoolean(Value: JsonValue; var Result: Boolean)
    begin
        Result := Value.AsBoolean();
    end;
}
