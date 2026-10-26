unit HttpWorkspace;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, ComCtrls, laz.VirtualTrees, SynEdit,
  SynEditHighlighter, SynHighlighterHttp, Graphics, Forms, StdCtrls, Buttons,
  Menus, Dialogs,
  HttpFileParser, HttpFileAST, HttpFileExecutor, CurlRequestExecutor,
  HttpFileResponses;

type
  TWorkspaceEvent = procedure(ASender: TObject) of object;
  TWorkspaceErrorEvent = procedure(ASender: TObject; const AMessage: string) of object;

  { THttpWorkspace - encapsulates one .http file with its editor, parser, executor, and UI }
  THttpWorkspace = class(TComponent)
  private
    FFilePath: string;
    FModified: Boolean;
    FParser: THttpFileParser;
    FExecutor: TCurlRequestExecutor;
    FCurrentEndpointIndex: Integer;
    FIsExecuting: Boolean;
    
    // UI components
    FMainPanel: TPanel;
    FLeftPanel: TPanel;
    FRightPanel: TPanel;
    FHorizontalSplitter: TSplitter;
    FVerticalSplitter: TSplitter;
    
    // Left: Request Explorer
    FExplorerPanel: TPanel;
    FExplorerHeader: TPanel;
    FExplorerLabel: TLabel;
    FTreeView: TLazVirtualStringTree;
    
    // Center: Source Editor
    FEditorPanel: TPanel;
    FEditorHeader: TPanel;
    FEditorLabel: TLabel;
    FEditor: TSynEdit;
    FHighlighter: TSynHttpSyn;
    
    // Right: Inspector
    FInspectorPanel: TPanel;
    FInspectorHeader: TPanel;
    FInspectorLabel: TLabel;
    FInspectorTabs: TPageControl;
    FTabResponse: TTabSheet;
    FTabHeaders: TTabSheet;
    FTabRequest: TTabSheet;
    FTabDebug: TTabSheet;
    
    FResponseEditor: TSynEdit;
    FHeadersEditor: TSynEdit;
    FRequestEditor: TSynEdit;
    FDebugEditor: TSynEdit;
    
    FResponseStatus: TPanel;
    FStatusLabel: TLabel;
    
    // Events
    FOnModifiedChanged: TWorkspaceEvent;
    FOnStatusChanged: TWorkspaceEvent;
    FOnError: TWorkspaceErrorEvent;
    
    procedure InitializeUI;
    procedure SetupColors;
    procedure SetupTreeView;
    procedure SetupEditor;
    procedure SetupInspector;
    
    procedure TreeViewGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: String);
    procedure TreeViewChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeViewDblClick(Sender: TObject);
    procedure TreeViewInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode;
      var InitialStates: TVirtualNodeInitStates);
    procedure TreeViewInitChildren(Sender: TBaseVirtualTree; Node: PVirtualNode;
      var ChildCount: Cardinal);
      
    procedure EditorChange(Sender: TObject);
    procedure EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure OnRequestExecuted(ASender: TObject; const ARequestName: string;
      AResponse: THttpResponse);
    
    procedure SetFilePath(const AValue: string);
    procedure SetModified(AValue: Boolean);
    
    procedure RebuildTree;
    procedure NavigateToLine(ALine: Integer);
    procedure UpdateInspector;
    procedure AddDebugMessage(const AMessage: string; ASeverity: THttpSeverity = hsInfo);
    
    function GetNodeType(Node: PVirtualNode): Integer; // 0=root, 1=var, 2=endpoint, 3=error
    function GetNodeData(Node: PVirtualNode): Pointer;
    
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    
    procedure CreateNew;
    procedure LoadFromFile(const AFileName: string);
    function SaveToFile(const AFileName: string): Boolean;
    function Save: Boolean;
    
    procedure Parse;
    procedure ExecuteCurrentRequest;
    procedure ExecuteAllRequests;
    procedure StopExecution;
    
    procedure ShowExplorer(AVisible: Boolean);
    procedure ShowInspector(AVisible: Boolean);
    procedure ShowDebugPanel(AVisible: Boolean);
    
    property FilePath: string read FFilePath write SetFilePath;
    property Modified: boolean read FModified write SetModified;
    property Parser: THttpFileParser read FParser;
    property Executor: TCurlRequestExecutor read FExecutor;
    property CurrentEndpointIndex: Integer read FCurrentEndpointIndex;
    property IsExecuting: Boolean read FIsExecuting;
    
    property MainPanel: TPanel read FMainPanel;
    property Editor: TSynEdit read FEditor;
    
    property OnModifiedChanged: TWorkspaceEvent read FOnModifiedChanged write FOnModifiedChanged;
    property OnStatusChanged: TWorkspaceEvent read FOnStatusChanged write FOnStatusChanged;
    property OnError: TWorkspaceErrorEvent read FOnError write FOnError;
  end;

