unit MainFormUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ActnList, StdCtrls, ExtCtrls, Buttons, LCLType,
  HttpWorkspace;

type

  { TMainForm }

  TMainForm = class(TForm)
    // Actions
    ActionList: TActionList;
    ActFileNew: TAction;
    ActFileOpen: TAction;
    ActFileSave: TAction;
    ActFileSaveAs: TAction;
    ActFileClose: TAction;
    ActFileExit: TAction;
    ActEditUndo: TAction;
    ActEditRedo: TAction;
    ActEditCut: TAction;
    ActEditCopy: TAction;
    ActEditPaste: TAction;
    ActEditFind: TAction;
    ActEditReplace: TAction;
    ActRequestRun: TAction;
    ActRequestRunAll: TAction;
    ActRequestStop: TAction;
    ActRequestNext: TAction;
    ActRequestPrev: TAction;
    ActViewExplorer: TAction;
    ActViewInspector: TAction;
    ActViewDebug: TAction;
    ActViewReset: TAction;
    ActToolsEnv: TAction;
    ActToolsDiag: TAction;
    ActToolsPrefs: TAction;
    ActHelpDocs: TAction;
    ActHelpAbout: TAction;
    
    // Dialogs
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    
    // Main menu
    MainMenu: TMainMenu;
    MenuFile: TMenuItem;
    MenuFileNew: TMenuItem;
    MenuFileOpen: TMenuItem;
    MenuFileSave: TMenuItem;
    MenuFileSaveAs: TMenuItem;
    MenuFileSep1: TMenuItem;
    MenuFileClose: TMenuItem;
    MenuFileSep2: TMenuItem;
    MenuFileExit: TMenuItem;
    
    MenuEdit: TMenuItem;
    MenuEditUndo: TMenuItem;
    MenuEditRedo: TMenuItem;
    MenuEditSep1: TMenuItem;
    MenuEditCut: TMenuItem;
    MenuEditCopy: TMenuItem;
    MenuEditPaste: TMenuItem;
    MenuEditSep2: TMenuItem;
    MenuEditFind: TMenuItem;
    MenuEditReplace: TMenuItem;
    
    MenuRequest: TMenuItem;
    MenuRequestRun: TMenuItem;
    MenuRequestRunAll: TMenuItem;
    MenuRequestStop: TMenuItem;
    MenuRequestSep1: TMenuItem;
    MenuRequestNext: TMenuItem;
    MenuRequestPrev: TMenuItem;
    
    MenuView: TMenuItem;
    MenuViewExplorer: TMenuItem;
    MenuViewInspector: TMenuItem;
    MenuViewDebug: TMenuItem;
    MenuViewSep1: TMenuItem;
    MenuViewReset: TMenuItem;
    
    MenuTools: TMenuItem;
    MenuToolsEnv: TMenuItem;
    MenuToolsDiag: TMenuItem;
    MenuToolsSep1: TMenuItem;
    MenuToolsPrefs: TMenuItem;
    
    MenuHelp: TMenuItem;
    MenuHelpDocs: TMenuItem;
    MenuHelpSep1: TMenuItem;
    MenuHelpAbout: TMenuItem;
    
    // Toolbar
    ToolBar: TToolBar;
    BtnNew: TToolButton;
    BtnOpen: TToolButton;
    BtnSave: TToolButton;
    BtnSep1: TToolButton;
    BtnRun: TToolButton;
    BtnRunAll: TToolButton;
    BtnStop: TToolButton;
    BtnSep2: TToolButton;
    BtnExplorer: TToolButton;
    BtnDebug: TToolButton;
    BtnSep3: TToolButton;
    BtnSettings: TToolButton;
    
    // Tab control
    TabControl: TPageControl;
    
    // Status bar
    StatusBar: TStatusBar;
    
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    
    procedure ActFileNewExecute(Sender: TObject);
    procedure ActFileOpenExecute(Sender: TObject);
    procedure ActFileSaveExecute(Sender: TObject);
    procedure ActFileSaveAsExecute(Sender: TObject);
    procedure ActFileCloseExecute(Sender: TObject);
    procedure ActFileExitExecute(Sender: TObject);
    
    procedure ActEditUndoExecute(Sender: TObject);
    procedure ActEditRedoExecute(Sender: TObject);
    procedure ActEditCutExecute(Sender: TObject);
    procedure ActEditCopyExecute(Sender: TObject);
    procedure ActEditPasteExecute(Sender: TObject);
    procedure ActEditFindExecute(Sender: TObject);
    procedure ActEditReplaceExecute(Sender: TObject);
    
    procedure ActRequestRunExecute(Sender: TObject);
    procedure ActRequestRunAllExecute(Sender: TObject);
    procedure ActRequestStopExecute(Sender: TObject);
    procedure ActRequestNextExecute(Sender: TObject);
    procedure ActRequestPrevExecute(Sender: TObject);
    
    procedure ActViewExplorerExecute(Sender: TObject);
    procedure ActViewInspectorExecute(Sender: TObject);
    procedure ActViewDebugExecute(Sender: TObject);
    procedure ActViewResetExecute(Sender: TObject);
    
    procedure ActToolsEnvExecute(Sender: TObject);
    procedure ActToolsDiagExecute(Sender: TObject);
    procedure ActToolsPrefsExecute(Sender: TObject);
    
    procedure ActHelpDocsExecute(Sender: TObject);
    procedure ActHelpAboutExecute(Sender: TObject);
    
    procedure TabControlChange(Sender: TObject);
    
  private
    FExplorerVisible: Boolean;
    FInspectorVisible: Boolean;
    FDebugVisible: Boolean;
    
    procedure CreateNewWorkspace;
    function GetCurrentWorkspace: THttpWorkspace;
    function GetWorkspace(AIndex: Integer): THttpWorkspace;
    procedure UpdateActions;
    procedure UpdateStatusBar;
    procedure OnWorkspaceModified(ASender: TObject);
    procedure OnWorkspaceStatus(ASender: TObject);
    procedure OnWorkspaceError(ASender: TObject; const AMessage: string);
    procedure SetupColors;
    function PromptSaveChanges(AWorkspace: THttpWorkspace): Boolean;
    procedure CloseWorkspace(AIndex: Integer);
    
  public
    property CurrentWorkspace: THttpWorkspace read GetCurrentWorkspace;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  Math;

