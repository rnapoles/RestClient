unit SynHighlighterJSON;
{
  SynHighlighterJSON.pas
  ----------------------
  JSON syntax highlighter for Lazarus 4.8 / Free Pascal SynEdit.

  Verified API details (from C:\lazarus\components\synedit\ , Lazarus 4.8)
  -------------------------------------------------------------------------
  * Base class  : TSynCustomFoldHighlighter (SynEditHighlighterFoldBase)
  * SetLine     : method name confirmed (NOT InitForScanningLine, which is 5.0+)
  * Token ready : SetLine calls Next so the first token is immediately available
                  (same pattern as TSynCppSyn)
  * GetEol      : returns fTokenID = tkNull; NullProc sets tkNull without
                  incrementing Run, matching TSynCppSyn behaviour
  * Range       : custom lexer state stored in CodeFoldRange.RangeType as a
                  Pointer-cast integer; inherited GetRange returns deduplicated
                  fixed copy from fRanges (TSynCustomHighlighterRanges AVL tree)
  * Folding     : StartCodeFoldBlock / EndCodeFoldBlock from
                  TSynCustomFoldHighlighter; DecreaseLevel must match
                  IncreaseLevel (both True for normal foldable blocks)
  * GetTokenPos : 0-based byte offset into the line (confirmed in source)

  Token categories
  ----------------
  tkNull        EOL sentinel (not painted)
  tkSpace       JSON whitespace: space, tab (LF/CR stripped by editor)
  tkPunctuation curly-braces, square-brackets, colon, comma
  tkString      "..." value strings
  tkPropName    "..." immediately followed (optionally with whitespace) by ':'
  tkNumber      JSON numbers
  tkBoolean     true or false  (case-sensitive; True/FALSE -> tkInvalid)
  tkNullLit     null literal  (case-sensitive)
  tkInvalid     malformed or unsupported input (comments, bad escapes, etc.)

  Code folding
  ------------
  Curly-brace-open  opens an object fold (block-type JSON_BLOCK_OBJECT)
  Curly-brace-close closes an object fold; mismatched closer is tkInvalid
  Square-bracket-open  opens an array fold (block-type JSON_BLOCK_ARRAY)
  Square-bracket-close closes an array fold; mismatched closer is tkInvalid
  Delimiters inside strings never trigger folding.
  Same-line open+close is not collapsible (base class minimum-level
  bookkeeping handles this automatically).

  Limitations / unverified assumptions (documented honestly)
  ----------------------------------------------------------
  * Property-name look-ahead searches the rest of the current line only.
    A "key" on one line with ":" on the next is classified tkString.
  * Unterminated strings (reaching EOL) are wholly tkInvalid; the
    lsInString state is carried so folding is not confused, but the next
    line always starts fresh (JSON strings cannot legally span lines).
  * '/* */' block comments are tokenised as two separate tkInvalid tokens
    (one per line); we do not track multi-line comment state because JSON
    has no comments and it is always an error.
  * No design-time registration is included; add Register() if you want
    the IDE component palette entry.
}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Graphics,
  SynEditHighlighterFoldBase,
  SynEditHighlighter,
  SynEditStrConst;

const
  // Fold block-type identifiers – nonzero Pointer-sized integer constants
  JSON_BLOCK_OBJECT = Pointer(PtrUInt(1));
  JSON_BLOCK_ARRAY  = Pointer(PtrUInt(2));

