# ClamAV Daemon (clamd) Socket Commands

**Reference:** `man clamd`, https://docs.clamav.net/manual/Usage/Scanning.html#clamd

---

## Protocol Overview

### Command Delimiters

ClamD supports two command termination methods:

| Prefix | Example | Delimiter | Description |
|--------|---------|-----------|-------------|
| (none) | `PING` | Newline (`\n`) | Default behavior |
| `n` | `nPING` | Newline (`\n`) | Explicit newline delimiter |
| `z` | `zPING` | NULL (`\0`) | NULL delimiter (recommended) |

**Recommendation:** Use `z` prefix for commands to ensure proper parsing, especially for commands with arguments.

---

## Available Commands

### Connection Management

#### PING
Check if daemon is responding.
```
Command: PING (or zPING)
Response: PONG
```

#### VERSION
Get ClamAV version information.
```
Command: VERSION (or zVERSION)
Response: ClamAV X.X.X/SIGNATURES
Example: ClamAV 1.0.3/27154
```

#### VERSIONCOMMANDS
Get supported commands list.
```
Command: zVERSIONCOMMANDS
Response: X.X.X | COMMANDS: PING VERSION SCAN ...
```

#### SHUTDOWN
Gracefully shutdown the daemon.
```
Command: SHUTDOWN (or zSHUTDOWN)
Response: SHUTDOWN
Note: Connection closed immediately after
```

#### RELOAD
Reload virus database signatures.
```
Command: RELOAD (or zRELOAD)
Response: RELOADING
```

#### STATS
Get daemon statistics (queue, memory, etc.).
```
Command: zSTATS
Response: Multi-line statistics
Format: Subject to change between versions
```

---

### Scanning Commands

#### SCAN
Scan file or directory recursively with archive support. Stops on first virus found.
```
Command: zSCAN /path/to/file
Response: /path/to/file: OK
Response: /path/to/file: VirusName FOUND
Response: /path/to/file: ERROR: error_message
```

#### CONTSCAN
Scan recursively but do NOT stop when virus is found (reports all threats).
```
Command: zCONTSCAN /path/to/file
Response: /path/to/file: OK
Response: /path/to/file: VirusName FOUND
Note: Continues scanning even after finding threats
```

#### MULTISCAN
Scan directory recursively using multiple threads.
```
Command: zMULTISCAN /path/to/directory
Response: Multiple lines, one per file scanned
Note: Parallel scanning for better performance
```

#### ALLMATCHSCAN
Continue scanning after finding a match within a single file.
```
Command: zALLMATCHSCAN /path/to/file
Response: /path/to/file: Virus1 FOUND
Response: /path/to/file: Virus2 FOUND
Note: Reports all viruses found in same file
```

#### RAWSCAN
Scan without archive/recursive processing.
```
Command: zRAWSCAN /path/to/file
Response: /path/to/file: OK
Note: Scans file content only, no extraction
```

---

### Stream Scanning

#### INSTREAM
Scan data sent through the socket (used by ClamGUI).

**IMPORTANT:** Must use `n` or `z` prefix.

```
Command: zINSTREAM
Response: stream: OK
Response: stream: VirusName FOUND
Response: stream: ERROR: error_message
```

**Data Transmission Protocol:**

After sending `zINSTREAM\0`, send data in chunks:

```
[4-byte length][data][4-byte length][data]...[4-byte length: 0]
```

- **Length:** 4-byte unsigned integer in **network byte order**
- **Data:** Chunk content (max `StreamMaxLength` from clamd.conf)
- **Termination:** Send chunk with length = 0

**Swift Example:**
```swift
// Send command
send("zINSTREAM\0")

// Send chunk
var length: UInt32 = data.count.bigEndian
send(Data(bytes: &length, count: 4))
send(data)

// End stream
var zero: UInt32 = 0.bigEndian
send(Data(bytes: &zero, count: 4))

// Read response
let response = readLine() // "stream: OK" or "stream: VirusName FOUND"
```

**Size Limit:**
- Default: 25MB (configurable via `StreamMaxLength` in clamd.conf)
- Error if exceeded: `INSTREAM size limit exceeded`

---

### Session Commands

#### IDSESSION
Start an interactive session (commands processed in order).

**IMPORTANT:** Must use `n` or `z` prefix.

```
Command: zIDSESSION
Response: (no immediate response)

// Send commands with session ID
Command: 1 zPING
Response: 1: PONG

Command: 2 zSCAN /file
Response: 2: /file: OK

// End session
Command: zEND
```