const
  // Dark theme colors
  COLOR_BACKGROUND = $252525;
  COLOR_PANEL = $2D2D2D;
  COLOR_PANEL_HEADER = $353535;
  COLOR_TEXT = $E0E0E0;
  COLOR_TEXT_DIM = $909090;
  COLOR_ACCENT = $FFA000;
  COLOR_TOOLBAR = $202020;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'HTTP File Client';
  Width := 1400;
  Height := 900;
  Position := poScreenCenter;
  
  FExplorerVisible := True;
  FInspectorVisible := True;
  FDebugVisible := True;
  
  SetupColors;
  
  // Configure dialogs
  OpenDialog.Filter := 'HTTP Files (*.http)|*.http|All Files (*.*)|*.*';
  OpenDialog.DefaultExt := 'http';
  SaveDialog.Filter := 'HTTP Files (*.http)|*.http|All Files (*.*)|*.*';
  SaveDialog.DefaultExt := 'http';
  
  // Setup keyboard shortcuts
  ActFileNew.ShortCut := KeyToShortCut(VK_N, [ssCtrl]);
  ActFileOpen.ShortCut := KeyToShortCut(VK_O, [ssCtrl]);
  ActFileSave.ShortCut := KeyToShortCut(VK_S, [ssCtrl]);
  ActFileSaveAs.ShortCut := KeyToShortCut(VK_S, [ssCtrl, ssShift]);
  ActFileClose.ShortCut := KeyToShortCut(VK_W, [ssCtrl]);
  ActEditFind.ShortCut := KeyToShortCut(VK_F, [ssCtrl]);
  ActRequestRun.ShortCut := VK_F5;
  ActRequestRunAll.ShortCut := KeyToShortCut(VK_F5, [ssCtrl]);
  
  // Create initial workspace
  CreateNewWorkspace;
  UpdateActions;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I: Integer;
  Workspace: THttpWorkspace;
