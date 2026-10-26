unit SynHighlighterHttp;
(*
  SynHighlighterHttp.pas
  ----------------------
  Syntax highlighter with code folding for .http / .rest files, designed for
  Lazarus 4.8 / Free Pascal 3.2.2 SynEdit.

  Features:
  - Base class: TSynCustomFoldHighlighter (SynEditHighlighterFoldBase)
  - Full code folding for:
    * Request sections starting with '###' (HTTP_BLOCK_REQUEST)
    * Standalone requests without '###'
    * JSON / body objects '{ ... }' (HTTP_BLOCK_BRACE)
    * JSON / body arrays '[ ... ]' (HTTP_BLOCK_BRACKET)
  - Syntax highlighting categories:
    * HTTP request verbs (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, etc.)
    * URLs, paths, and query string parameters (?key=val, &key=val)
    * HTTP protocol version (HTTP/1.1, HTTP/2, HTTP/3)
    * Request and response headers (Header-Name: Value)
    * Variable declarations (@name = value)
    * Variable interpolations ({{name}}, {{$guid}}, {{req.response.body.$.id}})
    * Metadata directives (# @name, // @name, # @title, etc.)
    * Request separators (### [title])
    * Comments (# ... and // ...)
    * JSON payloads in request bodies:
      - Property names ("key":)
      - String values ("value")
      - Numbers (123, -4.56e7)
      - Booleans (true, false)
      - Null literal (null)
      - Braces and symbols ({, }, [, ], :, ,)
    * File body references (< ./path/file.json)
    * Pre/post request scripts (< {% ... %}, > {% ... %})
  - Robust line-by-line range state persistence (lsRoot, lsHeaders, lsBody)
  - Zero interference between variable interpolation '{{...}}' and code folding
*)

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Graphics,
  SynEditHighlighterFoldBase,
  SynEditHighlighter;

const
  // Fold block-type identifiers (nonzero Pointer-sized integer constants)
  HTTP_BLOCK_REQUEST = Pointer(PtrUInt(1));
  HTTP_BLOCK_BRACE   = Pointer(PtrUInt(2));
  HTTP_BLOCK_BRACKET = Pointer(PtrUInt(3));

type
  // -----------------------------------------------------------------------
  // Visual token classification
  // -----------------------------------------------------------------------
  THttpTokenKind = (
    tkNull,          // EOL sentinel (never painted)
    tkSpace,         // Whitespace (spaces, tabs)
    tkComment,       // Comments: # text or // text
    tkDirective,     // Directives / metadata: # @name ..., # @title ...
    tkSeparator,     // Request separator: ### [title]
    tkHttpMethod,    // HTTP Verbs: GET, POST, PUT, DELETE, etc.
    tkUrl,           // URL and path components
    tkQueryParam,    // Query parameters: ?param=val or &param=val
    tkHttpVersion,   // HTTP/1.1, HTTP/2, etc.
    tkHeaderName,    // Header name: Content-Type, Accept, etc.
    tkHeaderValue,   // Header value
    tkVariable,      // Variable declaration (@var) or interpolation ({{var}})
    tkPropName,      // JSON property name ("name":) in body
    tkString,        // String literal ("..." or '...')
    tkNumber,        // Numeric literal (123, -45.67)
    tkBoolean,       // true, false
    tkNullLit,       // null
    tkSymbol,        // Punctuation and symbols (:, =, ?, &, <, >, etc.)
    tkBrace,         // Braces { } [ ]
    tkBodyText,      // Raw or text body content
    tkFileRef,       // File reference path (< ./file.json)
    tkInvalid        // Malformed or unrecognized token
  );

  // -----------------------------------------------------------------------
  // Line-level lexer state persisted across lines in CodeFoldRange.RangeType
  // -----------------------------------------------------------------------
  THttpLexerState = (
    lsRoot,          // Top-level or section start (variables, comments, separator, request line)
    lsHeaders,       // In request headers (after request line, before blank line)
    lsBody           // In request body (after empty line following headers)
  );

  // -----------------------------------------------------------------------
  // Current line classification mode
  // -----------------------------------------------------------------------
  TLineMode = (
    lmBlank,
    lmSeparator,
    lmDirective,
    lmComment,
    lmVariableDecl,
    lmRequestLine,
    lmQueryContinuation,
    lmHeader,
    lmFileRef,
    lmBody
  );

  // -----------------------------------------------------------------------
  // TSynHttpSyn Highlighter
  // -----------------------------------------------------------------------
  TSynHttpSyn = class(TSynCustomFoldHighlighter)
  private
    // Scanner working variables (reset per line)
    fLine       : PChar;
    fLineStr    : string;
    fLineLen    : Integer;
    fLineNumber : Integer;
    Run         : Integer;
    fTokenPos   : Integer;
    fTokenID    : THttpTokenKind;

    // Line classification and persistence state
    fLexerState : THttpLexerState;
    fLineMode   : TLineMode;

    // Highlighting attributes
    fSpaceAttri       : TSynHighlighterAttributes;
    fCommentAttri     : TSynHighlighterAttributes;
    fDirectiveAttri   : TSynHighlighterAttributes;
    fSeparatorAttri   : TSynHighlighterAttributes;
    fMethodAttri      : TSynHighlighterAttributes;
    fUrlAttri         : TSynHighlighterAttributes;
    fQueryParamAttri  : TSynHighlighterAttributes;
    fVersionAttri     : TSynHighlighterAttributes;
    fHeaderNameAttri  : TSynHighlighterAttributes;
    fHeaderValueAttri : TSynHighlighterAttributes;
    fVariableAttri    : TSynHighlighterAttributes;
    fPropNameAttri    : TSynHighlighterAttributes;
    fStringAttri      : TSynHighlighterAttributes;
    fNumberAttri      : TSynHighlighterAttributes;
    fBooleanAttri     : TSynHighlighterAttributes;
    fNullLitAttri     : TSynHighlighterAttributes;
    fSymbolAttri      : TSynHighlighterAttributes;
    fBraceAttri       : TSynHighlighterAttributes;
    fBodyTextAttri    : TSynHighlighterAttributes;
    fFileRefAttri     : TSynHighlighterAttributes;
    fInvalidAttri     : TSynHighlighterAttributes;

    // Line pre-classification helpers
    procedure ClassifyCurrentLine;
    function  TryDetectVariableDecl(StartIdx: Integer): Boolean;
    function  TryDetectRequestLine(StartIdx: Integer): Boolean;
    function  TryDetectHeader(StartIdx: Integer): Boolean;

    // Token scanning helpers
    procedure NullProc;
    procedure ScanSpace;
    procedure ScanInterpolation;
    procedure ScanNumber;
    procedure ScanBodyString;
    procedure ScanOpenBrace;
    procedure ScanCloseBrace;
    procedure ScanOpenBracket;
    procedure ScanCloseBracket;
    procedure ScanSymbol;
    procedure ScanBodyIdent;
    procedure ScanInvalidOrBodyText;
    procedure ProcessSeparatorFolding;

    // Mode-specific dispatchers for Next
    procedure NextSeparatorToken;
    procedure NextDirectiveToken;
    procedure NextCommentToken;
    procedure NextVariableDeclToken;
    procedure NextRequestLineToken;
    procedure NextQueryToken;
    procedure NextHeaderToken;
    procedure NextFileRefToken;
    procedure NextBodyToken;

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

    // Range state persistence
    function  GetRange: Pointer; override;
    procedure SetRange(Value: Pointer); override;
    procedure ResetRange; override;

    // Attribute properties
    property SpaceAttri       : TSynHighlighterAttributes read fSpaceAttri;
    property CommentAttri     : TSynHighlighterAttributes read fCommentAttri;
    property DirectiveAttri   : TSynHighlighterAttributes read fDirectiveAttri;
    property SeparatorAttri   : TSynHighlighterAttributes read fSeparatorAttri;
    property MethodAttri      : TSynHighlighterAttributes read fMethodAttri;
    property UrlAttri         : TSynHighlighterAttributes read fUrlAttri;
    property QueryParamAttri  : TSynHighlighterAttributes read fQueryParamAttri;
    property VersionAttri     : TSynHighlighterAttributes read fVersionAttri;
    property HeaderNameAttri  : TSynHighlighterAttributes read fHeaderNameAttri;
    property HeaderValueAttri : TSynHighlighterAttributes read fHeaderValueAttri;
    property VariableAttri    : TSynHighlighterAttributes read fVariableAttri;
    property PropNameAttri    : TSynHighlighterAttributes read fPropNameAttri;
    property StringAttri      : TSynHighlighterAttributes read fStringAttri;
    property NumberAttri      : TSynHighlighterAttributes read fNumberAttri;
    property BooleanAttri     : TSynHighlighterAttributes read fBooleanAttri;
    property NullLitAttri     : TSynHighlighterAttributes read fNullLitAttri;
    property SymbolAttri      : TSynHighlighterAttributes read fSymbolAttri;
    property BraceAttri       : TSynHighlighterAttributes read fBraceAttri;
    property BodyTextAttri    : TSynHighlighterAttributes read fBodyTextAttri;
    property FileRefAttri     : TSynHighlighterAttributes read fFileRefAttri;
    property InvalidAttri     : TSynHighlighterAttributes read fInvalidAttri;
  end;

implementation

const
  KnownVerbs: array[0..18] of string = (
    'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE',
    'PATCH', 'PROPFIND', 'PROPPATCH', 'MKCOL', 'COPY', 'MOVE', 'LOCK',
    'UNLOCK', 'SEARCH', 'REPORT', 'MKCALENDAR');

function IsKnownVerb(const AWord: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(KnownVerbs) to High(KnownVerbs) do
    if SameText(KnownVerbs[I], AWord) then
    begin
      Result := True;
      Exit;
    end;
end;

function IsVariableNameChar(C: Char): Boolean; inline;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']);
end;

function IsHeaderNameChar(C: Char): Boolean; inline;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '!', '#', '$', '%', '&', '''',
                   '*', '+', '-', '.', '^', '_', '`', '|', '~']);
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9'];
end;

{ ===========================================================================
  Constructor / Destructor
  =========================================================================== }

constructor TSynHttpSyn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Whitespace
  fSpaceAttri := TSynHighlighterAttributes.Create('Whitespace', 'Whitespace');
  fSpaceAttri.Foreground := clNone;
  fSpaceAttri.Background := clNone;
  AddAttribute(fSpaceAttri);

  // Comments (# ..., // ...)
  fCommentAttri := TSynHighlighterAttributes.Create('Comment', 'Comment');
  fCommentAttri.Foreground := TColor($007A7A7A);  // mid gray
  fCommentAttri.Style := [fsItalic];
  AddAttribute(fCommentAttri);

  // Directives (# @name, # @title, etc.)
  fDirectiveAttri := TSynHighlighterAttributes.Create('Directive', 'Directive');
  fDirectiveAttri.Foreground := TColor($00D09020); // cyan/amber accent
  fDirectiveAttri.Style := [fsBold];
  AddAttribute(fDirectiveAttri);

  // Request Separator (### [title])
  fSeparatorAttri := TSynHighlighterAttributes.Create('Separator', 'Separator');
  fSeparatorAttri.Foreground := TColor($0000A0FF); // vibrant orange-amber
  fSeparatorAttri.Style := [fsBold];
  AddAttribute(fSeparatorAttri);

  // HTTP Method (GET, POST, PUT, DELETE, ...)
  fMethodAttri := TSynHighlighterAttributes.Create('HTTP Method', 'HTTP Method');
  fMethodAttri.Foreground := TColor($00FFA020);  // vivid royal blue / cyan
  fMethodAttri.Style := [fsBold];
  AddAttribute(fMethodAttri);

  // URL / Path
  fUrlAttri := TSynHighlighterAttributes.Create('URL', 'URL');
  fUrlAttri.Foreground := TColor($00E8B040);      // sky blue / turquoise
  AddAttribute(fUrlAttri);

  // Query parameter
  fQueryParamAttri := TSynHighlighterAttributes.Create('Query Parameter', 'Query Parameter');
  fQueryParamAttri.Foreground := TColor($00C09020); // cyan-teal
  AddAttribute(fQueryParamAttri);

  // HTTP Version (HTTP/1.1, HTTP/2, ...)
  fVersionAttri := TSynHighlighterAttributes.Create('HTTP Version', 'HTTP Version');
  fVersionAttri.Foreground := TColor($00909090);  // silver-gray
  fVersionAttri.Style := [fsBold];
  AddAttribute(fVersionAttri);

  // Header Name (Content-Type, Accept, ...)
  fHeaderNameAttri := TSynHighlighterAttributes.Create('Header Name', 'Header Name');
  fHeaderNameAttri.Foreground := TColor($00B07030); // steel blue / slate
  fHeaderNameAttri.Style := [fsBold];
  AddAttribute(fHeaderNameAttri);

  // Header Value
  fHeaderValueAttri := TSynHighlighterAttributes.Create('Header Value', 'Header Value');
  fHeaderValueAttri.Foreground := TColor($00D0D0D0); // light gray
  AddAttribute(fHeaderValueAttri);

  // Variable (@name, {{var}})
  fVariableAttri := TSynHighlighterAttributes.Create('Variable', 'Variable');
  fVariableAttri.Foreground := TColor($0050B0FF);  // warm amber / gold
  fVariableAttri.Style := [fsBold];
  AddAttribute(fVariableAttri);

  // JSON Property Name ("key":)
  fPropNameAttri := TSynHighlighterAttributes.Create('JSON Property Name', 'JSON Property Name');
  fPropNameAttri.Foreground := TColor($0000A0E0);  // teal / cyan
  AddAttribute(fPropNameAttri);

  // String ("value", 'value')
  fStringAttri := TSynHighlighterAttributes.Create('String', 'String');
  fStringAttri.Foreground := TColor($0040B040);    // emerald green
  AddAttribute(fStringAttri);

  // Number (123, 4.56)
  fNumberAttri := TSynHighlighterAttributes.Create('Number', 'Number');
  fNumberAttri.Foreground := TColor($002080E0);    // burnt orange
  AddAttribute(fNumberAttri);

  // Boolean (true, false)
  fBooleanAttri := TSynHighlighterAttributes.Create('Boolean', 'Boolean');
  fBooleanAttri.Foreground := TColor($005050D0);   // coral / crimson
  fBooleanAttri.Style := [fsBold];
  AddAttribute(fBooleanAttri);

  // Null literal (null)
  fNullLitAttri := TSynHighlighterAttributes.Create('Null', 'Null');
  fNullLitAttri.Foreground := clGray;
  fNullLitAttri.Style := [fsBold];
  AddAttribute(fNullLitAttri);

  // Symbols (:, =, ?, &, <, >, etc.)
  fSymbolAttri := TSynHighlighterAttributes.Create('Symbol', 'Symbol');
  fSymbolAttri.Foreground := TColor($00A0A0A0);    // mid-gray
  AddAttribute(fSymbolAttri);

  // Braces { } [ ]
  fBraceAttri := TSynHighlighterAttributes.Create('Brace', 'Brace');
  fBraceAttri.Foreground := TColor($00D8D8D8);     // bright silver
  AddAttribute(fBraceAttri);

  // Body Text
  fBodyTextAttri := TSynHighlighterAttributes.Create('Body Text', 'Body Text');
  fBodyTextAttri.Foreground := TColor($00D0D0D0);  // soft white
  AddAttribute(fBodyTextAttri);

  // File Reference (< ./file.json)
  fFileRefAttri := TSynHighlighterAttributes.Create('File Reference', 'File Reference');
  fFileRefAttri.Foreground := TColor($00E08080);   // lavender
  fFileRefAttri.Style := [fsItalic];
  AddAttribute(fFileRefAttri);

  // Invalid / Malformed
  fInvalidAttri := TSynHighlighterAttributes.Create('Invalid', 'Invalid');
  fInvalidAttri.Foreground := clRed;
  fInvalidAttri.Style := [fsUnderline];
  AddAttribute(fInvalidAttri);

  SetAttributesOnChange(@DefHighlightChange);

  fLexerState := lsRoot;
  fLineMode := lmBlank;
  fDefaultFilter := 'HTTP files (*.http;*.rest)|*.http;*.rest';
end;

destructor TSynHttpSyn.Destroy;
begin
  inherited Destroy;
end;

{ ===========================================================================
  Class / Meta
  =========================================================================== }

class function TSynHttpSyn.GetLanguageName: string;
begin
  Result := 'HTTP';
end;

function TSynHttpSyn.GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_COMMENT    : Result := fCommentAttri;
    SYN_ATTR_KEYWORD    : Result := fMethodAttri;
    SYN_ATTR_STRING     : Result := fStringAttri;
    SYN_ATTR_WHITESPACE : Result := fSpaceAttri;
    SYN_ATTR_SYMBOL     : Result := fSymbolAttri;
    SYN_ATTR_NUMBER     : Result := fNumberAttri;
    SYN_ATTR_IDENTIFIER : Result := fVariableAttri;
    else                  Result := nil;
  end;
end;

function TSynHttpSyn.GetRangeClass: TSynCustomHighlighterRangeClass;
begin
  Result := TSynCustomHighlighterRange;
end;

{ ===========================================================================
  Range state persistence
  =========================================================================== }

function TSynHttpSyn.GetRange: Pointer;
begin
  CodeFoldRange.RangeType := Pointer(PtrUInt(Ord(fLexerState)));
  Result := inherited GetRange;
end;

procedure TSynHttpSyn.SetRange(Value: Pointer);
begin
  inherited SetRange(Value);
  fLexerState := THttpLexerState(PtrUInt(CodeFoldRange.RangeType));
end;

procedure TSynHttpSyn.ResetRange;
begin
  inherited ResetRange;
  fLexerState := lsRoot;
end;

{ ===========================================================================
  SetLine
  =========================================================================== }

procedure TSynHttpSyn.SetLine(const NewValue: String; LineNumber: Integer);
begin
  fLineStr    := NewValue;
  fLineLen    := Length(fLineStr);
  fLine       := PChar(Pointer(fLineStr));
  Run         := 0;
  fLineNumber := LineNumber;
  inherited SetLine(NewValue, LineNumber);

  ClassifyCurrentLine;
  Next;
end;

{ ===========================================================================
  Line Pre-classification
  =========================================================================== }

function TSynHttpSyn.TryDetectVariableDecl(StartIdx: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := StartIdx;
  if (i >= fLineLen) or (fLine[i] <> '@') then
    Exit;
  Inc(i);
  if (i >= fLineLen) or not IsVariableNameChar(fLine[i]) then
    Exit;
  while (i < fLineLen) and IsVariableNameChar(fLine[i]) do
    Inc(i);
  while (i < fLineLen) and (fLine[i] in [' ', #9]) do
    Inc(i);
  if (i < fLineLen) and (fLine[i] = '=') then
    Result := True;
end;

function TSynHttpSyn.TryDetectRequestLine(StartIdx: Integer): Boolean;
var
  i, wStart: Integer;
  w: string;
begin
  Result := False;
  i := StartIdx;
  wStart := i;
  while (i < fLineLen) and not (fLine[i] in [' ', #9]) do
    Inc(i);
  if i = wStart then
    Exit;
  SetString(w, fLine + wStart, i - wStart);

  if IsKnownVerb(w) then
  begin
    Result := True;
    Exit;
  end;

  if (Copy(LowerCase(w), 1, 7) = 'http://') or (Copy(LowerCase(w), 1, 8) = 'https://') then
  begin
    Result := True;
    Exit;
  end;
end;

function TSynHttpSyn.TryDetectHeader(StartIdx: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := StartIdx;
  if (i >= fLineLen) or not IsHeaderNameChar(fLine[i]) then
    Exit;
  while (i < fLineLen) and IsHeaderNameChar(fLine[i]) do
    Inc(i);
  while (i < fLineLen) and (fLine[i] in [' ', #9]) do
    Inc(i);
  if (i < fLineLen) and (fLine[i] = ':') then
    Result := True;
end;

procedure TSynHttpSyn.ClassifyCurrentLine;
var
  i: Integer;
begin
  // Skip leading whitespace to examine the first non-space character
  i := 0;
  while (i < fLineLen) and (fLine[i] in [' ', #9]) do
    Inc(i);

  if i >= fLineLen then
  begin
    fLineMode := lmBlank;
    // An empty line in lsHeaders transitions state to lsBody
    if fLexerState = lsHeaders then
      fLexerState := lsBody;
    Exit;
  end;

  // 1. Separator: '###'
  if (fLine[i] = '#') and (i + 2 < fLineLen) and (fLine[i + 1] = '#') and (fLine[i + 2] = '#') then
  begin
    fLineMode := lmSeparator;
    fLexerState := lsRoot;
    Exit;
  end;

  // 2. Directive: '# @name', '// @name', '# @title', etc.
  if ((fLine[i] = '#') and (i + 1 < fLineLen) and (fLine[i + 1] = '@')) or
     ((fLine[i] = '#') and (i + 2 < fLineLen) and (fLine[i + 1] in [' ', #9]) and (fLine[i + 2] = '@')) or
     ((fLine[i] = '/') and (i + 1 < fLineLen) and (fLine[i + 1] = '/') and
      (Pos('@', Copy(fLineStr, i + 3, MaxInt)) > 0)) then
  begin
    fLineMode := lmDirective;
    if fLexerState = lsBody then
      fLexerState := lsRoot;
    Exit;
  end;

  // 3. Comments: '#' or '//'
  if (fLine[i] = '#') or ((fLine[i] = '/') and (i + 1 < fLineLen) and (fLine[i + 1] = '/')) then
  begin
    fLineMode := lmComment;
    Exit;
  end;

  // 4. File reference in body: '< ' (e.g. '< ./data.json')
  if (fLine[i] = '<') and (i + 1 < fLineLen) and (fLine[i + 1] in [' ', #9]) then
  begin
    fLineMode := lmFileRef;
    Exit;
  end;

  // 5. Variable declaration: '@name ='
  if (fLine[i] = '@') and TryDetectVariableDecl(i) then
  begin
    fLineMode := lmVariableDecl;
    if fLexerState = lsBody then
      fLexerState := lsRoot;
    Exit;
  end;

  // 6. Request line check: known HTTP verb or absolute URL
  if TryDetectRequestLine(i) then
  begin
    fLineMode := lmRequestLine;
    fLexerState := lsHeaders;
    Exit;
  end;

  // 7. Query parameter continuation in headers: '?param=' or '&param='
  if (fLexerState = lsHeaders) and (fLine[i] in ['?', '&']) then
  begin
    fLineMode := lmQueryContinuation;
    Exit;
  end;

  // 8. Header line in headers: 'Name: Value'
  if (fLexerState = lsHeaders) and TryDetectHeader(i) then
  begin
    fLineMode := lmHeader;
    Exit;
  end;

  // 9. Otherwise: body if in lsBody, or unclassified
  if fLexerState = lsBody then
    fLineMode := lmBody
  else if fLexerState = lsHeaders then
    fLineMode := lmHeader
  else
    fLineMode := lmBody;
end;

{ ===========================================================================
  Scan Helpers
  =========================================================================== }

procedure TSynHttpSyn.NullProc;
begin
  fTokenID := tkNull;
  // Run is NOT advanced – EOL sentinel
end;

procedure TSynHttpSyn.ScanSpace;
begin
  fTokenID := tkSpace;
  while (Run < fLineLen) and (fLine[Run] in [' ', #9]) do
    Inc(Run);
end;

procedure TSynHttpSyn.ScanInterpolation;
begin
  fTokenID := tkVariable;
  Inc(Run, 2); // consume '{{'
  while (Run + 1 < fLineLen) and not ((fLine[Run] = '}') and (fLine[Run + 1] = '}')) do
    Inc(Run);
  if (Run + 1 < fLineLen) and (fLine[Run] = '}') and (fLine[Run + 1] = '}') then
    Inc(Run, 2)
  else
    Run := fLineLen; // unterminated on this line
end;

procedure TSynHttpSyn.ScanNumber;
begin
  fTokenID := tkNumber;
  if (Run < fLineLen) and (fLine[Run] = '-') then
    Inc(Run);
  while (Run < fLineLen) and IsDigit(fLine[Run]) do
    Inc(Run);
  if (Run + 1 < fLineLen) and (fLine[Run] = '.') and IsDigit(fLine[Run + 1]) then
  begin
    Inc(Run); // '.'
    while (Run < fLineLen) and IsDigit(fLine[Run]) do
      Inc(Run);
  end;
  if (Run < fLineLen) and (fLine[Run] in ['e', 'E']) then
  begin
    Inc(Run);
    if (Run < fLineLen) and (fLine[Run] in ['+', '-']) then
      Inc(Run);
    while (Run < fLineLen) and IsDigit(fLine[Run]) do
      Inc(Run);
  end;
end;

procedure TSynHttpSyn.ScanBodyString;
var
  QuoteChar: Char;
  i: Integer;
begin
  QuoteChar := fLine[Run];
  Inc(Run); // consume opening quote

  while Run < fLineLen do
  begin
    if fLine[Run] = '\' then
    begin
      Inc(Run, 2); // skip escape char and escaped char
      Continue;
    end;
    if fLine[Run] = QuoteChar then
    begin
      Inc(Run); // consume closing quote
      Break;
    end;
    Inc(Run);
  end;

  // Look ahead to see if this string is a JSON property name (followed by ':')
  i := Run;
  while (i < fLineLen) and (fLine[i] in [' ', #9]) do
    Inc(i);

  if (i < fLineLen) and (fLine[i] = ':') then
    fTokenID := tkPropName
  else
    fTokenID := tkString;
end;

procedure TSynHttpSyn.ScanOpenBrace;
begin
  fTokenID := tkBrace;
  Inc(Run);
  StartCodeFoldBlock(HTTP_BLOCK_BRACE);
end;

procedure TSynHttpSyn.ScanCloseBrace;
begin
  if TopCodeFoldBlockType = HTTP_BLOCK_BRACE then
    EndCodeFoldBlock
  else if (TopCodeFoldBlockType <> nil) and (TopCodeFoldBlockType <> HTTP_BLOCK_REQUEST) then
  begin
    EndCodeFoldBlock;
    fTokenID := tkInvalid;
    Inc(Run);
    Exit;
  end;
  fTokenID := tkBrace;
  Inc(Run);
end;

procedure TSynHttpSyn.ScanOpenBracket;
begin
  fTokenID := tkBrace;
  Inc(Run);
  StartCodeFoldBlock(HTTP_BLOCK_BRACKET);
end;

procedure TSynHttpSyn.ScanCloseBracket;
begin
  if TopCodeFoldBlockType = HTTP_BLOCK_BRACKET then
    EndCodeFoldBlock
  else if (TopCodeFoldBlockType <> nil) and (TopCodeFoldBlockType <> HTTP_BLOCK_REQUEST) then
  begin
    EndCodeFoldBlock;
    fTokenID := tkInvalid;
    Inc(Run);
    Exit;
  end;
  fTokenID := tkBrace;
  Inc(Run);
end;

procedure TSynHttpSyn.ScanSymbol;
begin
  fTokenID := tkSymbol;
  Inc(Run);
end;

procedure TSynHttpSyn.ScanBodyIdent;
var
  Start: Integer;
  Word: string;
begin
  Start := Run;
  while (Run < fLineLen) and (fLine[Run] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(Run);
  SetString(Word, fLine + Start, Run - Start);

  if SameText(Word, 'true') or SameText(Word, 'false') then
    fTokenID := tkBoolean
  else if SameText(Word, 'null') then
    fTokenID := tkNullLit
  else
    fTokenID := tkBodyText;
end;

procedure TSynHttpSyn.ScanInvalidOrBodyText;
begin
  fTokenID := tkBodyText;
  Inc(Run); // ensures Run always advances
end;

procedure TSynHttpSyn.ProcessSeparatorFolding;
begin
  // Close any unclosed inner brace or bracket blocks first
  while (TopCodeFoldBlockType <> nil) and (TopCodeFoldBlockType <> HTTP_BLOCK_REQUEST) do
    EndCodeFoldBlock;

  // Close the previous request block if open
  if TopCodeFoldBlockType = HTTP_BLOCK_REQUEST then
    EndCodeFoldBlock;

  // Start the new request fold block
  StartCodeFoldBlock(HTTP_BLOCK_REQUEST);
end;

{ ===========================================================================
  Mode-Specific Token Dispatchers
  =========================================================================== }

procedure TSynHttpSyn.NextSeparatorToken;
begin
  if fLine[Run] = '#' then
  begin
    if (Run = fTokenPos) and (Run + 2 < fLineLen) and
       (fLine[Run + 1] = '#') and (fLine[Run + 2] = '#') then
    begin
      ProcessSeparatorFolding;
      while (Run < fLineLen) and (fLine[Run] = '#') do
        Inc(Run);
      fTokenID := tkSeparator;
      Exit;
    end;
  end;

  // Remainder of separator line is the section title
  while Run < fLineLen do
    Inc(Run);
  fTokenID := tkSeparator;
end;

procedure TSynHttpSyn.NextDirectiveToken;
begin
  if (fLine[Run] = '#') or (fLine[Run] = '/') then
  begin
    if (fLine[Run] = '/') and (Run + 1 < fLineLen) and (fLine[Run + 1] = '/') then
      Inc(Run, 2)
    else
      Inc(Run);
    fTokenID := tkComment;
  end
  else if fLine[Run] = '@' then
  begin
    Inc(Run);
    while (Run < fLineLen) and IsVariableNameChar(fLine[Run]) do
      Inc(Run);
    fTokenID := tkDirective;
  end
  else if fLine[Run] = '=' then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
  end
  else
  begin
    while (Run < fLineLen) and not (fLine[Run] in [' ', #9, '=']) do
      Inc(Run);
    fTokenID := tkVariable;
  end;
end;

procedure TSynHttpSyn.NextCommentToken;
begin
  // Line comment consumes the rest of the line
  while Run < fLineLen do
    Inc(Run);
  fTokenID := tkComment;
end;

procedure TSynHttpSyn.NextVariableDeclToken;
begin
  if fLine[Run] = '@' then
  begin
    Inc(Run);
    while (Run < fLineLen) and IsVariableNameChar(fLine[Run]) do
      Inc(Run);
    fTokenID := tkVariable;
  end
  else if fLine[Run] = '=' then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
  end
  else if (fLine[Run] = '{') and (Run + 1 < fLineLen) and (fLine[Run + 1] = '{') then
    ScanInterpolation
  else if fLine[Run] in ['"', ''''] then
    ScanBodyString
  else if (fLine[Run] in ['0'..'9', '-']) and
          ((Run + 1 >= fLineLen) or (fLine[Run + 1] in ['0'..'9'])) then
    ScanNumber
  else if (Pos('://', Copy(fLineStr, Run + 1, MaxInt)) > 0) or
          (Copy(fLineStr, Run + 1, 7) = 'http://') or
          (Copy(fLineStr, Run + 1, 8) = 'https://') then
  begin
    while (Run < fLineLen) and not (fLine[Run] in [' ', #9]) do
      Inc(Run);
    fTokenID := tkUrl;
  end
  else
  begin
    while (Run < fLineLen) and not (fLine[Run] in [' ', #9, '{']) do
      Inc(Run);
    fTokenID := tkString;
  end;
end;

procedure TSynHttpSyn.NextRequestLineToken;
var
  Start: Integer;
  Word: string;
begin
  // 1. Variable interpolation inside request line: '{{...}}'
  if (fLine[Run] = '{') and (Run + 1 < fLineLen) and (fLine[Run + 1] = '{') then
  begin
    ScanInterpolation;
    Exit;
  end;

  // 2. Query delimiters inside request line
  if fLine[Run] in ['?', '&'] then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
    Exit;
  end;

  if fLine[Run] = '=' then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
    Exit;
  end;

  // 3. Scan a word segment
  Start := Run;
  while (Run < fLineLen) and not (fLine[Run] in [' ', #9, '?', '&', '=', '{']) do
    Inc(Run);
  SetString(Word, fLine + Start, Run - Start);

  // Check for HTTP Verb at start of line
  if IsKnownVerb(Word) then
  begin
    fTokenID := tkHttpMethod;
    // If there was no preceding separator, this request starts a request fold
    if TopCodeFoldBlockType = nil then
      StartCodeFoldBlock(HTTP_BLOCK_REQUEST);
    Exit;
  end;

  // Check for HTTP Version at end of request line
  if SameText(Copy(Word, 1, 5), 'HTTP/') then
  begin
    fTokenID := tkHttpVersion;
    Exit;
  end;

  // Otherwise URL or query parameter component
  if (Start > 0) and (fLine[Start - 1] in ['?', '&']) then
    fTokenID := tkQueryParam
  else
    fTokenID := tkUrl;
end;

procedure TSynHttpSyn.NextQueryToken;
var
  Start: Integer;
begin
  if fLine[Run] in ['?', '&'] then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
  end
  else if fLine[Run] = '=' then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
  end
  else if (fLine[Run] = '{') and (Run + 1 < fLineLen) and (fLine[Run + 1] = '{') then
    ScanInterpolation
  else
  begin
    Start := Run;
    while (Run < fLineLen) and not (fLine[Run] in [' ', #9, '&', '=', '{']) do
      Inc(Run);
    if (Start > 0) and (fLine[Start - 1] = '=') then
      fTokenID := tkUrl
    else
      fTokenID := tkQueryParam;
  end;
end;

procedure TSynHttpSyn.NextHeaderToken;
var
  ColonPos: Integer;
begin
  // Check if we are still before the header ':'
  ColonPos := Pos(':', Copy(fLineStr, Run + 1, MaxInt));

  if (ColonPos > 0) and (fLine[Run] <> ':') then
  begin
    // Header name
    while (Run < fLineLen) and (fLine[Run] <> ':') and not (fLine[Run] in [' ', #9]) do
      Inc(Run);
    fTokenID := tkHeaderName;
    Exit;
  end;

  if fLine[Run] = ':' then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
    Exit;
  end;

  // Header value segment: handle {{...}} interpolation or text
  if (fLine[Run] = '{') and (Run + 1 < fLineLen) and (fLine[Run + 1] = '{') then
    ScanInterpolation
  else
  begin
    while (Run < fLineLen) and not ((fLine[Run] = '{') and (Run + 1 < fLineLen) and (fLine[Run + 1] = '{')) do
      Inc(Run);
    fTokenID := tkHeaderValue;
  end;
end;

procedure TSynHttpSyn.NextFileRefToken;
begin
  if fLine[Run] = '<' then
  begin
    Inc(Run);
    fTokenID := tkSymbol;
  end
  else
  begin
    while (Run < fLineLen) and (fLine[Run] <> '#') do
      Inc(Run);
    fTokenID := tkFileRef;
  end;
end;

procedure TSynHttpSyn.NextBodyToken;
begin
  case fLine[Run] of
    '{':
      if (Run + 1 < fLineLen) and (fLine[Run + 1] = '{') then
        ScanInterpolation
      else
        ScanOpenBrace;

    '}':
      if (Run + 1 < fLineLen) and (fLine[Run + 1] = '}') then
        ScanInterpolation
      else
        ScanCloseBrace;

    '[': ScanOpenBracket;
    ']': ScanCloseBracket;

    '"', '''': ScanBodyString;

    '0'..'9': ScanNumber;

    '-':
      if (Run + 1 < fLineLen) and IsDigit(fLine[Run + 1]) then
        ScanNumber
      else
        ScanSymbol;

    ':', ',', ';': ScanSymbol;
    '<', '>', '/', '=': ScanSymbol;

    'A'..'Z', 'a'..'z', '_': ScanBodyIdent;

    #0: NullProc;

    else
      ScanInvalidOrBodyText;
  end;
end;

{ ===========================================================================
  Next Dispatcher
  =========================================================================== }

procedure TSynHttpSyn.Next;
begin
  fTokenPos := Run;

  // End of line guard
  if Run >= fLineLen then
  begin
    NullProc;
    Exit;
  end;

  // Whitespace is always tokenized as tkSpace
  if fLine[Run] in [' ', #9] then
  begin
    ScanSpace;
    Exit;
  end;

  case fLineMode of
    lmSeparator         : NextSeparatorToken;
    lmDirective         : NextDirectiveToken;
    lmComment           : NextCommentToken;
    lmVariableDecl      : NextVariableDeclToken;
    lmRequestLine       : NextRequestLineToken;
    lmQueryContinuation : NextQueryToken;
    lmHeader            : NextHeaderToken;
    lmFileRef           : NextFileRefToken;
    lmBody, lmBlank     : NextBodyToken;
  end;
end;

{ ===========================================================================
  Token Query Methods
  =========================================================================== }

function TSynHttpSyn.GetEol: Boolean;
begin
  Result := fTokenID = tkNull;
end;

function TSynHttpSyn.GetToken: String;
begin
  SetString(Result, fLine + fTokenPos, Run - fTokenPos);
end;

procedure TSynHttpSyn.GetTokenEx(out TokenStart: PChar; out TokenLength: Integer);
begin
  TokenStart  := fLine + fTokenPos;
  TokenLength := Run - fTokenPos;
end;

function TSynHttpSyn.GetTokenPos: Integer;
begin
  Result := fTokenPos;
end;

function TSynHttpSyn.GetTokenKind: Integer;
begin
  Result := Ord(fTokenID);
end;

function TSynHttpSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case fTokenID of
    tkSpace       : Result := fSpaceAttri;
    tkComment     : Result := fCommentAttri;
    tkDirective   : Result := fDirectiveAttri;
    tkSeparator   : Result := fSeparatorAttri;
    tkHttpMethod  : Result := fMethodAttri;
    tkUrl         : Result := fUrlAttri;
    tkQueryParam  : Result := fQueryParamAttri;
    tkHttpVersion : Result := fVersionAttri;
    tkHeaderName  : Result := fHeaderNameAttri;
    tkHeaderValue : Result := fHeaderValueAttri;
    tkVariable    : Result := fVariableAttri;
    tkPropName    : Result := fPropNameAttri;
    tkString      : Result := fStringAttri;
    tkNumber      : Result := fNumberAttri;
    tkBoolean     : Result := fBooleanAttri;
    tkNullLit     : Result := fNullLitAttri;
    tkSymbol      : Result := fSymbolAttri;
    tkBrace       : Result := fBraceAttri;
    tkBodyText    : Result := fBodyTextAttri;
    tkFileRef     : Result := fFileRefAttri;
    tkInvalid     : Result := fInvalidAttri;
    tkNull        : Result := nil;
    else            Result := nil;
  end;
end;

end.