type
  PTreeNodeData = ^TTreeNodeData;
  TTreeNodeData = record
    NodeType: Integer; // 0=root, 1=variable, 2=endpoint, 3=error
    Index: Integer;    // index in Variables or Endpoints array
    Endpoint: TEndpoint;
    Variable: TVariable;
    Error: THttpParseError;
  end;

implementation

uses
  LCLType, LCLIntf, Math;

const
  // Dark theme colors
  COLOR_BACKGROUND = $252525;        // Dark graphite
  COLOR_PANEL = $2D2D2D;            // Charcoal
  COLOR_PANEL_HEADER = $353535;     // Lighter charcoal
  COLOR_TEXT = $E0E0E0;             // Light gray
  COLOR_TEXT_DIM = $909090;         // Dim gray
  COLOR_ACCENT = $FFA000;           // Cyan/teal
  COLOR_SUCCESS = $00AA00;          // Green
  COLOR_WARNING = $00AAFF;          // Amber
  COLOR_ERROR = $4444FF;            // Red
  COLOR_SELECTION = $4A4A4A;        // Selection gray
  COLOR_GUTTER = $202020;           // Gutter background

{ THttpWorkspace }

constructor THttpWorkspace.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFilePath := '';
  FModified := False;
  FCurrentEndpointIndex := -1;
  FIsExecuting := False;
  
  InitializeUI;
end;

destructor THttpWorkspace.Destroy;
begin
  FParser.Free;
  FExecutor.Free;
  inherited Destroy;
end;

procedure THttpWorkspace.InitializeUI;
begin
  // Main container
  FMainPanel := TPanel.Create(Self);
  FMainPanel.Parent := nil;
  FMainPanel.Align := alClient;
  FMainPanel.BevelOuter := bvNone;
  FMainPanel.Color := COLOR_BACKGROUND;
  
  // Left panel for explorer
  FLeftPanel := TPanel.Create(Self);
  FLeftPanel.Parent := FMainPanel;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := 250;
  FLeftPanel.BevelOuter := bvNone;
  FLeftPanel.Color := COLOR_PANEL;
  
  // Splitter
  FHorizontalSplitter := TSplitter.Create(Self);
  FHorizontalSplitter.Parent := FMainPanel;
  FHorizontalSplitter.Align := alLeft;
  FHorizontalSplitter.Width := 3;
  FHorizontalSplitter.Color := COLOR_BACKGROUND;
  
  // Right panel for inspector
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := FMainPanel;
  FRightPanel.Align := alRight;
  FRightPanel.Width := 400;
  FRightPanel.BevelOuter := bvNone;
  FRightPanel.Color := COLOR_PANEL;
  
  // Vertical splitter
  FVerticalSplitter := TSplitter.Create(Self);
  FVerticalSplitter.Parent := FMainPanel;
  FVerticalSplitter.Align := alRight;
  FVerticalSplitter.Width := 3;
  FVerticalSplitter.Color := COLOR_BACKGROUND;
  
  // Center panel for editor
  FEditorPanel := TPanel.Create(Self);
  FEditorPanel.Parent := FMainPanel;
  FEditorPanel.Align := alClient;
  FEditorPanel.BevelOuter := bvNone;
  FEditorPanel.Color := COLOR_BACKGROUND;
  
  SetupTreeView;
  SetupEditor;
  SetupInspector;
  SetupColors;
end;