begin
  CanClose := True;
  
  // Check all tabs for unsaved changes
  for I := TabControl.PageCount - 1 downto 0 do
  begin
    Workspace := GetWorkspace(I);
    if Assigned(Workspace) and Workspace.Modified then
    begin
      TabControl.ActivePageIndex := I;
      if not PromptSaveChanges(Workspace) then
      begin
        CanClose := False;
        Exit;
      end;
    end;
  end;
end;

procedure TMainForm.SetupColors;
begin
  Color := COLOR_BACKGROUND;
  
  // Toolbar
  ToolBar.Color := COLOR_TOOLBAR;
  ToolBar.Height := 36;
  
  // Tab control
  TabControl.Color := COLOR_PANEL;
  TabControl.Font.Color := COLOR_TEXT;
  
  // Status bar
  StatusBar.Color := COLOR_PANEL;
  StatusBar.Font.Color := COLOR_TEXT;
  StatusBar.Panels.Clear;
  StatusBar.Panels.Add; // File name
  StatusBar.Panels.Add; // Status
  StatusBar.Panels.Add; // Line:Col
  StatusBar.Panels[0].Width := 300;
  StatusBar.Panels[1].Width := 200;
  StatusBar.Panels[2].Width := 100;
end;

procedure TMainForm.CreateNewWorkspace;
var
  TabSheet: TTabSheet;
  Workspace: THttpWorkspace;
begin
  TabSheet := TTabSheet.Create(TabControl);
  TabSheet.PageControl := TabControl;
  TabSheet.Caption := 'New File';
  
  Workspace := THttpWorkspace.Create(TabSheet);
  Workspace.MainPanel.Parent := TabSheet;
  Workspace.OnModifiedChanged := @OnWorkspaceModified;
  Workspace.OnStatusChanged := @OnWorkspaceStatus;
  Workspace.OnError := @OnWorkspaceError;
  
  Workspace.ShowExplorer(FExplorerVisible);
  Workspace.ShowInspector(FInspectorVisible);
  Workspace.ShowDebugPanel(FDebugVisible);
  
  Workspace.CreateNew;
  
  TabControl.ActivePage := TabSheet;
  UpdateActions;
  UpdateStatusBar;
end;

function TMainForm.GetCurrentWorkspace: THttpWorkspace;
var
  TabSheet: TTabSheet;
  I: Integer;
begin
  Result := nil;
  TabSheet := TabControl.ActivePage;
  if Assigned(TabSheet) then
  begin
    for I := 0 to TabSheet.ComponentCount - 1 do
    begin
      if TabSheet.Components[I] is THttpWorkspace then
      begin
        Result := THttpWorkspace(TabSheet.Components[I]);
        Break;
      end;
    end;
  end;
end;

function TMainForm.GetWorkspace(AIndex: Integer): THttpWorkspace;
var
  TabSheet: TTabSheet;
  I: Integer;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < TabControl.PageCount) then
  begin
    TabSheet := TabControl.Pages[AIndex];
    for I := 0 to TabSheet.ComponentCount - 1 do
    begin
      if TabSheet.Components[I] is THttpWorkspace then
      begin
        Result := THttpWorkspace(TabSheet.Components[I]);
        Break;
      end;
    end;
  end;
end;

procedure TMainForm.UpdateActions;
var
  Workspace: THttpWorkspace;
  HasFile: Boolean;
  CanExecute: Boolean;
begin
  Workspace := CurrentWorkspace;
  HasFile := Assigned(Workspace);
  CanExecute := HasFile and Assigned(Workspace.Parser) and
    (Length(Workspace.Parser.HttpFile.Endpoints) > 0) and
    not Workspace.IsExecuting;
  
  // File actions
  ActFileSave.Enabled := HasFile and Workspace.Modified;
  ActFileSaveAs.Enabled := HasFile;
  ActFileClose.Enabled := HasFile;
  
  // Edit actions
  ActEditUndo.Enabled := HasFile and Workspace.Editor.CanUndo;
  ActEditRedo.Enabled := HasFile and Workspace.Editor.CanRedo;
  ActEditCut.Enabled := HasFile and Workspace.Editor.SelAvail;
  ActEditCopy.Enabled := HasFile and Workspace.Editor.SelAvail;
  ActEditPaste.Enabled := HasFile and Workspace.Editor.CanPaste;
  ActEditFind.Enabled := HasFile;
  ActEditReplace.Enabled := HasFile;
  
  // Request actions
  ActRequestRun.Enabled := CanExecute and (Workspace.CurrentEndpointIndex >= 0);
  ActRequestRunAll.Enabled := CanExecute;
  ActRequestStop.Enabled := HasFile and Workspace.IsExecuting;
  ActRequestNext.Enabled := CanExecute and 
    (Workspace.CurrentEndpointIndex < Length(Workspace.Parser.HttpFile.Endpoints) - 1);
  ActRequestPrev.Enabled := CanExecute and (Workspace.CurrentEndpointIndex > 0);
