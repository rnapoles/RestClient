# Quick Start Guide - HTTP File Client

## For Users

### Opening the Application
1. Double-click `RestClient.exe` (Windows) or run `RestClient` (Linux/macOS)
2. The application opens with a new empty HTTP file

### Loading an Example
1. Click **File** → **Open** (or press `Ctrl+O`)
2. Navigate to the project directory
3. Select `example.http`
4. The file loads and parses automatically

### Executing Requests
1. Look at the **Request Explorer** panel on the left
2. Click on **"Get All Posts"**
3. The editor jumps to that request
4. Click the **Run** button in the toolbar (or press `F5`)
5. The response appears in the **Inspector** panel on the right

### Viewing Responses
- **Response tab**: Shows the response body (JSON, HTML, text, etc.)
- **Headers tab**: Shows HTTP status line and response headers
- **Request tab**: Shows the actual request that was sent
- **Debug tab**: Shows execution log with timestamps

### Executing Multiple Requests
1. Click **Request** → **Run All** (or press `Ctrl+F5`)
2. Watch the debug panel as requests execute sequentially
3. Responses are stored and can be referenced by later requests

### Editing and Saving
1. Edit the HTTP file in the center panel
2. Modified files show `*` in the tab caption
3. Press `Ctrl+S` to save
4. Use `Ctrl+Shift+S` for Save As

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| `Ctrl+N` | New file |
| `Ctrl+O` | Open file |
| `Ctrl+S` | Save |
| `F5` | Run selected request |
| `Ctrl+F5` | Run all requests |
| `Ctrl+F` | Find in editor |
| `Ctrl+W` | Close current tab |

## For Developers

### Building from Source

#### Prerequisites
```bash
# Windows (using Chocolatey)
choco install lazarus

# Ubuntu/Debian
sudo apt-get install lazarus lcl-units

# macOS (using Homebrew)
brew install lazarus
```

#### Required Packages (usually included with Lazarus)
- LCL (Lazarus Component Library)
- SynEdit
- laz.VirtualTrees (VirtualTreeView)

#### libcurl Runtime
```bash
# Windows: Download libcurl.dll from https://curl.se/windows/
# Place in same directory as executable

# Ubuntu/Debian
sudo apt-get install libcurl4

# macOS
brew install curl
```

### Building in Lazarus IDE

1. **Open Project**
   ```
   Lazarus IDE → Project → Open Project
   Select: RestClient.lpi
   ```

2. **Install Packages** (if prompted)
   ```
   Package → Install/Uninstall Packages
   Add: laz.virtualtreeview_package
   Add: SynEditDsgn
   Click: Save and rebuild IDE
   ```

3. **Build**
   ```
   Run → Build (Shift+F9)
   ```

4. **Run**
   ```
   Run → Run (F9)
   ```

### Building from Command Line

```bash
# Navigate to project directory
cd RestClient

# Build release version
lazbuild --build-mode=Default RestClient.lpi

# Build debug version
lazbuild --build-mode=Debug RestClient.lpi

# Run
./RestClient
```

### Project Structure

```
RestClient/
├── MainFormUnit.pas         # Main window, menus, toolbars
├── HttpWorkspace.pas        # Per-file workspace controller
├── libs/                    # Parser and executor
│   ├── HttpFileParser.pas   # Main parser
│   ├── HttpFileExecutor.pas # Abstract executor
│   └── CurlRequestExecutor.pas # libcurl implementation
└── example.http             # Sample HTTP file
```

### Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  TMainForm                      │
│  ┌────────────┬──────────────┬──────────────┐  │
│  │   Tab 1    │    Tab 2     │    Tab 3     │  │
│  └────────────┴──────────────┴──────────────┘  │
│         │              │              │         │
│    ┌────▼─────┐   ┌───▼──────┐  ┌───▼──────┐  │
│    │Workspace │   │Workspace │  │Workspace │  │
│    │          │   │          │  │          │  │
│    │ Parser   │   │ Parser   │  │ Parser   │  │
│    │ Executor │   │ Executor │  │ Executor │  │
│    │ UI       │   │ UI       │  │ UI       │  │
│    └──────────┘   └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────┘
```

Each workspace is independent:
- Own parser instance
- Own executor instance
- Own UI state
- Own file path

### Key Events Flow

**Opening a File:**
```
User → File→Open
  → TMainForm.ActFileOpenExecute
    → Create THttpWorkspace
      → THttpWorkspace.LoadFromFile
        → Load text into editor
        → THttpFileParser.Create
        → THttpFileParser.Parse
        → Populate tree view
```

**Executing a Request:**
```
User → Run button (F5)
  → TMainForm.ActRequestRunExecute
    → THttpWorkspace.Parse (re-parse latest source)
    → THttpWorkspace.ExecuteCurrentRequest
      → TCurlRequestExecutor.ExecuteAt
        → HTTP request via libcurl
        → THttpResponse returned
        → Store in parser.Responses
        → Reparse (for response references)
      → Update inspector UI
      → Log to debug panel
```

### Extending the Application

#### Adding a New Menu Action
```pascal
// 1. Add action to ActionList
ActMyAction: TAction;

// 2. Set properties
ActMyAction.Caption := '&My Action';
ActMyAction.ShortCut := TextToShortCut('Ctrl+M');
ActMyAction.OnExecute := @ActMyActionExecute;

// 3. Implement handler
procedure TMainForm.ActMyActionExecute(Sender: TObject);
var
  Workspace: THttpWorkspace;
begin
  Workspace := CurrentWorkspace;
  if Assigned(Workspace) then
  begin
    // Your code here
  end;
end;

