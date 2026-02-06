# Alfred - Agent Management Dashboard

A unified dashboard for monitoring and managing all OpenClaw agents.

## Features

### 📊 Agent Monitoring
- **Real-time status** for all 5 agents (Nexus, Dearnote, Noyoupick, Ghostreel, Quickdraw)
- **Port monitoring** - attempts to connect to each agent's port to check availability
- **Response time tracking** - measures how quickly agents respond
- **Uptime monitoring** - tracks how long each agent has been running

### 📈 Metrics & Analytics
- **Request counts** - tracks total requests handled by each agent
- **Error monitoring** - displays error counts for each agent
- **System overview** - shows total running/stopped agents
- **Activity logs** - real-time activity feed with timestamps

### 🎨 Modern UI
- **Dark theme** optimized for monitoring
- **Responsive design** works on desktop and mobile
- **Auto-refresh** updates every 30 seconds
- **Manual refresh** button for instant updates
- **Status indicators** with color-coded agent health

## Agent Configuration

| Agent | Port | Channel | Status |
|-------|------|---------|--------|
| Nexus (main) | 18789 | main | Primary orchestration agent |
| Dearnote | 18800 | #dearnote | Note-taking and organization |
| Noyoupick | 18810 | #noyoupick | Decision-making assistant |
| Ghostreel | 18820 | #ghostreel | Content creation and media |
| Quickdraw | 18830 | #quickdraw | Fast response handler (disabled) |

## Usage

### Local Development
1. Open `index.html` in any modern web browser
2. The dashboard will automatically start monitoring agents
3. Use the "🔄 Refresh All" button to manually update status

### Web Server
```bash
# Simple Python server
python3 -m http.server 8080

# Node.js serve
npx serve .

# Any other static file server
```

Then visit `http://localhost:8080` in your browser.

## How It Works

### Status Detection
The dashboard attempts to connect to each agent's port using a health check approach:
- Tries to fetch from `http://localhost:{port}/health`
- If successful (or no CORS error), marks as "running"
- If connection fails, marks as "stopped" 
- Quickdraw is marked as "disabled" per requirements

### Activity Logging
- Logs all status checks with timestamps
- Maintains last 100 log entries
- Shows agent name, action, and timestamp
- Auto-scrolling log display

### Metrics
The dashboard tracks several key metrics:
- **Requests**: Total requests handled (simulated data)
- **Errors**: Error count for each agent
- **Response Time**: How quickly agents respond to health checks
- **Uptime**: How long each agent has been running

## Architecture

### Single File Design
The entire dashboard is contained in `index.html` for simplicity:
- **No build process** required
- **No dependencies** - pure HTML/CSS/JavaScript
- **Easy deployment** - just copy the file anywhere
- **Self-contained** - works offline after initial load

### Future Enhancements
The dashboard is designed to be easily extensible:
- Add real health check endpoints to agents
- Integrate with agent logs via file watching
- Add historical metrics storage
- Include token usage tracking
- Add alert/notification system

## Browser Support
- Chrome/Chromium (recommended)
- Firefox
- Safari
- Edge

Note: Uses modern JavaScript features (async/await, fetch API) so requires a recent browser.

## Version
v1.0.0 - Initial release with core monitoring features