procedure THttpWorkspace.SetupTreeView;
begin
  // Explorer header
  FExplorerPanel := TPanel.Create(Self);
  FExplorerPanel.Parent := FLeftPanel;
  FExplorerPanel.Align := alClient;
  FExplorerPanel.BevelOuter := bvNone;
  FExplorerPanel.Color := COLOR_PANEL;
  
  FExplorerHeader := TPanel.Create(Self);
  FExplorerHeader.Parent := FExplorerPanel;
  FExplorerHeader.Align := alTop;
  FExplorerHeader.Height := 32;
  FExplorerHeader.BevelOuter := bvNone;
  FExplorerHeader.Color := COLOR_PANEL_HEADER;
  
  FExplorerLabel := TLabel.Create(Self);
  FExplorerLabel.Parent := FExplorerHeader;
  FExplorerLabel.Align := alClient;
  FExplorerLabel.Layout := tlCenter;
  FExplorerLabel.BorderSpacing.Left := 10;
  FExplorerLabel.Caption := 'REQUEST EXPLORER';
  FExplorerLabel.Font.Color := COLOR_TEXT;
  FExplorerLabel.Font.Style := [fsBold];
  
  // Tree view
  FTreeView := TLazVirtualStringTree.Create(Self);
  FTreeView.Parent := FExplorerPanel;
  FTreeView.Align := alClient;
  FTreeView.Color := COLOR_PANEL;
  FTreeView.Colors.BorderColor := COLOR_BACKGROUND;
  FTreeView.Colors.FocusedSelectionColor := COLOR_SELECTION;
  FTreeView.Colors.UnfocusedSelectionColor := COLOR_SELECTION;
  FTreeView.Colors.SelectionRectangleBlendColor := COLOR_ACCENT;
  FTreeView.Font.Color := COLOR_TEXT;
  FTreeView.Header.Options := FTreeView.Header.Options - [hoVisible];
  FTreeView.TreeOptions.PaintOptions := FTreeView.TreeOptions.PaintOptions + [toShowRoot];
  FTreeView.TreeOptions.SelectionOptions := FTreeView.TreeOptions.SelectionOptions + [toFullRowSelect];
  FTreeView.NodeDataSize := SizeOf(TTreeNodeData);
  
  FTreeView.OnGetText := @TreeViewGetText;
  FTreeView.OnChange := @TreeViewChange;
  FTreeView.OnDblClick := @TreeViewDblClick;
  FTreeView.OnInitNode := @TreeViewInitNode;
  FTreeView.OnInitChildren := @TreeViewInitChildren;
end;

procedure THttpWorkspace.SetupEditor;
begin
  // Editor header
  FEditorHeader := TPanel.Create(Self);
  FEditorHeader.Parent := FEditorPanel;
  FEditorHeader.Align := alTop;
  FEditorHeader.Height := 32;
  FEditorHeader.BevelOuter := bvNone;
  FEditorHeader.Color := COLOR_PANEL_HEADER;
  
  FEditorLabel := TLabel.Create(Self);
  FEditorLabel.Parent := FEditorHeader;
  FEditorLabel.Align := alClient;
  FEditorLabel.Layout := tlCenter;
  FEditorLabel.BorderSpacing.Left := 10;
  FEditorLabel.Caption := 'SOURCE';
  FEditorLabel.Font.Color := COLOR_TEXT;
  FEditorLabel.Font.Style := [fsBold];
  
  // Editor
  FEditor := TSynEdit.Create(Self);
  FEditor.Parent := FEditorPanel;
  FEditor.Align := alClient;
  FEditor.Font.Name := 'Consolas';
  FEditor.Font.Size := 10;
  FEditor.Color := COLOR_BACKGROUND;
  FEditor.Font.Color := COLOR_TEXT;
  FEditor.Gutter.Color := COLOR_GUTTER;
  FEditor.Gutter.Visible := True;
  FEditor.TabWidth := 2;
  FEditor.OnChange := @EditorChange;
  FEditor.OnStatusChange := @EditorStatusChange;
  
  // HTTP file syntax highlighter
  FHighlighter := TSynHttpSyn.Create(Self);
  FEditor.Highlighter := FHighlighter;
end;

