#!/usr/bin/env python3
"""
USER REQUEST: "visualization with granularity of error, event, system and application relevant messages was expected"
USER COMPLAINT: "dashboard is sparse, unusable" + "0 Total Events"
ROOT CAUSE: Browser CORS policy blocks loading local JSON files (file:// protocol)
SOLUTION: Generate standalone HTML with embedded JSON data (no external file loading)
BENEFIT: Works immediately, no CORS issues, no server needed
"""

import json
import sys
from pathlib import Path

# PATHS
REPO_ROOT = Path(__file__).parent.parent.parent
JSON_FILE = REPO_ROOT / ".notes/visualizations/application-logs.json"
OUTPUT_FILE = REPO_ROOT / ".notes/visualizations/standalone-dashboard.html"

# LOAD DATA
print(f"Loading data from: {JSON_FILE}")
with open(JSON_FILE, 'r') as f:
    data = json.load(f)

print(f"✅ Loaded {len(data)} application log entries")

# GENERATE HTML WITH EMBEDDED DATA
html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Granular Error Messages - {len(data)} Entries</title>
    <style>
        body {{ font-family: 'Consolas', 'Monaco', monospace; margin: 0; padding: 20px; background: #1e1e1e; color: #d4d4d4; }}
        h1 {{ text-align: center; color: #4ec9b0; margin-bottom: 10px; }}
        .subtitle {{ text-align: center; color: #858585; font-size: 14px; margin-bottom: 30px; }}
        .controls {{ background: #252526; border: 1px solid #3e3e42; border-radius: 8px; padding: 20px; margin-bottom: 20px; display: flex; gap: 20px; flex-wrap: wrap; align-items: center; }}
        .control-group {{ display: flex; flex-direction: column; gap: 5px; }}
        .control-group label {{ font-size: 12px; color: #858585; text-transform: uppercase; }}
        .control-group select, .control-group input {{ background: #1e1e1e; border: 1px solid #3e3e42; color: #d4d4d4; padding: 8px 12px; border-radius: 4px; font-family: inherit; min-width: 200px; }}
        .stats {{ display: flex; gap: 20px; margin-left: auto; }}
        .stat {{ text-align: center; }}
        .stat-value {{ font-size: 24px; font-weight: bold; color: #4ec9b0; }}
        .stat-label {{ font-size: 11px; color: #858585; text-transform: uppercase; }}
        .event-list {{ background: #252526; border: 1px solid #3e3e42; border-radius: 8px; max-height: 800px; overflow-y: auto; }}
        .event-item {{ border-bottom: 1px solid #3e3e42; padding: 12px 15px; cursor: pointer; transition: background 0.2s; }}
        .event-item:hover {{ background: #2d2d30; }}
        .event-item.expanded {{ background: #2d2d30; }}
        .event-header {{ display: flex; align-items: center; gap: 10px; margin-bottom: 5px; }}
        .event-timestamp {{ color: #858585; font-size: 11px; }}
        .event-badge {{ padding: 2px 8px; border-radius: 3px; font-size: 10px; font-weight: bold; text-transform: uppercase; }}
        .badge-source {{ background: #1d5a3a; color: #4ec9b0; }}
        .badge-ERROR {{ background: #5a1d1d; color: #f48771; }}
        .badge-WARNING {{ background: #5a4d1d; color: #dcdcaa; }}
        .badge-INFO {{ background: #1d2d5a; color: #9cdcfe; }}
        .badge-has-stack {{ background: #5a3d1d; color: #ffa500; margin-left: auto; }}
        .event-message {{ color: #d4d4d4; font-size: 13px; line-height: 1.5; word-wrap: break-word; }}
        .stack-trace {{ display: none; margin-top: 10px; padding: 10px; background: #1e1e1e; border-left: 3px solid #ffa500; border-radius: 4px; }}
        .stack-trace.visible {{ display: block; }}
        .stack-trace-header {{ color: #ffa500; font-weight: bold; margin-bottom: 8px; font-size: 12px; }}
        .stack-trace-line {{ color: #9cdcfe; font-size: 11px; padding: 3px 0; padding-left: 15px; position: relative; }}
        .stack-trace-line::before {{ content: '▶'; position: absolute; left: 0; color: #858585; }}
        .stack-trace-line .function {{ color: #dcdcaa; font-weight: bold; }}
        .stack-trace-line .file {{ color: #4ec9b0; }}
        .stack-trace-line .location {{ color: #858585; }}
        .stack-trace-line .async {{ color: #ffa500; font-size: 10px; margin-left: 5px; }}
    </style>
</head>
<body>
    <h1>🔍 Granular Error Messages Dashboard</h1>
    <p class="subtitle">
        Showing {len(data)} individual error messages with FULL verbatim text<br>
        Filter by source, severity, or search for specific errors
    </p>
    
    <div class="controls">
        <div class="control-group">
            <label>Source File</label>
            <select id="filter-source">
                <option value="all">All Sources</option>
                <option value="Augment.log">Augment.log</option>
                <option value="watchdog">Watchdog</option>
            </select>
        </div>
        
        <div class="control-group">
            <label>Severity</label>
            <select id="filter-severity">
                <option value="all">All Severities</option>
                <option value="ERROR">Errors</option>
                <option value="WARNING">Warnings</option>
                <option value="INFO">Info</option>
            </select>
        </div>
        
        <div class="control-group">
            <label>Search Message</label>
            <input type="text" id="filter-search" placeholder="Search: Request cancelled, API call failed, etc.">
        </div>
        
        <div class="stats">
            <div class="stat">
                <div class="stat-value" id="stat-total">0</div>
                <div class="stat-label">Total</div>
            </div>
            <div class="stat">
                <div class="stat-value" id="stat-filtered">0</div>
                <div class="stat-label">Filtered</div>
            </div>
        </div>
    </div>
    
    <div class="event-list" id="event-list"></div>
    
    <script>
        // EMBEDDED DATA (no external file loading, no CORS issues)
        const APPLICATION_LOGS = {json.dumps(data, indent=8)};
        
        console.log(`✅ Loaded ${{APPLICATION_LOGS.length}} application log entries`);
        
        let allEvents = APPLICATION_LOGS;
        let filteredEvents = APPLICATION_LOGS;
        
        function updateStats() {{
            document.getElementById('stat-total').textContent = allEvents.length.toLocaleString();
            document.getElementById('stat-filtered').textContent = filteredEvents.length.toLocaleString();
        }}
        
        function filterEvents() {{
            const sourceFilter = document.getElementById('filter-source').value;
            const severityFilter = document.getElementById('filter-severity').value;
            const searchFilter = document.getElementById('filter-search').value.toLowerCase();
            
            filteredEvents = allEvents.filter(event => {{
                if (sourceFilter !== 'all' && event.source !== sourceFilter) return false;
                if (severityFilter !== 'all' && event.severity !== severityFilter) return false;
                if (searchFilter && !event.message.toLowerCase().includes(searchFilter)) return false;
                return true;
            }});
            
            renderEvents();
            updateStats();
        }}
        
        function renderEvents() {{
            const container = document.getElementById('event-list');
            container.innerHTML = '';

            filteredEvents.forEach((event, index) => {{
                const item = document.createElement('div');
                item.className = 'event-item';
                item.dataset.index = index;

                const header = document.createElement('div');
                header.className = 'event-header';

                const timestamp = document.createElement('span');
                timestamp.className = 'event-timestamp';
                timestamp.textContent = new Date(event.timestamp).toLocaleString();
                header.appendChild(timestamp);

                if (event.source) {{
                    const source = document.createElement('span');
                    source.className = 'event-badge badge-source';
                    source.textContent = event.source;
                    header.appendChild(source);
                }}

                if (event.severity) {{
                    const severity = document.createElement('span');
                    severity.className = `event-badge badge-${{event.severity}}`;
                    severity.textContent = event.severity;
                    header.appendChild(severity);
                }}

                // Add stack trace indicator badge
                if (event.stack_trace && event.stack_trace.length > 0) {{
                    const stackBadge = document.createElement('span');
                    stackBadge.className = 'event-badge badge-has-stack';
                    stackBadge.textContent = `${{event.stack_trace.length}} STACK LINES`;
                    header.appendChild(stackBadge);
                }}

                item.appendChild(header);

                const message = document.createElement('div');
                message.className = 'event-message';
                message.textContent = event.message;
                item.appendChild(message);

                // Add stack trace section (hidden by default)
                if (event.stack_trace && event.stack_trace.length > 0) {{
                    const stackTrace = document.createElement('div');
                    stackTrace.className = 'stack-trace';

                    const stackHeader = document.createElement('div');
                    stackHeader.className = 'stack-trace-header';
                    stackHeader.textContent = '📍 STACK TRACE (Click to toggle)';
                    stackTrace.appendChild(stackHeader);

                    event.stack_trace.forEach(line => {{
                        const stackLine = document.createElement('div');
                        stackLine.className = 'stack-trace-line';

                        // Parse watchdog format: "STACK: funcName @ file.js:line:col"
                        const watchdogMatch = line.match(/STACK:\\s+([^\\s@]+)\\s+@\\s+([^:]+):(\\d+):(\\d+)/);
                        if (watchdogMatch) {{
                            const funcName = watchdogMatch[1];
                            const filePath = watchdogMatch[2];
                            const lineNum = watchdogMatch[3];
                            const colNum = watchdogMatch[4];

                            // Simplify file path
                            const fileName = filePath.split('/').pop();

                            stackLine.innerHTML = `
                                <span class="function">${{funcName}}</span> @
                                <span class="file">${{fileName}}</span>:
                                <span class="location">${{lineNum}}:${{colNum}}</span>
                            `;
                        }} else {{
                            // Parse raw format: "at async eH.callApi (/path/extension.js:252:478050)"
                            const rawMatch = line.match(/at\\s+(async\\s+)?([^\\s(]+)\\s+\\(([^)]+):(\\d+):(\\d+)\\)/);
                            if (rawMatch) {{
                                const isAsync = rawMatch[1] ? true : false;
                                const funcName = rawMatch[2];
                                const filePath = rawMatch[3];
                                const lineNum = rawMatch[4];
                                const colNum = rawMatch[5];

                                // Simplify file path
                                const fileName = filePath.split('/').pop();

                                stackLine.innerHTML = `
                                    <span class="function">${{funcName}}</span> @
                                    <span class="file">${{fileName}}</span>:
                                    <span class="location">${{lineNum}}:${{colNum}}</span>
                                    ${{isAsync ? '<span class="async">(async)</span>' : ''}}
                                `;
                            }} else {{
                                // Fallback for unparsed lines
                                stackLine.textContent = line;
                            }}
                        }}

                        stackTrace.appendChild(stackLine);
                    }});

                    item.appendChild(stackTrace);

                    // Add click handler to toggle stack trace
                    item.addEventListener('click', () => {{
                        item.classList.toggle('expanded');
                        stackTrace.classList.toggle('visible');
                    }});
                }}

                container.appendChild(item);
            }});
        }}
        
        document.getElementById('filter-source').addEventListener('change', filterEvents);
        document.getElementById('filter-severity').addEventListener('change', filterEvents);
        document.getElementById('filter-search').addEventListener('input', filterEvents);
        
        renderEvents();
        updateStats();
    </script>
</body>
</html>'''

# WRITE OUTPUT
print(f"Writing standalone HTML to: {OUTPUT_FILE}")
with open(OUTPUT_FILE, 'w') as f:
    f.write(html)

print(f"✅ Generated standalone dashboard: {OUTPUT_FILE}")
print(f"   Contains: {len(data)} embedded application log entries")
print(f"   File size: {OUTPUT_FILE.stat().st_size / 1024:.1f} KB")
print(f"\n🌐 Open in browser: file://{OUTPUT_FILE}")

