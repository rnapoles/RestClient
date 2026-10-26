# Modern REST Client for Lazarus and FreePascal

A sleek, futuristic desktop REST client built with FreePascal and Lazarus LCL for working with `.http` files.

## Features

### Core Functionality
- ✅ Multi-file workspace with tabbed interface
- ✅ Parse and execute `.http` files
- ✅ Full integration with existing `THttpFileParser` and `TRequestExecutor`
- ✅ AST visualization with request explorer tree
- ✅ Live syntax editing with `TSynEdit`
- ✅ Response inspection (body, headers, resolved request, debug info)
- ✅ Variable substitution and response references
- ✅ Sequential request execution with dependency handling
- ✅ Dark developer-focused UI theme

### User Interface

#### Main Window
- **Menu Bar**: Complete menu system (File, Edit, Request, View, Tools, Help)
- **Toolbar**: Quick access to frequently used commands
- **Status Bar**: Shows file name, parse status, line/column position
- **Tab Control**: Multiple open `.http` files with independent state

#### Request Explorer (Left Panel)
- Hierarchical tree view of parsed HTTP file
- Shows endpoints with method, URL, and name
- Displays parse errors with line numbers
- Click to navigate to source
- Double-click to execute request

#### Source Editor (Center Panel)
- Syntax highlighting for `.http` files
- Line numbers and current line highlighting
- Search and replace functionality
- Undo/redo support
- Dirty state tracking

#### Response Inspector (Right Panel)
- **Response Tab**: Formatted response body
- **Headers Tab**: Status line and response headers
- **Request Tab**: Resolved outgoing request details
- **Debug Tab**: Execution log with timestamps and severity levels
- Status panel showing HTTP status code with color coding