procedure THttpWorkspace.SetupInspector;
begin
  // Inspector header
  FInspectorHeader := TPanel.Create(Self);
  FInspectorHeader.Parent := FRightPanel;
  FInspectorHeader.Align := alTop;
  FInspectorHeader.Height := 32;
  FInspectorHeader.BevelOuter := bvNone;
  FInspectorHeader.Color := COLOR_PANEL_HEADER;
  
  FInspectorLabel := TLabel.Create(Self);
  FInspectorLabel.Parent := FInspectorHeader;
  FInspectorLabel.Align := alClient;
  FInspectorLabel.Layout := tlCenter;
  FInspectorLabel.BorderSpacing.Left := 10;
  FInspectorLabel.Caption := 'INSPECTOR';
  FInspectorLabel.Font.Color := COLOR_TEXT;
  FInspectorLabel.Font.Style := [fsBold];
  
  // Response status panel
  FResponseStatus := TPanel.Create(Self);
  FResponseStatus.Parent := FRightPanel;
  FResponseStatus.Align := alTop;
  FResponseStatus.Height := 40;
  FResponseStatus.BevelOuter := bvNone;
  FResponseStatus.Color := COLOR_PANEL_HEADER;
  FResponseStatus.Visible := False;
  
  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FResponseStatus;
  FStatusLabel.Align := alClient;
  FStatusLabel.Layout := tlCenter;
  FStatusLabel.BorderSpacing.Left := 10;
  FStatusLabel.Font.Color := COLOR_TEXT;
  FStatusLabel.Font.Style := [fsBold];
  FStatusLabel.Font.Size := 10;
  
  // Inspector tabs
  FInspectorTabs := TPageControl.Create(Self);
  FInspectorTabs.Parent := FRightPanel;
  FInspectorTabs.Align := alClient;
  FInspectorTabs.Color := COLOR_PANEL;
  
  // Response tab
  FTabResponse := TTabSheet.Create(FInspectorTabs);
  FTabResponse.PageControl := FInspectorTabs;
  FTabResponse.Caption := 'Response';
  FTabResponse.Color := COLOR_PANEL;
  
  FResponseEditor := TSynEdit.Create(Self);
  FResponseEditor.Parent := FTabResponse;
  FResponseEditor.Align := alClient;
  FResponseEditor.Font.Name := 'Consolas';
  FResponseEditor.Font.Size := 9;
  FResponseEditor.Color := COLOR_BACKGROUND;
  FResponseEditor.Font.Color := COLOR_TEXT;
  FResponseEditor.Gutter.Visible := False;
  FResponseEditor.ReadOnly := True;
  
  // Headers tab
  FTabHeaders := TTabSheet.Create(FInspectorTabs);
  FTabHeaders.PageControl := FInspectorTabs;
  FTabHeaders.Caption := 'Headers';
  FTabHeaders.Color := COLOR_PANEL;
  
  FHeadersEditor := TSynEdit.Create(Self);
  FHeadersEditor.Parent := FTabHeaders;
  FHeadersEditor.Align := alClient;
  FHeadersEditor.Font.Name := 'Consolas';
  FHeadersEditor.Font.Size := 9;
  FHeadersEditor.Color := COLOR_BACKGROUND;
  FHeadersEditor.Font.Color := COLOR_TEXT;
  FHeadersEditor.Gutter.Visible := False;
  FHeadersEditor.ReadOnly := True;
  
  // Request tab
  FTabRequest := TTabSheet.Create(FInspectorTabs);
  FTabRequest.PageControl := FInspectorTabs;
  FTabRequest.Caption := 'Request';
  FTabRequest.Color := COLOR_PANEL;
  
  FRequestEditor := TSynEdit.Create(Self);
  FRequestEditor.Parent := FTabRequest;
  FRequestEditor.Align := alClient;
  FRequestEditor.Font.Name := 'Consolas';
  FRequestEditor.Font.Size := 9;
  FRequestEditor.Color := COLOR_BACKGROUND;
  FRequestEditor.Font.Color := COLOR_TEXT;
  FRequestEditor.Gutter.Visible := False;
  FRequestEditor.ReadOnly := True;
  
  // Debug tab
  FTabDebug := TTabSheet.Create(FInspectorTabs);
  FTabDebug.PageControl := FInspectorTabs;
  FTabDebug.Caption := 'Debug';
  FTabDebug.Color := COLOR_PANEL;
  
  FDebugEditor := TSynEdit.Create(Self);
  FDebugEditor.Parent := FTabDebug;
  FDebugEditor.Align := alClient;
  FDebugEditor.Font.Name := 'Consolas';
  FDebugEditor.Font.Size := 9;
  FDebugEditor.Color := COLOR_BACKGROUND;
  FDebugEditor.Font.Color := COLOR_TEXT;
  FDebugEditor.Gutter.Visible := False;
  FDebugEditor.ReadOnly := True;
  FDebugEditor.ScrollBars := ssAutoBoth;
end;

procedure THttpWorkspace.SetupColors;
begin
  // Additional color setup if needed
end;

procedure THttpWorkspace.CreateNew;
begin
  FFilePath := '';
  FModified := False;
  FEditor.Lines.Clear;
  FEditor.Lines.Add('### New Request');
  FEditor.Lines.Add('GET https://api.example.com/users');
  FEditor.Lines.Add('Accept: application/json');
  FModified := False;
  Parse;
end;

procedure THttpWorkspace.LoadFromFile(const AFileName: string);
begin
  FFilePath := AFileName;
  FEditor.Lines.LoadFromFile(AFileName);
  FModified := False;
  
  FEditorLabel.Caption := 'SOURCE - ' + ExtractFileName(AFileName);
  Parse;
  
  if Assigned(FOnModifiedChanged) then
    FOnModifiedChanged(Self);
end;

function THttpWorkspace.SaveToFile(const AFileName: string): Boolean;
begin
  Result := False;
  try
    FEditor.Lines.SaveToFile(AFileName);
    FFilePath := AFileName;
    FModified := False;
    FEditorLabel.Caption := 'SOURCE - ' + ExtractFileName(AFileName);
    if Assigned(FOnModifiedChanged) then
      FOnModifiedChanged(Self);
    Result := True;
  except
    on E: Exception do
    begin
      if Assigned(FOnError) then
        FOnError(Self, 'Failed to save file: ' + E.Message);
    end;
  end;
