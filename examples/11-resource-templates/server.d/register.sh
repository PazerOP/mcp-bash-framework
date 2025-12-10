#!/usr/bin/env bash
set -euo pipefail

# Manual templates: override project-files metadata and add logs-by-date.
mcp_resources_templates_manual_begin
mcp_resources_templates_register_manual '{
  "name": "project-files",
  "uriTemplate": "file:///{path}",
  "description": "Manual override with annotations applied",
  "annotations": {"audience": ["assistant"]}
}'
mcp_resources_templates_register_manual '{
  "name": "logs-by-date",
  "title": "Logs by Date",
  "uriTemplate": "file:///var/log/{service}/{date}.log",
  "description": "Access log files by service and date"
}'
mcp_resources_templates_manual_finalize
