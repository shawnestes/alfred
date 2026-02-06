const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// Agent configuration
const agents = [
    { name: 'Nexus', port: 18789, channel: 'main', type: 'primary' },
    { name: 'Dearnote', port: 18800, channel: '#dearnote', type: 'service' },
    { name: 'Noyoupick', port: 18810, channel: '#noyoupick', type: 'service' },
    { name: 'Ghostreel', port: 18820, channel: '#ghostreel', type: 'service' },
    { name: 'Quickdraw', port: 18830, channel: '#quickdraw', type: 'service', disabled: true }
];

// API Routes
app.get('/api/agents', (req, res) => {
    res.json(agents);
});

app.get('/api/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: '1.0.0'
    });
});

// Proxy endpoint for agent health checks (to avoid CORS)
app.get('/api/agent/:name/health', async (req, res) => {
    const agentName = req.params.name;
    const agent = agents.find(a => a.name.toLowerCase() === agentName.toLowerCase());
    
    if (!agent) {
        return res.status(404).json({ error: 'Agent not found' });
    }

    try {
        const fetch = require('node-fetch');
        const response = await fetch(`http://localhost:${agent.port}/health`, {
            timeout: 5000
        });
        
        const data = await response.text();
        res.json({
            status: 'running',
            port: agent.port,
            response: data,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.json({
            status: agent.disabled ? 'disabled' : 'stopped',
            port: agent.port,
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Serve the dashboard
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// Start server
app.listen(PORT, () => {
    console.log(`🚀 Alfred Dashboard running on http://localhost:${PORT}`);
    console.log(`📊 Monitoring ${agents.length} agents`);
    console.log(`🔗 API available at http://localhost:${PORT}/api`);
});

module.exports = app;