end;

function THttpWorkspace.Save: Boolean;
begin
  if FFilePath = '' then
    Result := False
  else
    Result := SaveToFile(FFilePath);
end;

procedure THttpWorkspace.Parse;
var
  BaseDir: string;
  I: Integer;
  Err: THttpParseError;
  SavedResponses: THttpResponseStore;
begin
  AddDebugMessage('Parsing HTTP file...', hsInfo);
  
  try
    // Preserve previously stored responses so that response references
    // (e.g. login.response.headers.X-AuthToken) keep resolving after a re-parse.
    SavedResponses := nil;
    if Assigned(FParser) then
    begin
      SavedResponses := THttpResponseStore.Create;
      SavedResponses.CopyFrom(FParser.Responses);
    end;

    // Free existing parser and executor
    FreeAndNil(FExecutor);
    FreeAndNil(FParser);

    // Create new parser
    FParser := THttpFileParser.Create(FEditor.Lines.Text);

    // Restore responses into the new parser before parsing
    if Assigned(SavedResponses) then
    begin
      FParser.Responses.CopyFrom(SavedResponses);
      FreeAndNil(SavedResponses);
    end;

    // Set base directory if file has been saved
    if FFilePath <> '' then
    begin
      BaseDir := ExtractFilePath(ExpandFileName(FFilePath));
      FParser.BaseDirectory := BaseDir;
      AddDebugMessage('Base directory: ' + BaseDir, hsInfo);
    end;
    
    // Parse
    FParser.Parse;
    
    // Create executor
    FExecutor := TCurlRequestExecutor.Create(FParser);
    FExecutor.OnExecuted := @OnRequestExecuted;
    
    // Report results
    if FParser.Errors.ErrorCount > 0 then
      AddDebugMessage(Format('Parse completed with %d error(s), %d warning(s)',
        [FParser.Errors.ErrorCount, FParser.Errors.WarningCount]), hsError)
    else if FParser.Errors.WarningCount > 0 then
      AddDebugMessage(Format('Parse completed with %d warning(s)',
        [FParser.Errors.WarningCount]), hsWarning)
    else
      AddDebugMessage(Format('Parse completed successfully. Found %d request(s), %d variable(s)',
        [Length(FParser.HttpFile.Endpoints), Length(FParser.HttpFile.Variables)]), hsInfo);
    
    // Log parse errors
    if FParser.Errors.Count > 0 then
    begin
      for I := 0 to FParser.Errors.Count - 1 do
      begin
        Err := FParser.Errors[I];
        AddDebugMessage(Format('[%d:%d] %s: %s',
          [Err.Row, Err.Column, UpperCase(SeverityName(Err.Severity)), Err.Message]),
          Err.Severity);
      end;
    end;
    
    RebuildTree;
    
    if Assigned(FOnStatusChanged) then
      FOnStatusChanged(Self);
      
  except
    on E: Exception do
    begin
      FreeAndNil(SavedResponses);
      AddDebugMessage('Parse failed: ' + E.Message, hsError);
      if Assigned(FOnError) then
        FOnError(Self, 'Parse failed: ' + E.Message);
    end;
  end;
end;

procedure THttpWorkspace.ExecuteCurrentRequest;
var
  Endpoint: TEndpoint;
begin
  if not Assigned(FParser) or not Assigned(FExecutor) then
  begin
    AddDebugMessage('Parser or executor not initialized', hsError);
    Exit;
  end;
  
  if (FCurrentEndpointIndex < 0) or (FCurrentEndpointIndex >= Length(FParser.HttpFile.Endpoints)) then
  begin
    AddDebugMessage('No request selected', hsWarning);
    Exit;
  end;
  
  FIsExecuting := True;
  try
    Endpoint := FParser.HttpFile.Endpoints[FCurrentEndpointIndex];
    AddDebugMessage(Format('Executing request: %s %s', [Endpoint.Verb, Endpoint.Url]), hsInfo);
    
    FExecutor.ExecuteAt(FCurrentEndpointIndex);
    
  except
    on E: Exception do
    begin
      AddDebugMessage('Execution failed: ' + E.Message, hsError);
      FIsExecuting := False;
      UpdateInspector;
      if Assigned(FOnError) then
        FOnError(Self, 'Execution failed: ' + E.Message);
    end;
  end;
end;

procedure THttpWorkspace.OnRequestExecuted(ASender: TObject;
  const ARequestName: string; AResponse: THttpResponse);
