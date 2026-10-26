program ReproduceFreeze;

{$mode objfpc}{$H+}

uses
  Interfaces,
  SysUtils, Classes, Controls, Forms,
  SynEdit, SynEditKeyCmds,
  SynHighlighterHttp;

var
  Form: TForm;
  Editor: TSynEdit;
  HL: TSynHttpSyn;
  i: Integer;
begin
  WriteLn('Initializing test form and SynEdit...');
  Application.Initialize;
  Form := TForm.Create(nil);
  try
    Editor := TSynEdit.Create(Form);
    Editor.Parent := Form;
    HL := TSynHttpSyn.Create(Form);
    Editor.Highlighter := HL;

    WriteLn('Test 1: Setting lines to example.http content...');
    Editor.Lines.LoadFromFile('example.http');
    Application.ProcessMessages;
    WriteLn('Test 1 Passed: example.http loaded.');

    WriteLn('Test 2: Typing "@newVar = {" at line 1...');
    Editor.CaretXY := Point(1, 1);
    Editor.InsertTextAtCaret('@');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('n');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('e');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('w');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('V');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('a');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('r');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret(' ');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret('=');
    Application.ProcessMessages;
    Editor.InsertTextAtCaret(' ');
    Application.ProcessMessages;
    WriteLn('Now pressing "{"...');
    Editor.InsertTextAtCaret('{');
    Application.ProcessMessages;
    WriteLn('Now pressing second "{"...');
    Editor.InsertTextAtCaret('{');
    Application.ProcessMessages;
    WriteLn('Test 2 Passed: "@newVar = {{" handled without freeze.');

    WriteLn('Test 3: In an existing URL, pressing "{" to insert a variable...');
    // Line 5 in example.http: GET {{baseUrl}}/posts
    Editor.CaretXY := Point(5, 5); // after GET
    Editor.InsertTextAtCaret('{');
    Application.ProcessMessages;
    WriteLn('Test 3 Passed: "{" in URL handled without freeze.');

    WriteLn('Test 4: On an empty line, pressing "{"...');
    Editor.Lines.Insert(2, '');
    Editor.CaretXY := Point(1, 3);
    Editor.InsertTextAtCaret('{');
    Application.ProcessMessages;
    WriteLn('Test 4 Passed: "{" on empty line handled without freeze.');

    WriteLn('Test 5: In headers, typing "{"...');
    Editor.CaretXY := Point(10, 8);
    Editor.InsertTextAtCaret('{');
    Application.ProcessMessages;
    WriteLn('Test 5 Passed: "{" in headers handled without freeze.');

    WriteLn('Test 6: Simulating UTF8KeyPress with "{"...');
    Editor.CaretXY := Point(1, 1);
    // Call UTF8KeyPress directly via SendChar or simulating key
    Editor.CommandProcessor(ecChar, '{', nil);
    Application.ProcessMessages;
    WriteLn('Test 6 Passed: ecChar "{" handled without freeze.');

    WriteLn('ALL REPRODUCTION TESTS PASSED!');
  finally
    Form.Free;
  end;
end.