end;

procedure TMainForm.UpdateStatusBar;
var
  Workspace: THttpWorkspace;
  StatusText: string;
begin
  Workspace := CurrentWorkspace;
  
  if Assigned(Workspace) then
  begin
    // File name
    if Workspace.FilePath <> '' then
      StatusBar.Panels[0].Text := ' ' + ExtractFileName(Workspace.FilePath)
    else
      StatusBar.Panels[0].Text := ' Untitled';
      
    if Workspace.Modified then
      StatusBar.Panels[0].Text := StatusBar.Panels[0].Text + ' *';
    
    // Status
    if Workspace.IsExecuting then
      StatusText := 'Executing...'
    else if Assigned(Workspace.Parser) then
    begin
      StatusText := Format('%d request(s)', [Length(Workspace.Parser.HttpFile.Endpoints)]);
      if Workspace.Parser.Errors.ErrorCount > 0 then
        StatusText := StatusText + Format(', %d error(s)', [Workspace.Parser.Errors.ErrorCount]);
    end
    else
      StatusText := 'Ready';
      
    StatusBar.Panels[1].Text := ' ' + StatusText;
    
    // Line and column
    StatusBar.Panels[2].Text := Format(' Ln %d, Col %d', 
      [Workspace.Editor.CaretY, Workspace.Editor.CaretX]);
  end
  else
  begin
    StatusBar.Panels[0].Text := '';
    StatusBar.Panels[1].Text := '';
    StatusBar.Panels[2].Text := '';
  end;
end;

procedure TMainForm.OnWorkspaceModified(ASender: TObject);
var
  Workspace: THttpWorkspace;
  TabSheet: TTabSheet;
  I: Integer;
begin
  if ASender is THttpWorkspace then
  begin
    Workspace := THttpWorkspace(ASender);
    
    // Find and update tab caption
    for I := 0 to TabControl.PageCount - 1 do
    begin
      TabSheet := TabControl.Pages[I];
      if GetWorkspace(I) = Workspace then
      begin
        if Workspace.FilePath <> '' then
          TabSheet.Caption := ExtractFileName(Workspace.FilePath)
        else
          TabSheet.Caption := 'New File';
          
        if Workspace.Modified then
          TabSheet.Caption := TabSheet.Caption + ' *';
          
        Break;
      end;
    end;
  end;
  
  UpdateActions;
  UpdateStatusBar;
end;

procedure TMainForm.OnWorkspaceStatus(ASender: TObject);
begin
  UpdateActions;
  UpdateStatusBar;
end;

procedure TMainForm.OnWorkspaceError(ASender: TObject; const AMessage: string);
begin
  MessageDlg('Error', AMessage, mtError, [mbOK], 0);
end;

function TMainForm.PromptSaveChanges(AWorkspace: THttpWorkspace): Boolean;
var
  Res: TModalResult;
  FileName: string;