begin
  FIsExecuting := False;
  
  if Assigned(AResponse) then
  begin
    AddDebugMessage(Format('Request "%s" completed: %d %s',
      [ARequestName, AResponse.StatusCode, AResponse.StatusText]), hsInfo);
    UpdateInspector;
  end
  else
    AddDebugMessage(Format('Request "%s" completed with no response', [ARequestName]), hsWarning);
  
  if Assigned(FOnStatusChanged) then
    FOnStatusChanged(Self);
end;

procedure THttpWorkspace.ExecuteAllRequests;
var
  I: Integer;
begin
  if not Assigned(FParser) or not Assigned(FExecutor) then
    Exit;
    
  FIsExecuting := True;
  AddDebugMessage(Format('Executing all %d request(s)...', [Length(FParser.HttpFile.Endpoints)]), hsInfo);
  
  try
    FExecutor.ExecuteAll;
    FIsExecuting := False;
    AddDebugMessage('All requests completed', hsInfo);
  except
    on E: Exception do
    begin
      AddDebugMessage('Execution failed: ' + E.Message, hsError);
      FIsExecuting := False;
      if Assigned(FOnError) then
        FOnError(Self, 'Execution failed: ' + E.Message);
    end;
  end;
  
  if Assigned(FOnStatusChanged) then
    FOnStatusChanged(Self);
end;

procedure THttpWorkspace.StopExecution;
begin
  // libcurl doesn't support cancellation easily
  // This would need to be implemented with threading
  FIsExecuting := False;
end;

procedure THttpWorkspace.RebuildTree;
var
  RootNode: PVirtualNode;
begin
  FTreeView.BeginUpdate;
  try
    FTreeView.Clear;
    
    if Assigned(FParser) and Assigned(FParser.HttpFile) then
    begin
      // Calculate child count: variables + endpoints + errors
      FTreeView.RootNodeCount := 1; // One root node
    end;
  finally
    FTreeView.EndUpdate;
  end;
end;

procedure THttpWorkspace.TreeViewInitNode(Sender: TBaseVirtualTree;
  ParentNode, Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
var
  Data: PTreeNodeData;
  ParentData: PTreeNodeData;
  NodeIndex: Integer;
begin
  Data := Sender.GetNodeData(Node);
  
  if not Assigned(Data) then
    Exit;
  
  // Initialize to safe defaults
  Data^.NodeType := 0;
  Data^.Index := 0;
  Data^.Endpoint := nil;
  Data^.Variable := nil;
  
  if ParentNode = nil then
  begin
    // Root node
    Include(InitialStates, ivsHasChildren);
  end
  else
  begin
    // Child of root - determine if endpoint or error
    ParentData := Sender.GetNodeData(ParentNode);
    
    if not Assigned(ParentData) or not Assigned(FParser) or not Assigned(FParser.HttpFile) then
      Exit;
    
    if ParentData^.NodeType = 0 then // Parent is root
    begin
      NodeIndex := Node^.Index;
      
      if NodeIndex < Length(FParser.HttpFile.Endpoints) then
      begin
        // This is an endpoint node
        Data^.NodeType := 2;
        Data^.Index := NodeIndex;
        Data^.Endpoint := FParser.HttpFile.Endpoints[NodeIndex];
      end
      else
      begin
        // This is an error node
        Data^.NodeType := 3;
        Data^.Index := NodeIndex - Length(FParser.HttpFile.Endpoints);
        if Data^.Index < FParser.Errors.Count then
          Data^.Error := FParser.Errors[Data^.Index];
      end;
    end;
  end;
end;

procedure THttpWorkspace.TreeViewInitChildren(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var ChildCount: Cardinal);
var
  Data: PTreeNodeData;
begin
  ChildCount := 0;
  
  if not Assigned(Node) then
    Exit;
    
  Data := Sender.GetNodeData(Node);
  
  if not Assigned(Data) or not Assigned(FParser) or not Assigned(FParser.HttpFile) then
    Exit;
  
  if Data^.NodeType = 0 then // Root node
  begin
    // Just set count - child nodes will be initialized by InitNode
    ChildCount := Length(FParser.HttpFile.Endpoints);
    if FParser.Errors.ErrorCount > 0 then
      ChildCount := ChildCount + Cardinal(FParser.Errors.ErrorCount);
  end;
end;

procedure THttpWorkspace.TreeViewGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: String);
var
  Data: PTreeNodeData;
  Endpoint: TEndpoint;
  Err: THttpParseError;
  UrlShort: string;
