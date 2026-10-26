unit MainFormUnit;
(*
  Minimal integration example -- attaching TSynJSONSyn to a TSynEdit.

  Steps
  -----
  1. Add SynHighlighterJSON.pas to your project (Project > Add Files).
  2. Add the unit name to your form unit uses clause.
  3. In FormCreate, construct TSynJSONSyn with the form as owner so Lazarus
     frees it automatically when the form is destroyed.
  4. Assign it to SynEdit1.Highlighter.

  No design-time registration is required for this usage pattern.
*)

{mode objfpc}
{H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  SynEdit,
  SynHighlighterJSON;

type
  TMainForm = class(TForm)
    SynEdit1: TSynEdit;
    procedure FormCreate(Sender: TObject);
  private
    FJSONHighlighter: TSynJSONSyn;
  end;

var
  MainForm: TMainForm;

implementation

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // Create the highlighter owned by the form; it will be freed automatically.
  FJSONHighlighter := TSynJSONSyn.Create(Self);

  // Attach -- one instance can serve multiple TSynEdit controls.
  SynEdit1.Highlighter := FJSONHighlighter;

  // Load sample JSON so highlighting is visible immediately.
  SynEdit1.Text :=
    '{' + LineEnding +
    '  "name": "Alice",' + LineEnding +
    '  "age": 30,' + LineEnding +
    '  "active": true,' + LineEnding +
    '  "score": -1.5e2,' + LineEnding +
    '  "tags": ["json", "lazarus"],' + LineEnding +
    '  "address": null' + LineEnding +
    '}';
end;

end.
