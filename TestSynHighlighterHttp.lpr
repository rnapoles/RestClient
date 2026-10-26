program TestSynHighlighterHttp;

{$mode objfpc}{$H+}

uses
  Interfaces,
  SysUtils, Classes,
  SynEditHighlighterFoldBase,
  SynEditHighlighter,
  SynHighlighterHttp;

type
  TTestHttpSyn = class(TSynHttpSyn)
  public
    function GetFoldLevel: Integer;
    function GetTopFoldType: Pointer;
  end;

function TTestHttpSyn.GetFoldLevel: Integer;
begin
  Result := CurrentCodeFoldBlockLevel;
end;

function TTestHttpSyn.GetTopFoldType: Pointer;
begin
  Result := TopCodeFoldBlockType;
end;

procedure AssertTrue(Condition: Boolean; const Msg: string);
begin
  if not Condition then
  begin
    WriteLn('FAIL: ', Msg);
    Halt(1);
  end;
end;

procedure TestExampleHttp;
var
  HL: TTestHttpSyn;
  Lines: TStringList;
  Ranges: array of Pointer;
  LineIdx: Integer;
  LineText, Reconstructed: string;
  TokenText: string;
  TokenCount: Integer;
begin
  WriteLn('--- Testing example.http ---');
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile('example.http');
    SetLength(Ranges, Lines.Count + 1);

    HL := TTestHttpSyn.Create(nil);
    try
      // Initial state
      HL.ResetRange;
      Ranges[0] := HL.GetRange;

      // Scan all lines, saving range after each line
      for LineIdx := 0 to Lines.Count - 1 do
      begin
        LineText := Lines[LineIdx];
        HL.SetRange(Ranges[LineIdx]);
        HL.SetLine(LineText, LineIdx);

        Reconstructed := '';
        TokenCount := 0;

        // Verify first token ready immediately (no initial Next needed)
        if LineText = '' then
        begin
          AssertTrue(HL.GetEol, Format('Line %d is empty but GetEol is false', [LineIdx + 1]));
        end
        else
        begin
          AssertTrue(not HL.GetEol, Format('Line %d has text but GetEol is true', [LineIdx + 1]));
        end;

        // Iterate through all tokens on the line
        while not HL.GetEol do
        begin
          TokenText := HL.GetToken;
          Reconstructed := Reconstructed + TokenText;
          Inc(TokenCount);
          HL.Next;
        end;

        // Verify every byte covered without loss or duplication
        AssertTrue(Reconstructed = LineText,
          Format('Line %d token reconstruction mismatch:%sExpected: "%s"%sGot:      "%s"',
            [LineIdx + 1, LineEnding, LineText, LineEnding, Reconstructed]));

        Ranges[LineIdx + 1] := HL.GetRange;
      end;

      WriteLn(Format('PASSED: All %d lines of example.http scanned and reconstructed with 100%% byte fidelity.', [Lines.Count]));

      // Test random line jumping using saved ranges (Rule: Scanning can start from any line)
      for LineIdx := Lines.Count - 1 downto 0 do
      begin
        LineText := Lines[LineIdx];
        HL.SetRange(Ranges[LineIdx]);
        HL.SetLine(LineText, LineIdx);

        Reconstructed := '';
        while not HL.GetEol do
        begin
          Reconstructed := Reconstructed + HL.GetToken;
          HL.Next;
        end;
        AssertTrue(Reconstructed = LineText,
          Format('Reverse pass: Line %d failed reconstruction with saved range', [LineIdx + 1]));
      end;
      WriteLn('PASSED: Random-access scanning with saved ranges verified.');

    finally
      HL.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TestInterpolationDoesNotFold;
var
  HL: TTestHttpSyn;
begin
  WriteLn('--- Testing Variable Interpolation Folding Immunity ---');
  HL := TTestHttpSyn.Create(nil);
  try
    HL.ResetRange;
    HL.SetLine('GET {{baseUrl}}/posts/{{userId}}', 0);

    while not HL.GetEol do
    begin
      if HL.GetTokenKind = Ord(tkVariable) then
      begin
        AssertTrue(Pos('{{', HL.GetToken) > 0, 'tkVariable should contain {{');
      end;
      HL.Next;
    end;

    // Fold level should be 1 for the request block itself, never increased by {{ or }}
    AssertTrue(HL.GetFoldLevel = 1,
      Format('Fold level after GET request should be 1, got %d', [HL.GetFoldLevel]));

    // Inside body with {{var}}
    HL.SetLine('{"userId": {{userId}}}', 1);
    while not HL.GetEol do
      HL.Next;

    // The JSON { and } open and close on the same line, {{userId}} did not touch fold level
    AssertTrue(HL.GetFoldLevel = 1, 'Fold level should remain 1');
    WriteLn('PASSED: {{...}} does not trigger or interfere with fold blocks.');
  finally
    HL.Free;
  end;
end;

procedure TestRequestFolding;
var
  HL: TTestHttpSyn;
begin
  WriteLn('--- Testing Section Separator Folding ---');
  HL := TTestHttpSyn.Create(nil);
  try
    HL.ResetRange;

    // Line 1: ### Request 1
    HL.SetLine('### Request 1', 0);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 1, 'Fold level should be 1 at first ###');

    // Line 2: GET https://api.com
    HL.SetLine('GET https://api.com', 1);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 1, 'Fold level should stay 1 in request');

    // Line 3: ### Request 2
    HL.SetLine('### Request 2', 2);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 1, 'Fold level should close previous request and open new one, staying 1');

    WriteLn('PASSED: ### separator folding tested successfully.');
  finally
    HL.Free;
  end;
end;

procedure TestJsonBodyFolding;
var
  HL: TTestHttpSyn;
begin
  WriteLn('--- Testing Nested JSON Body Folding ---');
  HL := TTestHttpSyn.Create(nil);
  try
    HL.ResetRange;

    // Request start
    HL.SetLine('### Create Post', 0);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 1, 'Level at ### should be 1');

    HL.SetLine('POST https://api.com/posts', 1);
    while not HL.GetEol do HL.Next;

    HL.SetLine('Content-Type: application/json', 2);
    while not HL.GetEol do HL.Next;

    HL.SetLine('', 3); // blank line transitions to body
    while not HL.GetEol do HL.Next;

    // Open brace
    HL.SetLine('{', 4);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 2, 'Level at { inside request should be 2');

    HL.SetLine('  "title": "Hello",', 5);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 2, 'Level inside { should remain 2');

    // Close brace
    HL.SetLine('}', 6);
    while not HL.GetEol do HL.Next;
    AssertTrue(HL.GetFoldLevel = 1, 'Level after } should decrease back to 1');

    WriteLn('PASSED: Nested JSON body folding tested successfully.');
  finally
    HL.Free;
  end;
end;

begin
  WriteLn('========================================');
  WriteLn(' SynHighlighterHttp Automated Test Suite ');
  WriteLn('========================================');
  TestExampleHttp;
  TestInterpolationDoesNotFold;
  TestRequestFolding;
  TestJsonBodyFolding;
  WriteLn('========================================');
  WriteLn(' ALL TESTS PASSED! ');
  WriteLn('========================================');
end.