begin
  CellText := '';
  
  if Node = nil then
    Exit;
    
  Data := Sender.GetNodeData(Node);
  if Data = nil then
    Exit;
  
  case Data^.NodeType of
    0: // Root
      CellText := 'HTTP File';
    1: // Variable
      if Assigned(Data^.Variable) then
        CellText := '@' + Data^.Variable.Name + ' = ' + Data^.Variable.Value;
    2: // Endpoint
      begin
        // CRITICAL: Don't access parser during execution
        // The executor calls FParser.Parse() which invalidates all endpoints
        if FIsExecuting then
        begin
          CellText := '<Executing...>';
          Exit;
        end;
        
        // Safety check: verify parser and endpoint array are valid
        if not Assigned(FParser) or not Assigned(FParser.HttpFile) then
        begin
          CellText := '<Parser not initialized>';
          Exit;
        end;
        
        if (Data^.Index < 0) or (Data^.Index >= Length(FParser.HttpFile.Endpoints)) then
        begin
          CellText := '<Invalid endpoint index>';
          Exit;
        end;
        
        // Get fresh endpoint reference from parser using INDEX (not from cached pointer)
        Endpoint := FParser.HttpFile.Endpoints[Data^.Index];
        if not Assigned(Endpoint) then
        begin
          CellText := '<Endpoint not found>';
          Exit;
        end;
        
        try
          UrlShort := Endpoint.Url;
          if Length(UrlShort) > 50 then
            UrlShort := Copy(UrlShort, 1, 47) + '...';
          
          if Endpoint.Name <> '' then
            CellText := Format('%s  %s %s', [Endpoint.Name, Endpoint.Verb, UrlShort])
          else
            CellText := Format('%s %s', [Endpoint.Verb, UrlShort]);
        except
          on E: Exception do
          CellText := '<' + e.ClassName + ':' + e.Message + '>' ;
        end;
      end;
    3: // Error
      begin
        if not Assigned(FParser) or not Assigned(FParser.Errors) then
        begin
          CellText := '<Parser errors not available>';
          Exit;
        end;
        
        if (Data^.Index < 0) or (Data^.Index >= FParser.Errors.Count) then
        begin
          CellText := '<Invalid error index>';
          Exit;
        end;
        
        Err := FParser.Errors[Data^.Index];
        CellText := Format('[Line %d] %s', [Err.Row, Err.Message]);
      end;
  end;
end;

procedure THttpWorkspace.TreeViewChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  Data: PTreeNodeData;
  Endpoint: TEndpoint;
begin
  if Node = nil then
    Exit;
    
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then
    Exit;
  
  if Data^.NodeType = 2 then // Endpoint
  begin
    FCurrentEndpointIndex := Data^.Index;
    
    // Get endpoint from parser using index, not from cached pointer
    if not FIsExecuting and Assigned(FParser) and Assigned(FParser.HttpFile) and
       (Data^.Index >= 0) and (Data^.Index < Length(FParser.HttpFile.Endpoints)) then
    begin
      Endpoint := FParser.HttpFile.Endpoints[Data^.Index];
      if Assigned(Endpoint) then
        NavigateToLine(Endpoint.Row);
    end;
    
    if Assigned(FOnStatusChanged) then
      FOnStatusChanged(Self);
  end
  else if Data^.NodeType = 3 then // Error
  begin
    if not FIsExecuting and Assigned(FParser) and Assigned(FParser.Errors) and
       (Data^.Index >= 0) and (Data^.Index < FParser.Errors.Count) then
    begin
      NavigateToLine(FParser.Errors[Data^.Index].Row);
    end;
  end;
end;

procedure THttpWorkspace.TreeViewDblClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PTreeNodeData;
begin
  Node := FTreeView.FocusedNode;
  if Node = nil then
    Exit;
    
  Data := FTreeView.GetNodeData(Node);
  if Data^.NodeType = 2 then // Endpoint
    ExecuteCurrentRequest;
end;

procedure THttpWorkspace.EditorChange(Sender: TObject);
begin
  if not FModified then
  begin
    FModified := True;
    if Assigned(FOnModifiedChanged) then
      FOnModifiedChanged(Self);
  end;
end;

procedure THttpWorkspace.EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
begin
  if Assigned(FOnStatusChanged) then
    FOnStatusChanged(Self);
end;

procedure THttpWorkspace.NavigateToLine(ALine: Integer);
begin
  if (ALine > 0) and (ALine <= FEditor.Lines.Count) then
  begin
    FEditor.CaretY := ALine;
    FEditor.CaretX := 1;
    FEditor.TopLine := Max(1, ALine - 5);
    FEditor.SetFocus;
  end;
end;