type

  // -----------------------------------------------------------------------
  // Token kind
  // -----------------------------------------------------------------------
  TJSONTokenKind = (
    tkNull,        // EOL sentinel
    tkSpace,       // whitespace
    tkPunctuation, // { } [ ] : ,
    tkString,      // string value
    tkPropName,    // property name (string before ':')
    tkNumber,      // numeric literal
    tkBoolean,     // true | false
    tkNullLit,     // null literal
    tkInvalid      // malformed / unrecognised
  );

  // -----------------------------------------------------------------------
  // Per-line lexer state stored in CodeFoldRange.RangeType
  // -----------------------------------------------------------------------
  TJSONLexerState = (
    lsDefault,   // normal scanning
    lsInString   // inside an unterminated string at EOL (error state)
  );

  // -----------------------------------------------------------------------
  // Main highlighter
  // -----------------------------------------------------------------------
  TSynJSONSyn = class(TSynCustomFoldHighlighter)
  private
    // Scanner working variables (reset for each line)
    fLine      : PChar;
    fLineStr   : string;      // keeps the Pascal string alive for fLine
    fLineLen   : Integer;
    fLineNumber: Integer;
    Run        : Integer;     // current byte position, 0-based
    fTokenPos  : Integer;     // start of current token, 0-based
    fTokenID   : TJSONTokenKind;

    // Per-line lexer state (persisted through GetRange / SetRange)
    fLexerState: TJSONLexerState;

    // Highlight attributes
    fSpaceAttri    : TSynHighlighterAttributes;
    fPunctAttri    : TSynHighlighterAttributes;
    fStringAttri   : TSynHighlighterAttributes;
    fPropNameAttri : TSynHighlighterAttributes;
    fNumberAttri   : TSynHighlighterAttributes;
    fBooleanAttri  : TSynHighlighterAttributes;
    fNullLitAttri  : TSynHighlighterAttributes;
    fInvalidAttri  : TSynHighlighterAttributes;

    // Scan helpers
    procedure NullProc;
    procedure ScanSpace;
    procedure ScanString;
    procedure ScanNumber;
    procedure ScanIdentOrKeyword;
    procedure ScanInvalid;
    function  LookAheadColon: Boolean;

  protected
    function GetRangeClass: TSynCustomHighlighterRangeClass; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    class function GetLanguageName: string; override;
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes; override;

    // Tokenisation contract
    procedure SetLine(const NewValue: String; LineNumber: Integer); override;
    procedure Next; override;
    function  GetEol: Boolean; override;
    function  GetToken: String; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: Integer); override;
    function  GetTokenPos: Integer; override;
    function  GetTokenKind: Integer; override;
    function  GetTokenAttribute: TSynHighlighterAttributes; override;

    // Range persistence
    function  GetRange: Pointer; override;
    procedure SetRange(Value: Pointer); override;
    procedure ResetRange; override;

    // Attribute access
    property SpaceAttri    : TSynHighlighterAttributes read fSpaceAttri;
    property PunctAttri    : TSynHighlighterAttributes read fPunctAttri;
    property StringAttri   : TSynHighlighterAttributes read fStringAttri;
    property PropNameAttri : TSynHighlighterAttributes read fPropNameAttri;
    property NumberAttri   : TSynHighlighterAttributes read fNumberAttri;
    property BooleanAttri  : TSynHighlighterAttributes read fBooleanAttri;
    property NullLitAttri  : TSynHighlighterAttributes read fNullLitAttri;
    property InvalidAttri  : TSynHighlighterAttributes read fInvalidAttri;
  end;

implementation

{ ===========================================================================
  Inline helpers
  =========================================================================== }