// 4. Add menu item in Form Designer
MenuEdit → Add item → Set Action property
```

#### Adding Response Formatting
```pascal
// In HttpWorkspace.pas, modify UpdateInspector
procedure THttpWorkspace.UpdateInspector;
begin
  // ... existing code ...
  
  // Add JSON formatting
  if IsJsonResponse(Response) then
    FResponseEditor.Lines.Text := FormatJson(Response.Body)
  else
    FResponseEditor.Lines.Text := Response.Body;
end;
```

#### Adding Custom Syntax Highlighting
```pascal
// Create new unit: HttpHighlighter.pas
type
  THttpHighlighter = class(TSynCustomHighlighter)
  // Implement highlighting for HTTP syntax
  end;

// In HttpWorkspace.SetupEditor
FHighlighter := THttpHighlighter.Create(Self);
FEditor.Highlighter := FHighlighter;
```

### Common Customizations

#### Changing Theme Colors
Edit `HttpWorkspace.pas` constants:
```pascal
const
  COLOR_BACKGROUND = $252525;   // Your color
  COLOR_ACCENT = $FFA000;       // Your accent
  // ... etc
```

#### Changing Default Timeouts
```pascal
// In HttpWorkspace.Parse, after creating executor:
FExecutor.TimeoutSeconds := 120;  // Default: 60
FExecutor.ConnectTimeoutSeconds := 45;  // Default: 30
```

#### Changing Default Font
```pascal
// In HttpWorkspace.SetupEditor:
FEditor.Font.Name := 'JetBrains Mono';
FEditor.Font.Size := 11;
```

### Debugging Tips

#### Enable Debug Logging
The debug panel shows execution flow. To add more logging:
```pascal
// In any workspace method
AddDebugMessage('My debug message', hsInfo);
AddDebugMessage('Warning message', hsWarning);
AddDebugMessage('Error message', hsError);
```

#### Inspecting Parser State
```pascal
// In TMainForm.ActToolsDiagExecute
ShowMessage(
  'Endpoints: ' + IntToStr(Length(Workspace.Parser.HttpFile.Endpoints)) + LineEnding +
  'Variables: ' + IntToStr(Length(Workspace.Parser.HttpFile.Variables))
);
```

#### Checking Executor Configuration
```pascal
// Add to ActToolsDiagExecute
ShowMessage(
  'Timeout: ' + IntToStr(Workspace.Executor.TimeoutSeconds) + 's' + LineEnding +
  'Follow Redirects: ' + BoolToStr(Workspace.Executor.FollowRedirects, True)
);
```

### Testing

#### Unit Test Structure (Recommended)
```pascal
unit HttpWorkspaceTests;

uses
  TestFramework, HttpWorkspace;

type
  THttpWorkspaceTest = class(TTestCase)
  published
    procedure TestCreateNew;
    procedure TestLoadFile;
    procedure TestParseValidFile;
    procedure TestExecuteRequest;
  end;

implementation

procedure THttpWorkspaceTest.TestCreateNew;
var
  Workspace: THttpWorkspace;
begin
  Workspace := THttpWorkspace.Create(nil);
  try
    Workspace.CreateNew;
    CheckTrue(Workspace.Editor.Lines.Count > 0);
    CheckFalse(Workspace.Modified);
  finally
    Workspace.Free;
  end;
end;
```

### Troubleshooting

#### Problem: "Package laz.virtualtreeview not found"
**Solution:**
```
Lazarus IDE → Package → Open Package File (.lpk)
Navigate to: lazarus/components/virtualtreeview/laz.virtualtreeview_package.lpk
Click: Compile
Click: Use → Add to Project
```

#### Problem: "Unit HttpFileParser not found"
**Solution:** Check project search paths
```
Project → Project Options → Compiler Options
→ Paths → Other Unit Files
Should include: libs;libs\jsonpath;libs\libcurl
```

#### Problem: "libcurl.dll not found" (Windows runtime)
**Solution:**
1. Download from https://curl.se/windows/
2. Extract libcurl.dll (or libcurl-x64.dll)
3. Place in same directory as RestClient.exe
4. Or add to System PATH

#### Problem: Application crashes on request execution
**Solution:** Check libcurl initialization
```pascal
// In HttpWorkspace.ExecuteCurrentRequest, add try-except:
try
  FExecutor.ExecuteAt(FCurrentEndpointIndex);
except
  on E: Exception do
  begin
    AddDebugMessage('Execution error: ' + E.Message, hsError);
    ShowMessage('Request failed: ' + E.Message);
  end;
end;
```

### Performance Optimization

#### For Large Files (>10,000 lines)
- Debounce parsing: Don't parse on every keystroke
- Consider lazy tree population
- Use streaming for huge responses

#### For Many Requests (>100 endpoints)
- Implement virtual tree more efficiently
- Consider pagination in tree
- Add progress indicator for Run All

### Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly (see Testing section)
4. Ensure no memory leaks (use Heaptrc)
5. Update documentation
6. Submit pull request

### Resources

- **Lazarus Documentation**: https://wiki.freepascal.org/Lazarus_Documentation
- **SynEdit Documentation**: https://wiki.freepascal.org/SynEdit
- **VirtualTreeView**: https://github.com/blikblum/VirtualTreeView-Lazarus
- **libcurl**: https://curl.se/libcurl/
- **HTTP File Format**: Based on JetBrains HTTP Client format

### Support

- **Issues**: Check existing issues first
- **Documentation**: See README_REST_CLIENT.md
- **Examples**: Use example.http as template
- **Parser Issues**: Check libs/HttpFileParser.pas

---

**Last Updated**: 2026-10-25  
**Version**: 1.0.0  
**FreePascal**: 3.2.2+  
**Lazarus**: 2.2.0+