### Dark Theme
- Background: Dark graphite (#252525)
- Panels: Charcoal (#2D2D2D)
- Accent: Cyan/teal (#FFA000)
- Success: Green (#00AA00)
- Warning: Amber (#00AAFF)
- Error: Red (#4444FF)
- High-contrast text for readability

## Architecture

### Component Structure
```
TMainForm
├── TActionList (centralized actions)
├── TMainMenu (File, Edit, Request, View, Tools, Help)
├── TToolBar (quick access buttons)
├── TPageControl (tabbed workspaces)
│   ├── TTabSheet (per file)
│   │   └── THttpWorkspace
│   │       ├── Request Explorer (TLazVirtualStringTree)
│   │       ├── Source Editor (TSynEdit)
│   │       └── Inspector (TPageControl)
│   │           ├── Response Body
│   │           ├── Response Headers
│   │           ├── Resolved Request
│   │           └── Debug Console
│   └── ... (additional tabs)
├── TOpenDialog
├── TSaveDialog
└── TStatusBar
```

### Key Classes

#### `THttpWorkspace`
Encapsulates a single `.http` file's complete state:
- File path and modified flag
- `THttpFileParser` instance
- `TCurlRequestExecutor` instance
- UI components (explorer, editor, inspector, debug)
- Current endpoint selection
- Execution state

**Responsibilities**:
- Loading and saving files
- Parsing HTTP source
- Executing requests
- Updating UI based on parser/executor state
- Managing component lifecycle

#### `TMainForm`
Main application window:
- Manages multiple workspaces
- Coordinates file operations (New, Open, Save, Close)
- Updates action states based on current workspace
- Handles unsaved changes on exit
- Maintains global view state (explorer, inspector, debug visibility)

## Integration with Existing Parser

The application uses the existing parser infrastructure:

### Parser (`THttpFileParser`)
```pascal
THttpFileParser = class
  constructor Create(const AInput: string);
  procedure Parse;
  property HttpFile: THttpFile;
  property Errors: THttpParseErrorList;
  property Responses: THttpResponseStore;
  property BaseDirectory: string;
end;
```

### AST Model (`HttpFileAST.pas`)
- `THttpFile`: Contains variables and endpoints
- `TVariable`: Variable declarations
- `TEndpoint`: Request with verb, URL, headers, body
- `TRequestHeader`/`TResponseHeader`: HTTP headers
- `THttpParseError`: Parse diagnostics

### Executor (`TRequestExecutor`, `TCurlRequestExecutor`)
```pascal
TRequestExecutor = class
  constructor Create(AParser: THttpFileParser);
  function ExecuteAt(AIndex: Integer): THttpResponse;
  function Execute(const ARequestName: string): THttpResponse;
  procedure ExecuteAll;
  property LastResponse: THttpResponse;
  property OnExecuted: TRequestExecutedEvent;
end;
```

## Build Instructions

### Prerequisites
1. **FreePascal Compiler**: Version 3.2.2 or later
2. **Lazarus IDE**: Version 2.2.0 or later
3. **Required Packages**:
   - LCL (Lazarus Component Library) - included with Lazarus
   - SynEdit - included with Lazarus
   - laz.VirtualTrees (VirtualTreeView) - included with Lazarus

### Building in Lazarus IDE
1. Open Lazarus IDE
2. Open `RestClient.lpi` project file
3. Ensure all required packages are installed:
   - Open **Package** → **Install/Uninstall Packages**
   - Verify `laz.virtualtreeview_package` and `SynEditDsgn` are installed
4. Select **Run** → **Build** (or press Shift+F9)
5. Select **Run** → **Run** (or press F9) to launch

### Building from Command Line
```bash
# Windows
lazbuild --build-mode=Default RestClient.lpi

# Linux/macOS
lazbuild --build-mode=Default RestClient.lpi
```

The compiled executable will be in the project directory:
- Windows: `RestClient.exe`
- Linux: `RestClient`
- macOS: `RestClient.app`

### Build Troubleshooting

**Missing libcurl at runtime**:
- Windows: Place `libcurl.dll` in the same directory as the executable
- Linux: Install libcurl: `sudo apt-get install libcurl4`
- macOS: Install via Homebrew: `brew install curl`

**Package not found errors**:
- Ensure `laz.virtualtreeview_package` is installed
- Rebuild Lazarus IDE if packages were just installed

**Unit search path errors**:
- The project includes `libs`, `libs/jsonpath`, and `libs/libcurl` in search paths
- Verify these directories exist relative to the project file

## Usage

### Opening Files
1. **File** → **Open** (Ctrl+O)
2. Select an `.http` file
3. The file is parsed and the AST displayed in the explorer

### Editing Requests
1. Edit source in the center panel
2. Changes are tracked (modified indicator: `*`)
3. Parser updates are triggered by execution or explicit reparse

### Executing Requests
1. Select a request in the explorer tree
2. Click **Run** button or press **F5**
3. Response appears in the inspector panel
4. Debug log shows execution details

### Sequential Execution
1. Click **Run All** (Ctrl+F5)
2. Requests execute in order
3. Response references are resolved automatically
4. Execution log shows progress

### Viewing Responses
- **Response tab**: Shows response body (auto-formatted JSON)
- **Headers tab**: Shows status line and headers
- **Request tab**: Shows the resolved request sent
- **Debug tab**: Shows execution timeline and errors

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| `Ctrl+N` | New file |
| `Ctrl+O` | Open file |
| `Ctrl+S` | Save file |
| `Ctrl+Shift+S` | Save As |
| `Ctrl+W` | Close tab |
| `Ctrl+F` | Find |
| `F5` | Run current request |
| `Ctrl+F5` | Run all requests |

## File Format

The application parses standard `.http` files:

```http
@baseUrl = https://api.example.com
@token = {{$dotenv API_TOKEN}}

### Get Users
GET {{baseUrl}}/api/users
Authorization: Bearer {{token}}
Accept: application/json

### Create User
# @name createUser
POST {{baseUrl}}/api/users
Content-Type: application/json
Authorization: Bearer {{token}}

{
  "name": "Alice",
  "email": "alice@example.com"
}

### Get Created User
GET {{baseUrl}}/api/users/{{createUser.response.body.$.id}}
Authorization: Bearer {{token}}
```

Features supported:
- Variable declarations: `@name = value`
- Variable references: `{{name}}`
- Functions: `{{$timestamp}}, {{$randomInt}}, {{$dotenv NAME}}`
- Response references: `{{requestName.response.headers.X}}`
- JSONPath selectors: `{{requestName.response.body.$.path.to.value}}`
- Request naming: `# @name requestName`
- Request titles: `### Title`
- File bodies: `< path/to/file.json`

## Known Limitations

1. **Cancellation**: Request cancellation is not fully implemented (libcurl limitation)
2. **Threading**: Execution is synchronous; the UI may freeze during long requests
3. **Large files**: Very large response bodies may impact performance
4. **Syntax highlighting**: Uses simple highlighter; a custom HTTP highlighter would enhance clarity
5. **Tree refresh**: Tree rebuilds on parse; selection state is not preserved

## Future Enhancements

### High Priority
- [ ] Async execution with progress callbacks
- [ ] Request cancellation support
- [ ] Custom syntax highlighter for `.http` files
- [ ] Pretty-print JSON responses
- [ ] Response size and timing metrics
- [ ] Copy response/request buttons

### Medium Priority
- [ ] Environment variable editor dialog
- [ ] Preferences dialog (timeout, TLS, user agent)
- [ ] Request history per file
- [ ] Export to cURL, Postman collection
- [ ] Dark theme customization

### Low Priority
- [ ] Multiple color themes
- [ ] Request templates
- [ ] Code generation from responses
- [ ] Response diff viewer
- [ ] WebSocket support

## Code Organization

### Main Units
- **MainFormUnit.pas**: Main application window, menu, toolbar, tabs
- **HttpWorkspace.pas**: Per-file workspace controller and UI
- **RestClient.lpr**: Application entry point

### Parser Libraries (libs/)
- **HttpFileParser.pas**: Main parser
- **HttpFileAST.pas**: AST model (THttpFile, TEndpoint, TVariable)
- **HttpFileExecutor.pas**: Abstract executor
- **CurlRequestExecutor.pas**: libcurl-based executor
- **HttpFileResponses.pas**: Response storage
- **HttpFileLexer.pas**: Tokenizer
- **HttpFileInterpolator.pas**: Variable and expression resolution
- **HttpFileFunctions.pas**: Built-in functions
- **HttpFileReferences.pas**: Response reference resolution
- **jsonpath/**: JSONPath query implementation

## Testing Recommendations

### Manual Testing Checklist
- [ ] Open multiple `.http` files in separate tabs
- [ ] Edit and save files (check dirty state)
- [ ] Parse files with errors (verify error display)
- [ ] Execute single request (check response display)
- [ ] Execute all requests (verify sequential execution)
- [ ] Use response references (verify chaining)
- [ ] Toggle explorer, inspector, debug panels
- [ ] Close tabs with unsaved changes (verify prompt)
- [ ] Exit application with unsaved changes (verify prompt)
- [ ] Resize panels with splitters
- [ ] Test keyboard shortcuts
- [ ] Test Find/Replace
- [ ] Verify status bar updates

### Integration Testing
- [ ] Test with files using `.env` variables
- [ ] Test with file body references (`< file.json`)
- [ ] Test with different HTTP methods (GET, POST, PUT, DELETE, PATCH)
- [ ] Test with authentication (Bearer, Basic)
- [ ] Test with various response types (JSON, XML, HTML, plain text)
- [ ] Test error conditions (network failure, invalid URL, timeout)

## Contributing

This implementation follows Lazarus and FreePascal conventions:
- Uses `{$mode objfpc}{$H+}` for compatibility
- Follows LCL component ownership model
- Uses event-driven architecture
- Separates UI from business logic

When extending:
1. Keep parser and executor as separate concerns
2. Maintain workspace independence (no shared state between tabs)
3. Update actions centrally in `TMainForm.UpdateActions`
4. Use the workspace's event handlers for notifications
5. Test resource cleanup (no memory leaks on tab close)

## License

This project uses the existing HTTP file parser and executor libraries.
Refer to the original project's license for terms.

## Support

For issues with:
- **Parser**: Check `HttpFileParser.pas` and `HttpFileLexer.pas`
- **Execution**: Check `HttpFileExecutor.pas` and `CurlRequestExecutor.pas`
- **UI**: Check `MainFormUnit.pas` and `HttpWorkspace.pas`
- **Build**: Verify Lazarus packages and search paths

---

**Version**: 1.0.0  
**Built with**: FreePascal 3.2.2, Lazarus 2.2.0  
**Platform**: Windows, Linux, macOS (x86_64, ARM64)