function IsJSONWS(C: Char): Boolean; inline;
begin
  Result := C in [' ', #9, #10, #13];
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9'];
end;

function IsHexDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9', 'A'..'F', 'a'..'f'];
end;

{ ===========================================================================
  Constructor / Destructor
  =========================================================================== }

constructor TSynJSONSyn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  fSpaceAttri := TSynHighlighterAttributes.Create('Whitespace', 'Whitespace');
  fSpaceAttri.Foreground := clNone;
  fSpaceAttri.Background := clNone;
  AddAttribute(fSpaceAttri);

  fPunctAttri := TSynHighlighterAttributes.Create('Punctuation', 'Punctuation');
  fPunctAttri.Foreground := TColor($00A0A0A0);  // mid-grey
  AddAttribute(fPunctAttri);

  fStringAttri := TSynHighlighterAttributes.Create('String', 'String');
  fStringAttri.Foreground := TColor($00007800);  // dark green
  AddAttribute(fStringAttri);

  fPropNameAttri := TSynHighlighterAttributes.Create('Property name', 'Property name');
  fPropNameAttri.Foreground := TColor($00007ABF);  // teal / gold
  AddAttribute(fPropNameAttri);

  fNumberAttri := TSynHighlighterAttributes.Create('Number', 'Number');
  fNumberAttri.Foreground := TColor($00A05000);  // burnt orange
  AddAttribute(fNumberAttri);

  fBooleanAttri := TSynHighlighterAttributes.Create('Boolean', 'Boolean');
  fBooleanAttri.Foreground := clMaroon;
  fBooleanAttri.Style := [fsBold];
  AddAttribute(fBooleanAttri);

  fNullLitAttri := TSynHighlighterAttributes.Create('Null', 'Null');
  fNullLitAttri.Foreground := clGray;
  fNullLitAttri.Style := [fsBold];
  AddAttribute(fNullLitAttri);

  fInvalidAttri := TSynHighlighterAttributes.Create('Invalid', 'Invalid');
  fInvalidAttri.Foreground := clRed;
  fInvalidAttri.Style := [fsUnderline];
  AddAttribute(fInvalidAttri);

  SetAttributesOnChange(@DefHighlightChange);

  fLexerState  := lsDefault;
  fDefaultFilter := 'JSON files (*.json)|*.json';
end;

destructor TSynJSONSyn.Destroy;
begin
  inherited Destroy;
end;

{ ===========================================================================
  Class / meta
  =========================================================================== }

class function TSynJSONSyn.GetLanguageName: string;
begin
  Result := 'JSON';
end;

function TSynJSONSyn.GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_STRING    : Result := fStringAttri;
    SYN_ATTR_NUMBER    : Result := fNumberAttri;
    SYN_ATTR_WHITESPACE: Result := fSpaceAttri;
    SYN_ATTR_SYMBOL    : Result := fPunctAttri;
    else                 Result := nil;
  end;
end;

function TSynJSONSyn.GetRangeClass: TSynCustomHighlighterRangeClass;
begin
  // Use the stock fold range; our lexer state fits in RangeType (one integer).
  Result := TSynCustomHighlighterRange;
end;

{ ===========================================================================
  Range persistence
  =========================================================================== }

function TSynJSONSyn.GetRange: Pointer;
begin
  CodeFoldRange.RangeType := Pointer(PtrUInt(Ord(fLexerState)));
  Result := inherited GetRange;
end;

procedure TSynJSONSyn.SetRange(Value: Pointer);
begin
  inherited SetRange(Value);                             // restores fold stack
  fLexerState := TJSONLexerState(PtrUInt(CodeFoldRange.RangeType));
end;

procedure TSynJSONSyn.ResetRange;
begin
  inherited ResetRange;
  fLexerState := lsDefault;
end;

{ ===========================================================================
  SetLine
  =========================================================================== }

procedure TSynJSONSyn.SetLine(const NewValue: String; LineNumber: Integer);
begin
  fLineStr    := NewValue;
  fLineLen    := Length(fLineStr);
  fLine       := PChar(Pointer(fLineStr));
  Run         := 0;
  fLineNumber := LineNumber;
  inherited SetLine(NewValue, LineNumber);
  // lsInString from a previous line means the line started inside a broken
  // string; reset to default for the new line (JSON strings cannot span lines).
  if fLexerState = lsInString then
    fLexerState := lsDefault;
  Next;  // position on the first token immediately
end;

{ ===========================================================================
  Scan helpers
  =========================================================================== }

procedure TSynJSONSyn.NullProc;
begin
  fTokenID := tkNull;
  // Run is NOT advanced – NUL at fLine[Run] is the EOL guard.
end;

procedure TSynJSONSyn.ScanSpace;
begin
  fTokenID := tkSpace;
  while (Run < fLineLen) and IsJSONWS(fLine[Run]) do
    Inc(Run);
end;

procedure TSynJSONSyn.ScanInvalid;
begin
  fTokenID := tkInvalid;
  Inc(Run);   // consume exactly one byte so the scanner always advances
end;

function TSynJSONSyn.LookAheadColon: Boolean;
var
  i: Integer;
begin
  i := Run;
  while (i < fLineLen) and IsJSONWS(fLine[i]) do Inc(i);
  Result := (i < fLineLen) and (fLine[i] = ':');
end;

{ ---------------------------------------------------------------------------
  ScanString
  Starts with fLine[Run] = '"' (already verified by caller).
  Sets fTokenID to tkPropName, tkString, or tkInvalid.
  --------------------------------------------------------------------------- }
procedure TSynJSONSyn.ScanString;
var
  HexCount: Integer;
  Closed  : Boolean;
begin
  Closed := False;
  Inc(Run);  // opening '"'

  while Run < fLineLen do
  begin
    case fLine[Run] of

      '"':
        begin
          Inc(Run);   // closing '"'
          Closed := True;
          Break;
        end;

      '\':
        begin
          Inc(Run);   // consume backslash
          if Run >= fLineLen then
          begin
            fTokenID := tkInvalid;
            fLexerState := lsDefault;
            Exit;
          end;
          case fLine[Run] of
            '"', '\', '/', 'b', 'f', 'n', 'r', 't':
              Inc(Run);
            'u':
              begin
                Inc(Run);   // 'u'
                HexCount := 0;
                while (Run < fLineLen) and (HexCount < 4) and IsHexDigit(fLine[Run]) do
                begin
                  Inc(Run);
                  Inc(HexCount);
                end;
                if HexCount < 4 then
                begin
                  fTokenID := tkInvalid;
                  fLexerState := lsDefault;
                  Exit;
                end;
              end;
            else
              begin
                Inc(Run);   // consume the invalid char after backslash
                fTokenID := tkInvalid;
                fLexerState := lsDefault;
                Exit;
              end;
          end;
        end;

      #0..#31:
        begin
          // Raw control character – illegal inside JSON string
          Inc(Run);
          fTokenID := tkInvalid;
          fLexerState := lsDefault;
          Exit;
        end;

      else
        Inc(Run);
    end;
  end;

  if not Closed then
  begin
    fTokenID := tkInvalid;
    fLexerState := lsInString;
    Exit;
  end;

  fLexerState := lsDefault;
  if LookAheadColon then
    fTokenID := tkPropName
  else
    fTokenID := tkString;
end;

{ ---------------------------------------------------------------------------
  ScanNumber
  JSON number grammar (ECMA-404):
    minus? integer fraction? exponent?
    integer  = '0' | [1-9][0-9]*
    fraction = '.' [0-9]+
    exponent = [eE][+-]? [0-9]+
  --------------------------------------------------------------------------- }
procedure TSynJSONSyn.ScanNumber;
var
  HasError: Boolean;
begin
  HasError := False;

  // Optional minus
  if (Run < fLineLen) and (fLine[Run] = '-') then
    Inc(Run);

  // Integer part
  if Run >= fLineLen then
  begin
    fTokenID := tkInvalid;
    Exit;
  end;

  if fLine[Run] = '0' then
  begin
    Inc(Run);
    if (Run < fLineLen) and IsDigit(fLine[Run]) then
      HasError := True;   // leading zero: 012 is invalid
  end
  else if IsDigit(fLine[Run]) then
  begin
    while (Run < fLineLen) and IsDigit(fLine[Run]) do Inc(Run);
  end
  else
  begin
    // '-' without a following digit
    fTokenID := tkInvalid;
    Exit;
  end;

  // Optional fraction
  if (Run < fLineLen) and (fLine[Run] = '.') then
  begin
    Inc(Run);
    if (Run >= fLineLen) or not IsDigit(fLine[Run]) then
      HasError := True  // "1." is invalid
    else
      while (Run < fLineLen) and IsDigit(fLine[Run]) do Inc(Run);
  end;

  // Optional exponent
  if (Run < fLineLen) and (fLine[Run] in ['e', 'E']) then
  begin
    Inc(Run);
    if (Run < fLineLen) and (fLine[Run] in ['+', '-']) then
      Inc(Run);
    if (Run >= fLineLen) or not IsDigit(fLine[Run]) then
      HasError := True  // "1e" is invalid
    else
      while (Run < fLineLen) and IsDigit(fLine[Run]) do Inc(Run);
  end;

  if HasError then
    fTokenID := tkInvalid
  else
    fTokenID := tkNumber;
end;

{ ---------------------------------------------------------------------------
  ScanIdentOrKeyword
  Only exact lowercase "true", "false", "null" are valid JSON literals.
  --------------------------------------------------------------------------- }
procedure TSynJSONSyn.ScanIdentOrKeyword;
var
  Start: Integer;
  Id   : string;
begin
  Start := Run;
  while (Run < fLineLen) and (fLine[Run] in ['A'..'Z','a'..'z','_','0'..'9']) do
    Inc(Run);
  SetString(Id, fLine + Start, Run - Start);
  if Id = 'true' then
    fTokenID := tkBoolean
  else if Id = 'false' then
    fTokenID := tkBoolean
  else if Id = 'null' then
    fTokenID := tkNullLit
  else
    fTokenID := tkInvalid;
end;

{ ===========================================================================
  Next – the main tokeniser dispatch
  =========================================================================== }

procedure TSynJSONSyn.Next;
begin
  fTokenPos := Run;

  if Run >= fLineLen then
  begin
    NullProc;
    Exit;
  end;

  case fLine[Run] of

    // -- Whitespace --------------------------------------------------------
    ' ', #9, #10, #13: ScanSpace;

    // -- String ------------------------------------------------------------
    '"': ScanString;

    // -- Number (digit) ----------------------------------------------------
    '0'..'9': ScanNumber;

    // -- Minus: start of number or lone invalid '-' ------------------------
    '-':
      if (Run + 1 < fLineLen) and IsDigit(fLine[Run + 1]) then
        ScanNumber
      else
      begin
        Inc(Run);
        fTokenID := tkInvalid;
      end;

    // -- Object open -------------------------------------------------------
    '{':
      begin
        fTokenID := tkPunctuation;
        Inc(Run);
        StartCodeFoldBlock(JSON_BLOCK_OBJECT);
      end;

    // -- Object close ------------------------------------------------------
    '}':
      begin
        if TopCodeFoldBlockType = JSON_BLOCK_OBJECT then
          EndCodeFoldBlock
        else if TopCodeFoldBlockType <> nil then
        begin
          // Mismatched closer – close the wrong block and mark invalid
          EndCodeFoldBlock;
          fTokenID := tkInvalid;
          Inc(Run);
          Exit;
        end;
        // No open block: extra '}' in partial / malformed JSON
        fTokenID := tkPunctuation;
        Inc(Run);
      end;

    // -- Array open --------------------------------------------------------
    '[':
      begin
        fTokenID := tkPunctuation;
        Inc(Run);
        StartCodeFoldBlock(JSON_BLOCK_ARRAY);
      end;

    // -- Array close -------------------------------------------------------
    ']':
      begin
        if TopCodeFoldBlockType = JSON_BLOCK_ARRAY then
          EndCodeFoldBlock
        else if TopCodeFoldBlockType <> nil then
        begin
          EndCodeFoldBlock;
          fTokenID := tkInvalid;
          Inc(Run);
          Exit;
        end;
        fTokenID := tkPunctuation;
        Inc(Run);
      end;

    // -- Colon and comma ---------------------------------------------------
    ':', ',':
      begin
        fTokenID := tkPunctuation;
        Inc(Run);
      end;

    // -- Comments: not valid JSON, mark as invalid -------------------------
    '/':
      begin
        Inc(Run);
        if (Run < fLineLen) and (fLine[Run] = '/') then
        begin
          // "//" line comment – consume to EOL
          while Run < fLineLen do Inc(Run);
        end
        else if (Run < fLineLen) and (fLine[Run] = '*') then
        begin
          // "/*" – consume the '*' and leave rest for ScanInvalid next call
          Inc(Run);
        end;
        fTokenID := tkInvalid;
      end;

    // -- Keywords and unknown identifier-like tokens -----------------------
    'A'..'Z', 'a'..'z', '_': ScanIdentOrKeyword;

    // -- NUL (end-of-line guard) -------------------------------------------
    #0: NullProc;

    // -- Everything else ---------------------------------------------------
    else ScanInvalid;

  end; // case
end;

{ ===========================================================================
  Token query methods
  =========================================================================== }

function TSynJSONSyn.GetEol: Boolean;
begin
  Result := fTokenID = tkNull;
end;

function TSynJSONSyn.GetToken: String;
begin
  SetString(Result, fLine + fTokenPos, Run - fTokenPos);
end;

procedure TSynJSONSyn.GetTokenEx(out TokenStart: PChar; out TokenLength: Integer);
begin
  TokenStart  := fLine + fTokenPos;
  TokenLength := Run - fTokenPos;
end;

function TSynJSONSyn.GetTokenPos: Integer;
begin
  Result := fTokenPos;
end;

function TSynJSONSyn.GetTokenKind: Integer;
begin
  Result := Ord(fTokenID);
end;

function TSynJSONSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case fTokenID of
    tkSpace      : Result := fSpaceAttri;
    tkPunctuation: Result := fPunctAttri;
    tkString     : Result := fStringAttri;
    tkPropName   : Result := fPropNameAttri;
    tkNumber     : Result := fNumberAttri;
    tkBoolean    : Result := fBooleanAttri;
    tkNullLit    : Result := fNullLitAttri;
    tkInvalid    : Result := fInvalidAttri;
    tkNull       : Result := nil;
    else           Result := nil;
  end;
end;

end.
