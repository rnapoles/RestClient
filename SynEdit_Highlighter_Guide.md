# Implementing a SynEdit Syntax Highlighter with Code Folding

**Target:** Lazarus 4.8 / Free Pascal 3.2.2  
**Verified against:** `C:\lazarus\components\synedit\` (installed source)

---

## 1. Overview

A SynEdit highlighter is a `TComponent` that SynEdit calls line-by-line to
classify text into coloured tokens. Adding code folding requires a specialised
base class that also tracks nesting depth. Both concerns share the same
scanning pass.

Key relationships:

- One highlighter instance can be attached to **many** `TSynEdit` controls.
- Each `TSynEdit` keeps its own per-line range data; the highlighter reads and
  writes that data through `GetRange` / `SetRange`.
- The highlighter **must not** store document-specific state in plain fields.
  Use the range mechanism instead.

---

## 2. Choose the right base class

| Need | Base class | Unit |
|------|-----------|------|
| Syntax highlighting only | `TSynCustomHighlighter` | `SynEditHighlighter` |
| Highlighting **and** folding | `TSynCustomFoldHighlighter` | `SynEditHighlighterFoldBase` |

For most real languages, choose `TSynCustomFoldHighlighter` upfront. It
inherits all standard highlighting plumbing.

```pascal
uses
  SynEditHighlighterFoldBase,
  SynEditHighlighter;

type
  TMyHighlighter = class(TSynCustomFoldHighlighter)
  ...
  end;
```

---

## 3. Token kinds and attributes

### 3.1 Define a token enumeration

```pascal
type
  TMyTokenKind = (
    tkNull,       // end-of-line sentinel — never painted
    tkSpace,      // whitespace
    tkKeyword,    // language keywords
    tkString,     // string literals
    tkNumber,     // numeric literals
    tkComment,    // comments
    tkSymbol,     // punctuation / operators
    tkInvalid     // malformed input
  );
```

`tkNull` (ordinal 0) is the EOL sentinel. `GetEol` returns `True` when
`fTokenID = tkNull`.

### 3.2 Create `TSynHighlighterAttributes` objects

Create one per visual category in the constructor and register each with
`AddAttribute`.

```pascal
constructor TMyHighlighter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  fKeywordAttri := TSynHighlighterAttributes.Create('Keyword', 'Keyword');
  fKeywordAttri.Foreground := clNavy;
  fKeywordAttri.Style := [fsBold];
  AddAttribute(fKeywordAttri);

  fStringAttri := TSynHighlighterAttributes.Create('String', 'String');
  fStringAttri.Foreground := clGreen;
  AddAttribute(fStringAttri);

  // ... more attributes ...

  SetAttributesOnChange(@DefHighlightChange);
  fDefaultFilter := 'My files (*.my)|*.my';