**Critical Implementation Notes:**
- ClamD processes commands **asynchronously**
- Client **MUST** read all replies before sending next command
- Use non-blocking sockets with `select()`/`poll()`
- Failure to read replies may cause ClamD to close connection
- Use `PING` to keep connection alive during idle periods

#### END
End IDSESSION.
```
Command: zEND
Response: (session closed)
```

---

### Legacy/Deprecated Commands

#### STREAM (Deprecated)
Returns port number for separate data connection.
```
Command: STREAM
Response: PORT 12345
Note: Use INSTREAM instead
```

#### SESSION (Not Supported)
Use `IDSESSION` instead.

#### FILDES
Scan file descriptor (Unix sockets only).
```
Command: FILDES
Note: Requires sending file descriptor via ancillary data
Complex implementation, not recommended for ClamGUI
```

---

## Response Format Reference

### Scan Results

All scan commands return results in this format:

```
<filename>: <result>
```

**Result values:**
- `OK` - File is clean
- `<VirusName> FOUND` - Threat detected
- `ERROR: <message>` - Scan error

**Common errors:**
- `ERROR: Can't allocate memory` - Out of memory
- `ERROR: Can't create temporary file` - Disk space issue
- `ERROR: Too many files` - MaxFiles limit reached
- `ERROR: File size exceeded` - MaxFileSize limit
- `ERROR: No such file or directory` - File not found
- `ERROR: Access denied` - Permission denied

---

## ClamGUI Implementation

### Commands Used

| Command | Usage | Implementation |
|---------|-------|----------------|
| `zPING` | Health check | Before scanning |
| `zVERSION` | Database version | Settings display |
| `zINSTREAM` | File scanning | Primary scan method |
| `zRELOAD` | Database refresh | After freshclam |
| `zSTATS` | Diagnostics | Future feature |
| `zSHUTDOWN` | Stop daemon | Settings action |

### Socket Configuration

```swift
// Socket path
let socketPath = "~/Library/Application Support/ClamGUI/clamd.sock"

// Connection
socketHandle = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

// Command format
let command = "zINSTREAM\0"  // NULL-terminated

// Chunk size
let chunkSize = 8192  // 8KB chunks

// Length prefix (network byte order)
var length: UInt32 = UInt32(chunk.count).bigEndian
```

---

## Configuration Reference

### Relevant clamd.conf Options

| Option | Default | Description |
|--------|---------|-------------|
| `LocalSocket` | - | Unix socket path |
| `LocalSocketMode` | 666 | Socket permissions |
| `StreamMaxLength` | 25M | Max INSTREAM data |
| `MaxFileSize` | 25M | Max file to scan |
| `MaxScanSize` | 100M | Max data to scan per file |
| `MaxFiles` | 10000 | Max files in archive |
| `MaxRecursion` | 16 | Archive recursion depth |
| `ReadTimeout` | 180 | Socket read timeout |
| `MaxConnectionQueueLength` | 30 | Max pending connections |

---

## Security Considerations

### Socket Permissions
- Default mode: 666 (world read/write)
- ClamGUI uses: 600 (owner only)
- Configure in `clamd.conf`: `LocalSocketMode 600`

### TCP vs Unix Socket
- **Unix socket:** Local only, file-based permissions
- **TCP socket:** Network accessible, no authentication
- **Recommendation:** Use Unix socket for local apps

### Sudo Mode
- Root daemon can access protected files
- Socket still restricted by `LocalSocketMode`
- ClamGUI manages privilege via launchd

---

## Best Practices

1. **Always use `z` prefix** for reliable command parsing
2. **Read all responses** before sending next command
3. **Handle errors gracefully** - connection may close on protocol violation
4. **Use INSTREAM** for file content scanning (not file paths)
5. **Respect size limits** - check file size before sending
6. **Implement timeouts** - network operations may hang
7. **Pool connections** - socket setup has overhead
8. **Use IDSESSION** for batch operations (with proper async handling)

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection refused | Daemon not running | Start clamd service |
| Permission denied | Socket mode too restrictive | Check `LocalSocketMode` |
| Stream size exceeded | File > `StreamMaxLength` | Increase limit or skip file |
| Connection closed | Protocol violation | Use correct delimiters |
| No response | Didn't read replies | Implement async read loop |
| Deadlock in IDSESSION | Sent command before reading | Read all replies first |