procedure THttpWorkspace.UpdateInspector;
var
  Response: THttpResponse;
  I: Integer;
  StatusColor: TColor;
  Endpoint: TEndpoint;
begin
  if not Assigned(FExecutor) or not Assigned(FExecutor.LastResponse) then
  begin
    FResponseStatus.Visible := False;
    FResponseEditor.Lines.Clear;
    FHeadersEditor.Lines.Clear;
    FRequestEditor.Lines.Clear;
    Exit;
  end;
  
  Response := FExecutor.LastResponse;
  
  // Update status panel
  FStatusLabel.Caption := Format('  %d %s', [Response.StatusCode, Response.StatusText]);
  if (Response.StatusCode >= 200) and (Response.StatusCode < 300) then
    StatusColor := COLOR_SUCCESS
  else if Response.StatusCode >= 400 then
    StatusColor := COLOR_ERROR
  else
    StatusColor := COLOR_WARNING;
  FStatusLabel.Font.Color := StatusColor;
  FResponseStatus.Visible := True;
  
  // Update response body
  FResponseEditor.Lines.Text := Response.Body;
  
  // Update headers
  FHeadersEditor.Lines.Clear;
  FHeadersEditor.Lines.Add(Format('%s %d %s', [Response.HttpVersion, Response.StatusCode, Response.StatusText]));
  FHeadersEditor.Lines.Add('');
  for I := 0 to Response.HeaderCount - 1 do
    FHeadersEditor.Lines.Add(Format('%s: %s', [Response.Headers[I].Name, Response.Headers[I].Value]));
  
  // Update request (if we have access to it)
  if (FCurrentEndpointIndex >= 0) and (FCurrentEndpointIndex < Length(FParser.HttpFile.Endpoints)) then
  begin
    Endpoint := FParser.HttpFile.Endpoints[FCurrentEndpointIndex];
    FRequestEditor.Lines.Clear;
    FRequestEditor.Lines.Add(Format('%s %s %s', [Endpoint.Verb, Endpoint.Url, Endpoint.HttpRevision]));
    for I := 0 to High(Endpoint.RequestHeaders) do
      FRequestEditor.Lines.Add(Format('%s: %s', [Endpoint.RequestHeaders[I].Name, Endpoint.RequestHeaders[I].Value]));
    if Endpoint.RequestBody <> '' then
    begin
      FRequestEditor.Lines.Add('');
      FRequestEditor.Lines.Add(Endpoint.RequestBody);
    end;
  end;
end;

procedure THttpWorkspace.AddDebugMessage(const AMessage: string; ASeverity: THttpSeverity);
var
  Prefix: string;
  TimeStr: string;
begin
  TimeStr := FormatDateTime('hh:nn:ss', Now);
  
  case ASeverity of
    hsError: Prefix := '[ERROR]';
    hsWarning: Prefix := '[WARN]';
  else
    Prefix := '[INFO]';
  end;
  
  FDebugEditor.Lines.Add(Format('[%s] %s %s', [TimeStr, Prefix, AMessage]));
  
  // Auto-scroll to bottom
  if FDebugEditor.Lines.Count > 0 then
    FDebugEditor.CaretY := FDebugEditor.Lines.Count;
end;

procedure THttpWorkspace.ShowExplorer(AVisible: Boolean);
begin
  FLeftPanel.Visible := AVisible;
  FHorizontalSplitter.Visible := AVisible;
end;

procedure THttpWorkspace.ShowInspector(AVisible: Boolean);
begin
  FRightPanel.Visible := AVisible;
  FVerticalSplitter.Visible := AVisible;
end;

procedure THttpWorkspace.ShowDebugPanel(AVisible: Boolean);
begin
  FTabDebug.TabVisible := AVisible;
end;

procedure THttpWorkspace.SetFilePath(const AValue: string);
begin
  if FFilePath <> AValue then
  begin
    FFilePath := AValue;
    if FFilePath <> '' then
      FEditorLabel.Caption := 'SOURCE - ' + ExtractFileName(FFilePath)
    else
      FEditorLabel.Caption := 'SOURCE';
  end;
end;

procedure THttpWorkspace.SetModified(AValue: Boolean);
begin
  if FModified <> AValue then
  begin
    FModified := AValue;
    if Assigned(FOnModifiedChanged) then
      FOnModifiedChanged(Self);
  end;
end;

function THttpWorkspace.GetNodeType(Node: PVirtualNode): Integer;
var
  Data: PTreeNodeData;
begin
  Data := FTreeView.GetNodeData(Node);
  Result := Data^.NodeType;
end;

function THttpWorkspace.GetNodeData(Node: PVirtualNode): Pointer;
begin
  Result := FTreeView.GetNodeData(Node);
end;

end.