begin
  Result := True;
  
  if AWorkspace.FilePath <> '' then
    FileName := ExtractFileName(AWorkspace.FilePath)
  else
    FileName := 'Untitled';
  
  Res := MessageDlg('Save Changes',
    Format('Do you want to save changes to "%s"?', [FileName]),
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  
  case Res of
    mrYes:
      begin
        if AWorkspace.FilePath <> '' then
          Result := AWorkspace.Save
        else
        begin
          SaveDialog.FileName := '';
          if SaveDialog.Execute then
            Result := AWorkspace.SaveToFile(SaveDialog.FileName)
          else
            Result := False;
        end;
      end;
    mrNo:
      Result := True;
    mrCancel:
      Result := False;
  end;
end;

procedure TMainForm.CloseWorkspace(AIndex: Integer);
var
  TabSheet: TTabSheet;
begin
  if (AIndex >= 0) and (AIndex < TabControl.PageCount) then
  begin
    TabSheet := TabControl.Pages[AIndex];
    TabSheet.Free;
    
    if TabControl.PageCount = 0 then
      CreateNewWorkspace;
      
    UpdateActions;
    UpdateStatusBar;
  end;
end;

// File Actions

procedure TMainForm.ActFileNewExecute(Sender: TObject);
begin
  CreateNewWorkspace;
end;

procedure TMainForm.ActFileOpenExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
  I: Integer;
begin
  if OpenDialog.Execute then
  begin
    // Check if file is already open
    for I := 0 to TabControl.PageCount - 1 do
    begin
      Workspace := GetWorkspace(I);
      if Assigned(Workspace) and (Workspace.FilePath = OpenDialog.FileName) then
      begin
        TabControl.ActivePageIndex := I;
        Exit;
      end;
    end;
    
    // Check if current workspace is empty and unmodified
    Workspace := CurrentWorkspace;
    if Assigned(Workspace) and (Workspace.FilePath = '') and
       not Workspace.Modified and (Workspace.Editor.Lines.Count <= 3) then
    begin
      // Reuse current tab
      Workspace.LoadFromFile(OpenDialog.FileName);
      TabControl.ActivePage.Caption := ExtractFileName(OpenDialog.FileName);
    end
    else
    begin
      // Create new tab
      CreateNewWorkspace;
      Workspace := CurrentWorkspace;
      if Assigned(Workspace) then
      begin
        Workspace.LoadFromFile(OpenDialog.FileName);
        TabControl.ActivePage.Caption := ExtractFileName(OpenDialog.FileName);
      end;
    end;
    
    UpdateActions;
    UpdateStatusBar;
  end;
end;

procedure TMainForm.ActFileSaveExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if not Assigned(Workspace) then
    Exit;
  
  if Workspace.FilePath <> '' then
    Workspace.Save
  else
    ActFileSaveAs.Execute;
end;

procedure TMainForm.ActFileSaveAsExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if not Assigned(Workspace) then
    Exit;
  
  if Workspace.FilePath <> '' then
    SaveDialog.FileName := Workspace.FilePath
  else
    SaveDialog.FileName := '';
  
  if SaveDialog.Execute then
  begin
    if Workspace.SaveToFile(SaveDialog.FileName) then
    begin
      TabControl.ActivePage.Caption := ExtractFileName(SaveDialog.FileName);
      UpdateActions;
      UpdateStatusBar;
    end;
  end;
end;

procedure TMainForm.ActFileCloseExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if not Assigned(Workspace) then
    Exit;
  
  if Workspace.Modified then
  begin
    if not PromptSaveChanges(Workspace) then
      Exit;
  end;
  
  CloseWorkspace(TabControl.ActivePageIndex);
end;

procedure TMainForm.ActFileExitExecute(Sender: TObject);
begin
  Close;
end;

// Edit Actions

procedure TMainForm.ActEditUndoExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
    Workspace.Editor.Undo;
end;

procedure TMainForm.ActEditRedoExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
    Workspace.Editor.Redo;
end;

procedure TMainForm.ActEditCutExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
    Workspace.Editor.CutToClipboard;
end;

procedure TMainForm.ActEditCopyExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
    Workspace.Editor.CopyToClipboard;
end;

procedure TMainForm.ActEditPasteExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
    Workspace.Editor.PasteFromClipboard;
end;

procedure TMainForm.ActEditFindExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
  begin
    // TSynEdit doesn't have SearchEngine in this version
    // User can use Ctrl+F in the IDE or we'd need to implement a dialog
    ShowMessage('Find: Use Ctrl+F when focus is in the editor');
  end;
end;

procedure TMainForm.ActEditReplaceExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
  begin
    // TSynEdit doesn't have SearchEngine in this version
    ShowMessage('Replace: Use Ctrl+H when focus is in the editor');
  end;
end;

// Request Actions

procedure TMainForm.ActRequestRunExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
  begin
    // Re-parse before execution to ensure we have latest source
    Workspace.Parse;
    Workspace.ExecuteCurrentRequest;
  end;
end;

procedure TMainForm.ActRequestRunAllExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
  begin
    Workspace.Parse;
    Workspace.ExecuteAllRequests;
  end;
end;

procedure TMainForm.ActRequestStopExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
    Workspace.StopExecution;
end;

procedure TMainForm.ActRequestNextExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) and Assigned(Workspace.Parser) then
  begin
    if Workspace.CurrentEndpointIndex < Length(Workspace.Parser.HttpFile.Endpoints) - 1 then
    begin
      // Would need to update tree selection - simplified for now
      ShowMessage('Use tree view to select next request');
    end;
  end;
