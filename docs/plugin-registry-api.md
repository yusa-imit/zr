# Plugin Registry API Specification

## Overview
The zr plugin registry provides a centralized index for discovering and installing zr plugins. This document defines the REST API for the registry server.

## Base URL
- Production: `https://registry.zr.dev` (future)
- Development: `http://localhost:8080`

## Endpoints

### 1. Search Plugins
**GET** `/v1/plugins/search`

Search for plugins by name, description, or tags.

**Query Parameters:**
- `q` (string, optional): Search query (searches name, description, tags)
- `tag` (string, optional): Filter by tag (can be repeated for multiple tags)
- `limit` (integer, optional): Maximum results (default: 50, max: 100)
- `offset` (integer, optional): Pagination offset (default: 0)

**Response:**
```json
{
  "total": 42,
  "offset": 0,
  "limit": 50,
  "plugins": [
    {
      "name": "docker",
      "org": "zr-runner",
      "version": "1.2.0",
      "description": "Docker container management plugin",
      "author": "ZR Team",
      "repository": "https://github.com/zr-runner/zr-plugin-docker",
      "tags": ["docker", "containers", "ci"],
      "downloads": 1234,
      "updated_at": "2026-03-01T12:00:00Z"
    }
  ]
}
```

### 2. Get Plugin Details
**GET** `/v1/plugins/:org/:name`

Get detailed information about a specific plugin.

**Path Parameters:**
- `org` (string): Organization/user name
- `name` (string): Plugin name

**Response:**
```json
{
  "name": "docker",
  "org": "zr-runner",
  "version": "1.2.0",
  "description": "Docker container management plugin",
  "author": "ZR Team",
  "repository": "https://github.com/zr-runner/zr-plugin-docker",
  "tags": ["docker", "containers", "ci"],
  "downloads": 1234,
  "versions": ["1.2.0", "1.1.0", "1.0.0"],
  "readme": "# Docker Plugin\n\nProvides...",
  "created_at": "2025-12-15T10:00:00Z",
  "updated_at": "2026-03-01T12:00:00Z"
}
```

### 3. List All Plugins
**GET** `/v1/plugins`

List all plugins in the registry with pagination.

**Query Parameters:**
- `limit` (integer, optional): Maximum results (default: 50, max: 100)
- `offset` (integer, optional): Pagination offset (default: 0)
- `sort` (string, optional): Sort field (`name`, `downloads`, `updated_at`; default: `name`)
- `order` (string, optional): Sort order (`asc`, `desc`; default: `asc`)

**Response:**
Same structure as search endpoint.

### 4. Health Check
**GET** `/health`

Check if the registry server is operational.

**Response:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "uptime": 123456
}
```

## Error Responses

All errors follow this format:
```json
{
  "error": {
    "code": "not_found",
    "message": "Plugin not found: zr-runner/nonexistent"
  }
}
```

### Error Codes
- `not_found` (404): Plugin not found
- `invalid_request` (400): Invalid query parameters
- `rate_limited` (429): Too many requests
- `server_error` (500): Internal server error

## Client Implementation

The zr CLI will implement a client that:
1. Falls back to local-only search if registry is unreachable
2. Caches responses for 1 hour
3. Respects rate limits with exponential backoff
4. Uses HTTP/1.1 with Keep-Alive

## Future Enhancements
- Plugin submission API (POST /v1/plugins)
- Authentication for publishing
- Webhook notifications for updates
- Analytics endpoint for download stats