end;
```

`AddAttribute` makes the attribute visible in the IDE colour-scheme editor.
`SetAttributesOnChange` triggers editor repaints when colours change.

### 3.3 Expose standard attribute slots (optional)

```pascal
function TMyHighlighter.GetDefaultAttribute(
    Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_KEYWORD   : Result := fKeywordAttri;
    SYN_ATTR_STRING    : Result := fStringAttri;
    SYN_ATTR_WHITESPACE: Result := fSpaceAttri;
    SYN_ATTR_NUMBER    : Result := fNumberAttri;
    else                 Result := nil;
  end;
end;
```

The `SYN_ATTR_*` constants are declared in `SynEditStrConst`.

---

## 4. The tokenisation contract

### 4.1 Invariants (verified in installed source)

1. **First token ready immediately after `SetLine`.**  
   SynEdit does **not** call `Next` before requesting the first token.  
   Solution: call `Next` as the last line of `SetLine`.

2. **`GetEol` returns `True` only when there is no more input.**  
   Use `fTokenID = tkNull`. The `NullProc` that sets `tkNull` must **not**
   advance `Run`.

3. **Tokens reproduce original source text exactly.**  
   `GetToken` returns a slice of `fLine` from `fTokenPos` to `Run`. Every
   byte must belong to exactly one token.

4. **Unknown characters must not cause an infinite loop.**  
   The catch-all branch must advance `Run` by at least one byte.

5. **Tokens are in source order.**  
   Never go backward in `Run`.

### 4.2 Scanner fields

```pascal
private
  fLine     : PChar;    // pointer into current line
  fLineStr  : string;   // keeps memory alive
  fLineLen  : Integer;
  Run       : Integer;  // current position (0-based byte offset)
  fTokenPos : Integer;  // start of current token (0-based)
  fTokenID  : TMyTokenKind;
```

`GetTokenPos` returns `fTokenPos`.  
Source confirmation: `synedithighlighter.pp:414` — comment says "0-based".

---

## 5. Implementing `SetLine`

```pascal
procedure TMyHighlighter.SetLine(const NewValue: String;
    LineNumber: Integer);
begin
  fLineStr := NewValue;           // keep Pascal string alive for PChar
  fLineLen := Length(fLineStr);
  fLine    := PChar(Pointer(fLineStr));
  Run      := 0;
  inherited SetLine(NewValue, LineNumber);  // fold base resets per-line state
  Next;   // <<< position on first token immediately
end;
```

> **Lazarus version note:** In Lazarus 4.x the override is `SetLine`.
> In Lazarus 5.0+ it was renamed `InitForScanningLine`.
> Verify `synedithighlighter.pp:440` in your installed source before coding.

---

## 6. Implementing `Next`

`Next` is the main token dispatcher.

```pascal
procedure TMyHighlighter.Next;
begin
  fTokenPos := Run;

  // Guard: at or past end of line data
  if Run >= fLineLen then
  begin
    fTokenID := tkNull;   // NullProc inline — do NOT advance Run
    Exit;
  end;

  // Resume any multi-line context carried from the previous line
  if fLexerState = lsInBlockComment then
  begin
    ScanBlockCommentBody;
    Exit;
  end;

  case fLine[Run] of
    ' ', #9              : ScanWhitespace;
    '"'                  : ScanString;
    '0'..'9'             : ScanNumber;
    'A'..'Z','a'..'z','_': ScanIdentOrKeyword;
    '{'                  : ScanOpenBrace;
    '}'                  : ScanCloseBrace;
    '/'                  : ScanSlash;
    #0                   : fTokenID := tkNull;   // PChar NUL terminator
    else
      begin
        Inc(Run);           // MUST advance — prevents infinite loop
        fTokenID := tkInvalid;
      end;
  end;
end;
```

### Whitespace helper

```pascal
procedure TMyHighlighter.ScanWhitespace;
begin
  fTokenID := tkSpace;
  while (Run < fLineLen) and (fLine[Run] in [' ', #9]) do
    Inc(Run);
end;
```

### Identifier / keyword helper

```pascal
procedure TMyHighlighter.ScanIdentOrKeyword;
var
  Start: Integer;
  Id   : string;
begin
  Start := Run;
  while (Run < fLineLen) and
        (fLine[Run] in ['A'..'Z','a'..'z','_','0'..'9']) do
    Inc(Run);
  SetString(Id, fLine + Start, Run - Start);
  if IsMyKeyword(Id) then
    fTokenID := tkKeyword
  else
    fTokenID := tkIdent;
end;
```

---

## 7. Mandatory token query methods

```pascal
function TMyHighlighter.GetEol: Boolean;
begin
  Result := fTokenID = tkNull;
end;

function TMyHighlighter.GetToken: String;
begin
  SetString(Result, fLine + fTokenPos, Run - fTokenPos);
end;

procedure TMyHighlighter.GetTokenEx(out TokenStart: PChar;
    out TokenLength: Integer);
begin
  TokenStart  := fLine + fTokenPos;
  TokenLength := Run - fTokenPos;
end;

function TMyHighlighter.GetTokenPos: Integer;
begin
  Result := fTokenPos;   // 0-based
end;

function TMyHighlighter.GetTokenKind: Integer;
begin
  Result := Ord(fTokenID);
end;

function TMyHighlighter.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case fTokenID of
    tkSpace  : Result := fSpaceAttri;
    tkKeyword: Result := fKeyAttri;
    tkString : Result := fStringAttri;
    tkComment: Result := fCommentAttri;
    tkInvalid: Result := fInvalidAttri;
    tkNull   : Result := nil;    // EOL sentinel has no attribute
    else       Result := nil;
  end;
end;
```

---

## 8. Range state — surviving line boundaries

For any construct that can span lines (block comments, multi-line strings,
`#ifdef` regions …) the highlighter must encode its **lexer state** so it
can restart tokenisation on any line from the saved state alone.

### 8.1 State representation

The fold base class provides `CodeFoldRange.RangeType` (type `Pointer`) for
storing per-line data alongside the fold stack. Cast a small integer:

```pascal
type
  TMyLexerState = (lsDefault, lsInBlockComment, lsInMultilineString);
```

### 8.2 `GetRange` — called after a line is fully scanned

```pascal
function TMyHighlighter.GetRange: Pointer;
begin
  // Store custom state, then let the base class return a deduplicated
  // fixed copy from its internal range pool.
  CodeFoldRange.RangeType := Pointer(PtrUInt(Ord(fLexerState)));
  Result := inherited GetRange;
end;
```

Source: `synedithighlighterfoldbase.pas:1739-1744` — `inherited GetRange`
calls `fRanges.GetEqual(FCodeFoldRange)` which returns a shared, immutable
snapshot stored in an AVL tree.

### 8.3 `SetRange` — called before scanning the next line

```pascal
procedure TMyHighlighter.SetRange(Value: Pointer);
begin
  inherited SetRange(Value);    // restores fold stack from snapshot
  fLexerState := TMyLexerState(PtrUInt(CodeFoldRange.RangeType));
end;
```

### 8.4 `ResetRange` — called before line 0

```pascal
procedure TMyHighlighter.ResetRange;
begin
  inherited ResetRange;
  fLexerState := lsDefault;
end;
```

### 8.5 Branching on persisted state in `Next`

```pascal
procedure TMyHighlighter.Next;
begin
  fTokenPos := Run;
  if Run >= fLineLen then begin fTokenID := tkNull; Exit; end;

  case fLexerState of
    lsInBlockComment   : begin ScanBlockCommentBody; Exit; end;
    lsInMultilineString: begin ScanMultilineStringBody; Exit; end;
  end;

  // Normal dispatch on fLine[Run] ...
end;
```

Inside `ScanBlockCommentBody`, set `fLexerState := lsDefault` when the
closing delimiter is found; leave it set to carry to the next line.

---

## 9. Code folding

### 9.1 Block type identifiers

Use nonzero pointer-sized integers. Different values prevent wrong-type
closers from accidentally closing the wrong block:

```pascal
const
  MY_BLOCK_PROC  = Pointer(PtrUInt(1));
  MY_BLOCK_BEGIN = Pointer(PtrUInt(2));
  MY_BLOCK_IF    = Pointer(PtrUInt(3));
```

### 9.2 Opening a fold

Call `StartCodeFoldBlock` immediately after consuming the opening delimiter.

```pascal
// After consuming 'begin':
fTokenID := tkKeyword;
StartCodeFoldBlock(MY_BLOCK_BEGIN);   // IncreaseLevel defaults to True
```

Verified signature (`synedithighlighterfoldbase.pas:435`):

```pascal
function StartCodeFoldBlock(
  ABlockType: Pointer;
  IncreaseLevel: Boolean = True
): TSynCustomCodeFoldBlock;
```

Use `IncreaseLevel := False` for internal tracking blocks that should
not themselves be user-collapsible.

### 9.3 Closing a fold

```pascal
// After consuming 'end':
if TopCodeFoldBlockType = MY_BLOCK_BEGIN then
  EndCodeFoldBlock;   // DecreaseLevel defaults to True
fTokenID := tkKeyword;
```

Verified signature (`synedithighlighterfoldbase.pas:437`):

```pascal
procedure EndCodeFoldBlock(DecreaseLevel: Boolean = True);
```

> **Critical:** `DecreaseLevel` must match the `IncreaseLevel` used when
> the block was opened. Mismatching these corrupts fold level tracking.

### 9.4 Inspecting the innermost open block

```pascal
function TopCodeFoldBlockType(DownIndex: Integer = 0): Pointer;
```

`DownIndex = 0` is the innermost block. Use this to validate that the closing
delimiter matches the expected opener:

```pascal
if TopCodeFoldBlockType = MY_BLOCK_BEGIN then
  EndCodeFoldBlock
else if TopCodeFoldBlockType <> nil then
begin
  // Mismatched closer — close anyway to prevent unbounded growth
  EndCodeFoldBlock;
  fTokenID := tkInvalid;   // make the error visible
  Inc(Run);
  Exit;
end;
```

### 9.5 Delimiters inside strings and comments

**Only call `StartCodeFoldBlock` / `EndCodeFoldBlock` from the `Next`
dispatch, never from inside a string or comment scanner.**

A string scanner that returns without fold calls is sufficient:

```pascal
procedure TMyHighlighter.ScanString;
begin
  fTokenID := tkString;
  Inc(Run);   // opening quote
  while Run < fLineLen do
  begin
    case fLine[Run] of
      '"': begin Inc(Run); Exit; end;   // closing — no fold call
      '\': Inc(Run);                    // skip escape char
    end;
    Inc(Run);
  end;
  fLexerState := lsDefault;   // unterminated: reset for next line
end;
```

### 9.6 Same-line open-and-close

The fold base class tracks the **minimum** fold level encountered on a line.
A fold that opens and closes on the same line never reduces the minimum below
the start level, so the framework automatically treats it as non-collapsible.
No special-casing is needed.

### 9.7 Nested folds

Fold blocks must be **strictly nested** — LIFO order. Overlapping folds
(e.g. an `#ifdef` that crosses a `begin`/`end` boundary) cannot both be
represented as foldable blocks simultaneously. If this arises, choose which
structure takes fold priority.

---

## 10. Custom range class (for complex languages)

If one `Pointer` worth of `RangeType` is not enough, subclass
`TSynCustomHighlighterRange`:

```pascal
type
  TMyRange = class(TSynCustomHighlighterRange)
  public
    BracketDepth: Integer;
    LexerState  : TMyLexerState;
    procedure Clear; override;
    function Compare(Range: TSynCustomHighlighterRange): Integer; override;
    procedure Assign(Src: TSynCustomHighlighterRange); override;
  end;
```

Override `GetRangeClass` to return it:

```pascal
function TMyHighlighter.GetRangeClass: TSynCustomHighlighterRangeClass;
begin
  Result := TMyRange;
end;
```

Access it via a typed cast helper:

```pascal
function TMyHighlighter.MyRange: TMyRange;
begin
  Result := TMyRange(CodeFoldRange);
end;
```

In `GetRange`:
```pascal
function TMyHighlighter.GetRange: Pointer;
begin
  MyRange.LexerState   := fLexerState;
  MyRange.BracketDepth := fBracketDepth;
  Result := inherited GetRange;
end;
```

In `SetRange`:
```pascal
procedure TMyHighlighter.SetRange(Value: Pointer);
begin
  inherited SetRange(Value);
  fLexerState   := MyRange.LexerState;
  fBracketDepth := MyRange.BracketDepth;
end;
```

> **Lazarus 4.x / 4.99+ compatibility:**  
> Lazarus 4.x uses an AVL tree with a `Compare` method for range
> deduplication. Lazarus 4.99+ switches to a `TDictionary` requiring
> `GetHashCode` and equality comparison. If your custom range class must
> target both, implement both sets of methods.

---

## 11. Integration — attaching to TSynEdit

```pascal
uses SynEdit, MyHighlighter;

procedure TForm1.FormCreate(Sender: TObject);
begin
  // Pass the form as owner — freed automatically on form destroy.
  SynEdit1.Highlighter := TMyHighlighter.Create(Self);
end;
```

One instance can serve multiple editors safely:

```pascal
var HL: TMyHighlighter;
begin
  HL := TMyHighlighter.Create(Self);
  SynEdit1.Highlighter := HL;
  SynEdit2.Highlighter := HL;
end;
```

---

## 12. Optional design-time registration

To appear in the IDE component palette, add a registration unit to a
design-time `.lpk` package. The highlighter unit needs no changes:

```pascal
unit MyHighlighterReg;
{$mode objfpc}{$H+}
interface
uses Classes, MyHighlighter;
procedure Register;
implementation
procedure Register;
begin
  RegisterComponents('SynEdit', [TMyHighlighter]);
end;
end.
```

---

## 13. Common mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Not calling `Next` at end of `SetLine` | First token invisible or wrong | Add `Next` as last line of `SetLine` |
| Advancing `Run` in NullProc | Scanner never signals EOL; infinite loop | Set `fTokenID := tkNull` only — never `Inc(Run)` |
| Mutable lexer state in a plain field | Second editor shows wrong colours | Store via `GetRange` / `SetRange` / `CodeFoldRange.RangeType` |
| `DecreaseLevel` mismatching `IncreaseLevel` | Fold nesting level corrupted | They must always match for the same block |
| Fold calls inside string scanner | Braces in strings open/close folds | Call `StartCodeFoldBlock` / `EndCodeFoldBlock` only from `Next` |
| No catch-all `Inc(Run)` | Unknown char causes infinite loop | Always advance `Run` at least once in the `else` branch |
| `GetTokenPos` returning 1-based index | All token positions off by one | Return raw `fTokenPos` (confirmed 0-based in source) |
| Overlapping folds | Fold gutter shows garbage | Ensure LIFO nesting; choose one structure if blocks truly overlap |

---

## 14. Verified API reference (Lazarus 4.8)

All entries read directly from `C:\lazarus\components\synedit\`.

| Method / property | Source file : line | Notes |
|-------------------|--------------------|-------|
| `procedure SetLine(const NewValue: String; LineNumber: Integer)` | `synedithighlighter.pp:440` | Still `SetLine` in 4.8; renamed in 5.0 |
| `function GetEol: Boolean` | `synhighlightercpp.pp:1471` | Returns `fTokenID = tkNull` |
| `function GetTokenPos: Integer` | `synedithighlighter.pp:414` | Comment: "0-based" |
| `function GetRange: Pointer` | `synedithighlighterfoldbase.pas:1739` | Calls `fRanges.GetEqual(FCodeFoldRange)` |
| `procedure SetRange(Value: Pointer)` | `synedithighlighterfoldbase.pas:1880` | Calls `FCodeFoldRange.Assign(...)` |
| `procedure ResetRange` | `synedithighlighterfoldbase.pas:1868` | Clears `FCodeFoldRange` |
| `function StartCodeFoldBlock(ABlockType: Pointer; IncreaseLevel: Boolean = True)` | `synedithighlighterfoldbase.pas:435` | Returns `TSynCustomCodeFoldBlock` |
| `procedure EndCodeFoldBlock(DecreaseLevel: Boolean = True)` | `synedithighlighterfoldbase.pas:437` | |
| `function TopCodeFoldBlockType(DownIndex: Integer = 0): Pointer` | `synedithighlighterfoldbase.pas:430` | 0 = innermost |
| `CodeFoldRange: TSynCustomHighlighterRange` | `synedithighlighterfoldbase.pas:429` | Working fold range |
| `CodeFoldRange.RangeType: Pointer` | `synedithighlighterfoldbase.pas` | Custom lexer state slot |

---

## 15. Test checklist

- [ ] First token ready after `SetLine` — no extra `Next` call needed
- [ ] Empty line: `GetEol` is `True` immediately
- [ ] Tokens reproduce source text; `GetToken` == source slice
- [ ] Every byte on every line covered by exactly one token
- [ ] Whitespace (spaces, tabs) appears as its own token
- [ ] Brackets inside strings do not change fold level
- [ ] Multi-line construct survives line boundaries via saved range
- [ ] Scanning can start from any line using only its saved range
- [ ] Adding or removing an opener near the top updates fold levels downstream
- [ ] Mismatched closers do not crash; error token is visible
- [ ] Unknown characters advance the scanner and produce `tkInvalid`
- [ ] `IncreaseLevel` and `DecreaseLevel` always match for each block type
- [ ] Same-line open+close is not presented as a collapsible fold
- [ ] One highlighter instance works correctly when shared by two editors