end;

procedure TMainForm.ActRequestPrevExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) and Assigned(Workspace.Parser) then
  begin
    if Workspace.CurrentEndpointIndex > 0 then
    begin
      ShowMessage('Use tree view to select previous request');
    end;
  end;
end;

// View Actions

procedure TMainForm.ActViewExplorerExecute(Sender: TObject);
var
  I: Integer;
  Workspace: THttpWorkspace;
begin
  FExplorerVisible := not FExplorerVisible;
  
  for I := 0 to TabControl.PageCount - 1 do
  begin
    Workspace := GetWorkspace(I);
    if Assigned(Workspace) then
      Workspace.ShowExplorer(FExplorerVisible);
  end;
end;

procedure TMainForm.ActViewInspectorExecute(Sender: TObject);
var
  I: Integer;
  Workspace: THttpWorkspace;
begin
  FInspectorVisible := not FInspectorVisible;
  
  for I := 0 to TabControl.PageCount - 1 do
  begin
    Workspace := GetWorkspace(I);
    if Assigned(Workspace) then
      Workspace.ShowInspector(FInspectorVisible);
  end;
end;

procedure TMainForm.ActViewDebugExecute(Sender: TObject);
var
  I: Integer;
  Workspace: THttpWorkspace;
begin
  FDebugVisible := not FDebugVisible;
  
  for I := 0 to TabControl.PageCount - 1 do
  begin
    Workspace := GetWorkspace(I);
    if Assigned(Workspace) then
      Workspace.ShowDebugPanel(FDebugVisible);
  end;
end;

procedure TMainForm.ActViewResetExecute(Sender: TObject);
var
  I: Integer;
  Workspace: THttpWorkspace;
begin
  FExplorerVisible := True;
  FInspectorVisible := True;
  FDebugVisible := True;
  
  for I := 0 to TabControl.PageCount - 1 do
  begin
    Workspace := GetWorkspace(I);
    if Assigned(Workspace) then
    begin
      Workspace.ShowExplorer(True);
      Workspace.ShowInspector(True);
      Workspace.ShowDebugPanel(True);
    end;
  end;
end;

// Tools Actions

procedure TMainForm.ActToolsEnvExecute(Sender: TObject);
begin
  ShowMessage('Environment Variables dialog - To be implemented');
end;

procedure TMainForm.ActToolsDiagExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
  Msg: string;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) and Assigned(Workspace.Parser) then
  begin
    Msg := Format('Parser Diagnostics:' + LineEnding +
      'Endpoints: %d' + LineEnding +
      'Variables: %d' + LineEnding +
      'Errors: %d' + LineEnding +
      'Warnings: %d',
      [Length(Workspace.Parser.HttpFile.Endpoints),
       Length(Workspace.Parser.HttpFile.Variables),
       Workspace.Parser.Errors.ErrorCount,
       Workspace.Parser.Errors.WarningCount]);
    ShowMessage(Msg);
  end;
end;

procedure TMainForm.ActToolsPrefsExecute(Sender: TObject);
begin
  ShowMessage('Preferences dialog - To be implemented');
end;

// Help Actions

procedure TMainForm.ActHelpDocsExecute(Sender: TObject);
begin
  ShowMessage('Documentation - To be implemented');
end;

procedure TMainForm.ActHelpAboutExecute(Sender: TObject);
begin
  ShowMessage('HTTP File Client' + LineEnding + LineEnding +
    'A modern REST client for .http files' + LineEnding +
    'Built with FreePascal and Lazarus LCL');
end;

procedure TMainForm.TabControlChange(Sender: TObject);
begin
  UpdateActions;
  UpdateStatusBar;
end;

end.
